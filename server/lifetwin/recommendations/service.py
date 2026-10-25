"""Two or three personal suggestions from the confirmed profile and the person's words.

Deterministic templates first. Each suggestion follows a lever from the model's
sensitivity ranking (levers.py), is grounded in one of the on-device package's
wellness cards and its public source, and uses the person's own words where they
gave any. Rules (owner and model-sensitivity rulings):

- never weight, never years gained, a date or a promise; no percentage points;
- smoking first for current smokers;
- activity is "none versus any": someone doing none gets a small start (10-15 min);
  someone walking may pick up the pace; someone at 150+ gets encouragement only;
- sleep only for people under 7 hours; never "more sleep" at 8 or more;
- sitting less last.
"""

import math
from urllib.parse import urlparse

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.model_inputs import character_hints
from lifetwin.onboarding.models import HabitNote, Recommendation
from lifetwin.personalize.providers import Personalizer
from lifetwin.personalize.service import consented, phrase_recommendations
from lifetwin.recommendations.levers import (
    LEVER_FIELD,
    LEVER_ORDER,
    MIN_ADULT_AGE,
    MODEL_VERSION,
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
UNDER_AGE = (
    "I'm only able to share ideas with adults for now. "
    "A parent, guardian or your doctor is the best person to ask about healthy habits."
)
# One plain sentence per lever and template: no numbers, no promise of benefit (max 90).
WHY_SHORT = {
    "quit_smoking": "Support is there whenever you feel ready to quit.",
    "activity_start": "Even a short, easy walk is a good place to begin.",
    "activity_enjoy": "Building on something you already enjoy is easier to keep up.",
    "activity_pace": "A faster pace for part of your walk is a simple next step.",
    "activity_more": "A little more of what you already do is within reach.",
    "keep_it_up": "You are already active, so keep doing what works for you.",
    "short_sleep_plus_1h": "A regular bedtime leaves room for the sleep adults are advised to get.",
    "sitting_minus_60_realistic": "Standing and moving a bit more often breaks up long sitting.",
}
NOTHING_YET = (
    "Once I know a little more about your days, I'll have some ideas for you. There's no rush."
)
GOAL = 150  # CDC: at least 150 moderate-equivalent minutes a week; vigorous counts double
GENTLE_BARRIERS = ("pain", "trouble", "arthritis", "fear of falling", "balance", "breath")


def _note(notes: list[HabitNote], topic: str) -> HabitNote | None:
    return next((note for note in reversed(notes) if note.topic == topic), None)


def _rec(
    lever: str, card: str, title: str, message: str, based_on: list[str], why: str | None = None
) -> Recommendation:
    source_title, source_url = SOURCES[card]
    return Recommendation(
        id=lever,
        lever=lever,
        title=title,
        message=message,
        based_on=based_on,
        wellness_card=card,
        source_title=source_title,
        source_url=source_url,
        why_short=WHY_SHORT[why or lever],
        source_domain=(urlparse(source_url).hostname or "").removeprefix("www."),
    )


def _experiment(
    rec: Recommendation, profile: HealthProfile
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


def _plural(kind: str) -> str:
    word = {"walking": "walk", "swimming": "swim", "cycling": "ride", "dancing": "dance"}.get(kind)
    return f"{word}s" if word else "sessions"


def _smoking(profile: HealthProfile, notes: list[HabitNote]) -> Recommendation | None:
    if profile.smoking_status != "current":
        return None
    note = _note(notes, "smoking")
    based = ["smoking_status"] + (["note:smoking"] if note else [])
    if note and note.tried_quitting == "yes":
        aid = f", with the {note.quit_aid}" if note.quit_aid else ""
        text = (
            f"You told me you've tried quitting before{aid}. It often takes a few tries. "
            "When you feel ready, you could call 1-800-QUIT-NOW for free support."
        )
    else:
        text = (
            "Quitting smoking helps health at any age. When you feel ready, you could call "
            "1-800-QUIT-NOW for free, friendly support."
        )
    return _rec("quit_smoking", "smoking", "Support for quitting", text, based)


def _activity_minutes(profile: HealthProfile) -> int | None:
    moderate, vigorous = profile.moderate_recreation_min_week, profile.vigorous_recreation_min_week
    if moderate is None and vigorous is None:
        return profile.exercise_minutes_weekly
    return (moderate or 0) + 2 * (vigorous or 0)


def _activity(profile: HealthProfile, notes: list[HabitNote]) -> Recommendation | None:
    minutes = _activity_minutes(profile)
    note = _note(notes, "exercise")
    kind = note.kind if note and note.kind else None
    company = (
        f" with your {note.with_}"
        if note and note.with_ and note.with_ not in {"alone", "a class", "a group"}
        else ""
    )
    barrier = note.barrier if note and note.barrier else None
    gentle = barrier is not None and any(word in barrier for word in GENTLE_BARRIERS)
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
    if minutes is None:
        if not kind:
            return None
        return _rec(
            "moderate_plus_90",
            "activity",
            "More of what you enjoy",
            f"You said you enjoy {kind}{company}. Adding one more time each week is an easy way to build on it.",
            based,
            "activity_enjoy",
        )
    if minutes == 0:
        if barrier and gentle:
            text = (
                f"You mentioned {barrier}. Even 10 to 15 minutes counts, so a gentle start, "
                "like a short walk or chair exercises, could be a good first step. Your doctor "
                "can suggest what's right for you."
            )
        elif barrier and "weather" in barrier:
            text = (
                f"You mentioned {barrier}. Even 10 to 15 minutes counts, so a short walk "
                "indoors, like around a mall, could be a good start."
            )
        else:
            text = (
                "Even 10 to 15 minutes counts. You could start small, with a short walk after "
                "a meal a few days a week."
            )
        return _rec("moderate_plus_90", "activity", "A small start", text, based, "activity_start")
    if minutes >= GOAL:
        doing = f" {kind}{company}" if kind else ""
        return _rec(
            "keep_it_up",
            "activity",
            "Keep it up",
            f"You're already active{', ' + doing.strip() if doing else ''}, at about {minutes} "
            f"minutes a week. That's at or above the {GOAL} minutes adults are advised to aim "
            "for. Keep it up!",
            based,
            "keep_it_up",
        )
    walks = (
        profile.moderate_recreation_min_week or 0
    ) > 0 and not profile.vigorous_recreation_min_week
    if walks and not gentle:
        doing = f"you {_verb(kind)}{company}" if kind else "you're active"
        return _rec(
            "vigorous_plus_60",
            "activity",
            "Pick up the pace",
            f"You said {doing}. You could try a faster pace for part of it. Minutes that leave "
            f"you out of breath count double toward the weekly {GOAL}.",
            based,
            "activity_pace",
        )
    gap = GOAL - minutes
    sessions = max(1, min(3, math.ceil(gap / 30)))
    total = minutes + 30 * sessions
    what = _plural(kind or "")
    one = what[:-1] if sessions == 1 else what
    count = {1: "one more", 2: "two more", 3: "three more"}[sessions]
    lead = f"You said you {_verb(kind)}{company}. " if kind else ""
    return _rec(
        "moderate_plus_90",
        "activity",
        "A little more of it",
        f"{lead}Adding {count} {one} of about 30 minutes a week would bring you to about "
        f"{total} minutes, close to the {GOAL} minutes adults are advised to aim for.",
        based,
        "activity_more",
    )


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


def _sleep(profile: HealthProfile, notes: list[HabitNote]) -> Recommendation | None:
    if profile.sleep_hours is None or profile.sleep_hours >= 7:
        return None
    note = _note(notes, "sleep")
    based = ["sleep_hours"] + (["note:sleep"] if note else [])
    if note and note.bedtime:
        text = (
            f"You said you go to bed around {note.bedtime}. Going to bed a little earlier could "
            "help you get closer to the 7 hours CDC suggests for adults."
        )
    else:
        text = (
            "You could try a regular bedtime that leaves room for 7 hours, which CDC suggests "
            "for adults."
        )
    if note and note.wakes_for:
        cause = WAKING.get(note.wakes_for, note.wakes_for)
        text += f" If {cause} often wakes you, it's worth mentioning to your doctor."
    return _rec("short_sleep_plus_1h", "sleep", "A bit more sleep", text, based)


WAKING = {"bathroom": "needing the bathroom", "worry": "worry", "noise": "noise"}
SITTING_TIPS = {
    "tv": "You said a lot of your sitting is watching TV. You could stand up and move "
    "around during the ads.",
    "reading": "You said you like to read. You could stand and stretch at the end of each chapter.",
    "driving": "You said you drive a lot. A short stretch break on longer drives helps break "
    "up the sitting.",
    "computer": "You said you spend time at the computer. You could stand up and walk around "
    "every half hour or so.",
    "puzzles": "You said you enjoy puzzles. You could get up for a short walk between them.",
}


def _sitting(profile: HealthProfile, notes: list[HabitNote]) -> Recommendation | None:
    if profile.sedentary_min_day is None or profile.sedentary_min_day < 240:
        return None
    note = _note(notes, "sitting")
    kinds = (note.kind or "").split(" and ") if note else []
    tip = next((SITTING_TIPS[k] for k in kinds if k in SITTING_TIPS), None)
    text = (tip or "You could try standing up and moving for a few minutes every hour.") + (
        " Moving more and sitting less is good advice for everyone."
    )
    based = ["sedentary_min_day"] + (["note:sitting"] if note else [])
    return _rec("sitting_minus_60_realistic", "sitting", "Sit a little less", text, based)


BUILDERS = {
    "quit_smoking": _smoking,
    "vigorous_plus_60": _activity,  # one activity suggestion covers both activity levers
    "moderate_plus_90": None,
    "short_sleep_plus_1h": _sleep,
    "sitting_minus_60_realistic": _sitting,
}


def suggest(profile: HealthProfile, notes: list[HabitNote]) -> list[Recommendation]:
    found: list[Recommendation] = []
    for lever in LEVER_ORDER:
        build = BUILDERS.get(lever)
        rec = build(profile, notes) if build else None
        if rec:
            effect = effect_category(rec.lever, profile.age, profile.sex)
            exp = _experiment(rec, profile)
            found.append(
                rec.model_copy(
                    update={
                        "effect": effect,
                        "experiment_lever": exp[0] if exp else None,
                        "experiment_target": exp[1] if exp else None,
                    }
                )
            )
    # Encouragement goes last: changes first, praise after.
    found.sort(key=lambda rec: rec.lever == "keep_it_up")
    return found[:3]


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
    recs = suggest(request.profile, request.habit_notes)
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
        character_hints=character_hints(request.profile, request.habit_notes),
        lever_ranking=LeverRanking(model_version=MODEL_VERSION, order=list(LEVER_ORDER)),
        phrased_by=phrased_by,
    )
