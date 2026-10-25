"""Stateless habit contracts: the phone stores the habit records and sends them each time.

Like check-ins, the server keeps nothing. Every request carries the person's age
(habits are for adults: under 18 gets ``age_not_supported`` and no health framing),
the phone's own date, and the habit records the phone holds. At most 2 habits are
active at once. A habit result never feeds a health score: behaviour reaches the
twin only through the measured inputs (sleep, activity, sitting, smoking).
"""

from datetime import date
from typing import Annotated, Literal

from pydantic import AfterValidator, Field, field_validator, model_validator

from lifetwin.core.models import ApiModel, HealthProfile, WholeNumber
from lifetwin.habits.answers import HabitResult
from lifetwin.habits.catalogue import CATALOGUE, CatalogId, Lever, Pillar
from lifetwin.habits.safety import SafetyKind

MAX_ACTIVE = 2
ADULT_AGE = 18


def _real_date(value: str) -> str:
    try:
        date.fromisoformat(value)
    except ValueError:
        raise ValueError("Dates must be real days, like 2026-10-24") from None
    return value


LocalDate = Annotated[
    str,
    Field(pattern=r"^\d{4}-\d{2}-\d{2}$", min_length=10, max_length=10),
    AfterValidator(_real_date),
]
HabitText = Annotated[str, Field(min_length=1, max_length=80)]
HabitStatus = Literal["proposed", "active", "dismissed", "graduated"]
HabitSource = Literal["said", "model_lever", "guideline"]
Mood = Literal["happy", "proud", "celebrate", "cozy", "concerned"]


def _clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = " ".join(value.split())
    if not any(ch.isalpha() for ch in cleaned):
        raise ValueError("Habit text needs some words")
    return cleaned


class HabitRecord(ApiModel):
    """One habit as the phone stores it (the design's ``Habit``)."""

    id: str = Field(pattern=r"^[a-z0-9_-]{1,48}$")
    catalog_id: CatalogId
    pillar: Pillar
    anchor: HabitText
    tiny_action: HabitText
    why_words: HabitText | None = None
    lever: Lever | None = None
    source: HabitSource
    status: HabitStatus
    started_on: LocalDate | None = None
    dismissed_until: LocalDate | None = None

    @field_validator("anchor", "tiny_action", "why_words")
    @classmethod
    def words(cls, value: str | None) -> str | None:
        return _clean_text(value)

    @model_validator(mode="after")
    def consistent(self):
        habit = CATALOGUE[self.catalog_id]
        if self.pillar != habit.pillar:
            raise ValueError("The pillar must match the catalogue habit")
        if self.lever not in (None, habit.lever):
            raise ValueError("The lever must match the catalogue habit")
        if self.status in {"active", "graduated"} and self.started_on is None:
            raise ValueError("An active habit needs started_on")
        if self.status == "dismissed" and self.dismissed_until is None:
            raise ValueError("A dismissed habit needs dismissed_until")
        if self.status != "dismissed" and self.dismissed_until is not None:
            raise ValueError("Only a dismissed habit has dismissed_until")
        return self


class HabitContext(ApiModel):
    age: Annotated[int, WholeNumber] = Field(ge=0, le=120)
    local_date: LocalDate
    habits: list[HabitRecord] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def habit_limits(self):
        ids = [habit.id for habit in self.habits]
        if len(set(ids)) != len(ids):
            raise ValueError("Habit ids must be unique")
        if sum(habit.status == "active" for habit in self.habits) > MAX_ACTIVE:
            raise ValueError(f"At most {MAX_ACTIVE} habits can be active")
        if sum(habit.status == "proposed" for habit in self.habits) > 1:
            raise ValueError("Only one habit can be proposed at a time")
        return self


class HabitProposeRequest(HabitContext):
    # Only smoking_status, exercise_minutes_weekly and sleep_hours are read, for ages 30+.
    profile: HealthProfile = Field(default_factory=HealthProfile)
    sitting_minutes_daily: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    # The person's own words, newest first: habit notes and recent check-in text.
    # Read only with memory consent.
    own_words: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(
        default_factory=list, max_length=5
    )
    memory_consent: bool = False

    @model_validator(mode="after")
    def consent_for_words(self):
        if self.own_words and not self.memory_consent:
            raise ValueError("own_words are read only with memory_consent")
        return self


