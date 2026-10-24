import pytest
from pydantic import ValidationError

from lifetwin.core.models import DeferredFeature, HealthProfile


def test_profile_is_only_raw_partial_input():
    profile = HealthProfile(weight_kg=70, height_cm=175, diabetes=False)
    assert profile.model_dump(exclude_none=True) == {
        "weight_kg": 70,
        "height_cm": 175,
        "diabetes": False,
    }


@pytest.mark.parametrize(
    "payload",
    [
        {"age": True},
        {"age": "35"},
        {"sleep_hours": float("nan")},
        {"weight_kg": float("inf")},
        {"game_health": 80},
        {"death_date": "2080-01-01"},
        {"bmi": 24},
        {"smoking_status": "occasionally"},
    ],
)
def test_profile_rejects_ambiguous_non_finite_and_non_health_fields(payload):
    with pytest.raises(ValidationError):
        HealthProfile.model_validate(payload)


def test_prediction_placeholder_contains_no_estimate_or_model_identity():
    body = DeferredFeature().model_dump()
    assert body["status"] == "not_implemented"
    assert body["prediction"] is None
    assert body["model_version"] is None


@pytest.mark.parametrize("value", [35.0, 35])
def test_integral_floats_are_accepted_for_whole_number_fields(value):
    profile = HealthProfile.model_validate(
        {"age": value, "exercise_minutes_weekly": value, "systolic_bp": 120.0, "diastolic_bp": 80.0}
    )
    assert profile.age == 35 and isinstance(profile.age, int)
    assert profile.systolic_bp == 120 and isinstance(profile.systolic_bp, int)


@pytest.mark.parametrize("field", ["age", "exercise_minutes_weekly", "systolic_bp"])
def test_non_integral_floats_are_still_rejected(field):
    with pytest.raises(ValidationError):
        HealthProfile.model_validate({field: 60.5})


@pytest.mark.parametrize("pair", [(80, 150), (120, 120)])
def test_systolic_must_exceed_diastolic_with_plain_message(pair):
    with pytest.raises(ValidationError, match="top blood pressure number is usually the bigger"):
        HealthProfile.model_validate({"systolic_bp": pair[0], "diastolic_bp": pair[1]})


def test_single_blood_pressure_value_is_allowed():
    assert HealthProfile.model_validate({"diastolic_bp": 80}).diastolic_bp == 80
    assert HealthProfile.model_validate({"systolic_bp": 120, "diastolic_bp": 80})
