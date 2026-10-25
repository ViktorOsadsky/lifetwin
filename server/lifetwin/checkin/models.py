"""Stateless check-in contracts: the caller holds the state and the previous answers.

Check-in history lives only on the phone (owner ruling); the server stores nothing,
so the client sends the previous answers with every turn. Weekly answers come back
as ``profile_update`` for the app to apply to the profile; daily answers are history.
Quick answers come back as ``daily_logs``: partial rows in the on-device model's
daily_logs names and units, for the app to merge into the day's row.
"""

import re
from datetime import date, timedelta
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator

from lifetwin.checkin.scripts import PAIRS, SCRIPTS, CheckinField, CheckinKind, QuickTopic
from lifetwin.core.models import ApiModel, CheckinValues, HealthProfile, WholeNumber
from lifetwin.onboarding.models import HabitNote, MascotEvent

ISO_DATE = r"\d{4}-\d{2}-\d{2}"
DayWord = Literal["today", "yesterday"]
SUGGESTIBLE = {"sleep_hours_last_night", "sleep_hours_night_before"}


class CheckinState(ApiModel):
    kind: CheckinKind
    # "probing": one optional habit follow-up ("What did you do?"), at most once.
    phase: Literal["asking", "confirming", "probing", "ready", "cancelled"] = "asking"
    # The script's questions in order; fixed at the start (the daily habit question
    # is asked only on some days).
    questions: list[CheckinField] = Field(min_length=1, max_length=9)
    current_field: CheckinField | None = None
    # The last check-in's answers, sent by the caller; read only for "same as last
    # week" and for mentioning the last answer.
    previous: CheckinValues = Field(default_factory=CheckinValues)
    confirmed: CheckinValues = Field(default_factory=CheckinValues)
    pending: CheckinValues = Field(default_factory=CheckinValues)
    # Weekly only: answers said early, beside another answer. Each is read back when its
    # own question comes up, which is then not asked.
    early: CheckinValues = Field(default_factory=CheckinValues)
    skipped_fields: list[CheckinField] = Field(default_factory=list, max_length=9)
    # "I don't know": left out, distinct from skipped, not asked again this check-in.
    unknown_fields: list[CheckinField] = Field(default_factory=list, max_length=9)
    # From the app (onboarding's memory_consent). Without it there are no habit
    # follow-ups and no habit notes.
    memory_consent: bool = False
    probe_asked: bool = False
    # Quick and daily: Mochi already added the soft "please call 911" line after a low
    # mood answer, so it is not said again in this check-in.
    care_line_shown: bool = False
    # The care reply ended with "keep going or stop here?": the next reply answers it.
    care_question_open: bool = False
    probe_topic: Literal["exercise", "sleep"] | None = None
    habit_notes: list[HabitNote] = Field(default_factory=list, max_length=5)
    # Quick only. The phone's date when the check-in started, and the day the activity
    # and sitting questions are about (the app's choice: "today" in the evening).
    local_date: str | None = Field(default=None, pattern=ISO_DATE)
    activity_day: DayWord | None = None
    # Quick only: Apple Health values the person has not confirmed yet. Each is
    # offered in its question ("Does that sound right?") when it comes up; never saved
    # without the yes to the read-back at the end.
    suggested: CheckinValues = Field(default_factory=CheckinValues)
    suggested_activity_min: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    # Apple Health's value is offered in the open question (quick), or the
    # held minutes below are Apple Health's exercise minutes.
    from_health: bool = False
    # The activity question is down to one pace: a follow-up ("And anything easier?"),
    # or "pottered in the garden all afternoon" asked how long.
    one_pace: bool = False
    # An activity duration whose pace Mochi asked about ("about 20 minutes": out of
    # breath, or easy?). Apple Health's exercise minutes start here too.
    held_minutes: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=10080)
    # Quick and daily only: the answers in ``pending`` that the check question is about
    # ("Did I hear 15 hours of sleep? That's a lot for one night..."). They are read back
    # with ``phase`` "confirming" and the question still open (``current_field``).
    checking: list[CheckinField] = Field(default_factory=list, max_length=2)
    # Quick and daily only: the open question was reopened ("go back"), so a new answer
    # replaces the heard one in full (both activity paces, not just the follow-up).
    reopened: bool = False
    # From the app (the profile's age): which everyday examples the questions use.
    # "older" (60 and over) keeps gardening and pottering about; "younger" uses the gym,
    # running, cycling, the commute and desk time; null uses examples for anyone.
    age_band: Literal["younger", "older"] | None = None

    @model_validator(mode="after")
    def consistent_state(self):
        if tuple(self.questions) not in SCRIPTS[self.kind]:
            raise ValueError("The questions must be one of this check-in's scripts")
        pending = self.pending.model_dump(exclude_none=True)
        if self.kind == "weekly":
            # Weekly: each answer is read back alone, so pending means a read-back.
            if bool(pending) != (self.phase == "confirming"):
                raise ValueError("Only the confirming phase may contain pending values")
            if self.checking:
                raise ValueError("Only quick and daily check-ins have a check question")
        else:
            # Quick and daily: answers are heard (pending) until the one read-back at the
            # end ("confirming" without a current field), or a check question about one.
            if pending and self.phase in {"ready", "cancelled"}:
                raise ValueError("A finished check-in has nothing pending")
            if self.phase == "confirming" and not pending:
                raise ValueError("A read-back needs the answers it reads back")
            if bool(self.checking) != (
                self.phase == "confirming" and self.current_field is not None
            ):
                raise ValueError("A read-back with an open question is a check question")
            if set(self.checking) - set(pending):
                raise ValueError("A check question is about pending answers")
        if len(set(self.skipped_fields)) != len(self.skipped_fields):
            raise ValueError("Skipped fields must be unique")
        if self.phase == "asking" and self.current_field is None:
            raise ValueError("An open question requires a current field")
        if self.phase == "confirming" and self.current_field is None and self.kind == "weekly":
            raise ValueError("A weekly read-back is about the open question")
        if self.phase in {"ready", "cancelled", "probing"} and self.current_field is not None:
            raise ValueError("This phase cannot have a current field")
        if self.current_field is not None and self.current_field not in self.questions:
            raise ValueError("The current field must be one of the script's questions")
        allowed = set(self.questions) | {
            second for first, second in PAIRS.items() if first in self.questions
        }
        for values in (self.confirmed, self.pending):
            if set(values.model_dump(exclude_none=True)) - allowed:
                raise ValueError("Answers must belong to the script's questions")
        if set(self.skipped_fields) - allowed or set(self.unknown_fields) - allowed:
            raise ValueError("Skipped and unknown fields must belong to the script's questions")
        quick = self.kind == "quick"
        if quick != (self.local_date is not None and self.activity_day is not None):
            raise ValueError("A quick check-in (and only one) has a local date and activity day")
        suggested = set(self.suggested.model_dump(exclude_none=True))
        if suggested - (SUGGESTIBLE & set(self.questions)):
            raise ValueError("Suggested values must be for this check-in's sleep questions")
        if self.suggested_activity_min is not None and "vigorous_recreation_min" not in (
            self.questions
        ):
            raise ValueError("Apple Health's exercise minutes need the activity question")
        offered = (
            self.kind != "weekly"
            and self.phase == "asking"
            and self.current_field is not None
            and getattr(self.suggested, self.current_field, None) is not None
        )
        if self.from_health and not (
            self.phase == "confirming" or self.held_minutes is not None or offered
        ):
            raise ValueError(
                "Only a read-back, an offered value or held minutes can come from Apple Health"
            )
        return self


