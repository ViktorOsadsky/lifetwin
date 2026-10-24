"""The change conversation: Mochi works out what changed, reads it back, then saves.

Built on the onboarding machinery through its public functions: the shared parser
reads each new value, and the shared intents handle fillers, room chatter, control
replies ("say that again", "go back"), read-back replies and the emergency pause.
What is new here are the change rules: the current value is said first, a big jump
gets a gentle double-check, age moves only by a birthday, sex at birth never changes
once saved, and diabetes is added or corrected only with a doctor's word.
"""

import logging
import math
import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date

from fastapi import HTTPException

from lifetwin.change.models import (
    NOTE_LENGTH,
    ChangeField,
    ChangeResponse,
    ChangeStartRequest,
    ChangeState,
    ChangeTurnRequest,
    HabitNote,
)
from lifetwin.change.scripts import (
    AGE_RULE,
    ALSO,
    ANYTHING_ELSE,
    BIRTHDAY,
    BOTH_BP,
    BP_NO_READING,
    BP_TALK,
    CANCELLED,
    CHANGE_THANKS,
    CHOOSE_AGAIN,
    DELETE_NOTE,
    DIABETES_NO_DOCTOR,
    DIABETES_STAYS,
    DOCTOR_QUESTION,
    DONE_AGAIN,
    GREETING,
    HELP,
    HELP_CHOOSING,
    HELP_CONFIRMING,
    HELP_PROBING,
    KEPT,
    LABELS,
    MEMORY_NOTE,
    METRIC,
    NEVER_MIND,
    NEW_VALUE,
    NOT_NOTED,
    NOTED,
    NOTHING_CHANGED,
    OTHERS,
    PRIVATE_NOTE,
    PROBE,
    RESTART,
    SAME,
    SAVED,
    SAVED_NAMES,
    SEX_FIXED,
    WHAT_CHANGED,
    WHY_NOTE,
    big_change,
    current_line,
    heard,
)
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.intents import (
    EMERGENCY_MESSAGE,
    RESUME_LEAD,
    asks_back,
    clean_reply,
    control_intent,
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
    QUESTIONS,
    TENS_WORDS,
    TOPICS,
    UNITS_WORDS,
    approximate,
    checkin_smoking,
    clarify,
    is_skip,
    no_new_reading,
    normalize_text,
    parse_reply,
    someone_else,
    weight_change,
)
from lifetwin.onboarding.service import (
    LOUDER_LEAD,
    NO_LEAD,
    NOT_CAUGHT,
    QUESTION_BACK_LEAD,
    REPEAT_LEAD,
    SLOWER_LEAD,
    THANKS,
    UNSURE_LEAD,
)

logger = logging.getLogger(__name__)

