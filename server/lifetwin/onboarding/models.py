"""Stateless mascot intake contracts; profiles are never stored server-side."""

from typing import Annotated, Literal

from pydantic import ConfigDict, Field, model_validator

from lifetwin.core.models import ApiModel, HealthProfile

ProfileField = Literal[
    "age",
    "sex",
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "smoking_status",
    "alcohol_drinks_weekly",
    "diabetes",
    "systolic_bp",
    "diastolic_bp",
    "general_health",
    "hypertension_diagnosed",
    "sedentary_min_day",
    "moderate_recreation_min_week",
    "vigorous_recreation_min_week",
]
FIELDS: tuple[ProfileField, ...] = tuple(HealthProfile.model_fields)
FIELD_COUNT = len(FIELDS)

# Short follow-ups that learn the habit behind an answer (catalogue: probes.py).
ProbeId = Literal[
    "activity",
    "inactive_barrier",
    "smoking_history",
    "quit_story",
    "sleep_pattern",
    "sitting_activities",
    "health_feeling",
]
HabitTopic = Literal["exercise", "sleep", "smoking", "sitting", "health"]
Words = Annotated[str, Field(min_length=1, max_length=80)]

# The on-device model's eleven inputs, with the package's exact ids. Height and
# weight together give bmi.
ModelInput = Literal[
    "age",
    "sex_nhanes",
    "bmi",
    "smoking_status",
    "diabetes_diagnosed",
    "hypertension_diagnosed",
    "general_health",
    "sleep_hours",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
    "sedentary_min_day",
]


