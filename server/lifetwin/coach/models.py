"""Stateless daily-plan contracts: the phone sends a snapshot, the server keeps nothing.

The plan loop (product meeting 2026-10-23): the phone sends the confirmed profile,
recent check-ins, habit notes (only with memory consent), goals and limits, and the
previous plan with per-item feedback. The server picks a new plan deterministically
from a cited catalogue, explains each change, and returns a replayable trace. The
phone stores the plan and sends it back next time; the server never stores it.

Card fields reuse the names of conversation-v2's ``Recommendation`` (``id``,
``lever``, ``title``, ``message``, ``based_on``, ``wellness_card``, ``source_title``,
``source_url``, ``causal_interpretation``) and add ``kind``, ``why`` and the
activity details. ``message`` is the card body Mochi says.
"""

from datetime import date
from typing import Annotated, Literal

from pydantic import AfterValidator, ConfigDict, Field, field_validator, model_validator

from lifetwin.core.models import ApiModel, HealthProfile, Wellbeing, WholeNumber
from lifetwin.onboarding.models import MascotEvent

ISO_DATE = r"^\d{4}-\d{2}-\d{2}$"


def _real_date(value: str | None) -> str | None:
    """A pattern match is not enough: 2026-02-30 must be refused, not crash later."""
    if value is not None:
        try:
            date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("Dates must be real calendar days, like 2026-10-24") from exc
    return value


RealDate = Annotated[str, Field(pattern=ISO_DATE), AfterValidator(_real_date)]
Words = Annotated[str, Field(min_length=1, max_length=80)]
Id = Annotated[str, Field(min_length=1, max_length=40, pattern=r"^[A-Za-z0-9_.:-]+$")]

# Limitation tags (docs/research/agentic-features.md §1). The app may send confirmed
# ones; the planner also reads them from habit notes and feedback reasons.
LimitTag = Literal["knee_pain", "walking_aid", "fall_risk", "cardio_caution", "seated_only"]
ItemKind = Literal["workout", "diet", "habit", "encourage"]
SlotId = Literal["move", "food", "habit", "cheer"]
TimeOfDay = Literal["morning", "afternoon", "evening"]
GeneralHealth = Literal["excellent", "very_good", "good", "fair", "poor"]
# Mochi's state follows effort and engagement, never the forecast (report §4).
MochiMood = Literal["happy", "proud", "cozy", "waiting", "concerned", "celebrate"]
# Same lever names as conversation-v2's recommendations; None for diet patterns,
# which are not model levers (weight is never a lever).
Lever = Literal[
    "quit_smoking",
    "vigorous_plus_60",
    "moderate_plus_90",
    "short_sleep_plus_1h",
    "sitting_minus_60_realistic",
    "keep_it_up",
]


class CoachProfile(HealthProfile):
    """The confirmed profile. Main's fields plus conversation-v2's extra model inputs,
    so either app version can send its profile. Height, weight and blood pressure are
    accepted but never used: weight is never a lever."""

    general_health: GeneralHealth | None = None
    hypertension: bool | None = None
    sitting_minutes_daily: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1439)
    moderate_minutes_weekly: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )
    vigorous_minutes_weekly: Annotated[int | None, WholeNumber] = Field(
        default=None, ge=0, le=10080
    )


class DaySummary(ApiModel):
    """One day of check-in history, in the on-device ``daily_logs`` names
    (codex/c-frequent-checkins) plus the check-in's ``wellbeing``."""

    date: RealDate
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    moderate_recreation_min: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    vigorous_recreation_min: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1440)
    sedentary_min_day: Annotated[int | None, WholeNumber] = Field(default=None, ge=0, le=1439)
    wellbeing: Wellbeing | None = None


READING_UNITS = {
    "systolic_bp": {"mmHg": (40, 300)},
    "diastolic_bp": {"mmHg": (20, 200)},
    "a1c": {"%": (3, 20)},
    "ldl": {"mg/dL": (10, 500), "mmol/L": (0.3, 13)},
}


