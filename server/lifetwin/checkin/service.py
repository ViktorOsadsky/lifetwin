"""Daily and weekly check-in turns on the onboarding conversation machinery.

The same rules as onboarding apply: each answer is read back and saved only after
a clear yes, a close answer gets a targeted follow-up instead of a guess, room
chatter is dropped, and someone else's value is never taken. The check-in adds
the previous answers: "same as last week" offers the last value back for a yes.
"""

import logging
import re
from collections.abc import Callable
from datetime import date

from fastapi import HTTPException

from lifetwin.checkin.models import (
    CheckinResponse,
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
)
from lifetwin.checkin.scripts import (
    CLOSINGS,
    DAILY,
    DAILY_WITH_HABIT,
    DONE_AGAIN,
    GREETINGS,
    HABIT_DAYS,
    HELP,
    HOW_ARE_YOU,
    NO_PREVIOUS,
    PRIVATE_NOTE,
    QUESTIONS,
    SAME_LEAD,
    URGENT_NOTE,
    WEEKLY,
    WHY_NOTE,
    CheckinField,
)
from lifetwin.core.models import CheckinValues
from lifetwin.onboarding.intents import (
    asks_back,
    clean_reply,
    control_intent,
    focus,
    keeps_answer,
    read_back_reply,
    same_as_before,
)
from lifetwin.onboarding.intents import phrase as words_of
from lifetwin.onboarding.models import MascotEvent
from lifetwin.onboarding.parsing import (
    BP_FIELDS,
    CHECKIN_BASE,
    URGENT,
    approximate,
    checkin_clarify,
    checkin_smoking,
    clarify,
    is_skip,
    no_new_reading,
    normalize_text,
    parse_reply,
)
from lifetwin.onboarding.service import (
    LOUDER_LEAD,
    NO_LEAD,
    NOT_CAUGHT,
    QUESTION_BACK_LEAD,
    REPEAT_LEAD,
    SKIPPED,
    SLOWER_LEAD,
    THANKS,
    UNSURE_LEAD,
    WHAT_NOW,
    _plain,
    _weight,
)

logger = logging.getLogger(__name__)

BOTH_BP = ["systolic_bp", "diastolic_bp"]
BOTH_BP_MESSAGE = 'Please tell me both blood pressure numbers, for example "120 over 80".'
BP_ORDER = "The top number is usually the bigger one. Could you check your reading?"
CONFIRM_FIRST = "Please answer yes or no to what I just read back first."
RESTART_QUESTION = (
    "Do you want to clear today's answers and start again? "
    "If so, say yes, start over. Otherwise, just keep going."
)
HOW_ARE_YOU_ASKED = re.compile(r"\bhow (?:are|r) (?:you|u)\b|\bhow's (?:it going|mochi)\b")
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
}
FEELING = {"good": "good", "okay": "okay", "not_great": "not great"}
WEEK = {"good": "a good week", "okay": "an okay week", "not_great": "a hard week"}


def _safe(read, *args, **kwargs):
    """A parser failure is a reply not understood, never a 500; only the type is logged."""
    try:
        return read(*args, **kwargs)
    except Exception as exc:  # noqa: BLE001 - any parser bug must degrade to a follow-up
        logger.warning("check-in parser failed: %s", type(exc).__name__)
        return None


def _many(value: float, unit: str) -> str:
    return f"{_plain(value)} {unit}{'' if value == 1 else 's'}"


def _pounds(kg: float) -> str:
    return f"{round(kg / 0.45359237)} pounds"


def _last(field: str, value, kind: str) -> str:
    """The previous answer as Mochi says it in a question ("7 hours", "130 over 80")."""
    if field in {"sleep_hours", "sleep_hours_last_night"}:
        return _many(value, "hour")
    if field in {"exercise_minutes_today", "exercise_minutes_weekly"}:
        return _many(value, "minute")
    if field in {"alcohol_drinks_yesterday", "alcohol_drinks_weekly"}:
        return _many(value, "drink")
    if field == "weight_kg":
        return _pounds(value)
    if field == "wellbeing":
        return (WEEK if kind == "weekly" else FEELING)[value]
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
SMOKING = {
    "current": "you smoke now",
    "former": "you don't smoke now, but you used to",
    "never": "you have never smoked",
    "unknown": "you're not sure about smoking",
}


def _facts(values: dict, kind: str, about: bool = False) -> list[str]:
    """One clause per answer, in the check-in's own time frame."""
    approx = "about " if about else ""
    parts = []
    for field, value in values.items():
        if field == "diastolic_bp":
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


