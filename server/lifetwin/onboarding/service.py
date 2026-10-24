"""Explicit candidate/confirmation transitions for text and final transcripts."""

import asyncio
import logging
import re
from collections.abc import Callable
from datetime import date

from fastapi import HTTPException

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.intents import (
    asks_back,
    clean_reply,
    control_intent,
    focus,
    keeps_answer,
    read_back_reply,
)
from lifetwin.onboarding.intents import phrase as words_of
from lifetwin.onboarding.models import (
    FIELDS,
    ConversationState,
    MascotEvent,
    TurnRequest,
    TurnResponse,
)
from lifetwin.onboarding.parsing import (
    BP_FIELDS,
    BP_ORDER_MESSAGE,
    EXAMPLES,
    FRIENDLY_LABELS,
    QUESTION_EXAMPLE_VALUES,
    QUESTIONS,
    approximate,
    birth_year_ages,
    clarify,
    corrects,
    grounded_candidates,
    is_skip,
    normalize_text,
    parse_reply,
)
from lifetwin.onboarding.providers import ExtractionUnavailable, Extractor

logger = logging.getLogger(__name__)


def _safe(read, *args, **kwargs):
    """A parser failure is a reply not understood, never a 500; only the type is logged."""
    try:
        return read(*args, **kwargs)
    except Exception as exc:  # noqa: BLE001 - any parser bug must degrade to a follow-up
        logger.warning("intake parser failed: %s", type(exc).__name__)
        return None


# "Yeah, that's right" said to "For example, 5 feet 10 inches" means the example fits.
EXAMPLE_YES = re.compile(
    r"(?:(?:yes|yeah|yea|yep|yup|uh huh|sure|right|correct|exactly)\s*)+"
    r"(?:(?:that's|thats|that is|it's|its)\s+(?:right|correct|me|it|true|about right))?"
    r"|(?:that's|thats|that is|it's|its)\s+(?:right|correct|me|it|true|about right)"
)
BOTH_BP = ["systolic_bp", "diastolic_bp"]
BOTH_BP_MESSAGE = 'Please tell me both blood pressure numbers, for example "120 over 80".'
SEX_WORDS = {
    "female": "female at birth",
    "male": "male at birth",
}
SMOKING_WORDS = {
    "never": "never smoked",
    "former": "smoked in the past",
    "current": "smoke now",
    "unknown": "not sure",
}


# Lead-ins for replies about the conversation itself; the prompt follows unchanged.
REPEAT_LEAD = "Of course. "
SLOWER_LEAD = "Of course, I'll go slower. "
LOUDER_LEAD = "I'll speak up. "
UNSURE_LEAD = "Is that a yes? Nothing has changed yet. "
NO_LEAD = "Okay, nothing has changed. "
QUESTION_BACK_LEAD = (
    "That's a good question, but I can't answer it here, and I haven't saved anything from it. "
)
RESTART_QUESTION = (
    "Do you want to clear all your answers and start again? "
    "Say 'yes, start over' to do that, or just keep answering."
)
DONE_LEAD = "Your answers are saved. Tap Continue to see your forecast."
WHAT_NOW = re.compile(
    r"(?:so )?(?:what now|now what|what next|what's next|what do i do now|what happens now|"
    r"what happens next|what do i do next|is that it|are we done|am i done|that's it then)"
)
THANKS = re.compile(r"\b(?:thanks|thank you|thank u|ty|cheers|much obliged)\b", re.I)
PRIVATE_NOTE = (
    "Your answers stay on your phone and LifeTwin's server, are used for your forecast, "
    "and nothing is saved until you say yes."
)
WHY_NOTE = (
    "I ask so your twin can make your forecast; your answers stay on your phone and "
    "LifeTwin's server, and nothing is saved until you say yes."
)
HELPER_NOTE = "The AI helper reads an answer only if you say it's okay."
SKIP_NOTE = 'If you\'d rather not answer, just say "skip".'
# A plain explanation of each question, with an example answer.
HELP: dict[str, str] = {
    "age": "I'm asking how many years old you are today. For example, say \"I'm 72\". "
    "You can also tell me the year you were born.",
    "sex": "I'm asking whether you were born female or male, because health numbers differ "
    'between the two. Just say "female" or "male".',
    "height_cm": "I'm asking how tall you are, standing without shoes. For example, "
    '"5 feet 10 inches" or "178 cm". A close guess is fine.',
    "weight_kg": 'I\'m asking how much you weigh. For example, "160 pounds" or "72 kg". '
    "A close guess is fine; I'll read it back to you.",
    "sleep_hours": "I'm asking how many hours you sleep on a usual night. For example, "
    '"7 hours", or "from 11 at night to 6 in the morning".',
    "exercise_minutes_weekly": "I'm asking how many minutes you move on purpose in a whole "
    "week, like walking, swimming or gardening. For example, a 30-minute walk 5 days a week "
    'is "150 minutes". If you don\'t exercise, say "none".',
    "smoking_status": 'I\'m asking about smoking cigarettes. Say "never" if you never smoked, '
    '"I quit" if you smoked in the past, or "I smoke" if you smoke now.',
    "alcohol_drinks_weekly": "I'm asking how many drinks of beer, wine or liquor you have in "
    'a usual week. One beer or one glass of wine is one drink. For example, "3 drinks", or '
    '"none".',
    "diabetes": "I'm asking if a doctor has ever told you that you have diabetes, also called "
    'high blood sugar. Say "yes", "no", or "I don\'t know".',
    "systolic_bp": "I'm asking for your blood pressure: the two numbers a blood pressure cuff "
    'shows, the bigger one first. For example, "120 over 80". If you don\'t know it, say '
    '"I don\'t know".',
    "diastolic_bp": "I'm asking for the bottom, smaller number of your blood pressure. For "
    'example, the 80 in "120 over 80". If you don\'t know it, say "I don\'t know".',
}


