"""Daily and weekly check-in turns on the onboarding conversation machinery.

The same rules as onboarding apply: nothing is saved without a clear yes, a close
answer gets a targeted follow-up instead of a guess, room chatter is dropped, and
someone else's value is never taken. The check-in adds the previous answers: "same
as last week" offers the last value back for a yes.

Quick and daily check-ins keep moving: each answer is heard (``pending``), echoed in
a few words, and the next question follows. One read-back at the end covers every
answer, and a yes saves them all (``confirmed``); corrections are still possible
there. A value that looks unusual (more than 14 hours of sleep, more than 300 minutes
of activity or 16 hours of sitting in a day) gets one gentle check question first
(``checking``). The weekly check-in, which changes the profile, still reads back each
answer.
"""

import logging
import re
from collections.abc import Callable
from datetime import date
from typing import Literal

from fastapi import HTTPException

from lifetwin.checkin.models import (
    CheckinResponse,
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
    QuickPlan,
    daily_logs,
    profile_update,
)
from lifetwin.checkin.scripts import (
    AGE_FORMS,
    AGE_HELP,
    CLOSINGS,
    DAILY,
    DAILY_WITH_HABIT,
    DONE_AGAIN,
    GREETINGS,
    HABIT_DAYS,
    HELP,
    HOW_ARE_YOU,
    NO_PREVIOUS,
    PACES,
    PAIRS,
    PRIVATE_NOTE,
    QUESTIONS,
    SAME_LEAD,
    SITTING_PROXIES,
    WEEKLY,
    WHY_NOTES,
    CheckinField,
    quick_script,
)
from lifetwin.checkin.understanding import (
    ACTIVITY,
    SELF_CORRECTION,
    last_said,
    read_activity,
    read_sitting,
)
from lifetwin.core.models import CheckinValues
from lifetwin.onboarding.habits import merge, read_notes
from lifetwin.onboarding.intents import (
    EMERGENCY_MESSAGE,
    RESUME_LEAD,
    asks_back,
    clean_reply,
    control_intent,
    dont_know,
    emergency,
    focus,
    keeps_answer,
    read_back_reply,
    resumes,
    same_as_before,
)
from lifetwin.onboarding.intents import phrase as words_of
from lifetwin.onboarding.models import MascotEvent
from lifetwin.onboarding.parsing import (
    BP_FIELDS,
    CHECKIN_BASE,
    _canonical,
    _others,
    approximate,
    checkin_clarify,
    checkin_smoking,
    clarify,
    is_skip,
    no_new_reading,
    normalize_text,
    parse_reply,
)
from lifetwin.onboarding.script import SUPPLEMENT_REPLY
from lifetwin.onboarding.service import (
    ASKING,
    LOUDER_LEAD,
    NO_LEAD,
    NOT_CAUGHT,
    QUESTION_BACK_LEAD,
    REPEAT_LEAD,
    SKIPPED,
    SLOWER_LEAD,
    SUPPLEMENTS,
    THANKS,
    UNSURE_LEAD,
    WHAT_NOW,
    _plain,
    _weight,
)

logger = logging.getLogger(__name__)

BOTH_BP = ["systolic_bp", "diastolic_bp"]
UNKNOWN_LEAD = "That's okay, we'll leave that one for today. "
PROBE_SKIPPED = "Of course. "
PROBES = {
    "exercise": "What did you do? Or we can just move on.",
    "sleep": "Did anything keep you up? Or we can just move on.",
}
PROBE_MOVE_ON = re.compile(
    r"(?:(?:let's|lets) )?(?:just )?(?:move on|keep going|skip(?: it)?)|next|pass|no|nope|nah|"
    r"nothing|not really|no thanks|(?:i'd )?rather not(?: say)?|never mind"
)
BOTH_BP_MESSAGE = 'Please tell me both blood pressure numbers, for example "120 over 80".'
BP_ORDER = "The top number is usually the bigger one. Could you check your reading?"
CONFIRM_FIRST = "Please answer yes or no to what I just read back first."
RESTART_QUESTION = (
    "Do you want to clear today's answers and start again? "
    "If so, say yes, start over. Otherwise, just keep going."
)
HOW_ARE_YOU_ASKED = re.compile(r"\bhow (?:are|r) (?:you|u)\b|\bhow's (?:it going|mochi)\b")
# "How are you, Mochi?" said on its own, with or without a question mark.
ASKED_HOW_I_AM = re.compile(
    r"(?:and |so |well )?(?:how (?:are|r) (?:you|u)|how's it going|how about you|and you)"
    r"(?: (?:doing|today|mochi|yourself|dear))*"
)
HOW_ARE_YOU_TAIL = re.compile(
    r"[\s,.;!-]*(?:and |how about |what about )?(?:how are )?(?:you|yourself)(?: mochi)?"
    r"(?: doing)?[\s?!.]*$",
    re.I,
)
EXAMPLES: dict[str, str] = {
    "sleep_hours_last_night": '"7 hours"',
    "exercise_minutes_today": '"20 minutes", or "none"',
    "alcohol_drinks_yesterday": '"2 drinks", or "none"',
    "wellbeing": '"good", "okay" or "not great"',
    "sleep_hours": '"7 hours"',
    "exercise_minutes_weekly": '"90 minutes"',
    "alcohol_drinks_weekly": '"3 drinks", or "none"',
    "smoking_status": '"no, I don\'t smoke"',
    "weight_kg": '"160 pounds"',
    "systolic_bp": '"120 over 80"',
    "sleep_hours_night_before": '"7 hours"',
    "vigorous_recreation_min": '"20 minutes out of breath", or "none"',
    "moderate_recreation_min": '"30 minutes", or "none"',
    "sedentary_min_day": '"about 6 hours"',
    "vigorous_recreation_min_week": '"an hour", or "none"',
    "moderate_recreation_min_week": '"2 hours", or "none"',
}
LABELS: dict[str, str] = {
    "sleep_hours_last_night": "sleep",
    "exercise_minutes_today": "exercise",
    "alcohol_drinks_yesterday": "drinks",
    "wellbeing": "feeling",
    "sleep_hours": "sleep",
    "exercise_minutes_weekly": "exercise",
    "alcohol_drinks_weekly": "drinks",
    "smoking_status": "smoking",
    "weight_kg": "weight",
    "systolic_bp": "blood pressure",
    "diastolic_bp": "blood pressure",
    "sleep_hours_night_before": "sleep",
    "vigorous_recreation_min": "activity",
    "moderate_recreation_min": "activity",
    "sedentary_min_day": "sitting",
    "vigorous_recreation_min_week": "activity",
    "moderate_recreation_min_week": "activity",
}
OVER_A_DAY = "That adds up to more than a whole day. Could you check it for me?"
FEELING = {"good": "good", "okay": "okay", "not_great": "not great"}
LAST_FEELING = {"good": "good", "okay": "okay", "not_great": "not so great"}
# Quick and daily: the one read-back at the end, and what follows a "no" to it.
FINAL_LEAD = "Before I save anything, here's what I heard: "
FINAL_ASK = " Is that right?"
FINAL_CHANGE = (
    'What should I change? You can say something like "my sleep was 6 hours", '
    'or "go back to my sitting".'
)
FINAL_WHICH = "Which answer should I change: {topics}?"
FINAL_UNSURE = UNSURE_LEAD + 'If all of that is right, say "yes", or tell me what to change.'
CHECKED = "Thanks for checking. "
WHICH_ANSWER = (
    'Sorry, I wasn\'t sure if that changes your last answer. To change it, say "go back". '
)
# Feeling words, so a reply's clause about how the person feels can be told apart.
FEELING_WORDS = (
    r"\b(?:good|great|fine|okay|ok|alright|all right|well|not great|not so great|meh|"
    r"rubbish|awful|terrible|lousy|grand|happy|sad|tired|knackered|exhausted|so so)\b"
)
# The topics a clause of a reply can be about, by its words.
TOPIC_CUES: dict[str, str] = {
    "sleep": (
        r"\b(?:slept|sleep\w*|asleep|bed|woke|awake|insomnia|nap\w*|kip|"
        r"last night|the night before)\b"
    ),
    "activity": ACTIVITY + r"|\b(?:exercis\w*|moved|moving|active|steps)\b",
    "sitting": (
        r"\b(?:sat|sit|sitting|seated|desk|sofa|couch|tv|telly|screens?|computer|laptop|"
        r"gaming|office|in the car|driving|drove)\b"
    ),
    "feeling": r"\b(?:feel\w*|felt|mood)\b|" + FEELING_WORDS,
    "drinks": (
        r"\b(?:drinks?|drank|beers?|wines?|pints?|glass(?:es)?|alcohol\w*|cocktails?|"
        r"spirits|whiske?y|vodka|gin|cider|booze)\b"
    ),
}
TOPIC_OF: dict[str, str] = {
    "sleep_hours_last_night": "sleep",
    "sleep_hours_night_before": "sleep",
    "exercise_minutes_today": "activity",
    "vigorous_recreation_min": "activity",
    "moderate_recreation_min": "activity",
    "sedentary_min_day": "sitting",
    "wellbeing": "feeling",
    "alcohol_drinks_yesterday": "drinks",
}
TOPIC_LABELS = {
    "sleep": "your sleep",
    "activity": "your activity",
    "sitting": "your sitting",
    "feeling": "how you're feeling",
    "drinks": "your drinks",
}
# Where a reply splits into clauses; "an hour and a half" stays one duration.
CLAUSES = (
    r"[;,]|(?<!\d)\.(?!\d)|\bbut\b|\bthen\b|\bplus\b|\balso\b|"
    r"\band\b(?! (?:a )?(?:half|quarter|bit|little)\b| three quarters\b| [\w-]+(?: [\w-]+)? min)"
)
# Words that make the rest of a reply more than a note beside the answer.
NOT_A_NOTE = (
    r"\d|\b(?:no|not|nope|actually|wait|sorry|mean|meant|rather|or|maybe|probably|perhaps|"
    r"make that|instead|correction|less|more|either|between|same|hours?|minutes?|mins?|"
    r"hrs?|bit|little|half|quarter|few|couple|lots?|odd|plus|ish|times?|each|every|"
    r"usually|normally)\b"
)
# "Go back, I slept 5 not 7": a correction to an earlier answer, said to a later question.
FIX_LEAD = re.compile(
    r"^\W*(?:(?:oh|no|sorry|um+|uh+)\W+)*"
    r"(?:go back|back up|actually|i meant|i mean|correction|oops|wait|hang on|hold on)\b"
    r"[\s,.;:!-]*"
)
# How much in one day looks unusual enough to check once, gently, before it's kept.
UNUSUAL = {
    "sleep": 14,  # hours a night
    "activity": 300,  # minutes in a day
    "sitting": 960,  # minutes in a day
}