class HabitUpdateRequest(HabitContext):
    action: Literal["accept", "edit", "dismiss"]
    habit_id: str = Field(pattern=r"^[a-z0-9_-]{1,48}$")
    # Edit only: the person's own words for any of the three parts.
    anchor: HabitText | None = None
    tiny_action: HabitText | None = None
    why_words: HabitText | None = None

    @field_validator("anchor", "tiny_action", "why_words")
    @classmethod
    def words(cls, value: str | None) -> str | None:
        return _clean_text(value)

    @model_validator(mode="after")
    def edit_payload(self):
        edits = [self.anchor, self.tiny_action, self.why_words]
        if self.action == "edit" and all(value is None for value in edits):
            raise ValueError("An edit needs anchor, tiny_action or why_words")
        if self.action != "edit" and any(value is not None for value in edits):
            raise ValueError("Only an edit accepts new words")
        return self


class HabitQuestionRequest(HabitContext):
    # "ask": the one habit question for today's check-in. "reply" reads the answer;
    # "skip" leaves the day unknown.
    action: Literal["ask", "reply", "skip"]
    habit_id: str | None = Field(default=None, pattern=r"^[a-z0-9_-]{1,48}$")
    text: str | None = Field(default=None, min_length=1, max_length=500)

    @model_validator(mode="after")
    def question_payload(self):
        if self.action in {"reply", "skip"} and self.habit_id is None:
            raise ValueError("A reply or skip needs habit_id")
        if self.action == "reply" and not (self.text or "").strip():
            raise ValueError("A reply needs nonempty text")
        if self.action != "reply" and self.text is not None:
            raise ValueError("Only a reply accepts text")
        return self


class HabitWeekRequest(ApiModel):
    age: Annotated[int, WholeNumber] = Field(ge=0, le=120)
    local_date: LocalDate
    habit: HabitRecord
    # One result per phone-local day; a day that is absent is unknown, never "not done".
    results: dict[LocalDate, HabitResult] = Field(default_factory=dict, max_length=400)


class _HabitReply(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    message: str = Field(min_length=1, max_length=1000)
    mood: Mood
    # An emergency line is on screen: the app shows a "Call 911" button the person taps.
    emergency: bool = False
    safety: SafetyKind | None = None
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Habit records live on the phone. The server keeps nothing.",
            "A habit never changes a health score or forecast by itself.",
        ],
        max_length=5,
    )


class HabitProposeResponse(_HabitReply):
    # proposed: a new idea, asked first. pending: the one already proposed, again.
    status: Literal["proposed", "pending", "at_limit", "nothing_new", "age_not_supported", "safety"]
    proposal: HabitRecord | None = None
    supports: str | None = None  # "This supports your Move." Never points or years.
    source_title: str | None = None
    source_url: str | None = None


class HabitUpdateResponse(_HabitReply):
    status: Literal["active", "proposed", "dismissed", "at_limit", "age_not_supported", "safety"]
    habit: HabitRecord | None = None


class HabitQuestionResponse(_HabitReply):
    status: Literal[
        "asking",
        "answered",
        "not_understood",
        "skipped",
        "no_active_habit",
        "age_not_supported",
        "safety",
    ]
    habit_id: str | None = None
    question: str | None = None
    # Answered only: the day's result. Skipped or not understood: null (unknown).
    result: HabitResult | None = None


class HabitWeekResponse(_HabitReply):
    status: Literal["ok", "age_not_supported"]
    habit_id: str
    # Null only when the age is not supported.
    week_start: LocalDate | None = None
    habit_days_this_week: int | None = Field(default=None, ge=0, le=7)
    good_week_this_week: bool | None = None
    # Over all the results sent, never in a row; nothing ever resets to zero.
    good_weeks_total: int | None = Field(default=None, ge=0)
    days_for_good_week: Literal[4] = 4
    ignored_future_days: int = Field(default=0, ge=0)