class Reading(ApiModel):
    """A confirmed reading the phone keeps over time (owner ruling 2026-10-24): blood
    pressure, and A1c or LDL from uploaded documents. Used only for trends and the
    crisis line; never a diagnosis, never sent to a provider."""

    field: Literal["systolic_bp", "diastolic_bp", "a1c", "ldl"]
    value: float = Field(ge=0, le=500)
    unit: Literal["mmHg", "%", "mg/dL", "mmol/L"]
    date: RealDate
    source: Literal["typed", "voice", "apple_health", "document", "checkin"]

    @model_validator(mode="after")
    def unit_and_range(self):
        ranges = READING_UNITS[self.field]
        if self.unit not in ranges:
            raise ValueError("That unit does not fit this reading")
        low, high = ranges[self.unit]
        if not low <= self.value <= high:
            raise ValueError("That reading is outside the accepted range")
        return self


class CoachNote(ApiModel):
    """A habit note the phone keeps (conversation-v2's ``HabitNote`` fields), plus the
    phone's ``id``, a first ``name`` for a pet or person, and the day it was noted.
    Notes are data, never instructions."""

    model_config = ConfigDict(
        extra="forbid",
        strict=True,
        allow_inf_nan=False,
        populate_by_name=True,
        serialize_by_alias=True,
    )

    id: Id
    topic: Literal[
        "exercise", "sleep", "smoking", "sitting", "health", "food", "pet", "people", "schedule"
    ]
    kind: Words | None = None
    with_: Words | None = Field(default=None, alias="with")
    time_of_day: Words | None = None
    frequency: Words | None = None
    barrier: Words | None = None
    bedtime: Words | None = None
    wake_time: Words | None = None
    wakes_for: Words | None = None
    naps: Words | None = None
    smoked_years: Words | None = None
    tried_quitting: Literal["yes", "no"] | None = None
    quit_aid: Words | None = None
    quit_ago: Words | None = None
    feeling: Words | None = None
    concern: Words | None = None
    reading: Words | None = None
    estimate_for: Words | None = None
    estimate: Words | None = None
    source: Literal["said", "ai_helper"] = "said"
    # A pet's or person's first name ("Biscuit", "Maya"). Never sent to a provider.
    name: Annotated[str, Field(min_length=1, max_length=30)] | None = None
    noted_on: RealDate | None = None


FeedbackStatus = Literal["accepted", "edited", "dismissed", "done", "not_done"]


class ItemFeedback(ApiModel):
    item_id: SlotId
    status: FeedbackStatus
    # The person's own words ("it hurt my knee", "too cold out"). Read by the
    # deterministic planner; never sent to a provider.
    reason: Annotated[str, Field(min_length=1, max_length=300)] | None = None
    # "edited": what the person changed.
    minutes: Annotated[int | None, WholeNumber] = Field(default=None, ge=1, le=120)
    time_of_day: TimeOfDay | None = None


class PlanFeedback(ApiModel):
    revision_id: Id
    items: list[ItemFeedback] = Field(default_factory=list, max_length=4)

    @model_validator(mode="after")
    def one_per_item(self):
        ids = [item.item_id for item in self.items]
        if len(set(ids)) != len(ids):
            raise ValueError("One feedback entry per plan item")
        return self


class PlanItemRef(ApiModel):
    """The part of a plan item the phone sends back: what was chosen, not the words."""

    id: SlotId
    kind: ItemKind
    catalog_id: Id
    minutes: Annotated[int | None, WholeNumber] = Field(default=None, ge=1, le=120)
    time_of_day: TimeOfDay | None = None
    callback_note_id: Id | None = None


