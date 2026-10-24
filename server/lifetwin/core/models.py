"""Input contracts only. These ranges validate data, not model eligibility."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

SCHEMA_VERSION = "1.0"


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)


class HealthProfile(ApiModel):
    """Explicitly supplied metric inputs; no risk or lifespan inference."""

    age: int | None = Field(default=None, ge=0, le=120)
    sex: Literal["female", "male", "intersex", "prefer_not_to_say"] | None = None
    height_cm: float | None = Field(default=None, ge=50, le=280)
    weight_kg: float | None = Field(default=None, ge=10, le=700)
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    exercise_minutes_weekly: int | None = Field(default=None, ge=0, le=10080)
    smoking_status: Literal["never", "former", "current", "unknown"] | None = None
    alcohol_drinks_weekly: float | None = Field(default=None, ge=0, le=200)
    diabetes: bool | None = None
    systolic_bp: int | None = Field(default=None, ge=40, le=300)
    diastolic_bp: int | None = Field(default=None, ge=20, le=200)


class ApiError(ApiModel):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    status: Literal["error"] = "error"
    code: str
    message: str
    request_id: str | None = None


class DeferredFeature(ApiModel):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    status: Literal["not_implemented"] = "not_implemented"
    code: Literal["prediction_not_implemented"] = "prediction_not_implemented"
    message: str = "Prediction functionality is reserved for a later implementation."
    prediction: None = None
    model_version: None = None


class CompareRequest(ApiModel):
    baseline: HealthProfile
    scenario: HealthProfile


class SensitivityRequest(ApiModel):
    profile: HealthProfile