ESTIMATED = {
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "alcohol_drinks_weekly",
}


def _plain(value: float, digits: int = 1) -> str:
    text = f"{value:.{digits}f}"
    # Only trim zeros after a decimal point: "170" must not become "17".
    return text.rstrip("0").rstrip(".") if "." in text else text


def _about(value: float, shown: str) -> str:
    return "" if abs(value - float(shown)) < 0.01 else "about "


def _count(value: float, unit: str) -> str:
    return "none" if value == 0 else f"{_plain(value)} {unit}{'' if value == 1 else 's'}"


def _both(metric: str, imperial: str, metric_exact: bool, imperial_exact: bool) -> str:
    # The unit the person used converts exactly, so it is shown first.
    if metric_exact and not imperial_exact:
        return f"{metric} ({imperial})"
    return f"{imperial} ({metric})"


def _height(cm: float) -> str:
    inches = cm / 2.54
    shown_in, shown_cm = str(round(inches)), _plain(cm, 0)
    feet, rest = divmod(round(inches), 12)
    imperial = f"{_about(inches, shown_in)}{feet} feet" + (f" {rest} inches" if rest else "")
    metric = f"{_about(cm, shown_cm)}{shown_cm} cm"
    return _both(metric, imperial, not _about(cm, shown_cm), not _about(inches, shown_in))


def _weight(kg: float) -> str:
    pounds = kg / 0.45359237
    shown_lb, shown_kg = _plain(pounds), _plain(kg)
    imperial = f"{_about(pounds, shown_lb)}{shown_lb} pounds"
    metric = f"{_about(kg, shown_kg)}{shown_kg} kg"
    return _both(metric, imperial, not _about(kg, shown_kg), not _about(pounds, shown_lb))


def describe(values: dict, about: set[str] = frozenset()) -> str:
    """Plain-language summary in the person's own unit, metric value beside it.

    Fields in ``about`` were estimated (the middle of a range) and say so.
    """
    parts = []
    for field, value in values.items():
        if field == "diastolic_bp" and "systolic_bp" in values:
            continue
        if field == "systolic_bp" and "diastolic_bp" in values:
            about_bp = "about " if field in about else ""  # "maybe like 130 over 85"
            parts.append(f"Blood pressure: {about_bp}{value} over {values['diastolic_bp']}")
            continue
        shown = {
            "age": lambda v: str(v),
            "sex": SEX_WORDS.get,
            "height_cm": _height,
            "weight_kg": _weight,
            "sleep_hours": lambda v: f"{_plain(v)} hour{'' if v == 1 else 's'} a night",
            "exercise_minutes_weekly": lambda v: _count(v, "minute") + " a week",
            "smoking_status": SMOKING_WORDS.get,
            "alcohol_drinks_weekly": lambda v: _count(v, "drink") + " a week",
            "diabetes": lambda v: "yes" if v else "no",
            "systolic_bp": str,
            "diastolic_bp": str,
        }[field](value)
        label = FRIENDLY_LABELS[field]
        if field in about and field in ESTIMATED and not shown.startswith("about "):
            shown = "about " + shown
        parts.append(f"{label[0].upper()}{label[1:]}: {shown}")
    return "; ".join(parts)


