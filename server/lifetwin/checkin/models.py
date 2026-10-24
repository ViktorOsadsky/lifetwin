"""Stateless check-in contracts: the caller holds the state and the previous answers.

Check-in history lives only on the phone (owner ruling); the server stores nothing,
so the client sends the previous answers with every turn. Weekly answers come back
as ``profile_update`` for the app to apply to the profile; daily answers are history.
"""

import re
from typing import Literal

from pydantic import Field, field_validator, model_validator

from lifetwin.checkin.scripts import SCRIPTS, CheckinField, CheckinKind
from lifetwin.core.models import ApiModel, CheckinValues, HealthProfile
from lifetwin.onboarding.models import HabitNote, MascotEvent


class CheckinState(ApiModel):
    kind: CheckinKind
    # "probing": one optional habit follow-up ("What did you do?"), at most once.
    phase: Literal["asking", "confirming", "probing", "ready", "cancelled"] = "asking"
    # The script's questions in order; fixed at the start (the daily habit question
    # is asked only on some days).
    questions: list[CheckinField] = Field(min_length=1, max_length=7)
    current_field: CheckinField | None = None
    # The last check-in's answers, sent by the caller; read only for "same as last
    # week" and for mentioning the last answer.
    previous: CheckinValues = Field(default_factory=CheckinValues)
    confirmed: CheckinValues = Field(default_factory=CheckinValues)
    pending: CheckinValues = Field(default_factory=CheckinValues)
    skipped_fields: list[CheckinField] = Field(default_factory=list, max_length=8)
    # "I don't know": left out, distinct from skipped, not asked again this check-in.
    unknown_fields: list[CheckinField] = Field(default_factory=list, max_length=8)
    # From the app (onboarding's memory_consent). Without it there are no habit
    # follow-ups and no habit notes.
    memory_consent: bool = False
    probe_asked: bool = False
    probe_topic: Literal["exercise", "sleep"] | None = None
    habit_notes: list[HabitNote] = Field(default_factory=list, max_length=5)

    @model_validator(mode="after")
    def consistent_state(self):
        if tuple(self.questions) not in SCRIPTS[self.kind]:
            raise ValueError("The questions must be one of this check-in's scripts")
        pending = self.pending.model_dump(exclude_none=True)
        if bool(pending) != (self.phase == "confirming"):
            raise ValueError("Only the confirming phase may contain pending values")
        if len(set(self.skipped_fields)) != len(self.skipped_fields):
            raise ValueError("Skipped fields must be unique")
        if self.phase in {"asking", "confirming"} and self.current_field is None:
            raise ValueError("An open question requires a current field")
        if self.phase in {"ready", "cancelled", "probing"} and self.current_field is not None:
            raise ValueError("This phase cannot have a current field")
        if self.current_field is not None and self.current_field not in self.questions:
            raise ValueError("The current field must be one of the script's questions")
        allowed = set(self.questions) | (
            {"diastolic_bp"} if "systolic_bp" in self.questions else set()
        )
        for values in (self.confirmed, self.pending):
            if set(values.model_dump(exclude_none=True)) - allowed:
                raise ValueError("Answers must belong to the script's questions")
        if set(self.skipped_fields) - allowed or set(self.unknown_fields) - allowed:
            raise ValueError("Skipped and unknown fields must belong to the script's questions")
        return self


def profile_update(state: CheckinState) -> HealthProfile:
    """The confirmed weekly answers that replace profile values; empty for a daily check-in."""
    if state.kind != "weekly":
        return HealthProfile()
    confirmed = state.confirmed.model_dump(exclude_none=True)
    return HealthProfile.model_validate(
        {field: value for field, value in confirmed.items() if field in HealthProfile.model_fields}
    )


class CheckinStartRequest(ApiModel):
    kind: CheckinKind
    previous: CheckinValues = Field(default_factory=CheckinValues)
    # The phone's own date (YYYY-MM-DD), so the daily habit question follows the
    # person's day rather than the server's time zone. Today on the server if absent.
    local_date: str | None = Field(default=None, min_length=10, max_length=10)
    # The person let Mochi remember the little things (onboarding's memory_consent).
    memory_consent: bool = False

    @field_validator("local_date")
    @classmethod
    def iso_date(cls, value: str | None) -> str | None:
        if value is not None and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValueError("local_date must look like 2026-10-24")
        return value


class CheckinTurnRequest(ApiModel):
    # "resume": the person tapped Continue after an emergency pause.
    action: Literal["reply", "confirm", "skip", "cancel", "resume"]
    state: CheckinState
    text: str | None = Field(default=None, min_length=1, max_length=2000)
    input_mode: Literal["text", "transcript"] = "text"

    @model_validator(mode="after")
    def action_payload(self):
        if self.action == "reply" and not (self.text or "").strip():
            raise ValueError("A reply requires nonempty text")
        if self.action != "reply" and self.text is not None:
            raise ValueError("Only the reply action accepts text")
        return self


class CheckinResponse(ApiModel):
    """The same shape as an onboarding turn: what to say, the state, and whether it's done."""

    schema_version: Literal["1.0"] = "1.0"
    state: CheckinState
    message: str = Field(min_length=1, max_length=1500)
    guide_mode: Literal["guided"] = "guided"
    provider_status: Literal["not_configured"] = "not_configured"
    voice_status: Literal["deferred", "available", "unavailable"] = "deferred"
    speech_hint: Literal["slower", "louder"] | None = None
    # The reply said something urgent is happening: the check-in is paused on the same
    # question. The app shows a "Call 911" button the person taps themselves, and
    # "Continue" (action "resume", or any reply) goes on where it stopped.
    emergency: bool = False
    # Weekly only: the confirmed answers as profile values (same fields, units and
    # ranges as onboarding). When ``complete`` is true, the app sets each non-null
    # field on the confirmed profile and reruns the forecast; null fields are left as
    # they are. Daily check-ins are history only, so this is always empty for them.
    profile_update: HealthProfile = Field(default_factory=HealthProfile)
    accepted_input_modes: list[Literal["text", "transcript"]] = Field(
        default_factory=lambda: ["text", "transcript"], min_length=2, max_length=2
    )
    mascot_events: list[MascotEvent] = Field(min_length=1, max_length=2)
    complete: bool
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Check-in history lives on the phone. The server keeps nothing.",
            "A check-in gives no score or medical advice; weekly answers update the profile.",
        ],
        max_length=5,
    )
