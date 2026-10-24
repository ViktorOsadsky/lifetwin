"""The deterministic daily planner: snapshot in, cited plan with changes and a trace out.

Order of work (report §7): the emergency line, red flags, fixed replies, then choices
from the catalogue only. The model's lever ranking orders the habit slot for people
inside the model's ages; it is never quoted. Mochi's mood follows effort, never the
forecast: nothing here reads a prediction or an experiment.

MASTER_PLAN "Daily health-planning agent": every plan records an input snapshot id;
the same snapshot on the same local day with nothing new reuses the plan; a day with
no log is unknown, never zero; too little data gives a labelled general plan.
"""

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import date

from lifetwin.coach import catalog as cat
from lifetwin.coach.models import (
    CoachNote,
    CoachPlanRequest,
    InputSummary,
    ItemFeedback,
    MemoryInstruction,
    PlanChange,
    PlanItem,
    PlanItemRef,
    PreviousPlan,
    TraceFact,
    TraceStep,
)
from lifetwin.coach.safety import (
    BLOCKED,
    CLEARED,
    DIABETES_FOOD,
    DIAGNOSIS,
    FORECAST,
    FORGET,
    FORGET_ALL,
    JOINT_PAIN,
    KIDNEY,
    MEDICINE,
    NO_TIME,
    SUPPLEMENT,
    WEATHER_INDOORS,
    WEIGHT,
    is_emergency,
    red_flag,
    safe_slot,
    words,
)
from lifetwin.onboarding.intents import EMERGENCY_MESSAGE

LEVER_SOURCE = "docs/model-sensitivity.json (personal-cox-v2-20261024T182404Z)"
LEVER_ORDER = (
    "quit_smoking",
    "vigorous_plus_60",
    "moderate_plus_90",
    "short_sleep_plus_1h",
    "sitting_minus_60_realistic",
)
MEMORY_DAYS = 90
STALE_DAYS = 7
GOAL_MINUTES = 150  # CDC: 150 moderate minutes a week; vigorous minutes count double
SHOWN_CHANGES = {"swapped", "stepped_up", "shorter", "seated", "edited", "paused", "removed"}

NOTE_LIMITS = {
    "knee_pain": re.compile(r"\b(?:knee|knees|hip|hips|arthritis|joint|joints)\b"),
    "walking_aid": re.compile(r"\b(?:walker|cane|rollator|walking stick|zimmer frame)\b"),
    "seated_only": re.compile(
        r"\b(?:wheelchair|can't stand|cannot stand|can not stand|bed ?bound|chair ?bound)\b"
    ),
    "fall_risk": re.compile(r"\b(?:fall|falls|falling|fell|balance|unsteady|wobbly)\b"),
    "cardio_caution": re.compile(r"\b(?:breath|breathless|heart|angina|chest)\b"),
}
PET = re.compile(r"\b(?:dog|dogs|pup|puppy|pet|cat)\b")
PET_GONE = re.compile(
    r"\b(?:dog|cat|pet|pup|puppy|\w+) (?:died|has died|passed|passed away|is gone)\b|"
    r"\blost my (?:dog|cat|pet)\b|\bput (?:him|her) down\b"
)
TIMES = {
    "morning": re.compile(r"\b(?:morning|mornings|breakfast|early)\b"),
    "afternoon": re.compile(r"\b(?:afternoon|afternoons|lunch|midday|noon)\b"),
    "evening": re.compile(r"\b(?:evening|evenings|dinner|supper|night)\b"),
}
FOOD_CARDS = (
    (re.compile(r"\bsoups?\b"), "dash_less_salt"),
    (re.compile(r"\b(?:fish|salmon|olive|vegetables?|salads?)\b"), "mediterranean"),
    (re.compile(r"\b(?:eggs?|yogh?urt|beans|chicken|cheese)\b"), "protein_each_meal"),
    (re.compile(r"\b(?:fruit|apples?|berries|oats|porridge)\b"), "fiber"),
)
HABIT_TIMES = {"quit_help": "morning", "sleep_routine": "evening", "sitting_breaks": "afternoon"}
STOP = {
    "about",
    "my",
    "the",
    "that",
    "this",
    "it",
    "please",
    "mochi",
    "to",
    "a",
    "an",
    "of",
    "me",
    "you",
    "i",
    "and",
    "know",
    "remember",
    "said",
    "told",
    "what",
    "now",
}
CLARIFY = "To make this more personal: on how many days did you get moving last week?"


class StaleRevision(Exception):
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


@dataclass
class Draft:
    """One item message as a provider may see it: names replaced by placeholders."""

    slot: str
    draft: str
    keep_words: tuple[str, ...]
    names: dict[str, str] = field(default_factory=dict)


@dataclass
class Plan:
    status: str
    revision_id: str | None
    based_on: str | None
    inputs: InputSummary | None
    plan_type: str | None
    reused_previous: bool
    clarify: str | None
    reply: str | None
    lines: list[str]
    items: list[PlanItem]
    changes: list[PlanChange]
    trace: list[TraceStep]
    mood: str
    emergency: bool
    movement_paused: bool
    memory_instruction: MemoryInstruction | None
    drafts: list[Draft]
    # A fixed safety reply was given: no provider call for this request.
    provider_blocked: bool


def fact(source: str, value: object) -> TraceFact:
    return TraceFact(source=source, value=str(value))