class ConversationService:
    def __init__(
        self,
        extractor: Extractor | None = None,
        *,
        timeout_seconds: float = 6,
        clock: Callable[[], date] = date.today,
    ):
        self.extractor = extractor
        self.timeout = max(0.1, min(timeout_seconds, 10.0))
        # Birth dates are read against today; tests inject a fixed day.
        self.clock = clock

    async def turn(self, request: TurnRequest) -> TurnResponse:
        state = request.state.model_copy(deep=True)
        mode = "guided"
        configured = self.extractor is not None and self.extractor.configured
        provider_status = "not_needed" if configured else "not_configured"
        action = request.action
        # Fillers, stutters and transcript punctuation go first; meaning stays.
        text = clean_reply(normalize_text(request.text or ""))
        today = self.clock()
        # Ink also transcribes other people in the room: only a voice transcript is
        # held to "someone else's number beside yours is asked about".
        voice = request.input_mode == "transcript"
        heard_for = state.current_field or next(
            iter(state.pending_profile.model_dump(exclude_none=True)), None
        )
        if action == "reply" and heard_for and state.phase in {"asking", "confirming"}:
            # Room chatter around the answer goes before anything else reads it.
            text = focus(text, heard_for, transcript=voice, confirming=state.phase == "confirming")

        def respond(message: str, hint: str | None = None) -> TurnResponse:
            reaction = {
                "idle": "idle",
                "asking": "asking",
                "confirming": "confirming",
                "ready": "celebrating",
                "cancelled": "idle",
            }[state.phase]
            return TurnResponse(
                state=state,
                message=message,
                guide_mode=mode,
                provider_status=provider_status,
                complete=state.phase == "ready",
                mascot_events=[MascotEvent(state=reaction, caption=message)],
                speech_hint=hint,
            )

        if action == "cancel":
            # Clear drafts and supplied health data from the returned session.
            state = ConversationState(phase="cancelled")
            return respond(
                "We can stop here. Your conversation state is cleared. Come back whenever you like."
            )
        if action == "start":
            if state.phase in {"cancelled", "idle"}:
                state.pending_profile = HealthProfile()
                self._advance(state)
            return respond(
                "Hi, I'm your twin's guide! You can type or talk to me. "
                "You can skip any question, and I'll check each answer with you before I save it. "
                + self._prompt(state)
            )
        if state.phase in {"idle", "cancelled"}:
            self._invalid("Start the conversation before sending another action.")
        read_back = None  # how a reply to a read-back is read, when not left to the reply
        if action == "reply" and state.phase == "ready" and WHAT_NOW.fullmatch(words_of(text)):
            return respond(DONE_LEAD)
        if action == "reply":
            intent = control_intent(text)
            kind = intent.kind if intent else None
            if kind in {"repeat", "slower", "louder"}:
                lead = {"repeat": REPEAT_LEAD, "slower": SLOWER_LEAD, "louder": LOUDER_LEAD}
                return respond(lead[kind] + self._prompt(state), None if kind == "repeat" else kind)
            if kind == "help":
                return respond(self._help(state))
            if kind in {"why", "private"}:
                note = WHY_NOTE if kind == "why" else PRIVATE_NOTE
                note += " " + HELPER_NOTE if configured else ""
                return respond(note + " " + self._prompt(state))
            if kind == "ask" and heard_for and not asks_back(text, heard_for, transcript=voice):
                kind = None  # chatter worded like a question, beside the answer
            if kind == "ask":
                return respond(QUESTION_BACK_LEAD + self._prompt(state))
            if kind in {"restart", "restart_confirmed"}:
                answers = state.model_dump(include={"confirmed_profile", "pending_profile"})
                if not state.skipped_fields and not any(
                    value is not None for profile in answers.values() for value in profile.values()
                ):
                    return respond(
                        "We're just getting started, so there's nothing to clear. "
                        + self._prompt(state)
                    )
                if kind == "restart_confirmed":
                    state = ConversationState(pending_profile=HealthProfile())
                    self._advance(state)
                    return respond(
                        "Okay, let's start over. I cleared your answers. " + self._prompt(state)
                    )
                # Nothing is held over to the next turn: the prompt that follows (a read-back
                # included) is what a bare "yes" will answer.
                return respond(RESTART_QUESTION + " " + self._prompt(state))
            if kind == "skip":
                if state.phase == "ready":
                    return respond("There are no questions left. " + self._prompt(state))
                text = "skip"
            if kind == "back":
                pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
                field = intent.field
                if state.phase == "confirming" and (field is None or field in pending_fields):
                    # "I made a mistake", "change my age to 47" during its read-back.
                    if intent.rest:
                        text, read_back = intent.rest, "correction"
                    else:
                        read_back = "no"
                else:
                    note = ""
                    if state.phase == "confirming":
                        # Unsaved answers are asked again later; saved ones never change here.
                        note = (
                            "I haven't saved your "
                            + " and ".join(
                                dict.fromkeys(self._label(name) for name in pending_fields)
                            )
                            + " answer yet, so I'll ask again later. "
                        )
                    field = field or self._previous(state)
                    if field is None:
                        return respond(
                            "This is the first question, so there's nothing to go back to. "
                            + self._prompt(state)
                        )
                    message = note + self._reopen(state, field)
                    if intent.rest:
                        # "Change my age to 47": the new answer is read back as usual.
                        answered = await self.turn(
                            TurnRequest(
                                action="reply",
                                state=state,
                                text=intent.rest,
                                input_mode=request.input_mode,
                                provider_consent=request.provider_consent,
                            )
                        )
                        if answered.state.phase == "confirming":
                            return answered
                    return respond(message)
        from_read_back = False
        if action == "reply" and state.phase == "confirming":
            # Only an unmistakable yes confirms; a no never does, and a correction
            # replaces only the answer being read back.
            heard, rest = (read_back, "") if read_back else read_back_reply(text)
            if read_back == "correction":
                rest = text
            pending = state.pending_profile.model_dump(exclude_none=True)
            if heard == "yes_value":
                # "Yes, 46" to "Age: 46" confirms; "yes, 47" is a question, not a yes.
                asked = "systolic_bp" if list(pending) == BOTH_BP else next(iter(pending))
                said = _safe(parse_reply, rest, asked, today=today) or {}
                heard = "yes" if said == pending else "unsure"
            if heard == "yes":
                action = "confirm"
            elif heard == "unsure":
                return respond(UNSURE_LEAD + self._prompt(state))
            elif heard == "no":
                pending_fields = list(pending)
                if len(pending_fields) == 1:
                    field = pending_fields[0]
                    return respond(
                        NO_LEAD + "Please tell me the right answer for "
                        f"your {FRIENDLY_LABELS[field]}, for example {EXAMPLES[field]}."
                    )
                if pending_fields == BOTH_BP:
                    return respond(NO_LEAD + BOTH_BP_MESSAGE)
                return respond(
                    NO_LEAD + "Which answer should I change? "
                    'Please say its name and the right answer, like "weight: 150 pounds".'
                )
            else:
                text = rest if heard == "correction" else text
                action, from_read_back = "correct", True
        if action == "confirm":
            if state.phase != "confirming":
                self._invalid("There are no pending answers to confirm.")
            additions = state.pending_profile.model_dump(exclude_none=True)
            merged = state.confirmed_profile.model_dump()
            merged.update(additions)
            state.confirmed_profile = HealthProfile.model_validate(merged)
            state.pending_profile = HealthProfile()
            state.skipped_fields = [
                field for field in state.skipped_fields if field not in additions
            ]
            self._advance(state)
            return respond("Confirmed! " + self._prompt(state))
        if action == "import":
            if state.phase == "confirming":
                self._invalid("Confirm or correct the pending answer before adding more.")
            asked = state.current_field
            additions = request.values.model_dump(exclude_none=True)
            merged = state.confirmed_profile.model_dump()
            merged.update(additions)
            state.confirmed_profile = HealthProfile.model_validate(merged)
            state.skipped_fields = [
                field for field in state.skipped_fields if field not in additions
            ]
            self._advance(state)
            # Stay on the question the person was answering if it is still open,
            # rather than jumping back to an earlier one.
            if (
                asked
                and getattr(state.confirmed_profile, asked) is None
                and asked not in state.skipped_fields
            ):
                state.current_field, state.phase = asked, "asking"
            count = "1 answer" if len(additions) == 1 else f"{len(additions)} answers"
            # Asking the same question again without saying why feels like being stuck.
            missing = (
                f"Your Health app didn't have your {FRIENDLY_LABELS[asked]}, so I still need it. "
                if asked and state.current_field == asked
                else ""
            )
            return respond(
                f"Thanks! I added {count} you checked from your Health app: "
                + describe(additions)
                + ". "
                + missing
                + self._prompt(state)
            )
        if action == "skip":
            target = request.field or state.current_field
            if target is None:
                self._invalid("Choose a field to skip.")
            if state.phase == "confirming":
                self._invalid("Confirm or correct pending answers before skipping a question.")
            if getattr(state.confirmed_profile, target) is not None:
                if target == state.current_field and request.field is None:
                    # Skipping a question reopened by "go back" keeps the saved answer.
                    self._advance(state)
                    return respond("Okay, I kept your answer. " + self._prompt(state))
                self._invalid("Skipping does not erase confirmed measurements.")
            self._skip(state, target)
            self._advance(state)
            return respond("That's okay; I won't fill it in. " + self._prompt(state))
        if state.phase == "ready" and action == "reply":
            # "Thank you", "ok", "bye", "what now?": a kind word, never an error.
            thanks = "You're welcome! " if THANKS.search(text) else ""
            return respond(thanks + DONE_LEAD)
        if state.phase == "ready" and action != "correct":
            self._invalid(
                "The conversation is ready. Use correct with a field to change an answer."
            )
        if state.phase == "confirming" and action != "correct":
            self._invalid("Confirm or correct the pending answers first.")
        target = request.field or state.current_field
        if action == "correct" and state.phase == "confirming" and request.field is None:
            pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
            if pending_fields == BOTH_BP:
                # A pending reading is corrected as a whole pair, never one guessed half.
                if len(_safe(parse_reply, text, "systolic_bp", today=today) or {}) != 2:
                    return respond(BOTH_BP_MESSAGE + " Nothing has changed.")
                pending_fields = ["systolic_bp"]
            if len(pending_fields) != 1:
                return respond(
                    "I have more than one answer waiting: "
                    + ", ".join(FRIENDLY_LABELS[field] for field in pending_fields)
                    + ". Which one do you want to change? Nothing has changed."
                )
            target = pending_fields[0]
        if target is None:
            self._invalid("Choose the field you want to correct.")
        asking = action == "reply" and state.phase == "asking"
        reopened = asking and self._saved(state, target)
        if reopened and (keeps_answer(text) or is_skip(text, target)):
            # A question reopened by "go back": "keep it" or "skip" leaves the saved answer.
            self._advance(state)
            return respond("Okay, I kept your answer. " + self._prompt(state))
        if is_skip(text, target):
            if action == "correct":
                if request.field and getattr(state.confirmed_profile, target) is not None:
                    # An explicitly chosen saved answer may be withdrawn to blank;
                    # this never adds or guesses a value.
                    confirmed = state.confirmed_profile.model_dump()
                    confirmed[target] = None
                    state.confirmed_profile = HealthProfile.model_validate(confirmed)
                    if target not in state.skipped_fields:
                        state.skipped_fields.append(target)
                    if state.phase != "confirming":
                        self._advance(state)
                    return respond(
                        f"Okay, I removed your {FRIENDLY_LABELS[target]} answer and left it "
                        "blank. If that was a mistake, just tell me the answer again. "
                        + self._prompt(state)
                    )
                return respond("Nothing has changed. " + self._prompt(state))
            self._skip(state, target)
            self._advance(state)
            return respond("I'll leave that unknown. " + self._prompt(state))
        candidates = _safe(parse_reply, text, target, today=today, strict=voice) or {}
        phrase = " ".join(text.lower().replace(",", " ").rstrip(".!?").split())
        # Only a fresh answer can mean the question's example: "no, that's right" during
        # a read-back is not a yes to "5 feet 10 inches".
        if (
            not candidates
            and asking
            and target in QUESTION_EXAMPLE_VALUES
            and EXAMPLE_YES.fullmatch(phrase)
        ):
            # Offered back as a normal answer, so it is still read back and confirmed.
            candidates = parse_reply(QUESTION_EXAMPLE_VALUES[target], target, today=today)
        # A targeted follow-up ("45 or 46?") beats asking the AI helper to guess.
        # "Born in 1980": work the age out and check it, instead of asking "45 or 46?".
        birth_note = None
        if not candidates and target == "age":
            guess = _safe(birth_year_ages, text, today=today)
            if guess:
                likely, other, lead = guess
                candidates = {"age": likely}
                when = "hasn't come yet" if likely > other else "has already passed"
                birth_note = (
                    f"{lead}: that makes you {likely}, or {other} if your birthday {when} this year. "
                    f"Is {likely} right? Say yes, or tell me the right age."
                )
        hint = None if candidates else _safe(clarify, text, target, today=today)
        if not candidates and configured and not hint:
            if request.provider_consent:
                try:
                    async with asyncio.timeout(self.timeout):
                        extraction = await self.extractor.extract(text, target)
                    candidates = (
                        _safe(grounded_candidates, text, extraction, target, today=today) or {}
                    )
                    # The helper answered; finding no usable value is not an outage.
                    provider_status = "used"
                    if candidates:
                        mode = "llm"
                except (ExtractionUnavailable, TimeoutError):
                    provider_status = "unavailable"
            else:
                provider_status = "consent_required"
        # A saved answer changes only when asked for by name or corrected explicitly
        # ("actually I'm 71, not 72"); "7 hours, oh man" can never rewrite sex.
        saved = state.confirmed_profile.model_dump(exclude_none=True)
        # A reopened question may replace its own saved answer (both blood pressure numbers).
        asked = {target} | (BP_FIELDS if reopened and target in BP_FIELDS else set())
        candidates = {
            field: value
            for field, value in candidates.items()
            if field not in saved
            or field == request.field
            or corrects(text, field)
            or (reopened and field in asked)
        }
        if from_read_back:
            # "No, I'm 47 and I weigh 150" to "Age: 46": only the age is replaced.
            held = state.pending_profile.model_dump(exclude_none=True)
            candidates = {field: value for field, value in candidates.items() if field in held}
        lone_bottom = list(candidates) == ["diastolic_bp"] and (
            state.confirmed_profile.systolic_bp is None
            and state.pending_profile.systolic_bp is None
        )
        # A bare "120" to the blood-pressure question is half a reading: ask for both.
        # A stated top number ("the top number is 130") is explicit and still accepted.
        lone_bottom = lone_bottom or (
            list(candidates) == ["systolic_bp"]
            and re.fullmatch(r"\d{2,3}", text.strip(" .!?"))
            and state.confirmed_profile.diastolic_bp is None
            and state.pending_profile.diastolic_bp is None
        )
        if lone_bottom:
            # A bottom number alone can only be checked against a known top number.
            candidates, mode = {}, "guided"
        if not candidates:
            notice = ""
            if provider_status == "consent_required":
                notice = (
                    "I can ask an AI helper to read this answer, but only if you say it's okay. "
                )
            elif provider_status == "unavailable":
                notice = "The AI helper isn't available right now, but we can keep going. "
            hint = BOTH_BP_MESSAGE if lone_bottom else hint
            if state.phase == "confirming":
                return respond(
                    notice
                    + (hint + " " if hint else "Sorry, I didn't understand that. ")
                    + "Nothing has changed. "
                    + self._prompt(state)
                )
            return respond(
                notice
                + (
                    hint
                    or "Sorry, I didn't understand that. You can answer in your own words, "
                    'or say "skip". '
                    + QUESTIONS[target]
                )
            )
        if action == "correct" and request.field and request.field not in candidates:
            return respond(
                "Please give the right answer for your "
                + FRIENDLY_LABELS[request.field]
                + ". "
                + QUESTIONS[request.field]
            )
        # Corrections replace affected pending values; unrelated pending values stay visible.
        pending = state.pending_profile.model_dump(exclude_none=True)
        pending.update(candidates)
        if not self._bp_ordered(state, pending):
            return respond(
                BP_ORDER_MESSAGE
                + " Nothing has changed. "
                + (self._prompt(state) if state.phase == "confirming" else QUESTIONS[target])
            )
        state.pending_profile = HealthProfile.model_validate(pending)
        state.phase = "confirming"
        state.current_field = next(iter(pending)) if len(pending) == 1 else None
        if birth_note and len(pending) == 1:
            return respond(birth_note)
        # A middle of a range ("7 or 8 hours") is read back as "about".
        return respond(self._prompt(state, about=set(candidates) if approximate(text) else set()))

    @staticmethod
    def _saved(state: ConversationState, field: str) -> bool:
        fields = BP_FIELDS if field in BP_FIELDS else {field}
        return any(getattr(state.confirmed_profile, name) is not None for name in fields)

    @staticmethod
    def _label(field: str) -> str:
        return "blood pressure" if field in BP_FIELDS else FRIENDLY_LABELS[field]

    @staticmethod
    def _previous(state: ConversationState) -> str | None:
        """The answered question before this one ("go back"), or the last one when done."""
        answered = [
            field
            for field in FIELDS
            if getattr(state.confirmed_profile, field) is not None or field in state.skipped_fields
        ]
        if state.phase == "asking":
            answered = [f for f in answered if FIELDS.index(f) < FIELDS.index(state.current_field)]
        if not answered:
            return None
        field = answered[-1]
        return "systolic_bp" if field == "diastolic_bp" and "systolic_bp" in answered else field

    def _reopen(self, state: ConversationState, field: str) -> str:
        """Ask a question again; its saved answer stays until a new one is confirmed."""
        state.pending_profile = HealthProfile()
        state.phase, state.current_field = "asking", field
        names = BOTH_BP if field == "systolic_bp" else [field]
        saved = {
            name: getattr(state.confirmed_profile, name)
            for name in names
            if getattr(state.confirmed_profile, name) is not None
        }
        label = self._label(field)
        if saved:
            return (
                f"Okay, let's go back to your {label}. Right now I have {describe(saved)}. "
                + QUESTIONS[field]
                + ' If that was right, say "keep it".'
            )
        if field in state.skipped_fields:
            return (
                f"Okay, let's go back to your {label}. You skipped it before. " + QUESTIONS[field]
            )
        return f"Okay, let's do your {label}. " + QUESTIONS[field]

    def _help(self, state: ConversationState) -> str:
        if state.phase == "confirming":
            pending = state.pending_profile.model_dump(exclude_none=True)
            return (
                "I'm checking that I heard you right before I save anything. I heard "
                + describe(pending)
                + '. If that\'s right, say "yes". If not, say "no" and then the right answer.'
            )
        if state.phase == "ready":
            return (
                "We're all done. To change an answer, say what to change, like \"change my "
                'weight". To clear everything and begin again, say "start over".'
            )
        return HELP[state.current_field] + " " + SKIP_NOTE

    @staticmethod
    def _skip(state: ConversationState, field: str) -> None:
        # The blood pressure question is one reading: skipping it skips both numbers.
        fields = BOTH_BP if field == "systolic_bp" else [field]
        for name in fields:
            if name not in state.skipped_fields and getattr(state.confirmed_profile, name) is None:
                state.skipped_fields.append(name)

    @staticmethod
    def _bp_ordered(state: ConversationState, pending: dict) -> bool:
        systolic = pending.get("systolic_bp", state.confirmed_profile.systolic_bp)
        diastolic = pending.get("diastolic_bp", state.confirmed_profile.diastolic_bp)
        return systolic is None or diastolic is None or systolic > diastolic

    @staticmethod
    def _advance(state: ConversationState) -> None:
        state.current_field = next(
            (
                field
                for field in FIELDS
                if getattr(state.confirmed_profile, field) is None
                and field not in state.skipped_fields
            ),
            None,
        )
        state.phase = "asking" if state.current_field else "ready"

    @staticmethod
    def _prompt(state: ConversationState, about: set[str] | None = None) -> str:
        if state.phase == "confirming":
            pending = state.pending_profile.model_dump(exclude_none=True)
            return (
                "Here is what I heard. "
                + describe(pending, about or set())
                + ". Is that right? Say yes, or tell me the right answer."
            )
        if state.phase == "ready":
            return (
                "All done! I saved the answers you confirmed and left skipped ones blank. "
                "Tap Continue to see your forecast. You can still change any answer."
            )
        return QUESTIONS[state.current_field]

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_conversation_transition", "message": message}
        )