def heard(values: dict, kind: str, about: bool = False) -> str:
    return " ".join(f"I heard {fact}." for fact in _facts(values, kind, about))


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
        if request.kind == "weekly":
            questions = WEEKLY
        else:
            questions = DAILY_WITH_HABIT if day.weekday() in HABIT_DAYS else DAILY
        state = CheckinState(
            kind=request.kind,
            questions=list(questions),
            current_field=questions[0],
            previous=request.previous,
        )
        return self._respond(state, GREETINGS[request.kind] + " " + self._prompt(state))

    # -- turns -------------------------------------------------------------------

    def turn(self, request: CheckinTurnRequest) -> CheckinResponse:
        state = request.state.model_copy(deep=True)
        action = request.action
        text = clean_reply(normalize_text(request.text or ""))
        voice = request.input_mode == "transcript"
        # An emergency is answered first, whatever else the reply holds.
        urgent = URGENT_NOTE if action == "reply" and _safe(URGENT.search, text) else ""

        def respond(message: str, hint: str | None = None) -> CheckinResponse:
            return self._respond(state, urgent + message, hint)

        if action == "cancel":
            state = CheckinState(
                kind=state.kind,
                phase="cancelled",
                questions=state.questions,
                previous=state.previous,
            )
            return respond("We can stop here. Nothing was saved. We can check in another time.")
        if state.phase == "cancelled":
            self._invalid("Please start the check-in again.")
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
            intent = control_intent(text)
            kind = intent.kind if intent else None
            if kind in {"repeat", "slower", "louder"}:
                lead = {"repeat": REPEAT_LEAD, "slower": SLOWER_LEAD, "louder": LOUDER_LEAD}
                return respond(lead[kind] + self._prompt(state), None if kind == "repeat" else kind)
            if kind == "help":
                return respond(self._help(state))
            if kind in {"why", "private"}:
                note = WHY_NOTE if kind == "why" else PRIVATE_NOTE
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
                    state = CheckinState(
                        kind=state.kind,
                        questions=state.questions,
                        current_field=state.questions[0],
                        previous=state.previous,
                    )
                    return respond(
                        "Okay, let's start over. I cleared today's answers. " + self._prompt(state)
                    )
                return respond(RESTART_QUESTION + " " + self._prompt(state))
            if kind == "skip":
                if state.phase == "ready":
                    return respond("There are no questions left. " + self._closing(state))
                text = "skip"
            if kind == "back":
                target = self._named(state, intent.field)
                pending = list(state.pending.model_dump(exclude_none=True))
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
            elif said == "no":
                if list(pending) == BOTH_BP:
                    return respond(NO_LEAD + BOTH_BP_MESSAGE)
                return respond(
                    NO_LEAD + f"What is the right answer? For example, {EXAMPLES[field]}."
                )
            else:
                text = rest if said == "correction" else text
        if action == "confirm":
            if state.phase != "confirming":
                self._invalid("There is nothing to confirm right now.")
            additions = state.pending.model_dump(exclude_none=True)
            merged = state.confirmed.model_dump() | additions
            state.confirmed = CheckinValues.model_validate(merged)
            state.pending = CheckinValues()
            state.skipped_fields = [f for f in state.skipped_fields if f not in additions]
            self._advance(state)
            return respond("Got it. " + self._prompt(state))
        if action == "skip":
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
        # A new answer: to the question, or in place of the one read back.
        reopened = state.phase == "asking" and self._saved(state, field)
        if reopened and (keeps_answer(text) or is_skip(text, field)):
            # A question reopened by "go back": "keep it" or "skip" leaves the saved answer.
            self._advance(state)
            return respond("Okay, I kept your answer. " + self._prompt(state))
        if state.phase == "asking" and (
            is_skip(text, field) or (field == "systolic_bp" and no_new_reading(text))
        ):
            self._skip(state, field)
            self._advance(state)
            return respond(SKIPPED + self._prompt(state))
        values, hint, same = _safe(self._read, state, text, voice) or ({}, None, False)
        if not values:
            ask = self._prompt(state) if state.phase == "confirming" else self._question(state)
            if hint and state.phase != "confirming":
                return respond(hint)
            return respond((hint or NOT_CAUGHT) + " " + ask)
        merged = state.confirmed.model_dump() | values
        if merged.get("systolic_bp") and merged.get("diastolic_bp"):
            if merged["systolic_bp"] <= merged["diastolic_bp"]:
                return respond(BP_ORDER + " " + self._question(state))
        state.pending = CheckinValues.model_validate(values)
        state.phase = "confirming"
        lead = SAME_LEAD if same else ""
        about = not same and bool(_safe(approximate, text))
        return respond(asked_back + lead + heard(values, state.kind, about) + " Is that right?")

    # -- reading an answer -------------------------------------------------------

    def _read(self, state: CheckinState, text: str, voice: bool):
        """(values, follow-up, same as before) for a reply to the current question."""
        field = state.current_field
        names = BOTH_BP if field == "systolic_bp" else [field]
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

    # -- helpers -----------------------------------------------------------------

    def _respond(
        self, state: CheckinState, message: str, hint: str | None = None
    ) -> CheckinResponse:
        reaction = {
            "asking": "asking",
            "confirming": "confirming",
            "ready": "celebrating",
            "cancelled": "idle",
        }[state.phase]
        return CheckinResponse(
            state=state,
            message=message,
            complete=state.phase == "ready",
            mascot_events=[MascotEvent(state=reaction, caption=message)],
            speech_hint=hint,
        )

    @staticmethod
    def _question(state: CheckinState, plain: bool = False) -> str:
        field = state.current_field
        forms = QUESTIONS[state.kind][field]
        names = BOTH_BP if field == "systolic_bp" else [field]
        values = [getattr(state.previous, name) for name in names]
        if plain or any(value is None for value in values):
            return forms["ask"]
        value = values[0]
        if field == "smoking_status":
            return forms.get(f"again_{value}", forms["ask"])
        if value == 0 and "again_none" in forms:
            return forms["again_none"]
        shown = f"{values[0]} over {values[1]}" if field == "systolic_bp" else None
        return forms["again"].format(value=shown or _last(field, value, state.kind))

    def _prompt(self, state: CheckinState) -> str:
        if state.phase == "confirming":
            pending = state.pending.model_dump(exclude_none=True)
            return heard(pending, state.kind) + " Is that right?"
        if state.phase == "ready":
            return self._closing(state)
        return self._question(state)

    @staticmethod
    def _closing(state: CheckinState) -> str:
        lines = CLOSINGS[state.kind]
        return lines["not_great"] if state.confirmed.wellbeing == "not_great" else lines["default"]

    def _help(self, state: CheckinState) -> str:
        if state.phase == "confirming":
            pending = state.pending.model_dump(exclude_none=True)
            return (
                "I'm checking that I heard you right before I save anything. "
                + heard(pending, state.kind)
                + ' If that\'s right, say "yes". If not, say "no" and then the right answer.'
            )
        if state.phase == "ready":
            return (
                "We're all done. To change an answer, say what to change, like \"change my "
                'sleep". To clear everything and begin again, say "start over".'
            )
        return (
            HELP[state.kind][state.current_field] + ' If you\'d rather not answer, just say "skip".'
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
        names = BOTH_BP if field == "systolic_bp" else [field]
        return any(getattr(state.confirmed, name) is not None for name in names)

    @staticmethod
    def _previous(state: CheckinState) -> CheckinField | None:
        """The answered or skipped question before this one, or the last one when done."""
        order = state.questions
        done = [
            name
            for name in order
            if CheckinService._saved(state, name) or name in state.skipped_fields
        ]
        if state.phase in {"asking", "confirming"}:
            done = [name for name in done if order.index(name) < order.index(state.current_field)]
        return done[-1] if done else None

    def _reopen(self, state: CheckinState, field: CheckinField) -> str:
        """Ask a question again; its saved answer stays until a new one is confirmed."""
        state.pending = CheckinValues()
        state.phase, state.current_field = "asking", field
        names = BOTH_BP if field == "systolic_bp" else [field]
        saved = {
            name: getattr(state.confirmed, name)
            for name in names
            if getattr(state.confirmed, name) is not None
        }
        label = LABELS[field]
        if saved:
            return (
                f"Okay, let's go back to your {label}. Right now I have that "
                f"{_facts(saved, state.kind)[0]}. "
                + self._question(state)
                + ' If that was right, say "keep it".'
            )
        if field in state.skipped_fields:
            return f"Okay, let's go back to your {label}. You skipped it before. " + self._question(
                state
            )
        return f"Okay, let's do your {label}. " + self._question(state)

    @staticmethod
    def _skip(state: CheckinState, field: str) -> None:
        names = BOTH_BP if field == "systolic_bp" else [field]
        for name in names:
            if name not in state.skipped_fields and getattr(state.confirmed, name) is None:
                state.skipped_fields.append(name)

    @staticmethod
    def _advance(state: CheckinState) -> None:
        state.current_field = next(
            (
                name
                for name in state.questions
                if not CheckinService._saved(state, name) and name not in state.skipped_fields
            ),
            None,
        )
        state.phase = "asking" if state.current_field else "ready"

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_checkin_transition", "message": message}
        )
