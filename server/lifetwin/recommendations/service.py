"""Two or three personal suggestions from the confirmed profile and the person's words.

Deterministic first. Each suggestion follows a lever from the model's sensitivity
ranking (levers.py), is grounded in one of the on-device package's wellness cards and
its public source, and is one idea from the catalog (ideas.py): the one that best fits
the person's own words, age band and limitations, rotated by local calendar day so the
screen changes from day to day but stays the same within a day. Rules (owner and
model-sensitivity rulings):

- never weight, never years gained, a date or a promise; no percentage points;
- smoking first for current smokers;
- activity is "none versus any": someone doing none gets a small start (10-15 min);
  someone walking may pick up the pace; someone at 150+ gets encouragement only;
- sleep only for people under 7 hours; never "more sleep" at 8 or more;
- sitting less last;
- an idea ruled out by a limitation the person mentioned is never shown.
"""

import re
from datetime import date
from urllib.parse import urlparse

from lifetwin.coach.safety import safe_slot
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.model_inputs import character_hints
from lifetwin.onboarding.models import HabitNote, Recommendation, RecommendationIdea
from lifetwin.personalize.providers import Personalizer
from lifetwin.personalize.service import consented, phrase_recommendations
from lifetwin.recommendations.ideas import (
    ALL_AGES,
    ANY_PAIN,
    IDEAS,
    INTEREST_PATTERNS,
    NOTE_LIMITS,
    TIME_WORDS,
    Idea,
)
from lifetwin.recommendations.levers import (
    LEVER_FIELD,
    LEVER_ORDER,
    MIN_ADULT_AGE,
    MODEL_VERSION,
    UNDER_AGE,
    effect_category,
)
from lifetwin.recommendations.models import (
    LeverRanking,
    RecommendationRequest,
    RecommendationResponse,
)

# The package's wellness-card sources (model_handoff/lifetwin_on_device/lib/src/assessment.dart).
SOURCES = {
    "activity": (
        "CDC: Physical activity for adults",
        "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html",
    ),
    "sitting": (
        "CDC: Physical activity for adults",
        "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html",
    ),
    "sleep": ("CDC: About sleep", "https://www.cdc.gov/sleep/about/index.html"),
    "smoking": ("CDC: Smoking and tobacco use", "https://www.cdc.gov/tobacco/about/"),
}
LEAD = "Here are a few ideas from what you told me."
NOTHING_YET = (
    "Once I know a little more about your days, I'll have some ideas for you. There's no rush."
)
GOAL = 150  # CDC: at least 150 moderate-equivalent minutes a week; vigorous counts double
MAX_MESSAGE = 400
QUITLINE = "When you're ready, 1-800-QUIT-NOW offers free support."
SMALL_START = "Even 10 to 15 minutes counts."
ASK_DOCTOR = "Your doctor can suggest what's right for you."
WAKING = {"bathroom": "needing the bathroom", "worry": "worry", "noise": "noise"}


def today() -> date:
    """The server's calendar day, used when the request names no local date."""
    return date.today()


def _note(notes: list[HabitNote], topic: str) -> HabitNote | None:
    return next((note for note in reversed(notes) if note.topic == topic), None)


def _slot(value: str | None) -> bool:
    """The coach's slot filter, except that a note may name vitamin D (well known, low risk)."""
    return bool(value) and safe_slot(re.sub(r"\bvitamin d\b", "walk", value, flags=re.I))


# --- What the person's words tell us ------------------------------------------------------


class Person:
    """The tags the idea picker matches on, from the profile and every habit note."""

    def __init__(self, profile: HealthProfile, notes: list[HabitNote]):
        text = " ".join(
            str(value)
            for note in notes
            for key, value in note.model_dump(by_alias=True, exclude_none=True).items()
            if key not in {"topic", "source", "estimate_for", "tried_quitting"}
        ).lower()
        self.limits = {tag for tag, pattern in NOTE_LIMITS.items() if pattern.search(text)}
        if ANY_PAIN.search(text):
            self.limits.add("knee_pain")  # unnamed pain: keep to joint-friendly ideas
        self.interests = {tag for tag, pattern in INTEREST_PATTERNS.items() if pattern.search(text)}
        if any(note.naps and note.naps.lower() not in {"no", "never"} for note in notes):
            self.interests.add("nap")
        self.times = {tag for tag, pattern in TIME_WORDS.items() if pattern.search(text)}
        withs = " ".join((note.with_ or "").lower() for note in notes)
        self.social = (
            "solo"
            if re.search(r"\b(?:alone|myself|on my own)\b", withs)
            else "social"
            if re.search(r"\b(?:friends?|group|class|wife|husband|partner|grand\w*)\b", withs)
            else None
        )
        self.weather = bool(re.search(r"\b(?:weather|rain\w*|cold|hot|snow\w*|ice|icy)\b", text))
        age = profile.age
        self.band = (
            None
            if age is None or age < 18
            else "18-39"
            if age < 40
            else "40-64"
            if age < 65
            else "65+"
        )


