import json
import logging
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.prediction.survival import DEFAULT_MODEL_DIR, SurvivalModel, model_inputs

ROOT = Path(__file__).resolve().parents[2]
RESPONSE_SCHEMA = Draft202012Validator(
    json.loads((ROOT / "contracts" / "prediction.schema.json").read_text())
)

# Fully specified model inputs with Victor's reference survival (%, at 1/3/5 years).
REFERENCE_70 = {
    "age": 70,
    "bmi": 26,
    "sleep_hours": 7,
    "vigorous_recreation_min_week": 0,
    "moderate_recreation_min_week": 150,
    "sedentary_min_day": 360,
    "sex_nhanes": 1,
    "smoking_status": 0,
    "diabetes_diagnosed": 0,
    "hypertension_diagnosed": 0,
    "general_health": 3,
}
REFERENCE_75 = {
    **REFERENCE_70,
    "age": 75,
    "smoking_status": 2,
    "diabetes_diagnosed": 1,
    "hypertension_diagnosed": 1,
    "general_health": 4,
    "moderate_recreation_min_week": 0,
}
INTAKE = {
    "age": 70,
    "sex": "male",
    "height_cm": 170,
    "weight_kg": 75,
    "sleep_hours": 7,
    "exercise_minutes_weekly": 150,
    "smoking_status": "never",
    "diabetes": False,
}


def config(**overrides):
    return Settings(
        _env_file=None, openai_api_key="", openai_model="", tavily_api_key="", **overrides
    )


@pytest.fixture(scope="module")
def model():
    return SurvivalModel.load(DEFAULT_MODEL_DIR)


@pytest.fixture
def client():
    with TestClient(create_app(config())) as instance:
        yield instance


@pytest.mark.parametrize(
    "row,expected",
    [(REFERENCE_70, [98.9, 96.0, 92.8]), (REFERENCE_75, [93.6, 79.0, 65.1])],
)
def test_reference_profiles_match_the_trained_model(model, row, expected):
    risk = model.risks([row])[0]
    assert [round(100 * model.survival_at(risk, years), 1) for years in (1, 3, 5)] == expected


def test_forward_pass_matches_keras_reference_risks(model):
    # Log risks computed by keras 3.15.1 (numpy backend) from model.keras for these rows.
    assert model.risks([REFERENCE_70, REFERENCE_75]) == pytest.approx(
        [0.7280543446540833, 2.472700834274292], abs=1e-5
    )


def test_intake_answers_map_to_model_inputs():
    row = model_inputs(
        HealthProfile.model_validate({**INTAKE, "sex": "female", "smoking_status": "current"})
    )
    assert row["bmi"] == pytest.approx(75 / 1.7**2)
    assert row["sex_nhanes"] == 2.0
    assert row["smoking_status"] == 2.0
    assert row["diabetes_diagnosed"] == 0.0
    assert row["moderate_recreation_min_week"] == 150.0
    assert row["vigorous_recreation_min_week"] == 0.0
    assert row["sedentary_min_day"] is None
    assert row["hypertension_diagnosed"] is None and row["general_health"] is None
    unknown = model_inputs(HealthProfile.model_validate({"smoking_status": "unknown"}))
    assert unknown["smoking_status"] is None and unknown["diabetes_diagnosed"] is None


def test_supported_forecast_shape(client):
    response = client.post("/api/predict", json=INTAKE)
    assert response.status_code == 200
    body = response.json()
    RESPONSE_SCHEMA.validate(body)
    assert body["status"] == "supported"
    assert body["max_horizon_years"] == 5
    assert [point["years"] for point in body["survival"]] == [1, 3, 5]
    assert body["model_version"].startswith("deepsurv-nhanes-")
    curve = body["curve"]
    assert curve[0] == {"years": 0.0, "survival": 1.0}
    assert curve[-1]["years"] == 5.0
    assert all(0 <= p["survival"] <= 1 and p["years"] <= 5 for p in curve)
    assert all(a["survival"] >= b["survival"] for a, b in zip(curve, curve[1:], strict=False))
    assert curve[-1]["survival"] == body["survival"][-1]["survival"]
    assert [item["feature"] for item in body["filled_in"]] == [
        "sedentary_min_day",
        "hypertension_diagnosed",
        "general_health",
    ]
    assert any("Smoking answers are assumed" in text for text in body["limitations"])
    for forbidden in ("death", "date", "expectancy", "countdown"):
        assert (
            forbidden
            not in json.dumps({k: v for k, v in body.items() if k != "limitations"}).lower()
        )


def test_skipped_categorical_answers_are_listed_as_filled_in(client):
    body = client.post(
        "/api/predict", json={**INTAKE, "smoking_status": "unknown", "diabetes": None}
    ).json()
    assert body["status"] == "supported"
    features = [item["feature"] for item in body["filled_in"]]
    assert "smoking_status" in features and "diabetes_diagnosed" in features


@pytest.mark.parametrize(
    "change,words",
    [
        ({"age": None}, "age and your sex"),
        ({"sex": None}, "age and your sex"),
        ({"age": 81}, "above 80"),
        ({"age": 17}, "adults"),
        ({"sleep_hours": None}, "how many hours you sleep. You can go back and add it."),
        ({"height_cm": None, "exercise_minutes_weekly": None}, "height and weight and how many"),
    ],
)
def test_unsupported_profiles_get_a_plain_reason_and_no_numbers(client, change, words):
    response = client.post("/api/predict", json={**INTAKE, **change})
    assert response.status_code == 200
    body = response.json()
    RESPONSE_SCHEMA.validate(body)
    assert body["status"] == "unsupported"
    assert words in body["reason"]
    assert body["survival"] == [] and body["curve"] == [] and body["filled_in"] == []


def test_age_80_is_still_supported_and_age_is_never_capped(client):
    assert client.post("/api/predict", json={**INTAKE, "age": 80}).json()["status"] == "supported"
    assert client.post("/api/predict", json={**INTAKE, "age": 95}).json()["status"] == "unsupported"


def test_missing_artifacts_keep_the_deferred_501(tmp_path):
    with TestClient(create_app(config(model_artifact_path=str(tmp_path)))) as client:
        response = client.post("/api/predict", json=INTAKE)
        assert response.status_code == 501
        assert response.json()["status"] == "not_implemented"
        assert client.get("/ready").json()["prediction"] == "not_implemented"


def test_ready_and_capabilities_report_the_model(client):
    assert client.get("/ready").json()["prediction"] == "available"
    assert client.get("/api/capabilities").json()["prediction"] == "available"


def test_model_version_hashes_the_artifact_files(tmp_path, model):
    for name in ("model.keras", "preprocessor.joblib", "baseline_hazard.csv", "metrics.json"):
        (tmp_path / name).write_bytes((DEFAULT_MODEL_DIR / name).read_bytes())
    assert SurvivalModel.load(tmp_path).version == model.version
    with (tmp_path / "metrics.json").open("a") as handle:
        handle.write("\n")
    assert SurvivalModel.load(tmp_path).version != model.version


def test_profile_is_not_logged(client, caplog):
    with caplog.at_level(logging.DEBUG):
        client.post("/api/predict", json={**INTAKE, "weight_kg": 81.234})
    assert "81.234" not in caplog.text
