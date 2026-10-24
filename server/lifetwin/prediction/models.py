"""Prediction response contract: survival probabilities at supported horizons, never a date."""

from typing import Literal

from pydantic import Field

from lifetwin.core.models import SCHEMA_VERSION, ApiModel


class HorizonSurvival(ApiModel):
    years: int = Field(ge=1, le=5)
    # Probability (0 to 1) that people with similar answers were still living at this horizon.
    survival: float = Field(ge=0, le=1)


class CurvePoint(ApiModel):
    years: float = Field(ge=0, le=5)
    survival: float = Field(ge=0, le=1)


class FilledInput(ApiModel):
    """A model input the user did not give; the model's missing-value policy filled it."""

    feature: str
    label: str


class PredictionResponse(ApiModel):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    status: Literal["supported", "unsupported"]
    model_version: str
    max_horizon_years: int = Field(default=5, ge=1, le=5)
    # Empty when unsupported: no fabricated numbers or curve.
    survival: list[HorizonSurvival]
    # Step curve from (0, 1) to the supported horizon; never increases.
    curve: list[CurvePoint]
    filled_in: list[FilledInput]
    # Plain-words reason when status is "unsupported".
    reason: str | None = None
    limitations: list[str]