def eligible(idea: Idea, person: Person) -> bool:
    """Never an idea a limitation rules out, the wrong age band, or a missing interest."""
    if person.limits & set(idea.avoid):
        return False
    if idea.needs and not person.interests & set(idea.interests):
        return False
    if person.band is None:
        # Unknown age: only ideas that suit every age, unless the person's words call for it.
        return idea.ages == ALL_AGES or (
            idea.needs and bool(person.interests & set(idea.interests))
        )
    return person.band in idea.ages


def score(idea: Idea, person: Person) -> int:
    shared = person.interests & set(idea.interests)
    # An idea made for something the person named (their dog, their grandkids) comes first.
    points = 3 * len(shared) + (2 if idea.needs and shared else 0)
    points += bool(person.times & set(idea.times))
    points += person.social is not None and idea.social == person.social
    if person.weather:
        points += {"indoor": 1, "outdoor": -2}.get(idea.place, 0)
    return points


def _day(local_date: str | date | None) -> int:
    if isinstance(local_date, str):
        local_date = date.fromisoformat(local_date)
    return (local_date or today()).toordinal()


def pick(lever: str, stage: str, person: Person, day: int) -> list[Idea]:
    """The fitting ideas, best first. Ties rotate by day, so each day leads with another."""
    pool = sorted(
        (i for i in IDEAS if i.lever == lever and stage in i.stages and eligible(i, person)),
        key=lambda i: i.id,
    )
    if not pool:
        return []
    shift = day + sum(map(ord, f"{lever}:{stage}"))
    out: list[Idea] = []
    for points in sorted({score(i, person) for i in pool}, reverse=True):
        tier = [i for i in pool if score(i, person) == points]
        k = shift % len(tier)
        out += tier[k:] + tier[:k]  # each tier rotates on its own: every idea gets its day
    return out


# --- Composing an idea's words --------------------------------------------------------------


def _fit(*parts: tuple[str, bool]) -> str:
    """Join (text, required) parts; drop optional ones from the front if it runs long."""
    kept = [p for p in parts if p[0]]
    while len(" ".join(t for t, _ in kept)) > MAX_MESSAGE:
        drop = next((p for p in kept if not p[1]), None)
        if drop is None:
            break
        kept.remove(drop)
    return " ".join(t for t, _ in kept)[:MAX_MESSAGE]


def _make(
    idea: Idea,
    message: str,
    based_on: list[str],
    kind: str | None = None,
) -> RecommendationIdea:
    source_title, source_url = SOURCES[idea.source]
    return RecommendationIdea(
        id=idea.id,
        lever=idea.lever,
        title=idea.title,
        message=message,
        based_on=based_on,
        wellness_card=idea.card,
        source_title=source_title,
        source_url=source_url,
        why_short=idea.why,
        source_domain=(urlparse(source_url).hostname or "").removeprefix("www."),
        kind=kind or idea.kind,
    )


def _with_alternatives(ideas: list[RecommendationIdea]) -> Recommendation | None:
    if not ideas:
        return None
    first, rest = ideas[0], ideas[1:4]
    return Recommendation(**first.model_dump(), alternatives=rest)


def _experiment(
    rec: RecommendationIdea, profile: HealthProfile
) -> tuple[str, float | int | str | None] | None:
    """The model input a lever changes and the value to try, from the person's own value.

    A missing current value is never filled in: the target is then None.
    """
    if rec.lever == "quit_smoking":
        return "smoking_status", "former"
    steps = {
        "vigorous_plus_60": ("vigorous_recreation_min_week", 60, None),
        "moderate_plus_90": ("moderate_recreation_min_week", 90, None),
        "short_sleep_plus_1h": ("sleep_hours", 1, 24),
        "sitting_minus_60_realistic": ("sedentary_min_day", -60, None),
    }
    if rec.lever not in steps:
        return None
    field, delta, cap = steps[rec.lever]
    current = getattr(profile, field)
    if current is None:
        return field, None
    target = current + delta
    return field, min(cap, target) if cap is not None else max(0, target)