class HabitNote(ApiModel):
    """What the person said about a habit, in short words taken from their reply.

    Notes are never health values and are never used by the model. They are returned
    to the app, which keeps them on the phone; the server stores nothing.
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=True,
        allow_inf_nan=False,
        populate_by_name=True,
        serialize_by_alias=True,
    )

    topic: HabitTopic
    kind: Words | None = None  # "walking and swimming", "tv and reading"
    with_: Words | None = Field(default=None, alias="with")  # "dog", "friends", "a class"
    time_of_day: Words | None = None  # "morning", "after dinner"
    frequency: Words | None = None  # "daily", "twice a week", "weekends"
    barrier: Words | None = None  # "knee pain", "cold weather", "fear of falling"
    bedtime: Words | None = None  # as said: "10", "11 pm", "midnight"
    wake_time: Words | None = None
    wakes_for: Words | None = None  # "bathroom", "back pain", "worry"
    naps: Words | None = None  # "after lunch", "yes", "no"
    smoked_years: Words | None = None
    tried_quitting: Literal["yes", "no"] | None = None
    quit_aid: Words | None = None  # "patch", "nicotine gum"
    quit_ago: Words | None = None  # "15 years"
    feeling: Words | None = None  # how they feel about their health: "good", "worried"
    concern: Words | None = None  # "balance", "memory", "knee pain"
    reading: Words | None = None  # a blood pressure reading, kept as context only
    # A value set from a simpler question ("most of the day sitting") is an estimate.
    estimate_for: ProfileField | None = None
    estimate: Words | None = None
    # "said": deterministic words from the reply; "ai_helper": the opt-in AI helper
    # quoted the reply (each value is an exact span of the person's words).
    source: Literal["said", "ai_helper"] = "said"


class ConversationState(ApiModel):
    # "remembering": Mochi asked whether it may remember the little things (memory
    # consent); "offering": Apple Health was offered; "probing": a habit follow-up is open.
    phase: Literal[
        "idle",
        "remembering",
        "asking",
        "offering",
        "probing",
        "confirming",
        # "missing": the intake is through, some of the estimate's answers are missing, and
        # Mochi asked once whether to answer them now ("Yes" asks only those; anything else ends).
        "missing",
        "ready",
        "cancelled",
    ] = "idle"
    confirmed_profile: HealthProfile = Field(default_factory=HealthProfile)
    pending_profile: HealthProfile = Field(default_factory=HealthProfile)
    current_field: ProfileField | None = None
    # Declined ("skip", "rather not say").
    skipped_fields: list[ProfileField] = Field(default_factory=list, max_length=FIELD_COUNT)
    # The person doesn't know. Distinct from skipped and from a value; never asked
    # again in the session unless the person brings it up.
    unknown_fields: list[ProfileField] = Field(default_factory=list, max_length=FIELD_COUNT)
    # Confirmed values that came from a simpler question (an estimate the person agreed to).
    estimated_fields: list[ProfileField] = Field(default_factory=list, max_length=FIELD_COUNT)
    # The simpler question is open for this field (after "I don't know"), and the
    # fields it was ever asked for (asked once each).
    proxy_field: ProfileField | None = None
    proxies_asked: list[ProfileField] = Field(default_factory=list, max_length=FIELD_COUNT)
    # What the person said to the simpler question, while its estimate is read back.
    pending_estimate: Words | None = None
    # Steering: a topic the person brought up ("I walk my dog") is asked next, with
    # their own words as the bridge ("You mentioned you walk your dog every morning.").
    steer_field: ProfileField | None = None
    steer_lead: Annotated[str, Field(min_length=1, max_length=200)] | None = None
    health_offered: bool = False
    # The Apple Health offer was repeated once after an unclear reply; never twice.
    health_reasked: bool = False
    current_probe: ProbeId | None = None
    probes_asked: list[ProbeId] = Field(default_factory=list, max_length=7)
    habit_notes: list[HabitNote] = Field(default_factory=list, max_length=10)
    # May Mochi remember the little things (habit notes)? Asked first. false: no habit
    # notes are kept or returned, no habit follow-ups, and suggestions use only the
    # confirmed profile. null: not asked (a state built by the caller).
    memory_consent: bool | None = None
    # Chosen at the start so Mochi's wording varies between sessions but stays the
    # same for the same state (reproducible tests).
    seed: int = Field(default=0, ge=0, le=2**31)
    # The last reply was small talk: one friendly turn, then back to the question.
    small_talk: bool = False
    # "Answer N more questions": only these fields are asked; every other field counts as
    # settled (never asked again). Set by the app with the saved profile in
    # `confirmed_profile`, or by a "yes" in the missing phase. Null: the whole intake.
    ask_only: list[ProfileField] | None = Field(default=None, max_length=FIELD_COUNT)
    # The end-of-intake offer of the missing answers was made (it is made once, never again).
    missing_offered: bool = False
    # Mochi asked "Just to check: is that a yes?" once for the open yes/no question. An
    # unclear reply to that check is a no (nothing is consented or saved); never a loop.
    yes_no_checked: bool = False

    @model_validator(mode="after")
    def consistent_state(self):
        pending = self.pending_profile.model_dump(exclude_none=True)
        if bool(pending) != (self.phase == "confirming"):
            raise ValueError("Only the confirming phase may contain pending values")
        for name in (
            "skipped_fields",
            "unknown_fields",
            "estimated_fields",
            "probes_asked",
            "proxies_asked",
        ):
            values = getattr(self, name)
            if len(set(values)) != len(values):
                raise ValueError("Skipped, unknown, estimated and probe lists must be unique")
        if self.phase == "asking" and self.current_field is None:
            raise ValueError("An asking state requires a current field")
        if self.phase in {
            "ready",
            "cancelled",
            "idle",
            "remembering",
            "offering",
            "probing",
            "missing",
        } and (self.current_field is not None):
            raise ValueError("This phase cannot have a current field")
        if (self.phase == "probing") != (self.current_probe is not None):
            raise ValueError("Only the probing phase has a current probe")
        return self


class TurnRequest(ApiModel):
    # "resume": the person tapped Continue after an emergency pause.
    action: Literal["start", "reply", "confirm", "correct", "skip", "cancel", "import", "resume"]
    state: ConversationState = Field(default_factory=ConversationState)
    text: str | None = Field(default=None, min_length=1, max_length=2000)
    input_mode: Literal["text", "transcript"] = "text"
    field: ProfileField | None = None
    provider_consent: bool = False
    # Per-provider opt-in to outside-AI wording (separate from the AI helper above),
    # e.g. {"claude": true}. Consent for one provider never covers another.
    outside_ai_consent: dict[Literal["claude", "muse"], bool] = Field(default_factory=dict)
    # "import": values the user already confirmed one by one on the phone
    # (e.g. Apple Health read-back). Validated like any profile; no source is sent.
    values: HealthProfile | None = None
    # Where imported values came from, for the mascot's words only. Upload is a
    # separate source from Apple Health (docs/document-upload.md).
    import_source: Literal["apple_health", "document", "wristband"] = "apple_health"

    @model_validator(mode="after")
    def action_payload(self):
        if self.action == "import" and not (
            self.values and self.values.model_dump(exclude_none=True)
        ):
            raise ValueError("An import requires at least one confirmed value")
        if self.action != "import" and self.values is not None:
            raise ValueError("Only the import action accepts values")
        if self.action in {"reply", "correct"} and not (self.text or "").strip():
            raise ValueError("A reply or correction requires nonempty text")
        if self.action not in {"reply", "correct"} and self.text is not None:
            raise ValueError("Only reply and correct actions accept text")
        if self.field is not None and self.action not in {"correct", "skip"}:
            raise ValueError("An explicit field is accepted only for correction or skipping")
        return self


class MascotEvent(ApiModel):
    # "concerned": a calm pose beside the emergency line, never a cheerful one.
    state: Literal["asking", "thinking", "confirming", "celebrating", "idle", "concerned"]
    caption: str = Field(min_length=1, max_length=1500)


class ModelProfile(ApiModel):
    """The on-device model's ``profile`` map, built only from confirmed answers.

    Keys and codes are the package's own (model_handoff/lifetwin_on_device). A null
    is a missing input. Height and weight are both set or both null, since the
    package derives bmi from the pair.
    """

    age: int | None = None
    sex_nhanes: Literal[1, 2] | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    smoking_status: Literal[0, 1, 2] | None = None
    diabetes_diagnosed: Literal[0, 1] | None = None
    hypertension_diagnosed: Literal[0, 1] | None = None
    general_health: Literal[1, 2, 3, 4, 5] | None = None
    sleep_hours: float | None = None
    vigorous_recreation_min_week: int | None = None
    moderate_recreation_min_week: int | None = None
    sedentary_min_day: int | None = None


class ModelInputs(ApiModel):
    """Which model inputs are known. With anything missing the model gives no number.

    ``status`` is "ready" only when all eleven inputs are known and age is 35-79;
    otherwise the app shows "still learning" (or the age message) instead of a number.
    """

    status: Literal["ready", "still_learning", "unsupported_age"]
    profile: ModelProfile
    # Every input without a usable value (includes unknown and skipped).
    missing: list[ModelInput] = Field(max_length=11)
    unknown: list[ModelInput] = Field(max_length=11)
    skipped: list[ModelInput] = Field(max_length=11)
    # Known inputs that rest on a simpler question (an estimate the person agreed to).
    estimated: list[ModelInput] = Field(max_length=11)


class CharacterHints(ApiModel):
    """Coarse, kind hints for the twin's look; null until there is something to go on.

    mood (how the person says they feel): "good", "okay", "not_great" (the check-in
    wellbeing scale). energy (sleep and activity): "high", "medium", "low".
    """

    mood: Literal["good", "okay", "not_great"] | None = None
    energy: Literal["high", "medium", "low"] | None = None


Lever = Literal[
    "quit_smoking",
    "vigorous_plus_60",
    "moderate_plus_90",
    "short_sleep_plus_1h",
    "sitting_minus_60_realistic",
    "keep_it_up",
]


# The idea's gesture, for Mochi's pose on the card.
IdeaKind = Literal[
    "walk", "dance", "stand", "stretch", "sleep", "eat", "social", "breath", "craving"
]


class RecommendationIdea(ApiModel):
    # The catalog idea's id (recommendations/ideas.py), e.g. "sit_ad_breaks".
    id: str = Field(min_length=1, max_length=60)
    # The model-sensitivity lever it follows, or "keep_it_up" for encouragement.
    lever: Lever
    title: str = Field(min_length=1, max_length=80)
    # Mochi's words: gentle, concrete, no numbers of years, no promises.
    message: str = Field(min_length=1, max_length=400)
    # Profile fields and habit-note topics it uses, e.g. "moderate_recreation_min_week", "note:exercise".
    based_on: list[str] = Field(max_length=6)
    # The package's wellness card it is grounded in, and that card's public source.
    wellness_card: Literal["smoking", "activity", "sleep", "sitting"]
    source_title: str
    source_url: str
    # How much the model's difference for people like this person is, as a category only
    # (never a number). Null for guideline-only items, coping tricks that are not the habit
    # change itself (a craving tip, a wind-down routine) and ages outside 18-85.
    effect: Literal["big", "some", "small", "tiny"] | None = None
    effect_note: Literal["Modeled difference for people like you, not a promise."] = (
        "Modeled difference for people like you, not a promise."
    )
    # The model input the lever changes and the value to try, so the app's Experiment can
    # preset the change. Both null for guideline-only items with no model lever.
    experiment_lever: str | None = None
    experiment_target: float | int | str | None = None
    # One plain sentence for a two-line card: no numbers, no promise of benefit.
    why_short: str = Field(default="", max_length=90)
    # Host of source_url, e.g. "cdc.gov".
    source_domain: str = ""
    kind: IdeaKind
    causal_interpretation: Literal[False] = False


class Recommendation(RecommendationIdea):
    # Up to three other ideas for the same lever, already checked against the person's
    # limitations and age, never the idea above. Alternatives have none of their own.
    alternatives: list[RecommendationIdea] = Field(default_factory=list, max_length=3)


class TurnResponse(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    state: ConversationState
    message: str = Field(min_length=1, max_length=1500)
    guide_mode: Literal["guided", "llm"] = "guided"
    provider_status: Literal[
        "not_configured", "consent_required", "used", "unavailable", "not_needed"
    ] = "not_configured"
    # Claude judged the transcript background speech, TV or another person, not the
    # person answering: the question stays open and the app asks once to say it again.
    off_topic: bool = False
    voice_status: Literal["deferred", "available", "unavailable"] = "deferred"
    # Set when the person asked to hear the prompt again more slowly or more loudly;
    # the message repeats the prompt, and a voice client may adjust playback.
    speech_hint: Literal["slower", "louder"] | None = None
    # The reply said something urgent is happening. The conversation is paused on the
    # same question: the app shows a "Call 911" button the person taps themselves, and
    # "Continue" (action "resume", or any reply) goes on where it stopped.
    emergency: bool = False
    accepted_input_modes: list[Literal["text", "transcript"]] = Field(
        default_factory=lambda: ["text", "transcript"], min_length=2, max_length=2
    )
    mascot_events: list[MascotEvent] = Field(min_length=1, max_length=2)
    complete: bool
    # Short answers the app may show as buttons; tapping one sends it as reply text.
    quick_replies: list[str] = Field(default_factory=list, max_length=8)
    # "open_health_import": the person said yes to Apple Health; the app opens its
    # import screen and then sends action "import" (or "skip" if nothing was used).
    # "open_ideas": the person asked for ideas; the app shows today's idea. The state is
    # unchanged and the current question comes back in the same message.
    client_action: Literal["open_health_import", "open_ideas"] | None = None
    # What the on-device model has so far, from confirmed answers only.
    model_inputs: ModelInputs
    character_hints: CharacterHints = Field(default_factory=CharacterHints)
    # "templates": Mochi's own words. A provider name: that provider phrased this line
    # (with the person's consent for it) and the line passed the safety check.
    phrased_by: Literal["templates", "muse", "claude"] = "templates"
    # Filled on the turn that completes the intake (same as POST /api/recommendations).
    recommendations: list[Recommendation] = Field(default_factory=list, max_length=3)
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Speech capture and playback are not implemented; final transcripts use the text path.",
            "Prediction functionality is deferred. No forecast is generated by intake.",
            "State is held by the caller. The server does not retain your conversation.",
        ],
        max_length=5,
    )


class ExtractionCandidate(ApiModel):
    field: ProfileField
    quote: str = Field(min_length=1, max_length=2000)
    # Claude only: the answer in the field's own unit, with the arithmetic done ("2 hours"
    # to a minutes question is 120). Never trusted: the deterministic reader re-checks it
    # (lifetwin/onboarding/computed.py) and wins when the two disagree.
    value: float | None = None


class ExtractionResult(ApiModel):
    candidates: list[ExtractionCandidate] = Field(max_length=FIELD_COUNT)
    # Claude only: the words are clearly not the person answering (TV, another person).
    off_topic: bool = False
