"""Input contracts only. These ranges validate data, not model eligibility."""

from typing import Annotated, Any, Literal

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, model_validator

SCHEMA_VERSION = "1.0"


BP_ORDER_MESSAGE = (
    "The top blood pressure number is usually the bigger one. Please check your reading."
)


def _integral_float_to_int(value: Any) -> Any:
    # JSON/Dart clients may send 35.0 for a whole number; 35.5 stays invalid.
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


WholeNumber = BeforeValidator(_integral_float_to_int)


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)


class HealthProfile(ApiModel):
    """Explicitly supplied metric inputs; no risk or lifespan inference."""

    age: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=120)
    sex: Literal["female", "male", "intersex", "prefer_not_to_say"] | None = None
    height_cm: float | None = Field(default=None, ge=50, le=280)
    weight_kg: float | None = Field(default=None, ge=10, le=700)
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    exercise_minutes_weekly: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )
    smoking_status: Literal["never", "former", "current", "unknown"] | None = None
    alcohol_drinks_weekly: float | None = Field(default=None, ge=0, le=200)
    diabetes: bool | None = None
    systolic_bp: Annotated[int | None, WholeNumber] = Field(default=None, ge=40, le=300)
    diastolic_bp: Annotated[int | None, WholeNumber] = Field(default=None, ge=20, le=200)

    @model_validator(mode="after")
    def blood_pressure_order(self):
        if (
            self.systolic_bp is not None
            and self.diastolic_bp is not None
            and self.systolic_bp <= self.diastolic_bp
        ):
            raise ValueError(BP_ORDER_MESSAGE)
        return self


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