BOTH = ("systolic_bp", "diastolic_bp")
# The answers whose change may have a reason worth remembering ("a new routine").
PROBED = {
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "smoking_status",
    "alcohol_drinks_weekly",
    "systolic_bp",
}
_NUMBER = r"(?:\d|\b(?:" + "|".join([*UNITS_WORDS, *TENS_WORDS, "hundred"]) + r")\b)"
# Words that say which answer someone wants to change ("I quit smoking", "my sugar").
TALK: dict[ChangeField, str] = {
    "age": r"\b(?:age|birthday|years? old|how old|a year older|turned \d{2,3})\b",
    "sex": r"\b(?:sex|gender|male|female|transgender|trans)\b|\bborn (?:a )?(?:man|woman|boy|girl)\b",
    "height_cm": TOPICS["height_cm"]
    + r"|\b(?:shrunk|shrank|shorter|taller|feet|foot|inch(?:es)?|cm|centimet\w*)\b",
    "weight_kg": TOPICS["weight_kg"]
    + r"|\b(?:pounds?|lbs?|kilos?|kgs?|stone|heavier|lighter|slimmer|thinner)\b",
    "sleep_hours": TOPICS["sleep_hours"] + r"|\bnights?\b",
    "exercise_minutes_weekly": TOPICS["exercise_minutes_weekly"] + r"|\b(?:active|activity)\b",
    "smoking_status": TOPICS["smoking_status"],
    "alcohol_drinks_weekly": TOPICS["alcohol_drinks_weekly"] + r"|\b(?:sober|teetotal\w*)\b",
    "diabetes": TOPICS["diabetes"] + r"|pre ?diabet\w*|\bdiabetic\b",
    "systolic_bp": TOPICS["blood_pressure"]
    + r"|\b(?:bp|hypertension)\b|\d{2,3}\s?(?:/|over)\s?\d{2,3}",
}
NOTHING = re.compile(
    r"(?:(?:no|nope|nah|well|oh|um|actually)\s+)*(?:no|nope|nah|nothing|nothing really|"
    r"nothing much|not really|nothing's changed|nothing has changed|nothing changed|"
    r"no change|no changes|it's the same|it's still the same|all the same|same|"
    r"no thanks|no thank you|that's all|that's it|not now|forget it|forget about it|cancel|"
    r"stop|i changed my mind|i've changed my mind|nothing else|no that's all)"
)
# Said around a new value, these describe the change, not an old value: "I'm down to 145".
DOWN_TO = re.compile(
    r"\b(?:(?:cut|come|came|got|gotten|went|gone|slimmed|been)\s+)?(?:back\s+)?down\s+to\b"
    r"|\b(?:shrunk|shrank|dropped)\s+(?:down\s+)?to\b",
    re.I,
)
CHANGE_ONLY = re.compile(
    r"(?:(?:yes|yeah|well|so|oh|and|but|actually)\s+)*(?:i've been|i have been|i've|i have|"
    r"i'm|i am|i)?\s*(?:(?:lost|gained|put on|dropped|shed)(?:\s+(?:some|a little|a bit|a lot|"
    r"a few|quite a bit|a little bit|a good bit))?(?:\s+of)?(?:\s+(?:weight|pounds|kilos))?"
    r"|(?:shrunk|shrank|gotten shorter|got shorter)(?:\s+(?:a bit|a little|some))?"
    r"|(?:sleeping|eating|feeling) better)"
)
CHANGE_CUE = re.compile(
    r"\b(?:lost|gained|put on|dropped|better|worse|more|less|fewer|longer|shorter|started|"
    r"starting|stopped|quit|gave up|cut (?:down|back)|new|changed|different|now|since|been|"
    r"higher|lower|heavier|lighter|thinner|shrunk|shrank|doctor|diagnos\w*|high|low)\b"
)
WHY_AFTER = re.compile(
    r"[\s,;.-]+(?:since|because|cause|'cause|after|thanks to|due to|now that|ever since)\b", re.I
)
# A reason for the change, kept as a habit note with memory consent.
REASON = re.compile(
    r"\b(?:because|cause|since|after|thanks to|due to|now that|started|starting|stopped|new|"
    r"doctor|diet|surgery|operation|retired|moved|routine)\b"
)
DOCTOR = re.compile(
    r"\b(?:doctor|doctors|doctor's|dr|doc|gp|physician|nurse|specialist|endocrinologist|"
    r"diagnos\w*|blood tests?|a1c|tests? (?:showed|came back|results?))\b"
)
DIABETES_GONE = re.compile(
    r"\b(?:cured|remission|reversed|went away|gone away|got rid of|no longer|anymore|any more)\b"
)
BIRTHDAY_SAID = re.compile(
    r"\b(?:had|celebrated|just had)\s+(?:a|my|another)\s+birthday\b|\bit was my birthday\b|"
    r"\bmy birthday (?:was|came|has (?:been|passed|come)|just passed)\b|\b(?:a|one) year older\b"
)
BP_TALK_CUE = re.compile(r"\b(?:blood pressure|pressure|hypertension|bp|doctor)\b")
INSTEAD = re.compile(r"[\s,]+(?:instead|then|please|too|as well|also)[\s.!?]*$", re.I)
CLEAR_WORDS = re.compile(r"\b(?:clear|erase|wipe|delete)\b")
# Words that only name an answer to change ("I'd like to update my weight, please").
NAMING = set(
    """my the i i'd i'm i've like to want wanna update change fix correct edit about hmm um uh
    well so please mochi answer it it's is oh okay ok yes yeah let's do can could we need would
    you a an for on with of me just quick now one question number reading too also and
    as then next instead""".split()
)


def _safe(read, *args, **kwargs):
    """A parser failure is a reply not understood, never a 500; only the type is logged."""
    try:
        return read(*args, **kwargs)
    except Exception as exc:  # noqa: BLE001 - any parser bug must degrade to a follow-up
        logger.warning("change parser failed: %s", type(exc).__name__)
        return None


