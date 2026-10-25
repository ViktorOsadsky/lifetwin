"""Adversarial tests for /api/predict (direction, bounds, no dates) and for the request
limits (oversized bodies, rate limit, garbage bodies) across every POST route.
"""

import itertools
import json
import re

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings

INTAKE = {
    "age": 60,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 80,
    "sleep_hours": 7,
    "exercise_minutes_weekly": 150,
    "smoking_status": "never",
    "diabetes": False,
}
DATE_LIKE = re.compile(r"\b(?:19|20|21)\d{2}-\d{2}-\d{2}\b|\b(?:19|20|21)\d{2}\b")


def settings(**over):
    base = dict(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
    return Settings(**{**base, **over})


@pytest.fixture(scope="module")
def client():
    return TestClient(create_app(settings()), raise_server_exceptions=False)


def predict(client, **change):
    response = client.post("/api/predict", json={**INTAKE, **change})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "supported", body
    return {point["years"]: point["survival"] for point in body["survival"]}


# --- Direction and bounds ------------------------------------------------------------------------------------------


def test_survival_is_a_probability_that_never_rises_with_time(client):
    for age, sex in itertools.product((18, 30, 45, 60, 70, 80), ("male", "female")):
        s = predict(client, age=age, sex=sex)
        assert all(0 <= v <= 1 for v in s.values()), (age, sex, s)
        assert s[1] >= s[3] >= s[5], (age, sex, s)


def test_older_people_do_not_have_better_survival_than_younger_otherwise_identical_ones(client):
    for sex in ("male", "female"):
        values = [predict(client, age=age, sex=sex)[5] for age in range(40, 81, 5)]
        assert values == sorted(values, reverse=True), (sex, values)


def test_a_current_smoker_never_outlives_an_otherwise_identical_never_smoker(client):
    for age, sex in itertools.product((40, 55, 65, 75, 80), ("male", "female")):
        never = predict(client, age=age, sex=sex, smoking_status="never")
        current = predict(client, age=age, sex=sex, smoking_status="current")
        for years in (1, 3, 5):
            assert current[years] <= never[years], (age, sex, years, current, never)


@pytest.mark.parametrize(
    "age",
    [
        45,
        60,
        pytest.param(
            75,
            marks=pytest.mark.xfail(
                strict=True,
                reason="BUG (model): a 75-year-old with diabetes gets better 5-year survival "
                "(0.8618) than the same person without (0.8355)",
            ),
        ),
    ],
)
def test_diabetes_never_looks_better_than_no_diabetes(client, age):
    assert predict(client, age=age, diabetes=True)[5] <= predict(client, age=age, diabetes=False)[5]


@pytest.mark.parametrize("age", [45, 60, 75])
def test_more_activity_never_looks_worse_up_to_a_very_active_week(client, age):
    values = [predict(client, age=age, exercise_minutes_weekly=m)[5] for m in (0, 150, 300, 600)]
    assert values == sorted(values), (age, values)


@pytest.mark.xfail(
    strict=True,
    reason="BUG (model): 3-5 hours of sleep is modeled as better than 7 "
    "(0.9591 / 0.9473 vs 0.9425), contradicting the 'sleep 7 hours' advice",
)
def test_short_sleep_never_looks_better_than_seven_hours(client):
    seven = predict(client, sleep_hours=7)[5]
    assert predict(client, sleep_hours=5)[5] <= seven
    assert predict(client, sleep_hours=3)[5] <= seven


def test_the_same_request_gives_the_same_numbers(client):
    assert predict(client) == predict(client)


def test_the_response_never_holds_a_date_or_a_year(client):
    body = client.post("/api/predict", json=INTAKE).json()
    visible = {k: v for k, v in body.items() if k not in {"model_version", "limitations"}}
    assert not DATE_LIKE.search(json.dumps(visible))
    assert not re.search(
        r"expectan|will (?:die|live)|countdown|age of death", json.dumps(body), re.I
    )


@pytest.mark.parametrize("age", [18, 19, 79, 80])
def test_supported_ages_are_supported(client, age):
    assert predict(client, age=age)


@pytest.mark.parametrize("age", [0, 17, 81, 85, 86, 120])
def test_unsupported_ages_get_a_reason_and_no_numbers(client, age):
    body = client.post("/api/predict", json={**INTAKE, "age": age}).json()
    assert body["status"] == "unsupported" and body["reason"]
    assert body["survival"] == [] and body["curve"] == [] and body["filled_in"] == []


@pytest.mark.parametrize("sex", ["intersex", "prefer_not_to_say", "other", "", "Male", "F"])
def test_a_sex_other_than_female_or_male_is_refused_never_guessed(client, sex):
    response = client.post("/api/predict", json={**INTAKE, "sex": sex})
    assert response.status_code == 422
    assert response.json()["code"] == "invalid_request"


def test_a_missing_sex_gets_no_numbers_and_no_guess(client):
    body = client.post("/api/predict", json={**INTAKE, "sex": None}).json()
    assert body["status"] == "unsupported" and body["survival"] == []
    assert "sex" in body["reason"]


@pytest.mark.parametrize(
    "change",
    [
        {"height_cm": 50, "weight_kg": 700},
        {"height_cm": 280, "weight_kg": 10},
        {"sleep_hours": 0},
        {"sleep_hours": 24},
        {"exercise_minutes_weekly": 10080},
        {"alcohol_drinks_weekly": 200},
        {"systolic_bp": 300, "diastolic_bp": 200 - 1},
    ],
)
def test_extreme_but_valid_values_never_crash_or_leave_zero_to_one(client, change):
    body = client.post("/api/predict", json={**INTAKE, **change}).json()
    assert body["status"] in {"supported", "unsupported"}
    for point in body["survival"]:
        assert 0 <= point["survival"] <= 1


@pytest.mark.parametrize(
    "change",
    [
        {"age": 60.5},
        {"age": "60"},
        {"height_cm": 49.9},
        {"weight_kg": 9},
        {"sleep_hours": 24.1},
        {"systolic_bp": 80, "diastolic_bp": 90},
        {"diabetes": "no"},
        {"smoking_status": "heavily"},
        {"score": 5},
    ],
)
def test_invalid_values_are_422_and_never_echoed(client, change):
    response = client.post("/api/predict", json={**INTAKE, **change})
    assert response.status_code == 422
    for value in change.values():
        if isinstance(value, str) and len(value) > 3:
            assert value not in response.text


# --- Limits across every POST route ----------------------------------------------------------------------------------


def post_routes(app):
    paths = app.openapi()["paths"]
    return sorted(path for path, ops in paths.items() if "post" in ops)


def test_the_set_of_post_routes_is_the_one_we_test():
    routes = post_routes(create_app(settings()))
    for expected in (
        "/api/predict",
        "/api/recommendations",
        "/api/coach/plan",
        "/api/onboarding/turn",
        "/api/checkin/start",
        "/api/checkin/turn",
        "/api/change/start",
        "/api/change/turn",
        "/api/documents/extract",
    ):
        assert expected in routes


def test_an_oversized_body_is_413_on_every_post_route_and_never_500():
    app = create_app(settings(max_body_bytes=512, max_document_body_bytes=2048))
    client = TestClient(app, raise_server_exceptions=False)
    for path in post_routes(app):
        limit = 2048 if path == "/api/documents/extract" else 512
        body = json.dumps({"text": "x" * (limit + 1)})
        response = client.post(path, content=body, headers={"content-type": "application/json"})
        assert response.status_code == 413, (path, response.status_code)
        assert response.json()["code"] == "body_too_large"
        assert "x" * 50 not in response.text


def test_a_body_exactly_at_the_limit_is_not_rejected_for_size():
    app = create_app(settings(max_body_bytes=512))
    client = TestClient(app, raise_server_exceptions=False)
    pad = 512 - len('{"text":""}')
    response = client.post(
        "/api/onboarding/turn",
        content='{"text":"' + "x" * pad + '"}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 422  # too long to be valid input, but not a size rejection


def test_the_document_route_has_its_own_bigger_limit():
    app = create_app(settings(max_body_bytes=512, max_document_body_bytes=4096))
    client = TestClient(app, raise_server_exceptions=False)
    middle = json.dumps({"pages": ["x" * 1500]})
    assert client.post("/api/documents/extract", content=middle).status_code != 413
    assert client.post("/api/predict", content=middle).status_code == 413


@pytest.mark.parametrize(
    ("content", "ctype"),
    [
        (b"{", "application/json"),
        (b"[]", "application/json"),
        (b"null", "application/json"),
        (b'"text"', "application/json"),
        (b"\xff\xfe\x00", "application/json"),
        (b"", "application/json"),
        (b"{}", "text/plain"),
        (b"[" * 20000, "application/json"),
        (b'{"profile": {"age": 1e999}}', "application/json"),
        (b'{"profile": {"age": NaN}}', "application/json"),
        (b'{"a":' * 3000, "application/json"),
    ],
)
def test_garbage_bodies_are_a_clean_4xx_on_every_post_route(content, ctype):
    app = create_app(settings(max_body_bytes=40000))
    client = TestClient(app, raise_server_exceptions=False)
    for path in post_routes(app):
        response = client.post(path, content=content, headers={"content-type": ctype})
        assert 400 <= response.status_code < 500, (path, response.status_code, response.text[:120])
        assert response.json()["status"] == "error"


def test_the_rate_limit_is_per_caller_across_routes_with_a_retry_hint():
    app = create_app(settings(rate_limit_per_minute=5))
    client = TestClient(app, raise_server_exceptions=False)
    paths = ["/api/predict", "/api/recommendations", "/api/coach/plan", "/api/checkin/start"]
    codes = [client.post(paths[i % 4], json={}).status_code for i in range(8)]
    assert 429 not in codes[:5] and codes[5:] == [429, 429, 429]
    limited = client.post("/api/predict", json=INTAKE)
    assert limited.status_code == 429
    assert limited.json()["code"] == "rate_limit_exceeded"
    assert int(limited.headers["retry-after"]) >= 1
    assert client.get("/health").status_code == 200  # probes are never limited


def test_a_413_still_counts_toward_the_rate_limit_so_it_cannot_be_used_to_flood():
    app = create_app(settings(rate_limit_per_minute=3, max_body_bytes=128))
    client = TestClient(app, raise_server_exceptions=False)
    big = json.dumps({"text": "x" * 300})
    codes = [client.post("/api/onboarding/turn", content=big).status_code for _ in range(5)]
    assert codes == [413, 413, 413, 429, 429]


def test_every_error_carries_a_request_id_and_never_the_request_body():
    app = create_app(settings(max_body_bytes=128))
    client = TestClient(app, raise_server_exceptions=False)
    response = client.post(
        "/api/predict", content=json.dumps({"age": 51, "note": "secret-note-" * 20})
    )
    assert response.status_code == 413
    assert response.headers["x-request-id"] == response.json()["request_id"]
    assert "secret-note" not in response.text
