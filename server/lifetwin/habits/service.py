"""Proposing, updating, asking about and summarising habits. Stateless and deterministic.

Order of checks on every request that carries words: an emergency first (any age),
then food worries, then the age floor (18+), then everything else. A habit is
proposed one at a time, asked first, and never while 2 are active.
"""

import re
from datetime import date, timedelta

from fastapi import HTTPException

from lifetwin.habits.answers import read_answer
from lifetwin.habits.catalogue import (
    CATALOGUE,
    GUIDELINE_ORDER,
    LEVER_HABIT,
    LEVER_ORDER,
    PILLAR_WORDS,
    CatalogId,
    Lever,
    age_band,
)
from lifetwin.habits.models import (
    ADULT_AGE,
    MAX_ACTIVE,
    HabitProposeRequest,
    HabitProposeResponse,
    HabitQuestionRequest,
    HabitQuestionResponse,
    HabitRecord,
    HabitUpdateRequest,
    HabitUpdateResponse,
    HabitWeekRequest,
    HabitWeekResponse,
)
from lifetwin.habits.safety import REPLIES, check, first_stop

DAYS_FOR_GOOD_WEEK = 4
DISMISS_DAYS = 14
# Ages 30+ get the model's levers; the survival model does not cover younger people.
LEVER_AGE = 30
AGE_NOT_SUPPORTED = (
    "Habits with Mochi are for adults, so I can't suggest health habits here. "
    "A parent, carer or doctor is a great person to talk to about feeling your best."
)
ASK_FIRST = "Want a small idea? "
CHOICES = " You can say yes, change it, or not now."
STILL_HERE = "Still here whenever you want it."

# The person's own words, matched to habits in order. Weight is never a reason.
WORD_RULES: tuple[tuple[re.Pattern[str], tuple[CatalogId, ...]], ...] = tuple(
    (re.compile(pattern), ids)
    for pattern, ids in (
        (r"\b(?:3|three) ?pm\b|\bafternoons?\b|\bafter lunch\b|\bslump\b", ("walk_after_lunch",)),
        (
            r"\bsmok\w*|\bcigarettes?\b|\bvap(?:e|es|ing)\b|\bnicotine\b",
            ("quit_help",),
        ),
        (
            r"\btired\b|\bexhausted\b|\bwiped(?: out)?\b|\bfoggy\b|\bno energy\b|\blow energy\b|"
            r"\bmore energy\b|\bsleepy\b|\bdrained\b|\bworn out\b|\bsluggish\b",
            ("morning_daylight", "walk_after_lunch"),
        ),
        (
            r"\bsleep\w*|\binsomnia\b|\bbedtime\b|\bnight owl\b|\bstay(?:ing)? up late\b|"
            r"\blate nights?\b|\bin bed\b",
            ("steady_bedtime", "morning_daylight"),
        ),
        (
            r"\bstress\w*|\banxi\w*|\boverwhelm\w*|\btense\b|\bworr\w*|\bon edge\b|\bfrazzled\b|"
            r"\bburn(?:ed|t) out\b|\bcalm(?:er)?\b|\bunwind\b|\brelax\w*",
            ("three_breaths", "walk_after_lunch"),
        ),
        (
            r"\blonel\w*|\bisolat\w*|\bmiss (?:my )?(?:friends|family|people)\b|"
            r"\b(?:no ?one|nobody) to talk\b|\bdisconnected\b|\bkeep in touch\b",
            ("text_a_friend",),
        ),
        (
            r"\bsit(?:ting)? (?:all day|too much|a lot)\b|\bdesk\b|\bstiff\b|\bcouch\b|\bsofa\b|"
            r"\bgaming\b|\bsedentary\b|\bscreen time\b",
            ("stand_on_calls",),
        ),
        (
            r"\bfocus\w*|\bconcentrat\w*|\bdistract\w*",
            ("stand_on_calls", "morning_daylight"),
        ),
        (
            r"\bfit(?:ness|ter)?\b|\bout of shape\b|\bget moving\b|\bmove more\b|\bwalk\w*|"
            r"\bstamina\b|\bexercise\b|\bmore active\b|\bkeep up with\b",
            ("brisk_walk", "walk_after_lunch"),
        ),
        (r"\bwater\b|\bthirsty\b|\bhydrat\w*|\bdehydrat\w*", ("water_with_meals",)),
    )
)


