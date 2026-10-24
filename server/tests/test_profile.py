import pytest
from lifetwin.core.models import DeferredFeature, HealthProfile
from pydantic import ValidationError


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