def _safe(read, *args, **kwargs):
    """A parser failure is a reply not understood, never a 500; only the type is logged."""
    try:
        return read(*args, **kwargs)
    except Exception as exc:  # noqa: BLE001 - any parser bug must degrade to a follow-up
        logger.warning("check-in parser failed: %s", type(exc).__name__)
        return None


def _many(value: float, unit: str) -> str:
    if value == 0.5:
        return f"half a{'n' if unit == 'hour' else ''} {unit}"
    return f"{_plain(value)} {unit}{'' if value == 1 else 's'}"


def _pounds(kg: float) -> str:
    return f"{round(kg / 0.45359237)} pounds"


def _duration(minutes: float) -> str:
    """Minutes as Mochi says them: "20 minutes", "an hour", "1.5 hours"."""
    if minutes >= 60 and minutes % 30 == 0:
        return "an hour" if minutes == 60 else _many(minutes / 60, "hour")
    return _many(minutes, "minute")


def _last(field: str, value, kind: str) -> str:
    """The previous answer as Mochi says it in a question ("7 hours", "130 over 80")."""
    if field in {"sleep_hours", "sleep_hours_last_night", "sleep_hours_night_before"}:
        return _many(value, "hour")
    if field in PACES or field == "sedentary_min_day":
        return _duration(value)
    if field in {"exercise_minutes_today", "exercise_minutes_weekly"}:
        return _many(value, "minute")
    if field in {"alcohol_drinks_yesterday", "alcohol_drinks_weekly"}:
        return _many(value, "drink")
    if field == "weight_kg":
        return _pounds(value)
    if field == "wellbeing":
        return LAST_FEELING[value]
    return str(value)


# How each amount is read back: (when it is none, otherwise, unit).
AMOUNTS: dict[str, tuple[str, str, str]] = {
    "sleep_hours_last_night": (
        "you didn't sleep at all last night",
        "you slept {} last night",
        "hour",
    ),
    "exercise_minutes_today": ("you didn't exercise today", "you moved for {} today", "minute"),
    "alcohol_drinks_yesterday": (
        "you had no alcoholic drinks yesterday",
        "you had {} yesterday",
        "drink",
    ),
    "sleep_hours": (
        "you hardly slept at all this week",
        "you slept {} on a usual night this week",
        "hour",
    ),
    "exercise_minutes_weekly": (
        "you didn't exercise this week",
        "you exercised {} this week",
        "minute",
    ),
    "alcohol_drinks_weekly": (
        "you had no alcoholic drinks this week",
        "you had {} this week",
        "drink",
    ),
}
# Quick and weekly activity and sitting: (when none, otherwise); "{day}" is the day.
SPANS: dict[str, tuple[str, str]] = {
    "vigorous_recreation_min": (
        "nothing got you out of breath {day}",
        "you did {} of activity that got you out of breath {day}",
    ),
    "moderate_recreation_min": (
        "you did no easy activity {day}",
        "you did {} of easy activity {day}",
    ),
    "vigorous_recreation_min_week": (
        "nothing got you out of breath this week",
        "you did {} of activity that got you out of breath this week",
    ),
    "moderate_recreation_min_week": (
        "you did no easy activity this week",
        "you did {} of easy activity this week",
    ),
}
SMOKING = {
    "current": "you smoke now",
    "former": "you don't smoke now, but you used to",
    "never": "you have never smoked",
    "unknown": "you're not sure about smoking",
}


def _facts(values: dict, kind: str, about: bool = False, day: str | None = None) -> list[str]:
    """One clause per answer, in the check-in's own time frame."""
    approx = "about " if about else ""
    parts = []
    for field, value in values.items():
        if field == "diastolic_bp":
            continue
        if field in SPANS:
            none, said = SPANS[field]
            text = none if value == 0 else said.format(approx + _duration(value), day="{day}")
            parts.append(text.format(day=day or "today"))
            continue
        if field == "sedentary_min_day":
            when = "on a usual day this week" if kind == "weekly" else day or "today"
            parts.append(f"you sat for {approx}{_duration(value)} {when}")
            continue
        if field == "sleep_hours_night_before":
            parts.append(
                "you didn't sleep at all the night before"
                if value == 0
                else f"you slept {approx}{_many(value, 'hour')} the night before"
            )
            continue
        if field == "systolic_bp":
            parts.append(f"your blood pressure was {approx}{value} over {values['diastolic_bp']}")
        elif field in AMOUNTS:
            none, said, unit = AMOUNTS[field]
            parts.append(none if value == 0 else said.format(approx + _many(value, unit)))
        elif field == "smoking_status":
            parts.append(SMOKING[value])
        elif field == "weight_kg":
            parts.append(f"you weigh {_weight(value)}")
        elif kind == "weekly":
            parts.append(f"your week was {FEELING[value]}")
        else:
            parts.append(f"you're feeling {FEELING[value]} today")
    return parts


