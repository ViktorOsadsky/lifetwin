"""Stateless "change through Mochi" contracts: the caller sends the profile every turn.

Saved answers have no edit fields in the app. "Change" or "Update" opens this short
conversation instead: Mochi says what it has now, asks what changed, reads the new
value back, and only after a yes returns it as ``profile_update`` (the same shape as a
weekly check-in). The server stores nothing.
"""

from typing import Literal, get_args

from pydantic import Field, model_validator

from lifetwin.core.models import ApiModel, HealthProfile
from lifetwin.onboarding.models import MascotEvent

# The answers a person can ask to change, in the profile's (and on-device model's) names.
# Blood pressure is one reading, so it is changed as both numbers under "systolic_bp"
# (the readings history keeps it). "exercise_minutes_weekly" is the older single
# activity answer, kept until the change conversation splits a duration by pace the
# way onboarding does; the model reads the two activity fields.
ChangeField = Literal[
    "age",
    "sex",
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
    "sedentary_min_day",
    "exercise_minutes_weekly",
    "smoking_status",
    "alcohol_drinks_weekly",
    "diabetes",
    "hypertension_diagnosed",
    "general_health",
    "systolic_bp",
]
CHANGE_FIELDS: tuple[ChangeField, ...] = get_args(ChangeField)
NOTE_LENGTH = 300


def _names(field: str | None) -> set[str]:
    if field is None:
        return set()
    return {"systolic_bp", "diastolic_bp"} if field == "systolic_bp" else {field}


class ChangeState(ApiModel):
    # choosing: "What would you like to update?"; asking: what changed for ``field``;
    # probing: the one gentle "did something change?" before the read-back;
    # confirming: the new value read back; done: finished (``saved`` may be empty).
    phase: Literal["choosing", "asking", "probing", "confirming", "done", "cancelled"] = "choosing"
    field: ChangeField | None = None
    # The new value being read back; nothing is saved until a yes.
    pending: HealthProfile = Field(default_factory=HealthProfile)
    # The confirmed new value; returned as ``profile_update`` while done.
    saved: HealthProfile = Field(default_factory=HealthProfile)
    # Other answers the person mentioned ("I quit drinking and smoking"), offered next.
    options: list[ChangeField] = Field(default_factory=list, max_length=10)
    probed: bool = False
    # The person gave the new value in kilograms or centimeters, so Mochi reads it back so.
    metric: bool = False
    # A doctor was mentioned for a diabetes change, so Mochi need not ask.
    doctor_said: bool = False
    # Why it changed, in the person's words; kept only with memory consent.
    note: str | None = Field(default=None, min_length=1, max_length=NOTE_LENGTH)

    @model_validator(mode="after")
    def consistent_state(self):
        pending = set(self.pending.model_dump(exclude_none=True))
        saved = set(self.saved.model_dump(exclude_none=True))
        if bool(pending) != (self.phase in {"probing", "confirming"}):
            raise ValueError("Only probing and confirming may hold a pending value")
        if saved and self.phase != "done":
            raise ValueError("Only the done phase may hold a saved value")
        if self.phase in {"asking", "probing", "confirming"} and self.field is None:
            raise ValueError("An open question requires a field")
        if self.phase in {"choosing", "cancelled"} and self.field is not None:
            raise ValueError("This phase cannot have a field")
        if not pending <= _names(self.field) or not saved <= _names(self.field):
            raise ValueError("A new value must belong to the field being changed")
        if len(set(self.options)) != len(self.options):
            raise ValueError("Options must be unique")
        return self


class ChangeStartRequest(ApiModel):
    # The confirmed profile as the app has it now.
    profile: HealthProfile = Field(default_factory=HealthProfile)
    # The answer next to the tapped "Change" button; none asks what to update.
    field: ChangeField | None = None
    # The person agreed that Mochi may remember notes about their habits.
    memory_consent: bool = False


class ChangeTurnRequest(ApiModel):
    # "resume": the person tapped Continue after an emergency pause.
    action: Literal["reply", "confirm", "cancel", "resume"]
    state: ChangeState
    profile: HealthProfile = Field(default_factory=HealthProfile)
    memory_consent: bool = False
    text: str | None = Field(default=None, min_length=1, max_length=2000)
    input_mode: Literal["text", "transcript"] = "text"

    @model_validator(mode="after")
    def action_payload(self):
        if self.action == "reply" and not (self.text or "").strip():
            raise ValueError("A reply requires nonempty text")
        if self.action != "reply" and self.text is not None:
            raise ValueError("Only the reply action accepts text")
        return self


class HabitNote(ApiModel):
    """What changed and why, in the person's words, for the app's habit memory."""

    field: ChangeField
    text: str = Field(min_length=1, max_length=NOTE_LENGTH)


class ChangeResponse(ApiModel):
    """The same shape as a check-in turn, plus the habit note."""

    schema_version: Literal["1.0"] = "1.0"
    state: ChangeState
    message: str = Field(min_length=1, max_length=1500)
    guide_mode: Literal["guided"] = "guided"
    provider_status: Literal["not_configured"] = "not_configured"
    voice_status: Literal["deferred", "available", "unavailable"] = "deferred"
    speech_hint: Literal["slower", "louder"] | None = None
    # The reply said something urgent is happening: the conversation is paused where it
    # was. The app shows a "Call 911" button the person taps themselves, and "Continue"
    # (action "resume", or any reply) goes on where it stopped.
    emergency: bool = False
    # The confirmed new value, in the profile's fields, units and ranges. When
    # ``complete`` is true the app sets each non-null field on the confirmed profile and
    # reruns the forecast; null fields stay as they are. Empty when nothing changed.
    profile_update: HealthProfile = Field(default_factory=HealthProfile)
    # Only with memory consent, and only with a saved change.
    habit_note: HabitNote | None = None
    accepted_input_modes: list[Literal["text", "transcript"]] = Field(
        default_factory=lambda: ["text", "transcript"], min_length=2, max_length=2
    )
    mascot_events: list[MascotEvent] = Field(min_length=1, max_length=2)
    complete: bool
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Your answers stay on your phone. The server keeps nothing.",
            "Nothing changes until you say yes. Mochi gives no medical advice.",
        ],
        max_length=5,
    )
