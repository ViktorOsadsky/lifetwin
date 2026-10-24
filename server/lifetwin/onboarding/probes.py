"""Mochi's short follow-ups: one question to learn the habit behind an answer.

The catalogue is data. A probe is asked right after one of its ``after`` answers is
confirmed, when ``applies`` holds, and only if it is among the ``MAX_PROBES`` most
useful probes still possible (by ``lever``, in the model-sensitivity order). It is
never asked twice, and never when the person already told Mochi about that habit.
"""

from collections.abc import Callable
from dataclasses import dataclass

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import HabitNote, HabitTopic, ProbeId, ProfileField
from lifetwin.onboarding.script import ASKED
from lifetwin.recommendations.levers import LEVER_ORDER

MAX_PROBES = 3


def _activity(profile: HealthProfile) -> int | None:
    """Known weekly activity minutes, or None while it could still be more than zero."""
    parts = [profile.moderate_minutes_weekly, profile.vigorous_minutes_weekly]
    known = [value for value in parts if value is not None]
    if any(known):
        return sum(known)
    if profile.exercise_minutes_weekly:
        return profile.exercise_minutes_weekly
    return 0 if len(known) == 2 else None


def _smoking(status: str) -> Callable[[HealthProfile], bool | None]:
    def applies(profile: HealthProfile) -> bool | None:
        if profile.smoking_status in {None, "unknown"}:
            return None
        return profile.smoking_status == status

    return applies


@dataclass(frozen=True)
class Probe:
    id: ProbeId
    topic: HabitTopic
    after: frozenset[ProfileField]
    applies: Callable[[HealthProfile], bool | None]  # None: not known yet
    lever: str | None  # model-sensitivity lever it helps with; None ranks last
    ask: tuple[str, ...]


ACTIVITY_FIELDS = frozenset(
    {"moderate_minutes_weekly", "vigorous_minutes_weekly", "exercise_minutes_weekly"}
)

PROBES: tuple[Probe, ...] = (
    Probe(
        "smoking_history",
        "smoking",
        frozenset({"smoking_status"}),
        _smoking("current"),
        "quit_smoking",
        (
            "Can I ask how long you've smoked, and if you've ever tried to quit?",
            "How long have you smoked? Have you ever tried to stop?",
        ),
    ),
    Probe(
        "activity",
        "exercise",
        ACTIVITY_FIELDS,
        lambda p: None if _activity(p) is None else _activity(p) > 0,
        "vigorous_plus_60",
        (
            "What do you like to do to stay active, and who with?",
            "What keeps you moving, and do you go with anyone?",
        ),
    ),
    Probe(
        "inactive_barrier",
        "exercise",
        ACTIVITY_FIELDS,
        lambda p: None if _activity(p) is None else _activity(p) == 0,
        "moderate_plus_90",
        (
            "Is anything making it hard to get moving these days?",
            "Does anything get in the way of moving more?",
        ),
    ),
    Probe(
        "sleep_pattern",
        "sleep",
        frozenset({"sleep_hours"}),
        lambda p: None if p.sleep_hours is None else p.sleep_hours < 7,
        "short_sleep_plus_1h",
        (
            "When do you usually go to bed, and does anything wake you?",
            "What time do you turn in, and does anything wake you up?",
        ),
    ),
    Probe(
        "sitting_activities",
        "sitting",
        frozenset({"sitting_minutes_daily"}),
        lambda p: None if p.sitting_minutes_daily is None else p.sitting_minutes_daily >= 360,
        "sitting_minus_60_realistic",
        (
            "What keeps you sitting most, like TV, reading or driving?",
            "What do you mostly do sitting down? TV, reading, driving?",
        ),
    ),
    Probe(
        "health_feeling",
        "health",
        frozenset({"general_health"}),
        # Only for a fair or poor rating: what is behind it helps the suggestions most.
        lambda p: None if p.general_health is None else p.general_health in {"fair", "poor"},
        None,
        (
            "How do you feel about your health these days?",
            "How are you feeling about your health lately?",
        ),
    ),
    Probe(
        "quit_story",
        "smoking",
        frozenset({"smoking_status"}),
        _smoking("former"),
        None,
        ("Good for you for quitting. How long ago was that?",),
    ),
)
BY_ID = {probe.id: probe for probe in PROBES}


def _rank(probe: Probe) -> int:
    return LEVER_ORDER.index(probe.lever) if probe.lever in LEVER_ORDER else len(LEVER_ORDER)


def choose(
    profile: HealthProfile,
    just_confirmed: set[str],
    answered: set[str],
    asked: list[str],
    notes: list[HabitNote],
) -> Probe | None:
    """The probe to ask now, if any.

    A probe can be asked once one of its ``after`` answers is settled (``answered``
    holds every field with a value, unknown or skipped), so one that lost out to a more
    useful probe is asked at the next answer instead. Probes that can still come later
    compete for the remaining slots: a sleep question early on does not use up the slot
    an activity question would need. ``just_confirmed`` breaks ties toward the answer
    just given.
    """
    if len(asked) >= MAX_PROBES:
        return None
    covered = {note.topic for note in notes if note.estimate_for is None}

    def open_(probe: Probe) -> bool:
        return probe.id not in asked and probe.topic not in covered

    now = [
        probe
        for probe in PROBES
        if open_(probe) and probe.after & answered and probe.applies(profile) is True
    ]
    if not now:
        return None
    best = min(now, key=lambda probe: (_rank(probe), not probe.after & just_confirmed))
    later = [
        probe
        for probe in PROBES
        if open_(probe)
        and probe.applies(profile) is not False
        and not (probe.after & set(ASKED) & answered)
        and probe not in now
    ]
    ahead = [probe for probe in later if _rank(probe) < _rank(best)]
    return best if len(ahead) < MAX_PROBES - len(asked) else None