def _shift(day: str, days: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=days)).isoformat()


# A weekly check-in's confirmed answers as profile values. HealthProfile now holds the
# on-device model's activity and sitting inputs itself, so check-ins and changes return
# the same shape.
ProfileUpdate = HealthProfile


class DailyLogPart(ApiModel):
    """Part of one ``daily_logs`` row, in the package's names and units. Null means
    not answered in this check-in. The app adds ``workday`` and keeps a day for the
    model only once all four values are known (see app/lib/checkin/README.md)."""

    date: str = Field(pattern=ISO_DATE)
    # The night before ``date`` (the person woke up on ``date``), in hours.
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    vigorous_recreation_min: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    moderate_recreation_min: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    sedentary_min_day: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1439)


def daily_logs(state: CheckinState) -> list[DailyLogPart]:
    """The confirmed quick answers as daily_logs rows, oldest first; empty otherwise."""
    if state.kind != "quick" or state.local_date is None:
        return []
    done = state.confirmed
    today = state.local_date
    activity = today if state.activity_day == "today" else _shift(today, -1)
    rows: dict[str, dict] = {}

    def put(day: str, name: str, value) -> None:
        if value is not None:
            rows.setdefault(day, {"date": day})[name] = value

    put(today, "sleep_hours", done.sleep_hours_last_night)
    put(_shift(today, -1), "sleep_hours", done.sleep_hours_night_before)
    for name in ("vigorous_recreation_min", "moderate_recreation_min", "sedentary_min_day"):
        put(activity, name, getattr(done, name))
    return [DailyLogPart.model_validate(rows[day]) for day in sorted(rows)]


def profile_update(state: CheckinState) -> ProfileUpdate:
    """The confirmed weekly answers that replace profile values; empty for other kinds.

    "Not sure" (``unknown``) never replaces what the profile already knows, so it is
    left out: a null field leaves the profile's value as it is.
    """
    if state.kind != "weekly":
        return ProfileUpdate()
    confirmed = state.confirmed.model_dump(exclude_none=True)
    return ProfileUpdate.model_validate(
        {
            field: value
            for field, value in confirmed.items()
            if field in ProfileUpdate.model_fields and value != "unknown"
        }
    )


