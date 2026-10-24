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


GeneralHealth = Literal["excellent", "very_good", "good", "fair", "poor"]


class HealthProfile(ApiModel):
    """Explicitly supplied metric inputs; no risk or lifespan inference."""

    age: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=120)
    # Sex at birth: the training data (NHANES) records only these two.
    sex: Literal["female", "male"] | None = None
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
    # Conversation v2: the remaining on-device model inputs, in the person's own terms.
    # How each maps to the model's codes is in onboarding/model_inputs.py.
    general_health: GeneralHealth | None = None
    # A doctor has told the person they have high blood pressure (a diagnosis, never
    # inferred from a reading).
    hypertension_diagnosed: bool | None = None
    # Awake time spent sitting on a usual day (reading, TV, driving all count).
    sedentary_min_day: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1439)
    # Recreational activity in a usual week: lighter ("a little out of breath") and harder.
    moderate_recreation_min_week: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )
    vigorous_recreation_min_week: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )

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


Wellbeing = Literal["good", "okay", "not_great"]


class CheckinValues(ApiModel):
    """Answers from a daily or weekly check-in, in the profile's own units and ranges.

    Weekly answers use the profile's field names, so a caller can offer them as
    profile updates. Daily answers are about one night or one day and have their
    own names, so they never pass for a usual week.
    """

    # Daily: one night, one day.
    sleep_hours_last_night: float | None = Field(default=None, ge=0, le=24)
    exercise_minutes_today: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    alcohol_drinks_yesterday: float | None = Field(default=None, ge=0, le=50)
    # Daily or weekly: how the person feels (daily) or how the week went (weekly).
    wellbeing: Wellbeing | None = None
    # Weekly: the same fields, units and ranges as HealthProfile.
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    exercise_minutes_weekly: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )
    smoking_status: Literal["never", "former", "current", "unknown"] | None = None
    alcohol_drinks_weekly: float | None = Field(default=None, ge=0, le=200)
    weight_kg: float | None = Field(default=None, ge=10, le=700)
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