class PreviousPlan(ApiModel):
    revision_id: Id
    based_on: Id | None = None
    local_date: RealDate
    input_snapshot_id: Id
    items: list[PlanItemRef] = Field(min_length=1, max_length=4)

    @model_validator(mode="after")
    def one_per_slot(self):
        if len({item.id for item in self.items}) != len(self.items):
            raise ValueError("One previous item per slot")
        return self


class CoachPlanRequest(ApiModel):
    profile: CoachProfile = Field(default_factory=CoachProfile)
    checkins: list[DaySummary] = Field(default_factory=list, max_length=28)
    readings: list[Reading] = Field(default_factory=list, max_length=60)
    # May Mochi use the little things it remembers? false or null: notes are ignored.
    memory_consent: bool | None = None
    habit_notes: list[CoachNote] = Field(default_factory=list, max_length=20)
    # The person's own goal words ("keep up with my grandkids").
    goals: list[Words] = Field(default_factory=list, max_length=3)
    limits: list[LimitTag] = Field(default_factory=list, max_length=5)
    # Movement stays paused after a red flag until the person says they were cleared.
    movement_paused: bool = False
    previous_plan: PreviousPlan | None = None
    feedback: PlanFeedback | None = None
    # The latest revision the phone holds. Feedback for an older plan is refused (409).
    latest_revision_id: Id | None = None
    # What the person just said to Mochi, if anything: a question, "forget that", a
    # symptom. Read deterministically; never sent to a provider.
    said: Annotated[str, Field(min_length=1, max_length=500)] | None = None
    # Per-provider opt-in, conversation-v2's shape. Consent for one never covers another.
    outside_ai_consent: dict[Literal["claude", "muse"], bool] = Field(default_factory=dict)
    local_date: RealDate
    local_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")

    @field_validator("local_time")
    @classmethod
    def clock(cls, value: str | None) -> str | None:
        if value is not None:
            hours, minutes = (int(part) for part in value.split(":"))
            if hours > 23 or minutes > 59:
                raise ValueError("local_time must look like 09:30")
        return value

    @model_validator(mode="after")
    def feedback_needs_plan(self):
        if self.feedback is not None and self.previous_plan is None:
            raise ValueError("Feedback needs the plan it is about")
        if self.feedback is not None and self.latest_revision_id is None:
            raise ValueError("Feedback needs latest_revision_id, so stale feedback is refused")
        # Freshness: nothing may be dated after the phone's own day.
        if any(day.date > self.local_date for day in self.checkins):
            raise ValueError("Check-ins cannot be dated after local_date")
        if any(reading.date > self.local_date for reading in self.readings):
            raise ValueError("Readings cannot be dated after local_date")
        if len({day.date for day in self.checkins}) != len(self.checkins):
            raise ValueError("One check-in summary per day")
        if len({note.id for note in self.habit_notes}) != len(self.habit_notes):
            raise ValueError("Habit note ids must be unique")
        return self


class PlanItem(ApiModel):
    id: SlotId
    kind: ItemKind
    # The catalogue action (MASTER_PLAN "action ID"); same value as catalog_id.
    action_id: Id
    catalog_id: Id
    lever: Lever | None = None
    title: str = Field(min_length=1, max_length=80)
    # The card body Mochi says (conversation-v2's ``message``).
    message: str = Field(min_length=1, max_length=400)
    why: str = Field(min_length=1, max_length=300)
    minutes: int | None = None
    # When in the day to do it. Every item has one.
    time_of_day: TimeOfDay
    intensity: Literal["light", "moderate", "vigorous"] | None = None
    # Workouts: how the person does it. "supported_standing": holding a counter or chair.
    position: Literal["seated", "supported_standing", "standing", "water"] | None = None
    # Which model input the minutes would count toward, if the person logs them.
    counts_as: Literal["moderate", "vigorous", "none"] | None = None
    based_on: list[str] = Field(max_length=8)
    wellness_card: Literal["activity", "sitting", "sleep", "smoking"] | None = None
    source_title: str
    source_url: str
    # The one remembered note this item calls back to, if any.
    callback_note_id: str | None = None
    # What the person can do with it; the phone sends the choice back as feedback.
    controls: list[Literal["accept", "edit", "dismiss"]] = Field(
        default_factory=lambda: ["accept", "edit", "dismiss"]
    )
    reviewed_by: Literal["awaiting professional review"] = "awaiting professional review"
    causal_interpretation: Literal[False] = False