def heard(values: dict, kind: str, about: bool = False, day: str | None = None) -> str:
    facts = _facts(values, kind, about, day)
    if len(facts) == 2 and all(field in SPANS for field in values):
        # One activity answer, both paces: the day is said once.
        when = " this week" if kind == "weekly" else f" {day or 'today'}"
        return f"I heard {facts[0].removesuffix(when)}, and {facts[1]}."
    return " ".join(f"I heard {fact}." for fact in facts)


def _deferred(state: CheckinState) -> bool:
    """Quick and daily check-ins read every answer back once, at the end."""
    return state.kind != "weekly"


def _echo(values: dict) -> str:
    """What was just heard, in a few words and no question: "7 hours, got it." Feeling
    gets a kind word instead."""
    if set(values) == {"wellbeing"}:
        return {
            "good": "Glad to hear it. ",
            "okay": "Thanks for telling me. ",
            "not_great": "I'm sorry it's not a great day. ",
        }[values["wellbeing"]]
    parts = []
    for name, value in values.items():
        if name in {"sleep_hours_last_night", "sleep_hours_night_before"}:
            parts.append("no sleep at all" if value == 0 else _many(value, "hour") + " of sleep")
        elif name == "vigorous_recreation_min":
            parts.append(
                "nothing out of breath" if value == 0 else f"{_duration(value)} out of breath"
            )
        elif name == "moderate_recreation_min":
            parts.append("nothing easy" if value == 0 else f"{_duration(value)} easy")
        elif name == "sedentary_min_day":
            parts.append(f"{_duration(value)} sitting")
        elif name == "exercise_minutes_today":
            parts.append("no exercise" if value == 0 else f"{_many(value, 'minute')} moving")
        elif name == "alcohol_drinks_yesterday":
            parts.append("no drinks" if value == 0 else _many(value, "drink"))
        elif name == "wellbeing":
            parts.append(f"feeling {FEELING[value]}")
    if not parts:
        return "Got it. "
    said = " and ".join(parts)
    return said[0].upper() + said[1:] + ", got it. "


def _day(state: CheckinState) -> str | None:
    return state.activity_day


def _fresh(state: CheckinState, **changes) -> CheckinState:
    """A new state for the same check-in (cancel, start over): same script and day."""
    return CheckinState(
        kind=state.kind,
        questions=state.questions,
        previous=state.previous,
        local_date=state.local_date,
        activity_day=state.activity_day,
        memory_consent=state.memory_consent,
        age_band=state.age_band,
        **changes,
    )