def _hash(body: object) -> str:
    text = json.dumps(body, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def revision_id(
    based_on: str | None, local_date: str, snapshot_id: str, refs: list[PlanItemRef]
) -> str:
    return "r" + _hash(
        {
            "based_on": based_on,
            "local_date": local_date,
            "snapshot": snapshot_id,
            "items": [ref.model_dump() for ref in refs],
        }
    )


def check_revision(req: CoachPlanRequest) -> None:
    """Refuse feedback for anything but the latest plan, and plans that were altered."""
    prev = req.previous_plan
    if prev is None:
        return
    if revision_id(prev.based_on, prev.local_date, prev.input_snapshot_id, prev.items) != (
        prev.revision_id
    ):
        raise StaleRevision("This plan has changed since Mochi made it. Please refresh it.")
    if req.latest_revision_id is not None and req.latest_revision_id != prev.revision_id:
        raise StaleRevision("There is a newer plan. Please use today's plan.")
    if req.feedback is not None and req.feedback.revision_id != prev.revision_id:
        raise StaleRevision("That feedback is for an older plan. Please use today's plan.")
    if prev.local_date > req.local_date:
        raise StaleRevision("That plan is from a later day. Please check the phone's date.")


def _days(earlier: str, later: str) -> int:
    return (date.fromisoformat(later) - date.fromisoformat(earlier)).days


def _note_text(note: CoachNote) -> str:
    skip = {"id", "topic", "name", "source", "noted_on"}
    data = note.model_dump(by_alias=True, exclude_none=True)
    return words(" ".join(str(value) for key, value in data.items() if key not in skip))


def _first_name(note: CoachNote) -> str | None:
    name = note.name
    if name and re.fullmatch(r"[A-Z][a-zA-Z'-]{0,19}", name) and not BLOCKED.search(name):
        return name
    return None


def _n(value: int | None) -> int:
    return value or 0


def _moved(day) -> int | None:
    """Moderate-equivalent minutes logged that day; None when the day has no activity log."""
    if day.moderate_recreation_min is None and day.vigorous_recreation_min is None:
        return None
    return _n(day.moderate_recreation_min) + 2 * _n(day.vigorous_recreation_min)


class Planner:
    def __init__(self, req: CoachPlanRequest):
        self.req = req
        self.today = req.local_date
        self.profile = req.profile
        self.prev: PreviousPlan | None = req.previous_plan
        self.prev_refs = {ref.id: ref for ref in (self.prev.items if self.prev else [])}
        self.feedback: dict[str, ItemFeedback] = (
            {item.item_id: item for item in req.feedback.items} if req.feedback else {}
        )
        self.limits: set[str] = set(req.limits)
        self.limit_facts: list[TraceFact] = [fact("limits", tag) for tag in req.limits]
        self.reply: str | None = None
        self.provider_blocked = False
        self.paused = req.movement_paused
        self.pause_reason = "movement_paused" if req.movement_paused else None
        self.cleared = False
        self.concerned = False
        self.memory_instruction: MemoryInstruction | None = None
        self.forgotten: set[str] = set()
        self.ignore_notes = False
        self.pet_gone = False
        self.food_focus: str | None = None
        self.callback_used = False
        self.trace: list[TraceStep] = []
        self.changes: list[PlanChange] = []
        self.drafts: list[Draft] = []

    # -- inputs ---------------------------------------------------------------

    def notes(self) -> list[CoachNote]:
        """Notes Mochi may use: only with memory consent, recent, and not being forgotten."""
        if self.req.memory_consent is not True or self.ignore_notes:
            return []
        return [
            note
            for note in self.req.habit_notes
            if note.id not in self.forgotten
            and not (note.noted_on and not 0 <= _days(note.noted_on, self.today) <= MEMORY_DAYS)
        ]

    def recent_checkins(self) -> list:
        return [d for d in self.req.checkins if 0 <= _days(d.date, self.today) < STALE_DAYS]

    def snapshot(self) -> str:
        """The observed inputs this plan rests on (never the said text or feedback)."""
        return "s" + _hash(
            {
                "profile": self.profile.model_dump(exclude_none=True),
                "checkins": [d.model_dump(exclude_none=True) for d in self.req.checkins],
                "notes": [n.model_dump(exclude_none=True) for n in self.notes()],
                "goals": self.req.goals if self.req.memory_consent is True else [],
                "limits": sorted(self.req.limits),
                "paused": self.req.movement_paused,
                "local_date": self.today,
            }
        )

    def input_summary(self, snapshot_id: str) -> InputSummary:
        p = self.profile
        observed = [f"profile.{k}" for k in p.model_dump(exclude_none=True)]
        logged = [d for d in self.recent_checkins() if _moved(d) is not None]
        if self.req.checkins:
            observed.append(f"checkins ({len(self.req.checkins)} days)")
        observed += [f"note:{n.id}" for n in self.notes()]
        missing = []
        if (
            p.exercise_minutes_weekly is None
            and p.moderate_minutes_weekly is None
            and p.vigorous_minutes_weekly is None
            and not logged
        ):
            missing.append("weekly activity")
        if p.age is None:
            missing.append("age")
        if p.sleep_hours is None and not any(d.sleep_hours is not None for d in self.req.checkins):
            missing.append("sleep")
        stale = []
        if self.req.checkins:
            last = max(d.date for d in self.req.checkins)
            if _days(last, self.today) >= STALE_DAYS:
                stale.append(f"checkins (last on {last})")
        return InputSummary(
            snapshot_id=snapshot_id,
            observed=observed,
            missing=missing,
            stale=stale,
            days_logged_last_7=len(logged),
        )

    def read_said(self) -> None:
        said = self.req.said
        if not said:
            return
        text = words(said)
        if PET_GONE.search(text):
            self.pet_gone = True
            self.reply = "I'm so sorry. Losing a pet is very hard."
            return
        if red_flag(said):
            self.paused, self.pause_reason, self.concerned = True, "said", True
            self.reply, self.provider_blocked = cat.RED_FLAG_REPLY, True
            return
        if self.paused and CLEARED.search(text):
            self.paused, self.cleared, self.pause_reason = False, True, None
            self.reply = cat.CLEARED_REPLY
            return
        if FORGET_ALL.search(text):
            self.ignore_notes = True
            self.memory_instruction = MemoryInstruction(
                action="forget_all",
                note_ids=[note.id for note in self.req.habit_notes],
                confirm_prompt="Do you want me to forget everything I remember about you? "
                "I'll ask once more to be sure.",
                confirmations_needed=2,
            )
            self.reply = "Okay. I won't use anything I remember while you decide."
            return
        forget = FORGET.search(text)
        if forget:
            self.forget(forget.group(1))
            return
        if SUPPLEMENT.search(text):
            self.reply = cat.SUPPLEMENT_REPLY
        elif MEDICINE.search(text):
            self.reply = cat.MEDICINE_REPLY
        elif KIDNEY.search(text):
            self.reply, self.food_focus = cat.KIDNEY_FOOD_REPLY, "care_team_kidney"
        elif DIABETES_FOOD.search(text) or (
            self.profile.diabetes and re.search(r"\b(?:eat|food|meal|carbs?)\b", text)
        ):
            self.reply, self.food_focus = cat.DIABETES_FOOD_REPLY, "care_team_food"
        elif WEIGHT.search(text):
            self.reply = cat.WEIGHT_REPLY
        elif FORECAST.search(text):
            self.reply = cat.FORECAST_REPLY
        elif DIAGNOSIS.search(text):
            self.reply = cat.DIAGNOSIS_REPLY
        if self.reply:
            self.provider_blocked = True
            title, url = cat.REPLY_SOURCES.get(self.reply, (None, None))
            if url:
                self.trace.append(
                    TraceStep(
                        item_id="plan",
                        facts=[fact("said", "a question with a fixed answer")],
                        rule="fixed_reply: reviewed text, no provider call (report §3, §7)",
                        evidence=url,
                        action=f"fixed reply ({title})",
                    )
                )
        if JOINT_PAIN.search(text):
            self.add_limit("knee_pain", "said", "joint pain")
            self.concerned = True

    def forget(self, rest: str) -> None:
        rest_words = [w for w in rest.split() if w not in STOP]
        if not rest_words:
            note_id = next(
                (ref.callback_note_id for ref in self.prev_refs.values() if ref.callback_note_id),
                None,
            )
            if note_id is None:
                self.reply = cat.FORGET_WHICH
                return
            ids = [note_id]
        else:
            ids = [
                note.id
                for note in self.req.habit_notes
                if any(
                    re.search(
                        rf"\b{re.escape(w)}",
                        f"{_note_text(note)} {note.topic} {words(note.name or '')}",
                    )
                    for w in rest_words
                )
            ]
            if not ids:
                self.reply = cat.FORGET_NOT_FOUND
                return
        self.forgotten.update(ids)
        self.memory_instruction = MemoryInstruction(
            action="forget",
            note_ids=ids,
            confirm_prompt="Should I forget that? Say yes and I'll take it out of my notebook.",
        )
        self.reply = "Okay. I won't use that while you decide."

    def add_limit(self, tag: str, source: str, value: str) -> None:
        self.limits.add(tag)
        self.limit_facts.append(fact(source, f"{value} -> {tag}"))

    def read_feedback_and_notes(self) -> None:
        for slot, item in self.feedback.items():
            if not item.reason:
                continue
            if red_flag(item.reason):
                self.paused, self.pause_reason, self.concerned = True, f"feedback.{slot}", True
                self.provider_blocked = True
            if JOINT_PAIN.search(words(item.reason)):
                self.add_limit("knee_pain", f"feedback.{slot}", "said it hurt")
                self.concerned = True
        for note in self.notes():
            if note.topic == "people":
                continue  # never a third party's health
            text = _note_text(note)
            for tag, pattern in NOTE_LIMITS.items():
                if pattern.search(text):
                    self.add_limit(tag, f"note:{note.id}", text)

    def weekly_minutes(self) -> tuple[int | None, list[TraceFact]]:
        p = self.profile
        found: list[tuple[int, TraceFact]] = []
        if p.moderate_minutes_weekly is not None or p.vigorous_minutes_weekly is not None:
            value = _n(p.moderate_minutes_weekly) + 2 * _n(p.vigorous_minutes_weekly)
            found.append((value, fact("profile.moderate + 2 x vigorous minutes weekly", value)))
        elif p.exercise_minutes_weekly is not None:
            value = p.exercise_minutes_weekly
            found.append((value, fact("profile.exercise_minutes_weekly", value)))
        logged = [m for d in self.recent_checkins() if (m := _moved(d)) is not None]
        if logged:
            # Only logged days count; a day without a log is unknown, so this is a floor.
            found.append(
                (
                    sum(logged),
                    fact(f"checkins.{len(logged)} logged days this week, minutes", sum(logged)),
                )
            )
        if not found:
            return None, [fact("profile", "weekly activity not known")]
        return max(value for value, _ in found), [f for _, f in found]

    def active_days(self, start: int, end: int) -> int | None:
        """Days with activity, ``start`` to ``end`` days ago; None when no day was logged."""
        logged = {
            d.date: m
            for d in self.req.checkins
            if start <= _days(d.date, self.today) <= end and (m := _moved(d)) is not None
        }
        move = self.feedback.get("move")
        if move and move.status == "done" and self.prev:
            if start <= _days(self.prev.local_date, self.today) <= end:
                logged[self.prev.local_date] = max(logged.get(self.prev.local_date, 0), 1)
        if not logged:
            return None
        return sum(1 for minutes in logged.values() if minutes > 0)

    def has_data(self) -> bool:
        return bool(
            self.profile.model_dump(exclude_none=True)
            or self.req.checkins
            or self.req.limits
            or self.notes()
            or self.prev
        )

    def default_time(self) -> str:
        clock = self.req.local_time
        if clock is None or clock < "11:00":
            return "morning"
        return "afternoon" if clock < "16:00" else "evening"

    # -- movement -------------------------------------------------------------

    def level(self) -> tuple[str, list[TraceFact]]:
        minutes, facts = self.weekly_minutes()
        if minutes is None or minutes == 0:
            level = "none"
        elif minutes < GOAL_MINUTES:
            level = "some"
        else:
            level = "active"
        if self.profile.general_health in {"fair", "poor"} and level != "none":
            facts.append(fact("profile.general_health", self.profile.general_health))
            level = "some" if level == "active" else "none"
        return level, facts

    def feeling_low(self) -> bool:
        latest = sorted((d for d in self.req.checkins if d.wellbeing), key=lambda d: d.date)
        return (
            bool(latest)
            and latest[-1].wellbeing == "not_great"
            and (_days(latest[-1].date, self.today) <= 2)
        )

    def anchor_note(self, activity: cat.Activity) -> CoachNote | None:
        for note in self.notes():
            text = _note_text(note)
            if note.topic == "pet" or PET.search(text):
                if activity.id == "walk_short" and not self.pet_gone:
                    return note
                continue
            if note.topic == "exercise" and any(a in text for a in activity.anchors):
                return note
        return None

    def pick_activity(
        self, level: str, avoid: set[str], indoor: bool = False
    ) -> tuple[cat.Activity, CoachNote | None]:
        pool = [
            cat.ACTIVITIES[a]
            for a in cat.POOLS[level]
            if a not in avoid
            and cat.allowed(cat.ACTIVITIES[a], self.limits, age=self.profile.age)
            and (not indoor or cat.ACTIVITIES[a].indoor)
        ]
        if not pool:
            pool = [cat.ACTIVITIES["seated_arm_raises"]]
        if not self.callback_used:
            for activity in pool:
                note = self.anchor_note(activity)
                if note is not None:
                    return activity, note
            # A remembered limitation that shaped the pick ("knee pain" -> seated).
            for f in self.limit_facts:
                if f.source.startswith("note:") and f.value.endswith("knee_pain"):
                    note_id = f.source.removeprefix("note:")
                    note = next((n for n in self.notes() if n.id == note_id), None)
                    if note is not None:
                        return pool[0], note
        return pool[0], None

    def note_time(self, note: CoachNote | None) -> str | None:
        if note is None:
            return None
        text = words(" ".join(filter(None, [note.time_of_day, note.frequency])))
        return next((name for name, rx in TIMES.items() if rx.search(text)), None)

    def callback_sentence(self, note: CoachNote) -> tuple[str, str, dict[str, str]] | None:
        """(template sentence, provider draft with placeholders, placeholder names)."""
        text = _note_text(note)
        name = _first_name(note)
        if note.topic == "pet" or PET.search(text):
            if name:
                sentence = "You told me you like walking with {pet}."
                return sentence.format(pet=name), sentence, {"{pet}": name}
            animal = "dog" if "dog" in text or note.topic == "pet" else "pet"
            line = f"You told me you like walking with your {animal}."
            return line, line, {}
        if note.kind and safe_slot(note.kind):
            line = f"You told me you enjoy {note.kind.lower()}."
            return line, line, {}
        part = re.search(r"\b(knee|hip|back|joint)s?\b", text)
        if part:
            line = f"You told me about your {part.group(1)}, so this one is easy on it."
            return line, line, {}
        return None

    def build_move(self, level: str, level_facts: list[TraceFact]) -> PlanItem | None:
        prev_ref = self.prev_refs.get("move")
        fb = self.feedback.get("move")
        facts = level_facts + self.limit_facts
        age = self.profile.age
        if self.paused:
            reason = (
                "movement stays paused until your doctor says it's okay"
                if self.pause_reason == "movement_paused"
                else "you mentioned a warning sign"
            )
            self.changes.append(
                PlanChange(
                    item_id="move",
                    change="paused",
                    explanation=f"No movement idea today, because {reason}. Please check with "
                    "your doctor first.",
                )
            )
            self.trace.append(
                TraceStep(
                    item_id="plan",
                    facts=facts + [fact(self.pause_reason or "said", "red flag or pause")],
                    rule="red_flag_gate: warning signs pause movement until cleared (report §1)",
                    evidence=cat.NIA_EXERCISE[1],
                    action="no workout item; check-with-your-doctor line",
                )
            )
            return None

        small = level == "none" or self.cleared or self.feeling_low()
        if self.feeling_low():
            facts.append(fact("checkins.wellbeing", "not_great: keep it gentle"))
        cap = cat.SMALL_START_MAX if small else None

        def fresh(avoid: set[str], indoor: bool = False):
            activity, note = self.pick_activity(
                level if not self.cleared else "none", avoid, indoor
            )
            return activity, note, min(activity.minutes, cap or activity.max_minutes)

        prev_act = cat.ACTIVITIES.get(prev_ref.catalog_id) if prev_ref else None
        note, time = None, None
        if prev_act is None or self.cleared:
            activity, note, minutes = fresh(set())
            change, why = "new", "A fresh pick from the activity list."
            rule = f"pick_{level}: first allowed item in the {level} pool"
            if note is not None:
                rule += f", anchored to note:{note.id}"
            if self.cleared:
                why = "Your doctor said it's okay, so movement is back, starting small."
                rule = "cleared: movement resumes as a small start"
        else:
            prev_minutes = prev_ref.minutes or prev_act.minutes
            time = prev_ref.time_of_day
            status = fb.status if fb else None
            reason = words(fb.reason) if fb and fb.reason else ""
            facts = facts + [fact("previous_plan.move", f"{prev_act.id}, {prev_minutes} min")]
            if fb:
                facts.append(
                    fact("feedback.move", status + (f": {fb.reason}" if fb.reason else ""))
                )
            activity, minutes = prev_act, prev_minutes
            old = prev_act.title.lower()
            if not cat.allowed(prev_act, self.limits, age=age):
                activity, note, minutes = fresh({prev_act.id})
                if "knee_pain" in self.limits and activity.position in {"seated", "water"}:
                    change = "seated"
                    hurt = (
                        f"{old} hurt your knee"
                        if JOINT_PAIN.search(reason)
                        else "your knee is sore"
                    )
                    why = (
                        f"You said {hurt}, so today is a seated routine: {activity.title.lower()}."
                        if activity.position == "seated"
                        else f"You said {hurt}, so today is gentle on the knees: "
                        f"{activity.title.lower()}."
                    )
                else:
                    change = "swapped"
                    why = f"{prev_act.title} doesn't fit what you told me, so today it's " + (
                        f"{activity.title.lower()}."
                    )
                rule = "limit_gate: the previous item is ruled out by a limitation tag"
            elif status == "dismissed":
                indoor = bool(WEATHER_INDOORS.search(reason))
                activity, note, minutes = fresh({prev_act.id}, indoor)
                change = "swapped"
                why = f"You set aside {old}, so today I picked {activity.title.lower()} instead" + (
                    ", indoors." if indoor else "."
                )
                rule = "dismissed: swap to the next allowed item" + (", indoors" if indoor else "")
            elif status == "done":
                bigger = min(prev_minutes + 5, prev_act.max_minutes)
                nxt = cat.ACTIVITIES.get(prev_act.next_id or "")
                if self.feeling_low():
                    change, rule = "kept", "done, but feeling low: keep, no step up"
                    why = f"You did {old}. Nice work! Let's keep it the same while you feel low."
                elif bigger > prev_minutes:
                    minutes, change = bigger, "stepped_up"
                    why = f"You did {old}. Nice work! Today let's try {minutes} minutes."
                    rule = "done: small step up (+5 minutes, within the item's range)"
                elif nxt and cat.allowed(nxt, self.limits, age=age) and nxt.id in cat.POOLS[level]:
                    activity, minutes, change = nxt, nxt.min_minutes, "stepped_up"
                    why = f"You did {old} at its longest. Ready for {nxt.title.lower()}?"
                    rule = "done at the top of the range: next item on the ladder"
                else:
                    change, rule = "kept", "done at the top of the range: keep"
                    why = f"You did {old}. That's a good amount, so it stays."
            elif status == "not_done" and NO_TIME.search(reason):
                minutes = max(prev_act.min_minutes, prev_minutes - 5)
                change = "shorter" if minutes < prev_minutes else "kept"
                why = (
                    f"You said there wasn't time, so today's is shorter: {minutes} minutes."
                    if change == "shorter"
                    else "You said there wasn't time. It's already short, so it stays."
                )
                rule = "not_done, no time: shorter, never a step up"
            elif status == "not_done" and WEATHER_INDOORS.search(reason) and not prev_act.indoor:
                activity, note, minutes = fresh({prev_act.id}, True)
                change = "swapped"
                why = f"You said the weather got in the way, so today it's {activity.title.lower()}, indoors."
                rule = "not_done, weather: swap to an indoor item"
            elif status == "not_done":
                change, rule = "kept", "not_done: keep, no step up"
                why = f"No rush. I kept {old} the same for today."
            elif status == "edited":
                wanted = fb.minutes or prev_minutes
                minutes = max(prev_act.min_minutes, min(wanted, prev_act.max_minutes))
                time = fb.time_of_day or time
                change, rule = "edited", "edited: keep the person's change, within the item's range"
                why = (
                    f"You changed it to {minutes} minutes"
                    + (f" in the {time}" if fb.time_of_day else "")
                    + ", so I kept it that way."
                )
            elif status == "accepted":
                change, rule = "kept", "accepted: keep"
                why = f"You said yes to {old}, so it stays on today's plan."
            else:
                change, rule = "kept", "no feedback: keep"
                why = f"I kept {old}, since I haven't heard how it went."
        self.changes.append(PlanChange(item_id="move", change=change, explanation=why))
        return self.move_item(activity, minutes, note, time, facts, rule)

    def move_item(
        self,
        activity: cat.Activity,
        minutes: int,
        note: CoachNote | None,
        time: str | None,
        facts: list[TraceFact],
        rule: str,
    ) -> PlanItem:
        body = activity.steps.format(minutes=minutes)
        keep = list(activity.keep_words)
        if "walking_aid" in self.limits and activity.position == "standing":
            body += " Bring your walker or cane."
            keep.append("walker or cane")
        if "cardio_caution" in self.limits:
            body += " Check with your doctor before doing more."
            keep.append("doctor")
        elif "fall_risk" in self.limits:
            body += " Ask your doctor about a balance class."
            keep.append("doctor")
        draft, names, callback_id = body, {}, None
        if note is not None and not self.callback_used:
            sentence = self.callback_sentence(note)
            if sentence is not None:
                line, draft_line, names = sentence
                body, draft = f"{line} {body}", f"{draft_line} {draft}"
                callback_id = note.id
                self.callback_used = True
                time = time or self.note_time(note)
                facts = facts + [fact(f"note:{note.id}", _note_text(note) or note.topic)]
        time = time or self.default_time()
        lever = {"vigorous": "vigorous_plus_60", "moderate": "moderate_plus_90"}.get(
            activity.counts_as
        )
        if activity.component in {"balance", "strength"}:
            why = "Strength and balance moves help keep you steady on your feet."
        else:
            why = {
                "light": "A gentle start you can do at home. Every bit of movement counts.",
                "moderate": "Moving at an easy pace on most days is what the guidelines for "
                "older adults ask for.",
                "vigorous": "You're already active, and a harder session now and then is part "
                "of the guidelines.",
            }[activity.intensity]
        self.trace.append(
            TraceStep(
                item_id="move",
                facts=facts,
                rule=rule,
                evidence=activity.source[1],
                action=f"{activity.id}, {minutes} min, {activity.position}, {time}"
                + (f", callback note:{callback_id}" if callback_id else ""),
            )
        )
        self.drafts.append(Draft("move", draft, tuple(keep), names))
        return PlanItem(
            id="move",
            kind="workout",
            action_id=activity.id,
            catalog_id=activity.id,
            lever=lever,
            title=activity.title,
            message=body,
            why=why,
            minutes=minutes,
            time_of_day=time,
            intensity=activity.intensity,
            position=activity.position,
            counts_as=activity.counts_as,
            based_on=sorted({f.source for f in facts})[:8],
            wellness_card="activity",
            source_title=activity.source[0],
            source_url=activity.source[1],
            callback_note_id=callback_id,
        )

    # -- food -----------------------------------------------------------------

    def diet_gate(self) -> tuple[str | None, list[TraceFact]]:
        if self.food_focus:
            return self.food_focus, [fact("said", "a food question with a condition")]
        note_text = " ".join(_note_text(n) for n in self.notes() if n.topic != "people")
        if KIDNEY.search(note_text):
            return "care_team_kidney", [fact("notes", "kidney")]
        if self.profile.diabetes:
            return "care_team_food", [fact("profile.diabetes", True)]
        return None, []

    def build_food(self) -> PlanItem:
        prev_ref = self.prev_refs.get("food")
        fb = self.feedback.get("food")
        gate, facts = self.diet_gate()
        order = list(cat.DIET_ORDER)
        if self.profile.hypertension:
            order.remove("dash_less_salt")
            order.insert(0, "dash_less_salt")
            facts.append(fact("profile.hypertension", True))
        prev_card = cat.DIET.get(prev_ref.catalog_id) if prev_ref else None
        dismissed = bool(fb and fb.status == "dismissed")
        if fb:
            facts.append(fact("feedback.food", fb.status + (f": {fb.reason}" if fb.reason else "")))
        note = None
        if gate is None and not self.callback_used and (prev_card is None or dismissed):
            for n in self.notes():
                if n.topic == "food" and safe_slot(n.kind):
                    card_id = next((c for rx, c in FOOD_CARDS if rx.search(_note_text(n))), None)
                    if card_id and not (dismissed and prev_card and prev_card.id == card_id):
                        note = n
                        order.remove(card_id)
                        order.insert(0, card_id)
                        break
        if gate is not None:
            card = cat.DIET[gate]
            if dismissed and prev_card and prev_card.id == gate:
                card = cat.DIET["fluids"]
            change = (
                "new" if prev_card is None else ("kept" if prev_card.id == card.id else "swapped")
            )
            rule = "condition_gate: diabetes or kidney -> care team or dietitian (report §2)"
        elif prev_card is None or prev_card.fixed:
            card, change = cat.DIET[order[0]], "new" if prev_card is None else "swapped"
            rule = "pattern_order: first pattern for this profile"
        elif dismissed:
            card = cat.DIET[next(c for c in order if c != prev_card.id)]
            change, rule = "swapped", "dismissed: next food pattern"
        else:
            card, change, rule = prev_card, "kept", f"{fb.status if fb else 'no feedback'}: keep"
        explanation = {
            "new": "A food pattern to try.",
            "kept": f"Kept {card.title.lower()}, since nothing called for a change.",
            "swapped": (
                f"You set that one aside, so here's {card.title.lower()} instead."
                if dismissed
                else f"Changed to {card.title.lower()}, to fit what you told me."
            ),
        }[change]
        self.changes.append(PlanChange(item_id="food", change=change, explanation=explanation))
        body, callback_id = card.message, None
        if note is not None:
            body = f"You told me you love {note.kind.lower()}. {body}"
            callback_id = note.id
            self.callback_used = True
            facts.append(fact(f"note:{note.id}", _note_text(note)))
        time = (
            prev_ref.time_of_day
            if prev_ref and prev_ref.catalog_id == card.id and prev_ref.time_of_day
            else "afternoon"
        )
        return self.food_item(card, body, callback_id, facts, rule, time)

    def food_item(
        self,
        card: cat.Card,
        body: str,
        callback_id: str | None,
        facts: list[TraceFact],
        rule: str,
        time: str,
    ) -> PlanItem:
        self.trace.append(
            TraceStep(
                item_id="food",
                facts=facts or [fact("default", "no food facts, so the first pattern")],
                rule=rule,
                evidence=card.source[1],
                action=card.id + (f", callback note:{callback_id}" if callback_id else ""),
            )
        )
        if not card.fixed:
            self.drafts.append(Draft("food", body, card.keep_words))
        return PlanItem(
            id="food",
            kind="diet",
            action_id=card.id,
            catalog_id=card.id,
            title=card.title,
            message=body,
            why=card.why,
            time_of_day=time,
            based_on=sorted({f.source for f in facts})[:8] or ["default"],
            source_title=card.source[0],
            source_url=card.source[1],
            callback_note_id=callback_id,
        )

    # -- habit ----------------------------------------------------------------

    def habit_choices(self) -> list[tuple[str, list[TraceFact]]]:
        p = self.profile
        out: list[tuple[str, list[TraceFact]]] = []
        if p.smoking_status == "current":
            out.append(("quit_help", [fact("profile.smoking_status", "current")]))
        recent = self.recent_checkins()
        sleep, sleep_source = p.sleep_hours, "profile.sleep_hours"
        nights = [d.sleep_hours for d in recent if d.sleep_hours is not None]
        if nights:
            sleep, sleep_source = sum(nights) / len(nights), "checkins.average sleep"
        if sleep is not None and sleep < 7:
            out.append(("sleep_routine", [fact(sleep_source, round(sleep, 1))]))
        sitting, sitting_source = p.sitting_minutes_daily, "profile.sitting_minutes_daily"
        sat = [d.sedentary_min_day for d in recent if d.sedentary_min_day is not None]
        if sat:
            sitting, sitting_source = round(sum(sat) / len(sat)), "checkins.average sitting"
        if sitting is None or sitting >= 90:
            out.append(
                (
                    "sitting_breaks",
                    [fact(sitting_source, sitting if sitting is not None else "not known")],
                )
            )
        return out

    def build_habit(self) -> PlanItem | None:
        prev_ref = self.prev_refs.get("habit")
        fb = self.feedback.get("habit")
        choices = dict(self.habit_choices())
        age = self.profile.age
        rule = (
            f"lever order from {LEVER_SOURCE}: " + " > ".join(LEVER_ORDER)
            if age is not None and 35 <= age <= 79
            else "guideline order (age outside the model's 35-79 range, so no model ranking)"
        )
        ids = list(choices)
        if prev_ref and fb and fb.status == "dismissed":
            ids = [c for c in ids if c != prev_ref.catalog_id]
            if not ids:
                self.changes.append(
                    PlanChange(
                        item_id="habit",
                        change="removed",
                        explanation="You set the habit idea aside, so I left it off today.",
                    )
                )
                self.trace.append(
                    TraceStep(
                        item_id="habit",
                        facts=[fact("feedback.habit", "dismissed")],
                        rule="dismissed, and no other habit applies",
                        evidence=cat.HABITS.get(
                            prev_ref.catalog_id, cat.HABITS["sitting_breaks"]
                        ).source[1],
                        action="no habit item",
                    )
                )
                return None
            chosen, change = ids[0], "swapped"
            explanation = f"You set that one aside, so here's {cat.HABITS[chosen].title.lower()}."
        elif not ids:
            if prev_ref:
                self.changes.append(
                    PlanChange(
                        item_id="habit",
                        change="removed",
                        explanation="Your sleep and sitting answers look fine, so no habit idea today.",
                    )
                )
            return None
        elif prev_ref and prev_ref.catalog_id in ids:
            chosen, change = prev_ref.catalog_id, "kept"
            explanation = f"Kept {cat.HABITS[chosen].title.lower()}, since it still fits."
        else:
            chosen = ids[0]
            change = "new" if not prev_ref else "swapped"
            explanation = (
                "A small habit to try."
                if change == "new"
                else f"Changed to {cat.HABITS[chosen].title.lower()}, to fit your latest answers."
            )
        card = cat.HABITS[chosen]
        facts = choices[chosen] + ([fact("feedback.habit", fb.status)] if fb else [])
        message = (
            card.variants.get("seated_only", card.message)
            if "seated_only" in self.limits
            else card.message
        )
        self.changes.append(PlanChange(item_id="habit", change=change, explanation=explanation))
        self.trace.append(
            TraceStep(
                item_id="habit", facts=facts, rule=rule, evidence=card.source[1], action=card.id
            )
        )
        self.drafts.append(Draft("habit", message, card.keep_words))
        return PlanItem(
            id="habit",
            kind="habit",
            action_id=card.id,
            catalog_id=card.id,
            lever=card.lever,
            title=card.title,
            message=message,
            why=card.why,
            time_of_day=HABIT_TIMES[card.id],
            based_on=sorted({f.source for f in facts})[:8],
            wellness_card=card.wellness_card,
            source_title=card.source[0],
            source_url=card.source[1],
        )

    # -- encouragement --------------------------------------------------------

    def mood(self) -> tuple[str, int | None, int, list[TraceFact]]:
        this_week = self.active_days(0, 6)
        last_week = self.active_days(7, 13)
        done = sorted(s for s, f in self.feedback.items() if f.status == "done")
        tasks = {s for s in self.feedback if s != "cheer"}
        unknown = "not logged (unknown)"
        facts = [
            fact("checkins.active days this week", unknown if this_week is None else this_week),
            fact("checkins.active days last week", unknown if last_week is None else last_week),
            fact("feedback.done", ",".join(done) or "none"),
        ]
        heard_lately = any(0 <= _days(d.date, self.today) <= 3 for d in self.req.checkins)
        if self.concerned or self.paused:
            mood = "concerned"
        elif len(done) >= 2 and set(done) >= tasks:
            mood = "celebrate"
        elif done:
            mood = "proud"
        elif this_week:
            # Fewer than last week is "cozy"; an unlogged week is unknown, never "fewer".
            mood = "cozy" if last_week is not None and this_week < last_week else "happy"
        elif this_week == 0:
            mood = "cozy"
        elif not heard_lately and not self.feedback:
            mood = "waiting"
        else:
            mood = "cozy"
        if self.feeling_low() and mood in {"happy", "proud", "celebrate"}:
            facts.append(fact("checkins.wellbeing", "not_great: tone only"))
            mood = "cozy"
        good_weeks = sum(1 for w in range(4) if (self.active_days(7 * w, 7 * w + 6) or 0) >= 2)
        facts.append(fact("checkins.good weeks of the last 4 (2+ active days)", good_weeks))
        return mood, this_week, good_weeks, facts

    def build_cheer(
        self,
        mood: str,
        this_week: int | None,
        good_weeks: int,
        facts: list[TraceFact],
        titles: dict[str, str],
    ) -> PlanItem:
        done = [titles[s] for s, f in self.feedback.items() if f.status == "done" and s in titles]
        days = this_week or 0
        text = {
            "concerned": "I'm sorry you're not feeling your best. Rest is fine, and gentle is good.",
            "celebrate": "You did everything on the last plan. That's worth a little dance!",
            "proud": f"You did {done[0].lower() if done else 'your plan'}. Nice work!",
            "happy": f"You moved on {days} {'day' if days == 1 else 'days'} this week. "
            "Your legs will thank you.",
            "cozy": "Some weeks are like that. Want to pick one small thing for today?",
            "waiting": "Nice to hear from you. How have you been?",
        }[mood]
        if mood in {"happy", "proud", "celebrate"} and good_weeks >= 2:
            text += f" That makes {good_weeks} good weeks lately."
        goal = next((g for g in self.req.goals if self.goal_ok(g)), None)
        if (
            goal
            and self.req.memory_consent is True
            and not self.ignore_notes
            and not self.callback_used
            and mood != "concerned"
        ):
            mine = re.sub(r"\bmy\b", "your", re.sub(r"\b(?:I|me)\b", "you", goal.strip(" .")))
            text += f" You told me you want to {mine[0].lower()}{mine[1:]}."
            facts = facts + [fact("goals", goal)]
        self.changes.append(
            PlanChange(
                item_id="cheer", change="new", explanation="Fresh words from how your days went."
            )
        )
        self.trace.append(
            TraceStep(
                item_id="cheer",
                facts=facts,
                rule="tone_table: mood follows effort and engagement, never the forecast; "
                "good weeks, never streaks (report §4)",
                evidence=cat.GAIN_FRAMING[1],
                action=f"mood {mood}",
            )
        )
        self.drafts.append(Draft("cheer", text, ()))
        return PlanItem(
            id="cheer",
            kind="encourage",
            action_id=f"cheer_{mood}",
            catalog_id=f"cheer_{mood}",
            lever="keep_it_up",
            title="A word from Mochi",
            message=text,
            why="Mochi notices effort. Every bit counts.",
            time_of_day=self.default_time(),
            based_on=sorted({f.source for f in facts})[:8],
            source_title=cat.GAIN_FRAMING[0],
            source_url=cat.GAIN_FRAMING[1],
        )

    @staticmethod
    def goal_ok(goal: str) -> bool:
        return (
            bool(re.fullmatch(r"[A-Za-z][A-Za-z' ,-]{0,79}", goal.strip()))
            and len(goal.split()) <= 8
            and not BLOCKED.search(goal)
        )

    # -- the run --------------------------------------------------------------

    def reusable(self, snapshot_id: str) -> bool:
        """Same day, same observed inputs, nothing new said or reported: keep the plan."""
        prev = self.prev
        return bool(
            prev
            and prev.local_date == self.today
            and prev.input_snapshot_id == snapshot_id
            and not self.req.said
            and all(f.status == "accepted" and not f.reason for f in self.feedback.values())
        )

    def run(self) -> Plan:
        texts = [self.req.said] + [f.reason for f in self.feedback.values()]
        if any(is_emergency(t) for t in texts):
            return self.emergency_plan()
        self.read_said()
        self.read_feedback_and_notes()
        snapshot_id = self.snapshot()
        if self.reusable(snapshot_id):
            return self.reuse(snapshot_id)
        items: list[PlanItem] = []
        general = not self.has_data()
        if general:
            facts = [fact("default", "no profile, check-ins, notes or plan yet")]
            self.trace.append(
                TraceStep(
                    item_id="plan",
                    facts=facts,
                    rule="fallback: nothing confirmed yet, so a labelled general plan with the "
                    "safest seated start",
                    evidence=cat.CDC_OLDER[1],
                    action="general plan",
                )
            )
            activity = cat.ACTIVITIES["chair_march"]
            self.changes.append(
                PlanChange(
                    item_id="move",
                    change="new",
                    explanation="A gentle start while I get to know you.",
                )
            )
            items.append(
                self.move_item(
                    activity,
                    activity.minutes,
                    None,
                    None,
                    facts,
                    "fallback: chair marching suits everyone",
                )
            )
        else:
            level, level_facts = self.level()
            move = self.build_move(level, level_facts)
            if move:
                items.append(move)
        items.append(self.build_food())
        habit = self.build_habit()
        if habit:
            items.append(habit)
        mood, this_week, good_weeks, mood_facts = self.mood()
        items.append(
            self.build_cheer(
                mood, this_week, good_weeks, mood_facts, {i.id: i.title for i in items}
            )
        )
        return self.finish(items, snapshot_id, mood, general)

    def refs(self, items: list[PlanItem]) -> list[PlanItemRef]:
        return [
            PlanItemRef(
                id=i.id,
                kind=i.kind,
                catalog_id=i.catalog_id,
                minutes=i.minutes,
                time_of_day=i.time_of_day,
                callback_note_id=i.callback_note_id,
            )
            for i in items
        ]

    def finish(self, items: list[PlanItem], snapshot_id: str, mood: str, general: bool) -> Plan:
        based_on = self.prev.revision_id if self.prev else None
        inputs = self.input_summary(snapshot_id)
        clarify = CLARIFY if "weekly activity" in inputs.missing else None
        return Plan(
            status="ok",
            revision_id=revision_id(based_on, self.today, snapshot_id, self.refs(items)),
            based_on=based_on,
            inputs=inputs,
            plan_type="general" if general else "personal",
            reused_previous=False,
            clarify=clarify,
            reply=self.reply,
            lines=self.lines(items, general),
            items=items,
            changes=self.changes,
            trace=self.trace,
            mood=mood,
            emergency=False,
            movement_paused=self.paused,
            memory_instruction=self.memory_instruction,
            drafts=self.drafts,
            provider_blocked=self.provider_blocked,
        )

    def reuse(self, snapshot_id: str) -> Plan:
        """Rebuild today's plan from its own choices; the same revision comes back."""
        prev = self.prev
        items: list[PlanItem] = []
        notes = {n.id: n for n in self.notes()}
        for ref in prev.items:
            facts = [
                fact("previous_plan", f"{ref.id}: {ref.catalog_id}"),
                fact("inputs", f"snapshot {snapshot_id} unchanged today"),
            ]
            if ref.id == "move" and ref.catalog_id in cat.ACTIVITIES:
                activity = cat.ACTIVITIES[ref.catalog_id]
                items.append(
                    self.move_item(
                        activity,
                        ref.minutes or activity.minutes,
                        notes.get(ref.callback_note_id or ""),
                        ref.time_of_day,
                        facts,
                        "reuse: nothing new since today's plan",
                    )
                )
            elif ref.id == "food" and ref.catalog_id in cat.DIET:
                card = cat.DIET[ref.catalog_id]
                items.append(
                    self.food_item(
                        card,
                        card.message,
                        None,
                        facts,
                        "reuse: nothing new since today's plan",
                        ref.time_of_day or "afternoon",
                    )
                )
            elif ref.id == "habit" and ref.catalog_id in cat.HABITS:
                card = cat.HABITS[ref.catalog_id]
                self.trace.append(
                    TraceStep(
                        item_id="habit",
                        facts=facts,
                        rule="reuse: nothing new since today's plan",
                        evidence=card.source[1],
                        action=card.id,
                    )
                )
                self.drafts.append(Draft("habit", card.message, card.keep_words))
                items.append(
                    PlanItem(
                        id="habit",
                        kind="habit",
                        action_id=card.id,
                        catalog_id=card.id,
                        lever=card.lever,
                        title=card.title,
                        message=card.message,
                        why=card.why,
                        time_of_day=ref.time_of_day or HABIT_TIMES[card.id],
                        based_on=["previous_plan"],
                        wellness_card=card.wellness_card,
                        source_title=card.source[0],
                        source_url=card.source[1],
                    )
                )
        mood, this_week, good_weeks, mood_facts = self.mood()
        cheer_ref = self.prev_refs.get("cheer")
        if cheer_ref and cheer_ref.catalog_id.startswith("cheer_"):
            mood = cheer_ref.catalog_id.removeprefix("cheer_")
        cheer = self.build_cheer(
            mood, this_week, good_weeks, mood_facts, {i.id: i.title for i in items}
        )
        if cheer_ref and cheer_ref.time_of_day:
            cheer = cheer.model_copy(update={"time_of_day": cheer_ref.time_of_day})
        items.append(cheer)
        self.changes = [
            PlanChange(
                item_id=i.id,
                change="kept",
                explanation="Nothing new since today's plan, so it stays the same.",
            )
            for i in items
        ]
        lines = ["Nothing new since this morning, so today's plan stays the same."]
        lines += [i.message for i in items]
        return Plan(
            status="ok",
            revision_id=prev.revision_id,
            based_on=prev.based_on,
            inputs=self.input_summary(snapshot_id),
            plan_type="personal",
            reused_previous=True,
            clarify=None,
            reply=None,
            lines=lines[:10],
            items=items,
            changes=self.changes,
            trace=self.trace,
            mood=mood,
            emergency=False,
            movement_paused=self.paused,
            memory_instruction=None,
            drafts=self.drafts,
            provider_blocked=False,
        )

    def lines(self, items: list[PlanItem], general: bool) -> list[str]:
        out = [self.reply] if self.reply else []
        if general:
            out.append("Here's a general plan for today, until I know a little more about you.")
        elif self.prev is None:
            out.append("Here's a small plan for today.")
        else:
            out.append("Here's today's plan.")
        shown = [
            c.explanation
            for c in self.changes
            if c.change in SHOWN_CHANGES
            or (c.change == "new" and self.cleared and c.item_id == "move")
        ]
        if self.prev is not None and not shown:
            shown = ["I kept the plan the same, since nothing called for a change."]
        out.extend(shown[: max(0, 10 - len(out) - len(items))])
        out.extend(item.message for item in items)
        return out[:10]

    def emergency_plan(self) -> Plan:
        self.trace.append(
            TraceStep(
                item_id="plan",
                facts=[fact("said", "something urgent is happening now")],
                rule="emergency_gate: the existing 911 line; no plan and no provider call",
                evidence="server/lifetwin/onboarding/intents.py (EMERGENCY)",
                action="911 line, no plan",
            )
        )
        return Plan(
            status="emergency",
            revision_id=None,
            based_on=self.prev.revision_id if self.prev else None,
            inputs=None,
            plan_type=None,
            reused_previous=False,
            clarify=None,
            reply=EMERGENCY_MESSAGE,
            lines=[EMERGENCY_MESSAGE],
            items=[],
            changes=[],
            trace=self.trace,
            mood="concerned",
            emergency=True,
            movement_paused=self.req.movement_paused,
            memory_instruction=None,
            drafts=[],
            provider_blocked=True,
        )
