"""Explicit candidate/confirmation transitions for text and final transcripts."""

import asyncio
import logging
import re
from collections.abc import Callable
from datetime import date

from fastapi import HTTPException

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import (
    FIELDS,
    ConversationState,
    MascotEvent,
    TurnRequest,
    TurnResponse,
)
from lifetwin.onboarding.parsing import (
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


# Only these exact replies confirm pending answers; anything vaguer re-asks.
AFFIRMATIVES = {
    "yes",
    "yeah",
    "yep",
    "yes please",
    "correct",
    "yes correct",
    "that's correct",
    "that is correct",
    "yes that's correct",
    "yes that is correct",
    "that's right",
    "that is right",
    "yes that's right",
    "yes that is right",
    "yes it is",
    "yup",
    "yep that's right",
    "yeah that's right",
    "yes that's it",
    "that's it",
    "exactly",
    "absolutely",
    "you got it",
    "yes indeed",
    "uh huh",
    "mm hm",
    "yes sir",
    "yes ma'am",
    "that sounds right",
}
# "yes but 6 ft" both confirms and corrects; it changes nothing and asks again.
# "Yeah, that's right" said to "For example, 5 feet 10 inches" means the example fits.
EXAMPLE_YES = re.compile(
    r"(?:(?:yes|yeah|yea|yep|yup|uh huh|sure|right|correct|exactly)\s*)+"
    r"(?:(?:that's|thats|that is|it's|its)\s+(?:right|correct|me|it|true|about right))?"
    r"|(?:that's|thats|that is|it's|its)\s+(?:right|correct|me|it|true|about right)"
)
MIXED_YES = re.compile(r"(?:yes|yeah|yep|yup|correct)\b.*(?:\d|\b(?:but|no|not|actually)\b)")
NEGATIVE = re.compile(r"(?:no|nope)\b\s*(?:(?:it's|it is|actually|i meant)\b\s*)?(.*)")
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
            parts.append(f"Blood pressure: {value} over {values['diastolic_bp']}")
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
        text = normalize_text(request.text or "")
        today = self.clock()

        def respond(message: str) -> TurnResponse:
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
        if action == "reply" and state.phase == "confirming":
            # A spoken or typed "yes" confirms; "no, ..." corrects; nothing vague confirms.
            phrase = " ".join(text.lower().replace(",", " ").rstrip(".!?").split())
            if phrase in AFFIRMATIVES:
                action = "confirm"
            elif MIXED_YES.match(phrase):
                return respond(
                    "Sorry, I couldn't tell if that was a yes. Nothing has changed. "
                    + self._prompt(state)
                )
            else:
                negative = NEGATIVE.fullmatch(phrase)
                if negative:
                    text = negative.group(1).strip()
                    if not text:
                        pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
                        if len(pending_fields) == 1:
                            field = pending_fields[0]
                            return respond(
                                "Okay, nothing has changed. Please tell me the right answer for "
                                f"your {FRIENDLY_LABELS[field]}, for example {EXAMPLES[field]}."
                            )
                        if pending_fields == BOTH_BP:
                            return respond("Okay, nothing has changed. " + BOTH_BP_MESSAGE)
                        return respond(
                            "Okay, nothing has changed. Which answer should I change? "
                            'Please say its name and the right answer, like "weight: 150 pounds".'
                        )
                action = "correct"
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
                self._invalid("Skipping does not erase confirmed measurements.")
            if target not in state.skipped_fields:
                state.skipped_fields.append(target)
            self._advance(state)
            return respond("That's okay; I won't fill it in. " + self._prompt(state))
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
            if target not in state.skipped_fields:
                state.skipped_fields.append(target)
            self._advance(state)
            return respond("I'll leave that unknown. " + self._prompt(state))
        candidates = _safe(parse_reply, text, target, today=today) or {}
        phrase = " ".join(text.lower().replace(",", " ").rstrip(".!?").split())
        # Only a fresh answer can mean the question's example: "no, that's right" during
        # a read-back is not a yes to "5 feet 10 inches".
        asking = action == "reply" and state.phase == "asking"
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
        candidates = {
            field: value
            for field, value in candidates.items()
            if field not in saved or field == request.field or corrects(text, field)
        }
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
                "Forecasts are not available yet. You can still change any answer."
            )
        return QUESTIONS[state.current_field]

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_conversation_transition", "message": message}
        )
