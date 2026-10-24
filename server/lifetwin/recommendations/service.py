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

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.model_inputs import character_hints
from lifetwin.onboarding.models import HabitNote, Recommendation
from lifetwin.recommendations.levers import LEVER_ORDER, MODEL_VERSION
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
GENTLE_BARRIERS = ("pain", "trouble", "arthritis", "fear of falling", "balance", "breath")


def _note(notes: list[HabitNote], topic: str) -> HabitNote | None:
    return next((note for note in reversed(notes) if note.topic == topic), None)


def _rec(lever: str, card: str, title: str, message: str, based_on: list[str]) -> Recommendation:
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
    )


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
    moderate, vigorous = profile.moderate_minutes_weekly, profile.vigorous_minutes_weekly
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
        for f in ("moderate_minutes_weekly", "vigorous_minutes_weekly", "exercise_minutes_weekly")
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
        return _rec("moderate_plus_90", "activity", "A small start", text, based)
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
        )
    walks = (profile.moderate_minutes_weekly or 0) > 0 and not profile.vigorous_minutes_weekly
    if walks and not gentle:
        doing = f"you {_verb(kind)}{company}" if kind else "you're active"
        return _rec(
            "vigorous_plus_60",
            "activity",
            "Pick up the pace",
            f"You said {doing}. You could try going a little faster for part of it, until "
            "you're breathing harder. Brisk minutes count double toward the weekly goal of "
            f"{GOAL} minutes.",
            based,
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
        text += f" If {note.wakes_for} keeps waking you, it's worth mentioning to your doctor."
    return _rec("short_sleep_plus_1h", "sleep", "A bit more sleep", text, based)


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
    if profile.sitting_minutes_daily is None or profile.sitting_minutes_daily < 240:
        return None
    note = _note(notes, "sitting")
    kinds = (note.kind or "").split(" and ") if note else []
    tip = next((SITTING_TIPS[k] for k in kinds if k in SITTING_TIPS), None)
    text = (tip or "You could try standing up and moving for a few minutes every hour.") + (
        " Moving more and sitting less is good advice for everyone."
    )
    based = ["sitting_minutes_daily"] + (["note:sitting"] if note else [])
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
            found.append(rec)
    # Encouragement goes last: changes first, praise after.
    found.sort(key=lambda rec: rec.lever == "keep_it_up")
    return found[:3]


def recommend(request: RecommendationRequest) -> RecommendationResponse:
    recs = suggest(request.profile, request.habit_notes)
    message = " ".join([LEAD, *(rec.message for rec in recs)]) if recs else NOTHING_YET
    return RecommendationResponse(
        status="ok" if recs else "not_enough_information",
        message=message[:1500],
        recommendations=recs,
        character_hints=character_hints(request.profile, request.habit_notes),
        lever_ranking=LeverRanking(model_version=MODEL_VERSION, order=list(LEVER_ORDER)),
    )