def _names(field: str) -> tuple[str, ...]:
    return BOTH if field == "systolic_bp" else (field,)


def _same(got: dict, want: dict) -> bool:
    if got.keys() != want.keys():
        return False
    return all(
        a == b
        if not isinstance(a, (int, float))
        or not isinstance(b, (int, float))
        or isinstance(a, bool)
        or isinstance(b, bool)
        else math.isclose(a, b, abs_tol=0.01)
        for a, b in ((got[key], want[key]) for key in want)
    )


def _value_text(text: str) -> str:
    """The reply with words that describe the change (not an old value) taken out."""
    parts = re.split(r"([,.;!]+\s*)", text)
    kept = [
        part for i, part in enumerate(parts) if i % 2 or not CHANGE_ONLY.fullmatch(words_of(part))
    ]
    shorter = "".join(kept).strip(" ,.;!")
    if shorter and re.search(_NUMBER, shorter.lower()):
        text = shorter
    # "150, since I started walking": the reason after the value is not part of it.
    reason = WHY_AFTER.search(text)
    if reason and re.search(_NUMBER, text[: reason.start()].lower()):
        if not re.search(_NUMBER, text[reason.start() :].lower()):
            text = text[: reason.start()]
    return " ".join(DOWN_TO.sub(" ", text).split()).strip(" ,.;!")


def _note(text: str) -> str:
    return clean_reply(normalize_text(text))[:NOTE_LENGTH].strip() or text[:NOTE_LENGTH]


@dataclass
class _Turn:
    profile: dict
    consent: bool
    voice: bool
    today: date


