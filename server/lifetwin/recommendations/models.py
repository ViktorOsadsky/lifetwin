"""Stateless recommendations: the client sends the confirmed profile and habit notes."""

from datetime import date
from typing import Annotated, Literal

from pydantic import AfterValidator, Field

from lifetwin.core.models import ApiModel, HealthProfile
from lifetwin.onboarding.models import CharacterHints, HabitNote, Recommendation


def _real_date(value: str | None) -> str | None:
    if value is not None:
        try:
            date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("Dates must be real calendar days, like 2026-10-24") from exc
    return value


LocalDate = Annotated[str, Field(pattern=r"^\d{4}-\d{2}-\d{2}$"), AfterValidator(_real_date)]


class RecommendationRequest(ApiModel):
    profile: HealthProfile
    habit_notes: list[HabitNote] = Field(default_factory=list, max_length=10)
    # Per-provider opt-in for outside-AI wording, e.g. {"claude": true}. Consent for one
    # provider never covers another. Without it, Mochi's own templates are used.
    outside_ai_consent: dict[Literal["claude", "muse"], bool] = Field(default_factory=dict)
    # The phone's calendar day, e.g. "2026-10-24". Ideas rotate by day: the same day
    # always shows the same ideas. Missing: the server's today.
    local_date: LocalDate | None = None


class LeverRanking(ApiModel):
    source: Literal["docs/model-sensitivity.json"] = "docs/model-sensitivity.json"
    model_version: str
    order: list[str]


class RecommendationResponse(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    # "not_enough_information": nothing confirmed yet that a suggestion could rest on.
    status: Literal["ok", "not_enough_information", "under_age"]
    # Mochi's spoken lines: a short lead-in, then each suggestion.
    message: str = Field(min_length=1, max_length=1500)
    recommendations: list[Recommendation] = Field(max_length=3)
    # Today's one featured idea: the id of the first non-encouragement recommendation
    # (or the first one), stable for the whole local day. Null unless status is "ok".
    featured: str | None = None
    # Model input fields still empty, in lever-ranking order; only when status is
    # "not_enough_information", otherwise empty.
    missing_inputs: list[str] = Field(default_factory=list, max_length=10)
    character_hints: CharacterHints
    lever_ranking: LeverRanking
    # "templates": Mochi's own wording. A provider name: that provider phrased the
    # suggestions (with consent) and every line passed the safety check.
    phrased_by: Literal["templates", "claude", "muse"] = "templates"
    causal_interpretation: Literal[False] = False
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Suggestions follow public-health guidance and the model's lever ranking; "
            "they are not medical advice and promise no benefit.",
            "The model compares similar people over one to five years; it does not show "
            "what a change would do for you.",
            "The server keeps nothing. Habit notes and history stay on your phone.",
        ],
        max_length=5,
    )