def _words(text: str) -> str:
    return " ".join(re.sub(r"[^\w'\s-]", " ", text.lower().replace("’", "'")).split())


def _day(value: str) -> date:
    return date.fromisoformat(value)


def _not_found() -> HTTPException:
    return HTTPException(
        status_code=404,
        detail={"code": "habit_not_found", "message": "That habit isn't on this phone."},
    )


def _invalid(message: str) -> HTTPException:
    return HTTPException(
        status_code=409, detail={"code": "invalid_habit_transition", "message": message}
    )


def phrase(habit: HabitRecord) -> str:
    """ "After lunch, walk for 2 minutes outside" """
    return f"{habit.anchor.rstrip(' ,.')}, {habit.tiny_action.rstrip(' .')}"


class HabitService:
    # -- propose -----------------------------------------------------------------

    def propose(self, request: HabitProposeRequest) -> HabitProposeResponse:
        words = request.own_words if request.memory_consent else []
        stop = first_stop(words)
        if stop:
            return HabitProposeResponse(
                status="safety",
                message=REPLIES[stop],
                mood="concerned",
                emergency=stop == "emergency",
                safety=stop,
            )
        if request.age < ADULT_AGE:
            return HabitProposeResponse(
                status="age_not_supported", message=AGE_NOT_SUPPORTED, mood="cozy"
            )
        active = [habit for habit in request.habits if habit.status == "active"]
        if len(active) >= MAX_ACTIVE:
            return HabitProposeResponse(
                status="at_limit",
                message=(
                    "You already have two habits going, which is plenty. "
                    "Let's keep enjoying those for now."
                ),
                mood="happy",
            )
        pending = next((habit for habit in request.habits if habit.status == "proposed"), None)
        if pending:
            return self._offer(pending, "pending")
        today = _day(request.local_date)
        taken = {
            habit.catalog_id
            for habit in request.habits
            if habit.status in {"active", "graduated"}
            or (habit.status == "dismissed" and _day(habit.dismissed_until or "") > today)
        }
        for catalog_id, source, why, lever in self._candidates(request, words):
            if catalog_id in taken:
                continue
            item = CATALOGUE[catalog_id]
            record = HabitRecord(
                id=f"{catalog_id}-{request.local_date.replace('-', '')}",
                catalog_id=catalog_id,
                pillar=item.pillar,
                anchor=item.anchors[age_band(request.age)],
                tiny_action=item.tiny_action,
                why_words=why,
                lever=lever,
                source=source,
                status="proposed",
            )
            return self._offer(record, "proposed")
        return HabitProposeResponse(
            status="nothing_new",
            message="I don't have a new idea right now. " + STILL_HERE,
            mood="cozy",
        )

    @staticmethod
    def _candidates(request: HabitProposeRequest, words: list[str]):
        """(catalog id, source, why words, lever) in ranking order; repeats are skipped later."""
        smoker = request.profile.smoking_status == "current"
        for text in words:
            if check(text):
                continue  # supplements, medicines or alcohol: never a reason for a habit
            said = _words(text)
            plain = " ".join(text.split())
            why = plain if len(plain) <= 80 and any(ch.isalpha() for ch in plain) else None
            for pattern, ids in WORD_RULES:
                if pattern.search(said):
                    for catalog_id in ids:
                        yield catalog_id, "said", why, CATALOGUE[catalog_id].lever
        if request.age >= LEVER_AGE:
            for lever in LEVER_ORDER:
                if HabitService._lever_applies(request, lever):
                    yield LEVER_HABIT[lever], "model_lever", None, lever
        if smoker:
            yield "quit_help", "guideline", None, None
        for catalog_id in GUIDELINE_ORDER:
            yield catalog_id, "guideline", None, None

    @staticmethod
    def _lever_applies(request: HabitProposeRequest, lever: Lever) -> bool:
        profile = request.profile
        if lever == "quit_smoking":
            return profile.smoking_status == "current"
        if lever in {"vigorous_activity", "moderate_activity"}:
            # Below the guideline; extra activity above it changes almost nothing.
            minutes = profile.exercise_minutes_weekly
            return minutes is not None and minutes < 150
        if lever == "sleep":
            return profile.sleep_hours is not None and profile.sleep_hours < 7
        minutes = request.sitting_minutes_daily
        return minutes is not None and minutes >= 90

    @staticmethod
    def _offer(record: HabitRecord, status: str) -> HabitProposeResponse:
        item = CATALOGUE[record.catalog_id]
        if record.catalog_id == "quit_help":
            message = (
                "If you'd ever like help with smoking, here's one small step: "
                + phrase(record)
                + ". No pressure at all."
            )
        else:
            message = ASK_FIRST + phrase(record) + "."
            if record.source == "said":
                message += (
                    f' You said "{record.why_words}", so this might help.'
                    if record.why_words
                    else " It fits what you told me."
                )
            elif record.source == "model_lever":
                message += " It's one of the everyday changes your twin responds to."
            else:
                message += " It's a small step from everyday health guidelines."
        return HabitProposeResponse(
            status=status,
            proposal=record,
            message=message + CHOICES,
            mood="happy",
            supports=f"This supports your {PILLAR_WORDS[record.pillar]}.",
            source_title=item.source.title,
            source_url=item.source.url,
        )

    # -- accept, edit, dismiss -----------------------------------------------------

    def update(self, request: HabitUpdateRequest) -> HabitUpdateResponse:
        habit = next((h for h in request.habits if h.id == request.habit_id), None)
        if habit is None:
            raise _not_found()
        edits = {
            name: value
            for name in ("anchor", "tiny_action", "why_words")
            if (value := getattr(request, name)) is not None
        }
        for value in edits.values():
            kind = check(value)
            if kind:
                return HabitUpdateResponse(
                    status="safety",
                    habit=habit,
                    message=REPLIES[kind],
                    mood="concerned",
                    emergency=kind == "emergency",
                    safety=kind,
                )
        if request.age < ADULT_AGE:
            return HabitUpdateResponse(
                status="age_not_supported", message=AGE_NOT_SUPPORTED, mood="cozy"
            )
        if request.action == "accept":
            if habit.status == "active":
                return HabitUpdateResponse(
                    status="active",
                    habit=habit,
                    message="That one's already one of your habits.",
                    mood="happy",
                )
            if habit.status != "proposed":
                raise _invalid("Only a suggested habit can be started.")
            others = [h for h in request.habits if h.status == "active" and h.id != habit.id]
            if len(others) >= MAX_ACTIVE:
                return HabitUpdateResponse(
                    status="at_limit",
                    habit=habit,
                    message=(
                        "You already have two habits going. Want to set one aside first? "
                        "Then we can start this one."
                    ),
                    mood="happy",
                )
            started = habit.model_copy(
                update={"status": "active", "started_on": request.local_date}
            )
            return HabitUpdateResponse(
                status="active",
                habit=HabitRecord.model_validate(started.model_dump()),
                message=f"Lovely. {phrase(started)}. I'll ask about it now and then.",
                mood="happy",
            )
        if request.action == "edit":
            if habit.status not in {"proposed", "active"}:
                raise _invalid("Only a suggested or current habit can be changed.")
            changed = HabitRecord.model_validate(habit.model_dump() | edits)
            return HabitUpdateResponse(
                status=changed.status,  # type: ignore[arg-type]
                habit=changed,
                message=f"Got it. Now it's: {phrase(changed)}.",
                mood="happy",
            )
        if habit.status == "dismissed":
            return HabitUpdateResponse(
                status="dismissed", habit=habit, message="That's set aside already.", mood="cozy"
            )
        if habit.status not in {"proposed", "active"}:
            raise _invalid("Only a suggested or current habit can be set aside.")
        until = (_day(request.local_date) + timedelta(days=DISMISS_DAYS)).isoformat()
        dismissed = HabitRecord.model_validate(
            habit.model_dump() | {"status": "dismissed", "dismissed_until": until}
        )
        return HabitUpdateResponse(
            status="dismissed",
            habit=dismissed,
            message="No problem. I won't suggest that one again for a while.",
            mood="cozy",
        )

    # -- the check-in habit question -----------------------------------------------

    def question(self, request: HabitQuestionRequest) -> HabitQuestionResponse:
        if request.action == "reply":
            kind = first_stop([request.text or ""])
            if kind:
                return HabitQuestionResponse(
                    status="safety",
                    habit_id=request.habit_id,
                    message=REPLIES[kind],
                    mood="concerned",
                    emergency=kind == "emergency",
                    safety=kind,
                )
        if request.age < ADULT_AGE:
            return HabitQuestionResponse(
                status="age_not_supported", message=AGE_NOT_SUPPORTED, mood="cozy"
            )
        active = sorted(
            (habit for habit in request.habits if habit.status == "active"), key=lambda h: h.id
        )
        if request.action == "ask":
            if not active:
                return HabitQuestionResponse(
                    status="no_active_habit",
                    message="There's no habit to ask about today.",
                    mood="cozy",
                )
            chosen = next((h for h in active if h.id == request.habit_id), None)
            if chosen is None:
                # One question per check-in; with two habits, they take turns by day.
                chosen = active[_day(request.local_date).toordinal() % len(active)]
            question = (
                f'And your habit: "{phrase(chosen)}." Did you get to it today? '
                "Yes, sort of, or not today?"
            )
            return HabitQuestionResponse(
                status="asking",
                habit_id=chosen.id,
                question=question,
                message=question,
                mood="happy",
            )
        habit = next((h for h in request.habits if h.id == request.habit_id), None)
        if habit is None:
            raise _not_found()
        if habit.status != "active":
            raise _invalid("Only a current habit can be checked in.")
        if request.action == "skip":
            return self._skipped(habit)
        reading = read_answer(request.text or "")
        if reading == "unknown":
            return self._skipped(habit)
        if reading is None:
            return HabitQuestionResponse(
                status="not_understood",
                habit_id=habit.id,
                question=f"Did you get to it today? {phrase(habit)}. Yes, sort of, or not today?",
                message=(
                    "Sorry, I didn't quite catch that. Did you get to it today? "
                    "You can say yes, sort of, or not today."
                ),
                mood="happy",
            )
        message, mood = {
            "done": ("Nice one! That's a habit day.", "proud"),
            "partly": ("That still counts. Nice.", "proud"),
            "not_today": ("That's okay. There's always tomorrow.", "cozy"),
        }[reading]
        return HabitQuestionResponse(
            status="answered",
            habit_id=habit.id,
            result=reading,
            message=message,
            mood=mood,  # type: ignore[arg-type]
        )

    @staticmethod
    def _skipped(habit: HabitRecord) -> HabitQuestionResponse:
        return HabitQuestionResponse(
            status="skipped",
            habit_id=habit.id,
            message="That's fine. We'll leave today blank.",
            mood="cozy",
        )

    # -- the weekly summary ----------------------------------------------------------

    def week(self, request: HabitWeekRequest) -> HabitWeekResponse:
        habit = request.habit
        if request.age < ADULT_AGE:
            return HabitWeekResponse(
                status="age_not_supported",
                habit_id=habit.id,
                message=AGE_NOT_SUPPORTED,
                mood="cozy",
            )
        summary = week_summary(request.results, _day(request.local_date))
        days, good, total = summary["this_week"], summary["good"], summary["total"]
        name = CATALOGUE[habit.catalog_id].name
        if good:
            message = (
                f"That's your first good week with {name}!"
                if total == 1
                else f"That's {total} good weeks with {name}!"
            )
            mood = "celebrate"
        else:
            message = (
                f"{days} habit day{'' if days == 1 else 's'} so far this week."
                if days
                else STILL_HERE
            )
            if total:
                message += f" You've had {total} good week{'' if total == 1 else 's'} with it."
            mood = "proud" if days else "cozy"
        return HabitWeekResponse(
            status="ok",
            habit_id=habit.id,
            week_start=summary["week_start"],
            habit_days_this_week=days,
            good_week_this_week=good,
            good_weeks_total=total,
            ignored_future_days=summary["future"],
            message=message,
            mood=mood,  # type: ignore[arg-type]
        )


def week_start(day: date) -> date:
    """The Monday of the Monday-to-Sunday week the day is in."""
    return day - timedelta(days=day.weekday())


def week_summary(results: dict[str, str], today: date) -> dict:
    """Habit days this week, good weeks over all time (4+ days), and future days ignored.

    A habit day is a day marked done or partly. Days that are absent are unknown and
    never count against anything; good weeks are counted, never in a row.
    """
    per_week: dict[date, int] = {}
    future = 0
    for key, result in results.items():
        day = _day(key)
        if day > today:
            future += 1
            continue
        if result in {"done", "partly"}:
            start = week_start(day)
            per_week[start] = per_week.get(start, 0) + 1
    this_start = week_start(today)
    this_week = per_week.get(this_start, 0)
    return {
        "week_start": this_start.isoformat(),
        "this_week": this_week,
        "good": this_week >= DAYS_FOR_GOOD_WEEK,
        "total": sum(count >= DAYS_FOR_GOOD_WEEK for count in per_week.values()),
        "future": future,
    }