def missing_inputs(profile: HealthProfile) -> list[str]:
    return [f for f in LEVER_FIELD.values() if getattr(profile, f) is None]


# --- One builder per lever --------------------------------------------------------------


def _smoking(profile: HealthProfile, notes: list[HabitNote], person: Person, day: int):
    if profile.smoking_status != "current":
        return None
    note = _note(notes, "smoking")
    based = ["smoking_status"] + (["note:smoking"] if note else [])
    opener = ""
    if note and note.tried_quitting == "yes":
        aid = f", with the {note.quit_aid}" if note.quit_aid else ""
        opener = f"You told me you've tried quitting before{aid}. It often takes a few tries."
    out = []
    for idea in pick("quit_smoking", "any", person, day):
        line = "" if "QUIT-NOW" in idea.message else QUITLINE
        out.append(_make(idea, _fit((opener, False), (idea.message, True), (line, True)), based))
    return _with_alternatives(out)


def _activity_minutes(profile: HealthProfile) -> int | None:
    moderate, vigorous = profile.moderate_recreation_min_week, profile.vigorous_recreation_min_week
    if moderate is None and vigorous is None:
        return profile.exercise_minutes_weekly
    return (moderate or 0) + 2 * (vigorous or 0)


def _verb(kind: str | None) -> str:
    return {
        "walking": "walk",
        "swimming": "swim",
        "gardening": "garden",
        "dancing": "dance",
        "cycling": "cycle",
        "golf": "play golf",
        "tennis": "play tennis",
        "yoga": "do yoga",
        "tai chi": "do tai chi",
    }.get(kind or "", f"enjoy {kind}" if kind else "keep active")


def _praised_kind(kind: str | None) -> str:
    """Mochi's pose for encouragement: the activity it praises, or a walk."""
    words = (kind or "").lower()
    if "danc" in words:
        return "dance"
    if any(w in words for w in ("yoga", "stretch", "tai chi", "pilates")):
        return "stretch"
    return "walk"


def _activity(profile: HealthProfile, notes: list[HabitNote], person: Person, day: int):
    minutes = _activity_minutes(profile)
    note = _note(notes, "exercise")
    kind = note.kind if note and _slot(note.kind) else None
    company = (
        f" with your {note.with_}"
        if note and _slot(note.with_) and note.with_ not in {"alone", "a class", "a group"}
        else ""
    )
    barrier = note.barrier if note and _slot(note.barrier) else None
    fields = [
        f
        for f in (
            "moderate_recreation_min_week",
            "vigorous_recreation_min_week",
            "exercise_minutes_weekly",
        )
        if getattr(profile, f) is not None
    ]
    based = fields + (["note:exercise"] if note else [])

    def build(lever: str, stage: str, opener: str = "", lead: str = "", tail: str = "", pose=None):
        return _with_alternatives(
            [
                _make(
                    idea,
                    _fit((opener, False), (lead, True), (idea.message, True), (tail, True)),
                    based,
                    pose,
                )
                for idea in pick(lever, stage, person, day)
            ]
        )

    if minutes is None:
        if not kind:
            return None
        return build("moderate_plus_90", "more", f"You said you enjoy {kind}{company}.")
    if minutes == 0:
        opener = f"You mentioned {barrier}." if barrier else ""
        tail = ASK_DOCTOR if person.limits else ""
        return build("moderate_plus_90", "start", opener, SMALL_START, tail)
    if minutes >= GOAL:
        doing = f", {kind}{company}" if kind else ""
        doing = doing if len(doing) <= 60 else ""  # room for the idea itself
        opener = (
            f"You're already active{doing}, at about {minutes} minutes a week. That's at or "
            f"above the {GOAL} minutes adults are advised to aim for. Keep it up!"
        )
        return build("keep_it_up", "keep", lead=opener, pose=_praised_kind(kind))
    walks = (
        profile.moderate_recreation_min_week or 0
    ) > 0 and not profile.vigorous_recreation_min_week
    if walks and not person.limits:
        doing = f"you {_verb(kind)}{company}" if kind else "you're active"
        pace = build("vigorous_plus_60", "pace", f"You said {doing}.")
        if pace:
            return pace
    opener = f"You said you {_verb(kind)}{company}." if kind else ""
    return build("moderate_plus_90", "more", opener)