class InputSummary(ApiModel):
    """What the plan was built from: real observations only, never experiments."""

    # Hash of the observed inputs (profile, check-ins, notes used, goals, limits, pause).
    # One effective revision per snapshot per local day: the same snapshot on the same
    # day with nothing new reuses the plan.
    snapshot_id: str
    observed: list[str]
    # Asked about but not known. A day without a log is unknown, never zero.
    missing: list[str]
    # Known but too old to lean on (a last check-in more than a week ago).
    stale: list[str]
    days_logged_last_7: int
    # Hypothetical experiment profiles never feed the planner.
    experiments_used: Literal[False] = False


ChangeKind = Literal[
    "new", "kept", "swapped", "stepped_up", "shorter", "seated", "edited", "paused", "removed"
]


class PlanChange(ApiModel):
    item_id: SlotId
    change: ChangeKind
    # Plain words: "You said the walk hurt your knee, so today is a seated routine."
    explanation: str = Field(min_length=1, max_length=300)


class TraceFact(ApiModel):
    # Where the fact came from: "profile.age", "note:n1", "feedback.move", "checkins",
    # "said", "limits", "default".
    source: str
    value: str


class TraceStep(ApiModel):
    item_id: SlotId | Literal["plan"]
    facts: list[TraceFact]
    rule: str
    evidence: str
    action: str


class MemoryInstruction(ApiModel):
    """What the app should do to its notebook after the person confirms."""

    action: Literal["forget", "forget_all"]
    note_ids: list[str] = Field(default_factory=list)
    confirm_prompt: str
    # "forget_all" asks twice (report §5).
    confirmations_needed: Literal[1, 2] = 1


class CoachPlanResponse(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    status: Literal["ok", "emergency"]
    revision_id: str | None
    based_on: str | None
    local_date: str
    inputs: InputSummary | None
    # "general": too little is known, so this is a labelled general plan.
    plan_type: Literal["personal", "general"] | None
    # True when nothing new arrived since today's plan: the same revision comes back.
    reused_previous: bool = False
    # A short question that would make the next plan more personal.
    clarify: str | None = None
    # "bp_crisis": a recent blood pressure reading at or above 180/120. The app shows
    # "Call my doctor" and a "Call 911" button the person taps themselves.
    alert: Literal["bp_crisis"] | None = None
    # Plain notes from the readings history ("your last few readings were higher").
    notices: list[str] = Field(default_factory=list, max_length=3)
    # Mochi's spoken lines, in order: the reply to what was said, the plan, the changes.
    lines: list[str] = Field(min_length=1, max_length=10)
    reply: str | None = None
    items: list[PlanItem] = Field(max_length=4)
    changes: list[PlanChange]
    trace: list[TraceStep]
    mood: MochiMood
    mascot_events: list[MascotEvent] = Field(min_length=1, max_length=2)
    emergency: bool = False
    movement_paused: bool = False
    memory_instruction: MemoryInstruction | None = None
    phrased_by: Literal["templates", "muse"] = "templates"
    provider_status: Literal[
        "not_requested", "not_configured", "used", "fallback", "unavailable", "daily_cap"
    ] = "not_requested"
    causal_interpretation: Literal[False] = False
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Ideas follow public-health guidance; they are not medical advice and promise "
            "no benefit. The activity and food lists await professional review.",
            "The server keeps nothing. The plan, notes and history stay on your phone.",
            "Plans refresh when the app is opened or resumed; nothing runs in the background.",
        ],
        max_length=5,
    )