class ChangeService:
    def __init__(self, *, clock: Callable[[], date] = date.today):
        # Ages from birth years are read against today; tests fix the day.
        self.clock = clock

    # -- start -------------------------------------------------------------------

    def start(self, request: ChangeStartRequest) -> ChangeResponse:
        turn = _Turn(request.profile.model_dump(), request.memory_consent, False, self.clock())
        state = ChangeState()
        if request.field is None:
            return self._respond(state, turn, GREETING)
        message = self._enter(state, turn, request.field)
        if state.phase == "asking":
            message = f"Let's update your {LABELS[request.field]}. " + message
        return self._respond(state, turn, message)

    # -- turns -------------------------------------------------------------------

    def turn(self, request: ChangeTurnRequest) -> ChangeResponse:
        state = request.state.model_copy(deep=True)
        turn = _Turn(
            request.profile.model_dump(),
            request.memory_consent,
            request.input_mode == "transcript",
            self.clock(),
        )
        if not turn.consent:
            state.note = None
        action = request.action
        text = clean_reply(normalize_text(request.text or ""))

        def respond(message: str, hint: str | None = None) -> ChangeResponse:
            return self._respond(state, turn, message, hint)

        if action == "reply" and state.phase != "cancelled" and _safe(emergency, text):
            # Paused where it was: no value, no next question, no cheer.
            return self._respond(state, turn, EMERGENCY_MESSAGE, urgent=True)
        if action == "cancel":
            state = ChangeState(phase="cancelled")
            return respond(CANCELLED)
        if state.phase == "cancelled":
            self._invalid("Please start the change again.")
        if action == "resume" or (action == "reply" and resumes(text)):
            return respond(RESUME_LEAD + self._prompt(state, turn))
        if action == "confirm":
            if state.phase != "confirming":
                self._invalid("There is nothing to confirm right now.")
            return respond(self._save(state, turn))

        field = state.field
        if field and state.phase in {"asking", "probing", "confirming"}:
            # Room chatter around the answer goes before anything else reads it.
            text = focus(text, field, transcript=turn.voice, confirming=state.phase == "confirming")
        # "Change my sleep instead" is the same request as "change my sleep".
        intent = control_intent(text)
        trimmed = control_intent(INSTEAD.sub("", text))
        if trimmed and trimmed.kind == "back" and getattr(intent, "kind", None) != "back":
            intent = trimmed
        kind = intent.kind if intent else None
        if kind in {"repeat", "slower", "louder"}:
            lead = {"repeat": REPEAT_LEAD, "slower": SLOWER_LEAD, "louder": LOUDER_LEAD}[kind]
            return respond(lead + self._prompt(state, turn), None if kind == "repeat" else kind)
        if kind == "help":
            return respond(self._help(state, turn))
        if kind in {"why", "private"}:
            note = WHY_NOTE if kind == "why" else PRIVATE_NOTE
            if turn.consent and state.phase == "probing":
                note += " " + MEMORY_NOTE
            return respond(note + " " + self._prompt(state, turn))
        if kind == "ask" and field and not asks_back(text, field, transcript=turn.voice):
            kind = None  # chatter worded like a question, beside the answer
        if kind == "ask":
            return respond(QUESTION_BACK_LEAD + self._prompt(state, turn))
        if kind in {"restart", "restart_confirmed"}:
            # Nothing is saved until a yes, so starting again clears only this talk.
            state = ChangeState()
            lead = DELETE_NOTE + " " if CLEAR_WORDS.search(words_of(text)) else ""
            return respond(lead + RESTART)
        if kind == "skip":
            if state.phase == "probing":
                state.phase = "confirming"
                return respond(NOT_NOTED + self._read_back(state, turn))
            return respond(self._unchanged(state, KEPT))
        if kind == "back":
            target = "systolic_bp" if intent.field == "diastolic_bp" else intent.field
            if target is None:
                if state.phase == "confirming":
                    return respond(self._said_no(state, turn))
                if state.phase in {"asking", "probing"}:
                    state = ChangeState()
                    return respond("Okay. " + GREETING.split("! ", 1)[1])
                return respond(self._prompt(state, turn))
            if target == field and state.phase in {"asking", "probing", "confirming"}:
                if not intent.rest:
                    if state.phase == "confirming":
                        return respond(self._said_no(state, turn))
                    return respond(self._prompt(state, turn))
                # "Change my weight to 150" while on the weight: the new answer.
                state.phase, state.pending = "asking", HealthProfile()
                return respond(self._answer(state, turn, intent.rest))
            # "Change my sleep instead": the other answer, with any new value said.
            options = [f for f in state.options if f != target]
            state.saved = HealthProfile()
            return respond(self._enter(state, turn, target, intent.rest, options=options))

        if state.phase == "choosing":
            return respond(self._choose(state, turn, text))
        if state.phase == "asking":
            return respond(self._answer(state, turn, text))
        if state.phase == "probing":
            return respond(self._probe_answer(state, turn, text))
        if state.phase == "confirming":
            return respond(self._reply_to_read_back(state, turn, text))
        return respond(self._after_done(state, turn, text))

    # -- choosing the answer to change --------------------------------------------

    @staticmethod
    def _mentioned(text: str) -> list[ChangeField]:
        """The answers a reply talks about, in the order it mentions them."""
        low = normalize_text(text).lower()
        found = {}
        for field, pattern in TALK.items():
            match = re.search(pattern, low)
            if match:
                found[field] = match.start()
        return sorted(found, key=found.get)

    def _choose(self, state: ChangeState, turn: _Turn, text: str) -> str:
        if self._nothing(text):
            return self._unchanged(state, NOTHING_CHANGED)
        mentioned = self._mentioned(text)
        if state.options:
            # "Which first: smoking or drinks?" -- "Smoking."
            picked = [f for f in mentioned if f in state.options] or mentioned
            if picked:
                options = [f for f in state.options if f != picked[0]]
                return self._enter(state, turn, picked[0], options=options)
        if not mentioned:
            if _safe(someone_else, text):
                return OTHERS + " " + GREETING.split("! ", 1)[1]
            return CHOOSE_AGAIN
        if len(mentioned) > 1:
            state.options = mentioned
            names = [f"your {LABELS[f]}" for f in mentioned]
            joined = ", ".join(names[:-1]) + " or " + names[-1]
            return f"Let's do one at a time. Which would you like to update first: {joined}?"
        return self._enter(state, turn, mentioned[0], text)

    def _enter(
        self,
        state: ChangeState,
        turn: _Turn,
        field: ChangeField,
        text: str | None = None,
        options: list[ChangeField] | None = None,
    ) -> str:
        """Start on one answer: say what Mochi has now, then read the answer if one came."""
        state.phase, state.field = "asking", field
        state.pending, state.saved = HealthProfile(), HealthProfile()
        state.probed = state.doctor_said = False
        state.options = list(options or [])
        if field == "sex" and turn.profile.get("sex") is not None:
            # Sex at birth never changes once saved; the person may pick another answer.
            state.phase, state.field = "choosing", None
            return SEX_FIXED + " " + ANYTHING_ELSE
        lead = current_line(field, turn.profile)
        if text is None:
            return lead + " " + self._first_question(field, turn.profile)
        text = focus(text, field, transcript=turn.voice)
        return self._answer(state, turn, text, lead=lead, entering=True)

    @staticmethod
    def _first_question(field: ChangeField, profile: dict) -> str:
        if profile.get(field) is None:
            return QUESTIONS[field]
        if field == "age":
            return "Have you had a birthday?"
        return WHAT_CHANGED

    # -- the new value -------------------------------------------------------------

    @staticmethod
    def _only_names(field: ChangeField, text: str) -> bool:
        words = re.sub(TALK[field], " ", normalize_text(text).lower())
        return all(word in NAMING for word in words_of(words).split())

    @staticmethod
    def _nothing(text: str) -> bool:
        words = words_of(text)
        return bool(NOTHING.fullmatch(words)) or keeps_answer(text) or same_as_before(text)

    def _answer(
        self, state: ChangeState, turn: _Turn, text: str, lead: str = "", entering: bool = False
    ) -> str:
        """A reply to "what's changed?" for ``state.field``."""
        field = state.field
        old = turn.profile.get(field)
        low = normalize_text(text).lower()
        before = lead + " " if lead else ""
        if self._nothing(text):
            return self._unchanged(state, NOTHING_CHANGED)
        if is_skip(text, field):
            return self._unchanged(state, KEPT)
        if field == "systolic_bp" and _safe(no_new_reading, text):
            return self._unchanged(state, BP_NO_READING)
        if field == "diabetes" and old is True and DIABETES_GONE.search(low):
            return self._unchanged(state, DIABETES_STAYS)
        values, hint, about, metric = self._read(field, text, turn)
        if not values and field == "age" and old is not None:
            # "I had a birthday", or "yes" to "Have you had a birthday?"
            birthday = BIRTHDAY_SAID.search(low) and not _safe(someone_else, text)
            if birthday or read_back_reply(text)[0] == "yes":
                values = {"age": old + 1}
        if field == "diabetes" and DOCTOR.search(low):
            state.doctor_said = True
        if not values:
            if turn.consent and REASON.search(low) and state.note is None:
                state.note = _note(text)
            if _safe(someone_else, text):
                return OTHERS + " " + before + NEW_VALUE[field]
            if hint:
                return before + hint
            if entering and self._only_names(field, text):
                # "My weight", "I'd like to update my exercise": what has changed?
                return before + self._first_question(field, turn.profile)
            if field == "systolic_bp" and BP_TALK_CUE.search(low):
                return BP_TALK + before + NEW_VALUE[field]
            if entering or CHANGE_CUE.search(low):
                # "I took up yoga": the change, without the new value yet.
                return CHANGE_THANKS + before + NEW_VALUE[field]
            return NOT_CAUGHT + " " + before + NEW_VALUE[field]
        state.metric = metric
        new = {name: values[name] for name in _names(field)}
        if _same(new, {name: turn.profile.get(name) for name in _names(field)}):
            return self._unchanged(state, SAME)
        if field == "age" and old is not None and new["age"] != old + 1:
            return AGE_RULE.format(old=old, new=new["age"], next=old + 1)
        if turn.consent and REASON.search(low) and state.note is None:
            state.note = _note(text)
        state.pending = HealthProfile.model_validate(new)
        if (
            turn.consent
            and field in PROBED
            and old is not None
            and not state.probed
            and state.note is None
        ):
            state.phase, state.probed = "probing", True
            return before + PROBE
        state.phase = "confirming"
        return before + self._read_back(state, turn, about)

    def _read(self, field: ChangeField, text: str, turn: _Turn):
        """(values, follow-up, about, metric) for a reply about ``field``."""
        metric = bool(METRIC.search(text))
        about = bool(_safe(approximate, text))
        if field == "weight_kg":
            change = _safe(weight_change, text)
            if change:
                delta, rest = change
                if re.search(r"\d", rest):
                    # "I lost 10 pounds, I'm 150 now": the value said as now counts.
                    found = _safe(parse_reply, _value_text(rest), field, today=turn.today) or {}
                    return found, None, about, metric
                old = turn.profile.get(field)
                if old is None:
                    return {}, None, about, metric
                try:
                    profile = HealthProfile(weight_kg=round(old + delta, 4))
                except ValueError:
                    return {}, None, about, metric
                return {field: profile.weight_kg}, None, True, metric
        reading = _value_text(text)
        if field == "smoking_status":
            status = _safe(checkin_smoking, reading, turn.profile.get(field))
            if status:
                return {field: status}, None, about, metric
        found = _safe(parse_reply, reading, field, today=turn.today, strict=turn.voice) or {}
        values = {name: found[name] for name in _names(field) if name in found}
        if field == "systolic_bp" and len(values) != 2:
            values = {}
        if values:
            return values, None, about, metric
        hint = _safe(clarify, reading, field, today=turn.today)
        if field == "systolic_bp" and not hint:
            if len(re.findall(r"(?<![\d.])\d{2,3}(?![\d.])", reading)) == 1:
                hint = BOTH_BP
        return {}, hint, about, metric

    def _read_back(self, state: ChangeState, turn: _Turn, about: bool = False) -> str:
        field = state.field
        values = state.pending.model_dump(exclude_none=True)
        old = turn.profile.get(field)
        if field == "diabetes":
            if values["diabetes"] and not state.doctor_said:
                return DOCTOR_QUESTION
            if not values["diabetes"]:
                return (
                    "Just to be sure: no doctor has ever told you that you have diabetes. "
                    "Is that right?"
                )
        check = big_change(field, values, turn.profile, state.metric)
        if check:
            return check
        lead = BIRTHDAY if field == "age" and old is not None and values["age"] == old + 1 else ""
        return lead + heard(field, values, turn.profile, state.metric, about) + " Is that right?"

    # -- the probe and the read-back ------------------------------------------------

    def _probe_answer(self, state: ChangeState, turn: _Turn, text: str) -> str:
        """The answer to "did something change, like a new routine?"."""
        values = self._read(state.field, text, turn)[0]
        pending = state.pending.model_dump(exclude_none=True)
        if values and not _same(values, pending):
            # "Actually it's 155, I've been walking": a new value, and the reason with it.
            state.phase, state.pending = "asking", HealthProfile()
            state.note = _note(text) if turn.consent else None
            return self._answer(state, turn, text)
        said = read_back_reply(text)[0]
        if said in {"no", "yes", "unsure"} or self._nothing(text) or is_skip(text, state.field):
            lead = NOT_NOTED
        else:
            state.note = _note(text) if turn.consent else None
            lead = NOTED if turn.consent else NOT_NOTED
        state.phase = "confirming"
        return lead + self._read_back(state, turn)

    def _reply_to_read_back(self, state: ChangeState, turn: _Turn, text: str) -> str:
        field = state.field
        pending = state.pending.model_dump(exclude_none=True)
        said, rest = read_back_reply(text)
        if field == "diabetes":
            # The doctor question is the diabetes question itself: "yes, last spring".
            answer = _safe(parse_reply, text, "diabetes", today=turn.today) or {}
            if said == "yes" or (answer and answer == pending and said != "no"):
                return self._save(state, turn)
            if said in {"no", "correction"} or answer:
                if pending["diabetes"] and not state.doctor_said:
                    return self._unchanged(state, DIABETES_NO_DOCTOR)
                return self._unchanged(state, KEPT)
            if said == "unsure":
                return UNSURE_LEAD + self._read_back(state, turn)
            return NOT_CAUGHT + " " + self._read_back(state, turn)
        if said == "yes_value":
            again = self._read(field, rest, turn)[0]
            said = "yes" if again and _same(again, pending) else "unsure"
        if said == "yes":
            return self._save(state, turn)
        if said == "unsure":
            return UNSURE_LEAD + self._read_back(state, turn)
        if said == "no":
            return self._said_no(state, turn)
        # A new answer in place of the one read back ("no, 155", or just "155").
        before = state.model_copy(deep=True)
        state.phase, state.pending = "asking", HealthProfile()
        message = self._answer(state, turn, rest if said == "correction" else text)
        if said == "other" and state.phase == "asking":
            for name in ChangeState.model_fields:
                setattr(state, name, getattr(before, name))
            return NOT_CAUGHT + " " + self._read_back(state, turn)
        return message

    def _said_no(self, state: ChangeState, turn: _Turn) -> str:
        if state.field == "age":
            # Only one birthday is ever offered, so a no leaves the age as it is.
            return self._unchanged(state, KEPT)
        state.phase, state.pending = "asking", HealthProfile()
        return NO_LEAD + NEW_VALUE[state.field]

    # -- endings ---------------------------------------------------------------------

    def _save(self, state: ChangeState, turn: _Turn) -> str:
        state.saved, state.pending = state.pending, HealthProfile()
        state.phase = "done"
        return SAVED.format(SAVED_NAMES.get(state.field, LABELS[state.field])) + self._also(state)

    def _unchanged(self, state: ChangeState, message: str) -> str:
        state.phase, state.pending, state.saved = "done", HealthProfile(), HealthProfile()
        return message + self._also(state)

    @staticmethod
    def _also(state: ChangeState) -> str:
        return " " + ALSO.format(LABELS[state.options[0]]) if state.options else ""

    def _after_done(self, state: ChangeState, turn: _Turn, text: str) -> str:
        said = read_back_reply(text)[0]
        if state.options and said == "yes":
            # "You also mentioned your drinks. Would you like to update that too?"
            following, *rest = state.options
            return self._enter(state, turn, following, options=rest)
        if state.options and (said == "no" or self._nothing(text)):
            state.options = []
            return "Okay. " + DONE_AGAIN
        if self._mentioned(text) and not self._nothing(text):
            fresh = ChangeState()
            message = self._choose(fresh, turn, text)
            for name in ChangeState.model_fields:
                setattr(state, name, getattr(fresh, name))
            return message
        thanks = "You're welcome! " if THANKS.search(text) else ""
        return thanks + DONE_AGAIN

    # -- helpers -------------------------------------------------------------------

    def _prompt(self, state: ChangeState, turn: _Turn) -> str:
        if state.phase == "choosing":
            if state.options:
                names = [f"your {LABELS[f]}" for f in state.options]
                joined = ", ".join(names[:-1]) + " or " + names[-1]
                return f"Which would you like to update first: {joined}?"
            return GREETING.split("! ", 1)[1]
        if state.phase == "asking":
            return (
                current_line(state.field, turn.profile)
                + " "
                + self._first_question(state.field, turn.profile)
            )
        if state.phase == "probing":
            return PROBE
        if state.phase == "confirming":
            return self._read_back(state, turn)
        return (ALSO.format(LABELS[state.options[0]])) if state.options else DONE_AGAIN

    def _help(self, state: ChangeState, turn: _Turn) -> str:
        if state.phase == "choosing":
            return HELP_CHOOSING + " " + self._prompt(state, turn)
        if state.phase == "asking":
            return HELP[state.field] + NEVER_MIND
        if state.phase == "probing":
            return HELP_PROBING
        if state.phase == "confirming":
            return HELP_CONFIRMING.format(self._read_back(state, turn))
        return DONE_AGAIN

    def _respond(
        self,
        state: ChangeState,
        turn: _Turn,
        message: str,
        hint: str | None = None,
        urgent: bool = False,
    ) -> ChangeResponse:
        # Re-validated, so a state the client could not send back is never returned.
        state = ChangeState.model_validate(state.model_dump())
        complete = state.phase == "done"
        update = state.saved if complete else HealthProfile()
        note = None
        if complete and turn.consent and state.note and update.model_dump(exclude_none=True):
            note = HabitNote(field=state.field, text=state.note)
        reaction = {
            "choosing": "asking",
            "asking": "asking",
            "probing": "asking",
            "confirming": "confirming",
            "done": "idle",
            "cancelled": "idle",
        }[state.phase]
        return ChangeResponse(
            state=state,
            message=message,
            complete=complete,
            mascot_events=[MascotEvent(state="concerned" if urgent else reaction, caption=message)],
            speech_hint=hint,
            emergency=urgent,
            profile_update=update,
            habit_note=note,
        )

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_change_transition", "message": message}
        )