def _sleep(profile: HealthProfile, notes: list[HabitNote], person: Person, day: int):
    if profile.sleep_hours is None or profile.sleep_hours >= 7:
        return None
    note = _note(notes, "sleep")
    based = ["sleep_hours"] + (["note:sleep"] if note else [])
    opener = f"You said you go to bed around {note.bedtime}." if note and note.bedtime else ""
    tail = ""
    if note and note.wakes_for:
        cause = WAKING.get(note.wakes_for, note.wakes_for)
        tail = f"If {cause} often wakes you, it's worth mentioning to your doctor."
    out = [
        _make(idea, _fit((opener, False), (idea.message, True), (tail, False)), based)
        for idea in pick("short_sleep_plus_1h", "any", person, day)
    ]
    return _with_alternatives(out)


def _sitting(profile: HealthProfile, notes: list[HabitNote], person: Person, day: int):
    if profile.sedentary_min_day is None or profile.sedentary_min_day < 240:
        return None
    based = ["sedentary_min_day"] + (["note:sitting"] if _note(notes, "sitting") else [])
    out = [
        _make(idea, idea.message, based)
        for idea in pick("sitting_minus_60_realistic", "any", person, day)
    ]
    return _with_alternatives(out)


BUILDERS = {
    "quit_smoking": _smoking,
    "vigorous_plus_60": _activity,  # one activity suggestion covers both activity levers
    "moderate_plus_90": None,
    "short_sleep_plus_1h": _sleep,
    "sitting_minus_60_realistic": _sitting,
}


def _fields(rec: RecommendationIdea, profile: HealthProfile) -> dict:
    exp = _experiment(rec, profile)
    return {
        "effect": effect_category(rec.lever, profile.age, profile.sex),
        "experiment_lever": exp[0] if exp else None,
        "experiment_target": exp[1] if exp else None,
    }


def suggest(
    profile: HealthProfile, notes: list[HabitNote], local_date: str | date | None = None
) -> list[Recommendation]:
    person, day = Person(profile, notes), _day(local_date)
    found: list[Recommendation] = []
    for lever in LEVER_ORDER:
        build = BUILDERS.get(lever)
        rec = build(profile, notes, person, day) if build else None
        if rec:
            fields = _fields(rec, profile)
            alternatives = [alt.model_copy(update=fields) for alt in rec.alternatives]
            found.append(rec.model_copy(update={**fields, "alternatives": alternatives}))
    # Encouragement goes last: changes first, praise after.
    found.sort(key=lambda rec: rec.lever == "keep_it_up")
    return found[:3]


def featured(recs: list[Recommendation]) -> str | None:
    """Today's one featured idea: the first change, or the encouragement if that is all."""
    first = next((rec for rec in recs if rec.lever != "keep_it_up"), recs[0] if recs else None)
    return first.id if first else None


async def recommend(
    request: RecommendationRequest, personalizer: Personalizer | None = None
) -> RecommendationResponse:
    if request.profile.age is not None and request.profile.age < MIN_ADULT_AGE:
        return RecommendationResponse(
            status="under_age",
            message=UNDER_AGE,
            recommendations=[],
            character_hints=character_hints(request.profile, []),
            lever_ranking=LeverRanking(model_version=MODEL_VERSION, order=list(LEVER_ORDER)),
        )
    recs = suggest(request.profile, request.habit_notes, request.local_date)
    phrased_by = "templates"
    if recs and consented(request.outside_ai_consent, personalizer):
        recs, used = await phrase_recommendations(
            personalizer, recs, request.profile.model_dump(), request.habit_notes
        )
        phrased_by = personalizer.name if used else "templates"
    message = " ".join([LEAD, *(rec.message for rec in recs)]) if recs else NOTHING_YET
    return RecommendationResponse(
        status="ok" if recs else "not_enough_information",
        missing_inputs=[] if recs else missing_inputs(request.profile),
        message=message[:1500],
        recommendations=recs,
        featured=featured(recs),
        character_hints=character_hints(request.profile, request.habit_notes),
        lever_ranking=LeverRanking(model_version=MODEL_VERSION, order=list(LEVER_ORDER)),
        phrased_by=phrased_by,
    )