class CheckinService:
    def __init__(self, *, clock: Callable[[], date] = date.today):
        # The habit rotation and spoken dates are read against today; tests fix the day.
        self.clock = clock

    # -- start -------------------------------------------------------------------

    def start(self, request: CheckinStartRequest) -> CheckinResponse:
        day = self.clock()
        if request.local_date:
            try:
                day = date.fromisoformat(request.local_date)
            except ValueError:
                self._invalid("Please send the phone's date as 2026-10-24.")
        quick = {}
        if request.kind == "quick":
            plan = request.quick or QuickPlan()
            questions = quick_script(list(plan.topics), plan.catch_up)
            hints = plan.suggested
            quick = {
                "local_date": day.isoformat(),
                "activity_day": plan.activity_day,
                "suggested": {
                    name: value
                    for name, value in (
                        ("sleep_hours_last_night", hints.sleep_hours_last_night),
                        ("sleep_hours_night_before", hints.sleep_hours_night_before),
                    )
                    if value is not None
                },
                "suggested_activity_min": hints.activity_minutes,
            }
        elif request.kind == "weekly":
            questions = WEEKLY
        else:
            questions = DAILY_WITH_HABIT if day.weekday() in HABIT_DAYS else DAILY
        state = CheckinState.model_validate(
            {
                "kind": request.kind,
                "questions": list(questions),
                "current_field": questions[0],
                "previous": request.previous,
                "memory_consent": request.memory_consent,
                "age_band": None
                if request.age is None
                else ("older" if request.age >= 60 else "younger"),
                **quick,
            }
        )
        self._offer(state)
        return self._respond(state, GREETINGS[request.kind] + " " + self._prompt(state))

    # -- turns -------------------------------------------------------------------

    def turn(self, request: CheckinTurnRequest) -> CheckinResponse:
        state = request.state.model_copy(deep=True)
        action = request.action
        text = clean_reply(normalize_text(request.text or ""))
        voice = request.input_mode == "transcript"

        def respond(message: str, hint: str | None = None) -> CheckinResponse:
            return self._respond(state, message, hint)

        if action == "reply" and state.phase != "cancelled" and _safe(emergency, text):
            # The check-in pauses on the same question: no value, no next question.
            return self._respond(state, EMERGENCY_MESSAGE, urgent=True)

        if action == "cancel":
            state = _fresh(state, phase="cancelled")
            return respond("We can stop here. Nothing was saved. We can check in another time.")
        if state.phase == "cancelled":
            self._invalid("Please start the check-in again.")
        if action == "resume" or (action == "reply" and resumes(text)):
            # "Continue" after a pause: the same question or read-back again.
            return respond(RESUME_LEAD + self._prompt(state))
        if state.phase == "probing" and action in {"reply", "skip"}:
            intent = control_intent(text) if action == "reply" else None
            if intent and intent.kind == "help":
                return respond(
                    "I'm just curious about your day. Tell me in a few words, or say "
                    '"let\'s move on". ' + self._prompt(state)
                )
            if intent and intent.kind not in {"skip", "repeat", "slower", "louder", "ask"}:
                # "Go back", "start over", "talk about my sleep": the follow-up ends first.
                state.probe_topic = None
                self._advance(state)
            elif intent is None or intent.kind in {"skip", "ask"}:
                lead = PROBE_SKIPPED
                if action == "reply" and not PROBE_MOVE_ON.fullmatch(words_of(text)):
                    notes = _safe(read_notes, text, topic=state.probe_topic) or []
                    state.habit_notes = merge(state.habit_notes, notes)[-5:]
                    lead = "Thanks for telling me. "
                state.probe_topic = None
                self._advance(state)
                return respond(lead + self._prompt(state))
        field = state.current_field
        if action == "reply" and field and state.phase in {"asking", "confirming"}:
            # Room chatter around the answer goes before anything else reads it.
            text = focus(
                text,
                field,
                transcript=voice,
                confirming=state.phase == "confirming",
                checkin=True,
            )
        asked_back = ""
        if action == "reply" and field == "wellbeing" and state.phase == "asking":
            # "I'm good, how are you?": the answer, and a kind word back.
            tail = HOW_ARE_YOU_TAIL.search(text)
            if tail and tail.start() > 0:
                text, asked_back = text[: tail.start()].strip(" ,.;!-"), HOW_ARE_YOU
        read_back = None
        if action == "reply":
            if state.phase == "ready" and WHAT_NOW.fullmatch(words_of(text)):
                return respond(DONE_AGAIN)
            if ASKED_HOW_I_AM.fullmatch(words_of(text)):
                return respond(HOW_ARE_YOU + self._prompt(state))
            if SUPPLEMENTS.search(words_of(text)) and ASKING.search(text.lower()):
                # Mochi never suggests a supplement: the same fixed reply as onboarding.
                return respond(SUPPLEMENT_REPLY + " " + self._prompt(state))
            intent = control_intent(text)
            kind = intent.kind if intent else None
            if kind in {"repeat", "slower", "louder"}:
                lead = {"repeat": REPEAT_LEAD, "slower": SLOWER_LEAD, "louder": LOUDER_LEAD}
                return respond(lead[kind] + self._prompt(state), None if kind == "repeat" else kind)
            if kind == "help":
                return respond(self._help(state))
            if kind in {"why", "private"}:
                note = WHY_NOTES[state.kind] if kind == "why" else PRIVATE_NOTE
                return respond(note + " " + self._prompt(state))
            if kind == "ask" and field and not asks_back(text, field, transcript=voice):
                kind = None  # chatter worded like a question, beside the answer
            if kind == "ask":
                if HOW_ARE_YOU_ASKED.search(words_of(text)):
                    return respond(HOW_ARE_YOU + self._prompt(state))
                return respond(QUESTION_BACK_LEAD + self._prompt(state))
            if kind in {"restart", "restart_confirmed"}:
                answered = (
                    state.confirmed.model_dump(exclude_none=True)
                    or state.pending.model_dump(exclude_none=True)
                    or state.skipped_fields
                )
                if not answered:
                    return respond(
                        "We're just getting started, so there's nothing to clear. "
                        + self._prompt(state)
                    )
                if kind == "restart_confirmed":
                    state = _fresh(state, current_field=state.questions[0])
                    return respond(
                        "Okay, let's start over. I cleared today's answers. " + self._prompt(state)
                    )
                return respond(RESTART_QUESTION + " " + self._prompt(state))
            if kind == "skip":
                if state.phase == "ready":
                    return respond("There are no questions left. " + self._closing(state))
                text = "skip"
            if kind == "jump":
                kind = "back"  # check-ins have a fixed script: a named topic reopens it
            if kind is None and _deferred(state) and state.phase in {"asking", "confirming"}:
                # "Go back, I slept 5 not 7" to a later question, or "my sleep was 6 hours"
                # to the read-back at the end: that answer is reopened and replaced.
                fix = self._fix(state, text)
                if fix:
                    return self._redo(state, *fix, request)
            if kind == "back":
                target = self._named(state, intent.field)
                pending = list(state.pending.model_dump(exclude_none=True))
                if _deferred(state) and target is not None and target != field:
                    return self._redo(state, target, intent.rest, request)
                if state.phase == "confirming" and (intent.field is None or target == field):
                    # "I made a mistake", "change my sleep to 6 hours" during its read-back.
                    if intent.rest:
                        text, read_back = intent.rest, "correction"
                    else:
                        read_back = "no"
                else:
                    if intent.field is not None and target is None:
                        return respond("That isn't part of this check-in. " + self._prompt(state))
                    note = ""
                    if state.phase == "confirming" and pending:
                        note = (
                            f"I haven't saved your {LABELS[pending[0]]} answer yet, "
                            "so I'll ask again later. "
                        )
                    target = target or self._previous(state)
                    if target is None:
                        return respond(
                            "This is the first question, so there's nothing to go back to. "
                            + self._prompt(state)
                        )
                    message = note + self._reopen(state, target)
                    if intent.rest:
                        # "Change my sleep to 6 hours": the new answer is read back as usual.
                        answered = self.turn(
                            CheckinTurnRequest(
                                action="reply",
                                state=state,
                                text=intent.rest,
                                input_mode=request.input_mode,
                            )
                        )
                        if answered.state.phase == "confirming":
                            return answered
                    return respond(message)
        if action == "reply" and state.phase == "confirming" and field is None:
            # The one read-back at the end (quick and daily). Only a plain yes saves.
            said, rest = (read_back, "") if read_back else read_back_reply(text)
            answered = self._answered_topics(state)
            if said == "yes_value" and len(answered) == 1:
                # "Yes, 7 hours" to "you slept 7 hours" saves; "yes, 8" is not a yes.
                (only,) = answered.values()
                again = self._read_later(state, only, rest, voice)
                kept = self._answers(state)
                said = "yes" if again and all(kept.get(k) == v for k, v in again.items()) else ""
            if said == "yes":
                action = "confirm"
            elif said == "no" and len(answered) == 1:
                # One answer: "no" goes straight to asking for the right one.
                (only,) = answered.values()
                self._reopen(state, only)
                return respond(
                    NO_LEAD + f"What is the right answer? For example, {EXAMPLES[only]}."
                )
            elif said == "no":
                return respond(NO_LEAD + FINAL_CHANGE)
            elif said in {"unsure", "yes_value", ""}:
                return respond(FINAL_UNSURE)
            else:
                fix = self._fix(state, rest if said == "correction" else text)
                if fix:
                    return self._redo(state, *fix, request)
                return respond(NOT_CAUGHT + " " + self._which(state))
        if action == "reply" and state.phase == "confirming":
            # Only an unmistakable yes confirms; a no never does.
            said, rest = (read_back, "") if read_back else read_back_reply(text)
            if read_back == "correction":
                rest = text
            pending = state.pending.model_dump(exclude_none=True)
            if said == "yes_value":
                # "Yes, 7" to "7 hours" confirms; "yes, 8" is a question, not a yes.
                again = _safe(self._read, state, rest, voice) or ({}, None, False)
                said = "yes" if again[0] == pending else "unsure"
            if said == "yes":
                action = "confirm"
            elif said == "unsure":
                return respond(UNSURE_LEAD + self._prompt(state))
            elif said == "no" and state.from_health:
                # Apple Health had it wrong: ask the question itself.
                state.pending, state.phase, state.from_health = CheckinValues(), "asking", False
                return respond(NO_LEAD + self._question(state))
            elif said == "no":
                if list(pending) == BOTH_BP:
                    return respond(NO_LEAD + BOTH_BP_MESSAGE)
                return respond(
                    NO_LEAD + f"What is the right answer? For example, {EXAMPLES[field]}."
                )
            else:
                text = rest if said == "correction" else text
        if action == "confirm" and _deferred(state):
            if state.phase == "asking" and self._suggestion(state) is not None:
                # "Looks right" to Apple Health's value: heard, like a spoken answer.
                return self._hear(state, {field: self._suggestion(state)}, request, text="")
            if state.phase != "confirming":
                self._invalid("There is nothing to confirm right now.")
            if field is None:
                # The yes to the read-back at the end: every answer is saved at once.
                state.confirmed = CheckinValues.model_validate(
                    state.confirmed.model_dump() | state.pending.model_dump(exclude_none=True)
                )
                state.pending, state.phase = CheckinValues(), "ready"
                return respond(self._closing(state))
            # A yes to the check question: the unusual value is heard after all.
            checked = {name: getattr(state.pending, name) for name in state.checking}
            state.checking = []
            return self._after_heard(state, checked, CHECKED)
        if action == "confirm":
            if state.phase != "confirming":
                self._invalid("There is nothing to confirm right now.")
            additions = state.pending.model_dump(exclude_none=True)
            merged = state.confirmed.model_dump() | additions
            state.confirmed = CheckinValues.model_validate(merged)
            state.pending = CheckinValues()
            state.from_health = False
            state.skipped_fields = [f for f in state.skipped_fields if f not in additions]
            topic = self._probe(state, additions)
            if topic:
                state.phase, state.current_field, state.probe_asked = "probing", None, True
                state.probe_topic = topic
                return respond("Got it. " + self._prompt(state))
            self._advance(state)
            return respond("Got it. " + self._prompt(state))
        if action == "skip":
            if state.phase == "confirming" and state.checking:
                # Skip during the check question: the unusual value isn't kept.
                self._drop_checking(state)
            self._drop_suggestion(state)
            if state.phase == "confirming" and state.from_health:
                # Skip during Apple Health's read-back: nothing of it is kept.
                state.pending, state.phase, state.from_health = CheckinValues(), "asking", False
            if state.phase == "confirming":
                self._invalid(CONFIRM_FIRST)
            if state.phase == "ready":
                self._invalid("There are no questions left.")
            self._skip(state, field)
            self._advance(state)
            return respond(SKIPPED + self._prompt(state))
        if state.phase == "ready":
            thanks = "You're welcome! " if THANKS.search(text) else ""
            return respond(thanks + DONE_AGAIN)
        suggestion = self._suggestion(state)
        if suggestion is not None:
            # "Apple Health says about 7 hours. Does that sound right?": a yes is heard
            # like any answer; a no asks the question itself; a number replaces it.
            said, rest = read_back_reply(text)
            if said == "yes":
                return self._hear(state, {field: suggestion}, request, text)
            self._drop_suggestion(state)
            if said == "no":
                return respond(NO_LEAD + self._question(state))
            if said in {"correction", "yes_value"}:
                text = rest
            # "More like 6 hours" sets Mochi's number right; it is no comparison.
            text = re.sub(r"^\W*(?:it was |it's |i'd say )?more like\b", "about", text, flags=re.I)
        # A new answer: to the question, or in place of the one read back.
        reopened = state.phase == "asking" and (state.reopened or self._saved(state, field))
        if reopened and (keeps_answer(text) or is_skip(text, field)):
            # A question reopened by "go back": "keep it" or "skip" leaves the saved answer.
            self._advance(state)
            return respond("Okay, I kept your answer. " + self._prompt(state))
        if (
            state.phase == "asking"
            and dont_know(text)
            and not is_skip(text, field)
            and not (field == "systolic_bp" and no_new_reading(text))
        ):
            # "Not sure", "I'd have to check": left out today, never asked again in it.
            names = BOTH_BP if field == "systolic_bp" else [field]
            state.unknown_fields += [n for n in names if n not in state.unknown_fields]
            self._advance(state)
            return respond(UNKNOWN_LEAD + self._prompt(state))
        if (state.phase == "asking" or state.checking) and (
            is_skip(text, field) or (field == "systolic_bp" and no_new_reading(text))
        ):
            self._drop_checking(state)
            self._skip(state, field)
            self._advance(state)
            return respond(SKIPPED + self._prompt(state))
        read = _safe(self._read_reply, state, text, voice) or ({}, None, False, {}, [])
        values, hint, same, extras, notes = read
        if not values:
            ask = self._prompt(state) if state.phase == "confirming" else self._question(state)
            if extras and _deferred(state) and state.phase == "asking":
                # The open question wasn't answered, but a later one was: kept for later.
                state.pending = CheckinValues.model_validate(
                    state.pending.model_dump(exclude_none=True) | extras
                )
                return respond(_echo(extras) + (hint or self._question(state)))
            if hint and state.phase != "confirming":
                return respond(hint)
            return respond((hint or NOT_CAUGHT) + " " + ask)
        before = self._answers(state, without=state.checking)
        merged = before | values | extras
        if merged.get("systolic_bp") and merged.get("diastolic_bp"):
            if merged["systolic_bp"] <= merged["diastolic_bp"]:
                return respond(BP_ORDER + " " + self._question(state))
        if self._over_a_day(state, merged):
            return respond(OVER_A_DAY + " " + self._question(state))
        if _deferred(state):
            self._drop_checking(state)  # a new answer replaces the value being checked
            lead = asked_back + (SAME_LEAD if same else "")
            return self._hear(state, values, request, text, lead=lead, extras=extras, notes=notes)
        state.pending = CheckinValues.model_validate(values)
        state.phase = "confirming"
        state.from_health = False
        state.held_minutes = None
        lead = SAME_LEAD if same else ""
        if self._unusual(state, values):
            lead += "That's quite a lot, so I just want to be sure. "
        about = not same and bool(_safe(approximate, text))
        return respond(
            asked_back + lead + heard(values, state.kind, about, _day(state)) + " Is that right?"
        )

    # -- quick and daily: answers heard now, read back once at the end ------------

    @staticmethod
    def _suggestion(state: CheckinState):
        """Apple Health's value for the open question, offered in the question itself."""
        if not _deferred(state) or state.phase != "asking" or state.current_field is None:
            return None
        return getattr(state.suggested, state.current_field, None)

    @staticmethod
    def _drop_suggestion(state: CheckinState) -> None:
        field = state.current_field
        if field and getattr(state.suggested, field, None) is not None and _deferred(state):
            state.suggested = CheckinValues.model_validate(
                state.suggested.model_dump(exclude_none=True) | {field: None}
            )
            if state.held_minutes is None:
                state.from_health = False

    @staticmethod
    def _drop_checking(state: CheckinState) -> None:
        """The value asked about by the check question is not kept."""
        if not state.checking:
            return
        state.pending = CheckinValues.model_validate(
            {
                name: value
                for name, value in state.pending.model_dump(exclude_none=True).items()
                if name not in state.checking
            }
        )
        state.checking = []
        if state.current_field is not None:
            state.phase = "asking"

    @staticmethod
    def _answers(state: CheckinState, without: list[str] | None = None) -> dict:
        """Everything answered so far: saved, and (quick and daily) heard."""
        answers = state.confirmed.model_dump(exclude_none=True)
        if _deferred(state):
            answers |= state.pending.model_dump(exclude_none=True)
        return {name: value for name, value in answers.items() if name not in (without or [])}

    @staticmethod
    def _unusual(state: CheckinState, values: dict) -> list[str]:
        """The fields in ``values`` that are more than a day usually holds."""
        week = 7 if state.kind == "weekly" else 1
        found = []
        for name, value in values.items():
            if name in {"sleep_hours", "sleep_hours_last_night", "sleep_hours_night_before"}:
                if value > UNUSUAL["sleep"]:
                    found.append(name)
            elif name == "sedentary_min_day" and value > UNUSUAL["sitting"]:
                found.append(name)
        activity = [name for name in values if name in PACES or name == "exercise_minutes_today"]
        if sum(values[name] for name in activity) > UNUSUAL["activity"] * week:
            found += activity
        return found

    def _hear(
        self,
        state: CheckinState,
        values: dict,
        request: CheckinTurnRequest,
        text: str,
        lead: str = "",
        extras: dict | None = None,
        notes: list | None = None,
    ) -> CheckinResponse:
        """A quick or daily answer: heard now, echoed, and read back once at the end.
        An unusual value gets one gentle check question first."""
        self._drop_suggestion(state)
        state.from_health, state.held_minutes = False, None
        if notes and state.memory_consent:
            state.habit_notes = merge(state.habit_notes, notes)[-5:]
        pending = state.pending.model_dump(exclude_none=True)
        if self._unusual(state, values):
            state.pending = CheckinValues.model_validate(pending | values)
            state.checking, state.phase = list(values), "confirming"
            return self._respond(state, lead + self._prompt(state))
        state.pending = CheckinValues.model_validate(pending | values | (extras or {}))
        return self._after_heard(
            state, values | (extras or {}), lead + _echo(values | (extras or {}))
        )

    def _after_heard(self, state: CheckinState, values: dict, lead: str) -> CheckinResponse:
        topic = self._probe(state, values)
        if topic:
            state.phase, state.current_field, state.probe_asked = "probing", None, True
            state.probe_topic = topic
        else:
            self._advance(state)
        return self._respond(state, lead + self._prompt(state))

    def _check_question(self, state: CheckinState) -> str:
        values = {name: getattr(state.pending, name) for name in state.checking}
        said = _echo(values).removesuffix(", got it. ")
        span = "night" if any("sleep" in name for name in values) else "day"
        return (
            f"Did I hear {said[0].lower() + said[1:]}? That's a lot for one {span}, so I just "
            "want to check. Is that right?"
        )

    def _summary(self, state: CheckinState) -> str:
        """The one read-back at the end: every answer heard, in the check-in's words."""
        pending = state.pending.model_dump(exclude_none=True)
        ordered = {}
        for name in state.questions:
            for each in (name, PAIRS.get(name)):
                if each in pending:
                    ordered[each] = pending[each]
        facts = _facts(ordered, state.kind, day=_day(state))
        if len(facts) > 1:
            facts[-1] = "and " + facts[-1]
        joined = ", ".join(facts) if len(facts) > 2 else " ".join(facts)
        return FINAL_LEAD + joined + "." + FINAL_ASK

    def _answered_topics(self, state: CheckinState) -> dict[str, str]:
        """Topic -> its first question, for the answers heard so far."""
        topics: dict[str, str] = {}
        for name in state.questions:
            names = [name, PAIRS[name]] if name in PAIRS else [name]
            if any(getattr(state.pending, n) is not None for n in names) and name in TOPIC_OF:
                topics.setdefault(TOPIC_OF[name], name)
        return topics

    def _which(self, state: CheckinState) -> str:
        labels = [TOPIC_LABELS[topic] for topic in self._answered_topics(state)]
        if len(labels) > 1:
            labels[-1] = "or " + labels[-1]
        return FINAL_WHICH.format(topics=(", " if len(labels) > 2 else " ").join(labels))

    def _fix(self, state: CheckinState, text: str) -> tuple[str, str | None] | None:
        """(question, new answer) for a correction to an earlier answer: "go back, I slept
        5 not 7" to a later question, or "my sleep was 6 hours" to the read-back."""
        final = state.phase == "confirming" and state.current_field is None
        if state.phase != "asking" and not final:
            return None
        rest = text
        if final:
            said, after = read_back_reply(text)
            if said == "correction":
                rest = after
            elif said != "other":
                return None
        else:
            lead = FIX_LEAD.match(text.lower())
            if not lead:
                return None
            rest = text[lead.end() :]
        answered = self._answered_topics(state)
        words = normalize_text(rest).lower()
        named = {topic for topic, cue in TOPIC_CUES.items() if re.search(cue, words)}
        if "feeling" in named and len(named) > 1:
            named.discard("feeling")
        candidates = named & set(answered)
        if final and not named and len(answered) == 1:
            candidates = set(answered)
        if not final and not named and rest.strip():
            # "No wait, 45" right after "40 minutes moving, got it": the last answer,
            # unless it reads as an answer to the open question ("actually, none").
            if re.match(r"\W*go back\b", text.lower()):
                last = self._previous(state)
                return (last, rest.strip(" ,.;:!-") or None) if last else None
            partner = {a: b for a, b in PAIRS.items() if a in PACES}
            partner |= {b: a for a, b in partner.items()}
            if (
                getattr(state.pending, partner.get(state.current_field, "") or "x", None)
                is not None
            ):
                return "?", None  # "wait, it was 45 minutes" to the activity follow-up
            last = self._previous(state)
            if last is None or last not in TOPIC_OF:
                return None
            if self._read_later(state, state.current_field, rest, False):
                return None
            return last, rest.strip(" ,.;:!-") or None
        if len(candidates) != 1:
            return None
        topic = candidates.pop()
        if not final and TOPIC_OF.get(state.current_field) == topic:
            return None  # an answer to the open question itself
        rest = rest.strip(" ,.;:!-")
        return answered[topic], rest or None

    def _redo(
        self, state: CheckinState, target: str, rest: str | None, request: CheckinTurnRequest
    ) -> CheckinResponse:
        """Reopen an earlier answer; a new answer said with it replaces the old one."""
        if target == "?":
            return self._respond(state, WHICH_ANSWER + self._question(state))
        message = self._reopen(state, target)
        if rest:
            answered = self.turn(
                CheckinTurnRequest(
                    action="reply", state=state, text=rest, input_mode=request.input_mode
                )
            )
            if answered.state != state:
                return answered  # heard, or a follow-up about it ("out of breath, or easy?")
        return self._respond(state, message)

    # -- reading an answer -------------------------------------------------------

    def _read_reply(self, state: CheckinState, text: str, voice: bool):
        """(values, follow-up, same, extras, notes) for a reply.

        Quick and daily replies may say more than the question asked: "7 hours, and I
        walked 20 minutes to work". Each clause is about one topic by its words; the
        open question reads its own clauses, and a later question that hasn't come up
        yet keeps what its clauses clearly say (``extras``), so it isn't asked again. A
        clause beside the answer that is only a note ("pretty good, my knee is sore")
        is a habit note, never a value.
        """
        if not _deferred(state) or state.phase != "asking":
            return (*self._read(state, text, voice), {}, [])
        clauses = [c.strip() for c in re.split(CLAUSES, text.lower()) if c and c.strip()]
        own = TOPIC_OF.get(state.current_field)
        topics: list[str | None] = []
        for clause in clauses:
            named = {t for t, cue in TOPIC_CUES.items() if re.search(cue, normalize_text(clause))}
            if "feeling" in named and len(named) > 1:
                named.discard("feeling")  # "slept well", "a good walk": not how they feel
            topics.append(next(iter(named)) if len(named) == 1 else (None if not named else "?"))
        later = self._later(state)
        if len(clauses) > 1 and "?" not in topics and set(topics) & set(later):
            # Clauses without a topic of their own belong to the open question.
            mine = [c for c, t in zip(clauses, topics, strict=True) if t in {None, own}]
            values, hint, same = (
                self._read(state, ", ".join(mine), voice) if mine else ({}, None, False)
            )
            extras: dict = {}
            for topic, field in later.items():
                said = [c for c, t in zip(clauses, topics, strict=True) if t == topic]
                if said:
                    extras |= self._read_later(state, field, ", ".join(said), voice)
            extras = {k: v for k, v in extras.items() if k not in values}
            unusual = self._unusual(state, extras)
            extras = {k: v for k, v in extras.items() if k not in unusual}
            return values, hint, False, extras, []
        values, hint, same = self._read(state, text, voice)
        if values or same or len(clauses) < 2 or own in {None, "activity"}:
            return values, hint, same, {}, []
        if any(t not in {None, own} for t in topics):
            return values, hint, same, {}, []
        # "4, couldn't stop worrying": the first clause answers; the rest is a note.
        rest = " ".join(clauses[1:])
        if re.search(NOT_A_NOTE, _canonical(rest)) or _safe(_others, rest):
            return values, hint, same, {}, []
        if own == "feeling" and re.search(FEELING_WORDS, rest):
            return values, hint, same, {}, []
        first, _, _ = self._read(state, clauses[0], voice)
        if not first:
            return values, hint, same, {}, []
        topic = {"feeling": "health", "sleep": "sleep"}.get(own)
        notes = (_safe(read_notes, text, topic=topic) or []) if topic else []
        return first, None, False, {}, notes

    def _later(self, state: CheckinState) -> dict[str, str]:
        """Topic -> question, for the questions after this one not answered yet."""
        order = state.questions
        at = order.index(state.current_field)
        later: dict[str, str] = {}
        for name in order[at + 1 :]:
            names = [name, PAIRS[name]] if name in PAIRS else [name]
            if any(self._saved(state, n) or n in state.skipped_fields for n in names):
                continue
            if name in state.unknown_fields or name not in TOPIC_OF:
                continue
            later.setdefault(TOPIC_OF[name], name)
        later.pop(TOPIC_OF.get(state.current_field), None)
        return later

    def _read_later(self, state: CheckinState, field: str, text: str, voice: bool) -> dict:
        """What a clause says for a later question, read as if that question were open."""
        ahead = state.model_copy(deep=True)
        ahead.current_field, ahead.one_pace, ahead.held_minutes = field, False, None
        ahead.from_health = False
        values, _, _ = _safe(self._read, ahead, text, voice) or ({}, None, False)
        return values

    def _read(self, state: CheckinState, text: str, voice: bool):
        """(values, follow-up, same as before) for a reply to the current question."""
        if SELF_CORRECTION.search(_canonical(normalize_text(text))):
            text = last_said(text)  # "7, actually 8": the number said last
        field = state.current_field
        names = self._asked(state)
        previous = {
            name: getattr(state.previous, name)
            for name in names
            if getattr(state.previous, name) is not None
        }
        if same_as_before(text):
            if len(previous) != len(names):
                return {}, NO_PREVIOUS + self._question(state, plain=True), False
            return previous, None, True
        today = self.clock()
        if field in PACES:
            return self._read_activity(state, text, today)
        if field == "sedentary_min_day":
            values, hint = read_sitting(
                text, week=state.kind == "weekly", day=state.activity_day or "today"
            )
            if hint and hint.endswith(" "):
                hint += self._question(state)
            return values, hint, False
        period = "week" if state.kind == "weekly" else None
        if field == "smoking_status":
            status = checkin_smoking(text, state.previous.smoking_status)
            if status:
                return {field: status}, None, False
        found = parse_reply(text, field, today=today, strict=voice, period=period)
        values = {name: found[name] for name in names if name in found}
        if field == "systolic_bp" and len(values) != 2:
            values = {}
        if values:
            return values, None, False
        hint = checkin_clarify(text, field, period=period) or clarify(
            text, field, today=today, period=period
        )
        return {}, hint, False

    def _read_activity(self, state: CheckinState, text: str, today: date):
        field = state.current_field
        names = self._asked(state)
        week = state.kind == "weekly"
        read = read_activity(
            text,
            open_paces=[PACES[name] for name in names],
            week=week,
            day=state.activity_day or "today",
            held=state.held_minutes,
            today=today,
        )
        held = (
            read.held if read.held is not None else (state.held_minutes if read.keep_held else None)
        )
        if held is None:
            state.from_health = False
        state.held_minutes = held
        if read.focus:
            pace = read.focus
            target = next(name for name in self._pair(state) if PACES[name] == pace)
            state.current_field, state.one_pace = target, True
        hint = read.hint
        if hint and hint.endswith(" "):
            hint += self._question(state)
        if not read.values and hint is None and week:
            # The weekly question's own follow-ups: "how often?", "a number, please".
            hint = checkin_clarify(text, "exercise_minutes_weekly", period="week")
        if read.values and field not in read.values and not set(read.values) & set(names):
            return {}, None, False
        return read.values, hint, False

    # -- helpers -----------------------------------------------------------------

    def _pair(self, state: CheckinState) -> list[str]:
        """The activity question's two fields in this check-in."""
        if state.kind == "weekly":
            return ["vigorous_recreation_min_week", "moderate_recreation_min_week"]
        return ["vigorous_recreation_min", "moderate_recreation_min"]

    def _asked(self, state: CheckinState) -> list[str]:
        """The fields the open question asks for: both blood pressure numbers, both
        activity paces on the first activity question, otherwise just the one."""
        field = state.current_field
        if field == "systolic_bp":
            return BOTH_BP
        pending = list(state.pending.model_dump(exclude_none=True))
        if _deferred(state):
            pending = list(state.checking)
        if state.phase == "confirming" and pending and set(pending) <= set(PACES):
            return pending  # a correction replaces what was read back
        second = PAIRS.get(field)
        if second and field in PACES and state.reopened:
            if not state.one_pace and state.held_minutes is None:
                return [field, second]  # the activity question reopened: a new whole answer
        if second and field in PACES and not state.one_pace and state.held_minutes is None:
            if not self._saved(state, second) and second not in state.skipped_fields:
                return [field, second]
        return [field]

    @staticmethod
    def _over_a_day(state: CheckinState, values: dict) -> bool:
        """Sleep, sitting and activity on one day can't add up to more than 24 hours."""
        if state.kind != "quick":
            return False
        moving = sum(
            values.get(name) or 0
            for name in ("vigorous_recreation_min", "moderate_recreation_min", "sedentary_min_day")
        )
        same_day = state.activity_day == "today"
        sleep = values.get("sleep_hours_last_night" if same_day else "sleep_hours_night_before")
        return moving + (sleep or 0) * 60 > 1440

    @staticmethod
    def _offer(state: CheckinState) -> None:
        """Apple Health's value for the question that comes up: offered in the question
        (quick), or read back once (weekly never has one)."""
        field = state.current_field
        if state.phase != "asking" or field is None:
            return
        value = getattr(state.suggested, field, None)
        if value is not None and _deferred(state):
            # Quick: "Apple Health says about 7 hours. Does that sound right?" is the
            # question itself; a yes is heard like any answer and read back at the end.
            state.from_health = True
        elif value is not None:
            state.pending = CheckinValues.model_validate({field: value})
            state.suggested = CheckinValues.model_validate(
                state.suggested.model_dump(exclude_none=True) | {field: None}
            )
            state.phase, state.from_health = "confirming", True
        elif field == "vigorous_recreation_min" and state.suggested_activity_min is not None:
            if not CheckinService._saved(state, "moderate_recreation_min"):
                state.held_minutes, state.from_health = state.suggested_activity_min, True
            state.suggested_activity_min = None

    def _respond(
        self, state: CheckinState, message: str, hint: str | None = None, urgent: bool = False
    ) -> CheckinResponse:
        reaction = {
            "asking": "asking",
            "probing": "asking",
            "confirming": "confirming",
            "ready": "celebrating",
            "cancelled": "idle",
        }[state.phase]
        return CheckinResponse(
            state=state,
            message=message,
            complete=state.phase == "ready",
            mascot_events=[MascotEvent(state="concerned" if urgent else reaction, caption=message)],
            speech_hint=hint,
            emergency=urgent,
            profile_update=profile_update(state),
            daily_logs=daily_logs(state),
        )

    def _forms(self, state: CheckinState, field: str) -> dict[str, str]:
        """The question's forms, with everyday examples for the person's age; a choice of
        wordings rotates by date."""
        forms = dict(QUESTIONS[state.kind][field])
        if field == "sedentary_min_day" and state.kind == "quick":
            forms["ask"] = SITTING_PROXIES
        if state.age_band:
            forms |= AGE_FORMS[state.age_band].get(state.kind, {}).get(field, {})
        day = date.fromisoformat(state.local_date) if state.local_date else self.clock()
        return {
            name: form[day.toordinal() % len(form)] if isinstance(form, tuple) else form
            for name, form in forms.items()
        }

    def _question(self, state: CheckinState, plain: bool = False) -> str:
        field = state.current_field
        forms = self._forms(state, field)
        day = state.activity_day or "today"
        suggestion = self._suggestion(state)
        if suggestion is not None and "health" in forms:
            return forms["health"].format(value=_many(suggestion, "hour"))
        if field in PACES:
            return self._activity_question(state, forms, plain).format(value="", day=day)
        names = BOTH_BP if field == "systolic_bp" else [field]
        values = [getattr(state.previous, name) for name in names]
        if plain or any(value is None for value in values):
            return forms["ask"].format(day=day)
        value = values[0]
        if field == "smoking_status":
            return forms.get(f"again_{value}", forms["ask"])
        if value == 0 and "again_none" in forms:
            return forms["again_none"]
        shown = f"{values[0]} over {values[1]}" if field == "systolic_bp" else None
        return forms["again"].format(value=shown or _last(field, value, state.kind), day=day)

    def _activity_question(self, state: CheckinState, forms: dict, plain: bool) -> str:
        held = state.held_minutes
        if held is not None:
            if state.from_health and "health" in forms:
                return forms["health"].replace("{value}", _duration(held))
            return (
                "Did that get you out of breath, like brisk walking uphill, "
                "or was it at an easy pace?"
            )
        names = self._asked(state)
        if len(names) == 1:
            if state.one_pace:
                return "About how long was it, in minutes or hours?"
            return forms["follow"]
        last = [getattr(state.previous, name) for name in names]
        if plain or any(value is None for value in last) or "again" not in forms:
            return forms["ask"]
        hard, easy = last
        said = (
            (
                "nothing that got you out of breath"
                if hard == 0
                else f"{_duration(hard)} that got you out of breath"
            )
            + " and "
            + ("no easy activity" if easy == 0 else f"{_duration(easy)} of easy activity")
        )
        return forms["again"].replace("{value}", said)

    def _prompt(self, state: CheckinState) -> str:
        if state.phase == "confirming" and _deferred(state):
            return self._check_question(state) if state.checking else self._summary(state)
        if state.phase == "confirming":
            pending = state.pending.model_dump(exclude_none=True)
            if state.from_health:
                field = next(iter(pending))
                return QUESTIONS[state.kind][field]["health"].format(
                    value=_many(pending[field], "hour")
                )
            return heard(pending, state.kind, day=_day(state)) + " Is that right?"
        if state.phase == "ready":
            return self._closing(state)
        if state.phase == "probing":
            return PROBES[state.probe_topic]
        return self._question(state)

    @staticmethod
    def _closing(state: CheckinState) -> str:
        lines = CLOSINGS[state.kind]
        return lines["not_great"] if state.confirmed.wellbeing == "not_great" else lines["default"]

    def _help(self, state: CheckinState) -> str:
        if state.phase == "confirming" and _deferred(state) and not state.checking:
            return (
                "I'm reading back everything you told me before I save it. If it's all right, "
                'say "yes". To change something, tell me, like "my sleep was 6 hours".'
            )
        if state.phase == "confirming" and _deferred(state):
            return (
                "That number is more than most days hold, so I'm checking I heard it right. "
                'If it is, say "yes". If not, tell me the right answer.'
            )
        if state.phase == "confirming":
            pending = state.pending.model_dump(exclude_none=True)
            return (
                "I'm checking that I heard you right before I save anything. "
                + heard(pending, state.kind, day=_day(state))
                + ' If that\'s right, say "yes". If not, say "no" and then the right answer.'
            )
        if state.phase == "ready":
            return (
                "We're all done. To change an answer, say what to change, like \"change my "
                'sleep". To clear everything and begin again, say "start over".'
            )
        return (
            AGE_HELP.get(state.age_band or "", {})
            .get(state.kind, {})
            .get(state.current_field, HELP[state.kind][state.current_field])
            + ' If you\'d rather not answer, just say "skip".'
        )

    @staticmethod
    def _named(state: CheckinState, field: str | None) -> CheckinField | None:
        """The script's question for a spoken name ("my sleep" is last night's, daily)."""
        if field is None:
            return None
        if field in BP_FIELDS:
            field = "systolic_bp"
        return next(
            (name for name in state.questions if CHECKIN_BASE.get(name, name) == field), None
        )

    @staticmethod
    def _saved(state: CheckinState, field: str) -> bool:
        """Answered: saved, or (quick and daily) heard and waiting for the read-back."""
        names = BOTH_BP if field == "systolic_bp" else [field]
        if any(getattr(state.confirmed, name) is not None for name in names):
            return True
        return _deferred(state) and any(
            getattr(state.pending, name) is not None and name not in state.checking
            for name in names
        )

    @staticmethod
    def _previous(state: CheckinState) -> CheckinField | None:
        """The answered or skipped question before this one, or the last one when done.
        From the activity follow-up, it is the activity question itself."""
        order = state.questions
        field = state.current_field
        if _deferred(state) and field in PACES and state.phase == "asking" and not state.reopened:
            first = next(a for a, b in PAIRS.items() if field in {a, b})
            if field != first or getattr(state.pending, PAIRS[first]) is not None:
                if CheckinService._saved(state, first) or CheckinService._saved(
                    state, PAIRS[first]
                ):
                    return first
        done = [
            name
            for name in order
            if CheckinService._saved(state, name) or name in state.skipped_fields
        ]
        if state.phase in {"asking", "confirming"} and state.current_field is not None:
            done = [name for name in done if order.index(name) < order.index(state.current_field)]
        return done[-1] if done else None

    def _reopen(self, state: CheckinState, field: CheckinField) -> str:
        """Ask a question again; its saved answer stays until a new one is confirmed
        (quick and daily: until a new one is heard)."""
        if _deferred(state):
            self._drop_checking(state)
            state.reopened = True
        else:
            state.pending = CheckinValues()
        state.phase, state.current_field = "asking", field
        state.one_pace, state.held_minutes, state.from_health = False, None, False
        names = BOTH_BP if field == "systolic_bp" else [field]
        if field in PAIRS and field in PACES:
            names = [field, PAIRS[field]]
        kept = self._answers(state)
        saved = {name: kept[name] for name in names if name in kept}
        label = LABELS[field]
        if saved:
            return (
                f"Okay, let's go back to your {label}. Right now I have that "
                f"{_facts(saved, state.kind, day=_day(state))[0]}. "
                + self._question(state, plain=True)
                + ' If that was right, say "keep it".'
            )
        if field in state.skipped_fields:
            return f"Okay, let's go back to your {label}. You skipped it before. " + self._question(
                state
            )
        return f"Okay, let's do your {label}. " + self._question(state)

    def _skip(self, state: CheckinState, field: str) -> None:
        names = self._asked(state) if field == state.current_field else [field]
        self._drop_suggestion(state)
        state.held_minutes, state.from_health = None, False
        for name in names:
            if name not in state.skipped_fields and getattr(state.confirmed, name) is None:
                state.skipped_fields.append(name)

    @staticmethod
    def _probe(state: CheckinState, additions: dict) -> Literal["exercise", "sleep"] | None:
        """One light habit follow-up per check-in, only with memory consent."""
        if not state.memory_consent or state.probe_asked:
            return None
        if (additions.get("exercise_minutes_today") or 0) > 0 or (
            additions.get("exercise_minutes_weekly") or 0
        ) > 0:
            return "exercise"
        night = additions.get("sleep_hours_last_night")
        if night is not None and night < 6:
            return "sleep"
        return None

    @staticmethod
    def _advance(state: CheckinState) -> None:
        state.current_field = next(
            (
                name
                for name in state.questions
                if not CheckinService._saved(state, name)
                and name not in state.skipped_fields
                and name not in state.unknown_fields
            ),
            None,
        )
        state.phase = "asking" if state.current_field else "ready"
        if (
            state.phase == "ready"
            and _deferred(state)
            and state.pending.model_dump(exclude_none=True)
        ):
            state.phase = "confirming"  # quick and daily: one read-back of every answer
        state.one_pace, state.held_minutes, state.from_health = False, None, False
        state.reopened = False
        CheckinService._offer(state)

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_checkin_transition", "message": message}
        )