class QuickSuggestions(ApiModel):
    """Apple Health values for the quick check-in, read on the phone and not yet
    confirmed. Mochi offers each in its question; nothing is kept without the final yes."""

    sleep_hours_last_night: float | None = Field(default=None, ge=0, le=24)
    sleep_hours_night_before: float | None = Field(default=None, ge=0, le=24)
    # Apple Health's exercise minutes on the activity day. They can't say which were out
    # of breath, so Mochi asks about the pace instead of the minutes.
    activity_minutes: Annotated[int | None, WholeNumber] = Field(default=None, ge=1, le=1440)


class QuickPlan(ApiModel):
    """What the quick check-in asks, chosen on the phone from the stored history."""

    # One to three of these; Mochi asks them in this order whatever the order here.
    topics: list[QuickTopic] = Field(
        default_factory=lambda: ["sleep", "activity", "sitting"], max_length=3
    )
    activity_day: DayWord = "yesterday"
    # "Yesterday was a bit of a blank": ask the night before's sleep, optionally, last.
    catch_up: bool = False
    suggested: QuickSuggestions = Field(default_factory=QuickSuggestions)

    @model_validator(mode="after")
    def something_to_ask(self):
        if len(set(self.topics)) != len(self.topics):
            raise ValueError("Each quick topic may appear once")
        if not self.topics and not self.catch_up:
            raise ValueError("A quick check-in needs at least one question")
        if self.suggested.sleep_hours_last_night is not None and "sleep" not in self.topics:
            raise ValueError("Last night's sleep is suggested but not asked")
        if self.suggested.sleep_hours_night_before is not None and not self.catch_up:
            raise ValueError("The night before's sleep is suggested but not asked")
        if self.suggested.activity_minutes is not None and "activity" not in self.topics:
            raise ValueError("Exercise minutes are suggested but activity is not asked")
        return self


class CheckinStartRequest(ApiModel):
    kind: CheckinKind
    previous: CheckinValues = Field(default_factory=CheckinValues)
    # The phone's own date (YYYY-MM-DD), so the daily habit question follows the
    # person's day rather than the server's time zone. Today on the server if absent.
    local_date: str | None = Field(default=None, min_length=10, max_length=10)
    # The person let Mochi remember the little things (onboarding's memory_consent).
    memory_consent: bool = False
    # The profile's age, if known: only which everyday examples Mochi uses (60 and over:
    # gardening and pottering about; younger: the gym, running, the commute, desk time).
    age: Annotated[int | None, WholeNumber] = Field(default=None, ge=18, le=120)
    # Quick only: what to ask (the defaults ask sleep, activity and sitting).
    quick: QuickPlan | None = None

    @model_validator(mode="after")
    def plan_for_quick(self):
        if self.quick is not None and self.kind != "quick":
            raise ValueError("Only a quick check-in takes a quick plan")
        return self

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
    # Per-provider opt-in to outside-AI wording of the care reply, e.g. {"claude": true}.
    # Consent for one provider never covers another. Empty: Mochi's own words.
    outside_ai_consent: dict[Literal["claude", "muse"], bool] = Field(default_factory=dict)

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
    # "open_ideas": the person asked for ideas; the app shows today's idea. The state is
    # unchanged and the same question comes back in the message.
    client_action: Literal["open_ideas"] | None = None
    # The reply said something urgent is happening: the check-in is paused on the same
    # question. The app shows a "Call 911" button the person taps themselves, and
    # "Continue" (action "resume", or any reply) goes on where it stopped.
    emergency: bool = False
    # Weekly only: the confirmed answers as profile values (same fields, units and
    # ranges as onboarding). When ``complete`` is true, the app sets each non-null
    # field on the confirmed profile and reruns the forecast; null fields are left as
    # they are. Daily check-ins are history only, so this is always empty for them.
    profile_update: ProfileUpdate = Field(default_factory=ProfileUpdate)
    # Quick only: the confirmed answers as parts of daily_logs rows (one row, or two
    # when the activity is yesterday's or the catch-up was answered), oldest first. When
    # ``complete`` is true the app merges each non-null value into its date's row; a row
    # goes to the model once all four values are known. Empty for other kinds.
    daily_logs: list[DailyLogPart] = Field(default_factory=list, max_length=2)
    accepted_input_modes: list[Literal["text", "transcript"]] = Field(
        default_factory=lambda: ["text", "transcript"], min_length=2, max_length=2
    )
    mascot_events: list[MascotEvent] = Field(min_length=1, max_length=2)
    complete: bool
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Check-in history lives on the phone. The server keeps nothing.",
            "A check-in gives no score or medical advice; weekly answers update the profile.",
            "Quick answers are parts of daily logs; the app keeps a day once it is complete.",
        ],
        max_length=5,
    )
