"""Explicit candidate/confirmation transitions for text and final transcripts.

Conversation v2 keeps every v1 rule (read-back before saving, corrections, the chatter
filter, other people's values refused, conversation controls, the emergency line) and
adds: a goal state (the model inputs still missing) that picks the next topic from
what the person just said, "I don't know" recorded as unknown, one simpler question
for some unknowns, Apple Health offered early, up to three habit follow-ups, one turn
of small talk, varied wording, and suggestions when the intake is complete.
"""

import asyncio
import logging
import re
import secrets
from collections.abc import Callable
from datetime import date

from fastapi import HTTPException

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.habits import blood_pressure_reading, merge, read_notes
from lifetwin.onboarding.intents import (
    EMERGENCY_MESSAGE,
    RESUME_LEAD,
    _on_topic,
    asks_back,
    asks_for_ideas,
    clean_reply,
    control_intent,
    dont_know,
    emergency,
    focus,
    hedged_answer,
    keeps_answer,
    read_back_reply,
    resumes,
    unknown_beside_answer,
)
from lifetwin.onboarding.intents import phrase as words_of
from lifetwin.onboarding.model_inputs import INPUTS as MODEL_INPUT_FIELDS
from lifetwin.onboarding.model_inputs import character_hints, model_inputs
from lifetwin.onboarding.models import (
    FIELDS,
    ConversationState,
    HabitNote,
    MascotEvent,
    ProfileField,
    Recommendation,
    TurnRequest,
    TurnResponse,
)
from lifetwin.onboarding.parsing import (
    BP_FIELDS,
    BP_ORDER_MESSAGE,
    EXAMPLES,
    FRIENDLY_LABELS,
    NO_WORDS,
    NOTHING,
    QUESTION_EXAMPLE_VALUES,
    QUESTIONS,
    SELF_AGE,
    SENTENCE_END,
    TOPIC_UNITS,
    TOPICS,
    UNKNOWN_WORDS,
    YES_WORDS,
    _canonical,
    _doubtful,
    _others,
    approximate,
    birth_year_ages,
    clarify,
    corrects,
    grounded_candidates,
    health_either,
    is_filler,
    is_skip,
    normalize_text,
    parse_reply,
    parse_value,
)
from lifetwin.onboarding.probes import BY_ID as PROBES
from lifetwin.onboarding.probes import MAX_PROBES
from lifetwin.onboarding.probes import choose as choose_probe
from lifetwin.onboarding.providers import ExtractionUnavailable, Extractor
from lifetwin.onboarding.script import (
    ACKS,
    ASKED,
    BP_READING,
    BY_FIELD,
    ESTIMATE_NOTE,
    FLIP,
    GREETING,
    HEALTH_DECLINED,
    HEALTH_FIELDS,
    HEALTH_OFFER,
    HEALTH_OFFER_REPLIES,
    HEALTH_OPEN,
    HEALTH_STEP,
    HEALTH_WORDS,
    HOW_ARE_YOU,
    LATER,
    MEMORY_ASK,
    MEMORY_NO,
    MEMORY_REPLIES,
    MEMORY_WHY,
    MEMORY_YES,
    ORDER,
    PROBE_OPTIONAL,
    PROBE_SKIPPED,
    PROBE_THANKS,
    SITTING_SHARES,
    SMALL_TALK,
    STEER_BACK,
    STEER_LEADS,
    STEERS,
    SUPPLEMENT_REPLY,
    UNKNOWN_ACKS,
    UNKNOWN_FIRST,
    pick,
)
from lifetwin.personalize.providers import Personalizer
from lifetwin.personalize.service import consented, phrase_question, phrase_recommendations
from lifetwin.recommendations.service import suggest

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
    "never": "have never smoked",
    "former": "smoked in the past",
    "current": "smoke now",
    "unknown": "are not sure about smoking",
}
HEALTH_RATINGS = {
    "excellent": "excellent",
    "very_good": "very good",
    "good": "good",
    "fair": "fair",
    "poor": "poor",
}


# Lead-ins for replies about the conversation itself; the prompt follows unchanged.
REPEAT_LEAD = "Of course. "
SLOWER_LEAD = "Of course, I'll go slower. "
LOUDER_LEAD = "I'll speak up. "
UNSURE_LEAD = "Is that a yes? "
NO_LEAD = "Okay. "
QUESTION_BACK_LEAD = "That's a good question, but I can't answer it here. "
RESTART_QUESTION = (
    "Do you want to clear your answers and start again? "
    "If so, say yes, start over. Otherwise, just keep going."
)
DONE_LEAD = "All done. Thank you. Tap Continue to see your forecast."
# The fields the estimate needs (the model's eleven inputs; height and weight give BMI), in the
# order they are asked.
ESTIMATE_FIELDS: tuple[ProfileField, ...] = tuple(
    field for field in ASKED if any(field in fields for fields in MODEL_INPUT_FIELDS.values())
)
# End of the intake with estimate answers missing: said once, never a loop.
MISSING_REPLIES = ("Yes", "Not now")
MISSING_LATER = "That's okay. You can answer them any time from Home. "
# Plainer names where two fields share one (both activity questions are "exercise").
ESTIMATE_LABELS = {
    "vigorous_recreation_min_week": "vigorous exercise",
    "moderate_recreation_min_week": "moderate exercise",
    "sedentary_min_day": "sitting time",
}


def _estimate_label(field: str) -> str:
    return ESTIMATE_LABELS.get(field) or FRIENDLY_LABELS[field]


# "Answer N more questions" (ask_only): only the missing answers, then back.
ASK_ONLY_LEAD = "Hi again! "
ASK_ONLY_NOTHING = "You've already answered everything I need. Tap Continue to go back."
ASK_ONLY_UNKNOWN = "That's okay. Your estimate needs this one, so I'll offer it once more later."
ASK_ONLY_DONE = "Thank you, that's all I needed. Tap Continue to see your estimate."
SKIPPED = "No problem. We'll skip that. "
NOT_CAUGHT = "Sorry, I didn't catch that."
# Only a hesitation or the start of a cut-off sentence ("and also", "um so"): nothing was
# answered, so there is nothing to apologise for. Or the reply was only about someone else.
TAKE_YOUR_TIME = "Take your time."
OTHER_PERSON_LEAD = "I only need your own answer, not anyone else's."
CONFIRM_FIRST = "Please answer yes or no to what I just read back first."
WHAT_NOW = re.compile(
    r"(?:so )?(?:what now|now what|what next|what's next|what do i do now|what happens now|"
    r"what happens next|what do i do next|is that it|are we done|am i done|that's it then)"
)
THANKS = re.compile(r"\b(?:thanks|thank you|thank u|ty|cheers|much obliged)\b", re.I)
HOW_ARE_YOU_ASKED = re.compile(
    r"^(?:and |so |well |oh )?(?:how (?:are|r) (?:you|u)|how's it going|how are things|"
    r"how have you been|how about you|and you)(?: (?:doing|today|mochi|yourself|dear))*$"
)
SUPPLEMENTS = re.compile(
    r"\b(?:supplements?|vitamins?|multi ?vitamins?|fish oil|omega ?3s?|turmeric|curcumin|"
    r"melatonin|coq ?10|ginkgo|ginseng|probiotics?|collagen|magnesium|zinc|glucosamine|"
    r"biotin|b ?12|iron (?:pills?|tablets?)|calcium (?:pills?|tablets?)|herbal (?:pills?|remed\w*)|"
    r"creatine|energy (?:drinks?|shots?)|pre[- ]?workout|caffeine (?:pills?|tablets?)|"
    r"protein (?:powders?|shakes?))\b"
)
IDEAS_LEAD = "I have an idea for you today. I'll show it to you now."
REQUEST = re.compile(
    r"^(?:please )?(?:recommend|suggest)\b|\b(?:can|could) you (?:recommend|suggest)\b"
)
ASKING = re.compile(
    r"\?|^(?:should|do|can|could|would|is|are|what|which|how)\b|\b(?:should i|do i need|"
    r"is it (?:good|ok|okay|safe)|what about|recommend|suggest)\b"
)
PRIVATE_NOTE = (
    "Your answers stay on your phone. LifeTwin's server uses them for your forecast "
    "but doesn't keep them. Nothing is saved until you say yes."
)
WHY_NOTE = (
    "I ask so your twin can make your forecast. Your answers stay on your phone, and "
    "LifeTwin's server doesn't keep them. Nothing is saved until you say yes."
)
HELPER_NOTE = "The AI helper reads an answer only if you say it's okay."
SKIP_NOTE = 'If you\'d rather not answer, just say "skip".'
HELP: dict[str, str] = {question.field: question.help for question in BY_FIELD.values()}
# Replies that end a habit follow-up without a note.
MOVE_ON = re.compile(
    r"(?:(?:let's|lets|can we|could we) )?(?:just )?(?:move on|keep going|go on|carry on|skip(?: it| that)?)"
    r"|next(?: question)?|pass|no|nope|nah|no thanks|not really|nothing|none|"
    r"(?:i'd|i would) (?:rather|prefer) not(?: say| talk about it| answer)?|rather not(?: say)?|"
    r"prefer not to (?:say|answer)|i don't want to (?:say|talk about it)|never mind"
)
YES_REPLY = re.compile(
    r"^(?:yes|yeah|yep|yup|yea|ya|aye|sure|certainly|definitely|absolutely|of course|ok|okay|please|why not|go ahead|let's do it|that would be (?:great|nice|lovely)|"
    r"that'd be (?:great|nice|lovely)|sounds good|use (?:it|apple health|the health app))"
    r"(?:[\s,!.]+(?:please|thanks|thank you|use (?:it|apple health|the health app)|"
    r"that would be (?:great|nice|lovely)|let's do it|sure))*$"
)
MEMORY_YES_REPLY = re.compile(
    r"^(?:yes|yeah|sure|of course|okay|ok|please do|go ahead|that's fine|that's okay|"
    r"that would be nice|that'd be nice|sounds good|fine|alright|all right|i don't mind|"
    r"i don't mind at all)(?:[\s,!.]+(?:please|thanks|thank you|remember|you can|go ahead|"
    r"that's fine|sure|of course|please do))*$|^(?:yes |sure |please )?remember(?: it| them| that)?(?: please)?$|^yes remember$"
)
MEMORY_NO_REPLY = re.compile(
    r"^(?:no|nope|nah|no thanks|no thank you|i'd rather not|i would rather not|rather not|"
    r"please don't|don't|i don't want (?:that|you to)|not really|better not|no no|"
    r"just the answers|only my answers|no just the answers)(?:[\s,!.]+(?:thanks|thank you|please|"
    r"just the answers|don't remember|please don't|i'd rather not))*$|^(?:please )?don't remember(?: anything| it| that)?$"
)
NO_REPLY = re.compile(
    r"^(?:no|nope|nah|no thanks|no thank you|not now|not today|maybe later|later|skip|"
    r"skip it|i'd rather not|rather not|i'd rather just answer|just ask me|i don't use it|"
    r"i don't have (?:it|an iphone|apple health|that)|i don't have an apple watch|"
    r"i don't know how|i don't use apple health)(?:[\s,!.]+(?:thanks|thank you|please|"
    r"just ask me|i'd rather just answer|i'll just tell you))*$"
)
# A decline of Apple Health in natural words (searched in the plain reply).
HEALTH_DECLINE = re.compile(
    r"\bi (?:don't|do not|dont) (?:have|use|own|want to use|wanna use|like) "
    r"(?:apple health|the health app|health app|that|it|an apple watch|a watch|a health app)\b"
    r"|\b(?:i'd|i would|id) (?:rather|prefer to|much rather) (?:just )?(?:tell|answer|say|talk)\b"
    r"|\bi (?:prefer|want|would like) to (?:just )?(?:answer|tell|say)\b"
    r"|\b(?:i'll|i will|ill) (?:just )?(?:tell|answer)\b|\blet me (?:just )?(?:tell|answer)\b"
    r"|\b(?:let's|lets|can we|could we) just (?:talk|chat)\b|^just (?:talk|chat)$"
    r"|\bno (?:apple )?(?:watch|health app|apple health|iphone)\b|\bwithout (?:apple health|it)\b"
    r"|\bask me instead\b|\bjust ask me\b|\bnot (?:using|interested in) (?:apple health|it|that)\b"
)
# The lead of a decline, stripped before the rest is read as an answer.
HEALTH_DECLINE_LEAD = re.compile(
    r"^\s*(?:(?:no|nope|nah)\b[\s,.!-]*)?(?:(?:i'd|i would|id) (?:rather|prefer to|much rather) "
    r"(?:just )?(?:tell|answer|say)(?: you| it| myself)?|(?:i'll|i will|ill) (?:just )?tell you|"
    r"let me (?:just )?(?:tell|answer)(?: you)?|i (?:prefer|want|would like) to (?:just )?"
    r"(?:answer|tell)(?: you| it| myself)?|(?:let's|lets) just talk)?[\s,.:;!-]*",
    re.IGNORECASE,
)
# "Yes, and I'm 72": the consent word first, an answer after it.
CONSENT_LEAD = re.compile(
    r"^\W*(?P<word>yes|yeah|yep|sure|of course|okay|ok|please do|go ahead|no|nope|nah)\b"
    r"[\s,.!;:-]*(?:(?:and|but|also|oh and)\b[\s,]*)?(?P<rest>\S.*)$",
    re.IGNORECASE | re.DOTALL,
)
CONSENT_NO_WORDS = {"no", "nope", "nah"}
# A yes to a read-back with another answer after it.
YES_AND = re.compile(
    r"^\W*(?:yes|yeah|yep|yup|that's right|correct|right)\b[\s,.!;:-]*(?:and|also|plus|oh and)\b"
    r"[\s,]*(?P<rest>\S.*)$",
    re.IGNORECASE | re.DOTALL,
)
# Words that mean a reply is about the person's own height, weight, sleep or activity.
PROFILE_WORDS = re.compile(
    r"\b(?:tall|height|weigh|weight|pounds?|lbs?|kilos?|kg|feet|foot|ft|inches|cm|sleep|"
    r"sleeping|slept|hours?|sit|sitting|walk|walking|walks|run|running|jog|swim|swimming|"
    r"exercise|workout|gym|yoga|bike|biking|cycling|active|steps)\b"
)
PROFILE_TALK = re.compile(r"\d|" + PROFILE_WORDS.pattern)


ESTIMATED = {
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "alcohol_drinks_weekly",
    "sedentary_min_day",
    "moderate_recreation_min_week",
    "vigorous_recreation_min_week",
}


def _plain(value: float, digits: int = 1) -> str:
    text = f"{value:.{digits}f}"
    # Only trim zeros after a decimal point: "170" must not become "17".
    return text.rstrip("0").rstrip(".") if "." in text else text


def _about(value: float, shown: str) -> str:
    return "" if abs(value - float(shown)) < 0.01 else "about "


def _count(value: float, unit: str) -> str:
    return "none" if value == 0 else f"{_plain(value)} {unit}{'' if value == 1 else 's'}"


def _duration(minutes: float) -> str:
    """ "90 minutes", "2 hours": the unit people use for that amount."""
    if minutes and minutes % 60 == 0:
        hours = minutes / 60
        return f"{_plain(hours)} hour{'' if hours == 1 else 's'}"
    return _count(minutes, "minute")


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


def _facts(values: dict, about: set[str] = frozenset()) -> list[str]:
    """What was said, one clause per answer ("you are 72"), metric value beside it.

    Fields in ``about`` were estimated (the middle of a range) and say so.
    """
    parts = []
    for field, value in values.items():
        if field == "diastolic_bp" and "systolic_bp" in values:
            continue
        if field == "systolic_bp" and "diastolic_bp" in values:
            about_bp = "about " if field in about else ""  # "maybe like 130 over 85"
            parts.append(f"your blood pressure is {about_bp}{value} over {values['diastolic_bp']}")
            continue
        shown = {
            "age": str,
            "sex": SEX_WORDS.get,
            "height_cm": _height,
            "weight_kg": _weight,
            "sleep_hours": lambda v: f"{_plain(v)} hour{'' if v == 1 else 's'}",
            "exercise_minutes_weekly": lambda v: _count(v, "minute"),
            "smoking_status": SMOKING_WORDS.get,
            "alcohol_drinks_weekly": lambda v: _count(v, "drink"),
            "diabetes": lambda v: "yes" if v else "no",
            "systolic_bp": str,
            "diastolic_bp": str,
            "general_health": HEALTH_RATINGS.get,
            "hypertension_diagnosed": lambda v: "yes" if v else "no",
            "sedentary_min_day": _duration,
            "moderate_recreation_min_week": _duration,
            "vigorous_recreation_min_week": _duration,
        }[field](value)
        if field in about and field in ESTIMATED and not shown.startswith("about "):
            shown = "about " + shown
        parts.append(
            {
                "age": f"you are {shown}",
                "sex": f"you were {shown}",
                "height_cm": f"you are {shown} tall",
                "weight_kg": f"you weigh {shown}",
                "sleep_hours": f"you sleep {shown} a night",
                "exercise_minutes_weekly": (
                    "you don't exercise" if value == 0 else f"you exercise {shown} a week"
                ),
                "smoking_status": f"you {shown}",
                "alcohol_drinks_weekly": (
                    "you don't drink" if value == 0 else f"you have {shown} a week"
                ),
                "diabetes": (
                    "a doctor has told you that you have diabetes"
                    if value
                    else "a doctor has not told you that you have diabetes"
                ),
                "systolic_bp": f"your top blood pressure number is {shown}",
                "diastolic_bp": f"your bottom blood pressure number is {shown}",
                "general_health": f"your health is {shown}",
                "hypertension_diagnosed": (
                    "a doctor has told you that you have high blood pressure"
                    if value
                    else "a doctor has not told you that you have high blood pressure"
                ),
                "sedentary_min_day": f"you sit {shown} a day",
                "moderate_recreation_min_week": (
                    "no lighter activity" if value == 0 else f"{shown} of lighter activity a week"
                ),
                "vigorous_recreation_min_week": (
                    "no harder exercise" if value == 0 else f"{shown} of harder exercise a week"
                ),
            }[field]
        )
    return parts


def heard(values: dict, about: set[str] = frozenset()) -> str:
    """One "I heard ..." sentence for everything being read back."""
    facts = _facts(values, about)
    if len(facts) > 1:
        facts = [", ".join(facts[:-1]) + (", and " if len(facts) > 2 else " and ") + facts[-1]]
    return " ".join(f"I heard {fact}." for fact in facts)


def _same_value(a, b) -> bool:
    """Equal answers, allowing for unit rounding (150 pounds read twice)."""
    if isinstance(a, (bool, str)) or isinstance(b, (bool, str)):
        return a == b
    return abs(float(a) - float(b)) <= max(0.06, 0.01 * abs(float(a)))


def _lower_first(text: str) -> str:
    return text[:1].lower() + text[1:] if text[:2] != "I " else text


def _flip(clause: str) -> str:
    """ "I walk my dog every morning" -> "you walk your dog every morning"."""
    words = re.split(r"([^\w']+)", clause)
    return "".join(FLIP.get(word.lower(), word) for word in words)


class ConversationService:
    def __init__(
        self,
        extractor: Extractor | None = None,
        *,
        timeout_seconds: float = 6,
        clock: Callable[[], date] = date.today,
        seed: Callable[[], int] | None = None,
        personalizer: Personalizer | None = None,
        max_probes: int = MAX_PROBES,
    ):
        self.extractor = extractor
        # The habit follow-ups per onboarding: 1 in the short demo (ONBOARDING_DEMO=1).
        self.max_probes = max(0, min(max_probes, MAX_PROBES))
        # Outside-AI wording (opt-in per provider); never used to read or decide values.
        self.personalizer = personalizer
        self.timeout = max(0.1, min(timeout_seconds, 10.0))
        # Birth dates are read against today; tests inject a fixed day.
        self.clock = clock
        # Each session's wording seed; tests may fix it (0 is the canonical wording).
        self.seed = seed or (lambda: secrets.randbelow(2**31 - 1) + 1)

    async def turn(self, request: TurnRequest) -> TurnResponse:
        response = await self._turn(request)
        if consented(request.outside_ai_consent, self.personalizer) and not response.emergency:
            response = await self._phrase(response)
        return response

    async def _phrase(self, response: TurnResponse) -> TurnResponse:
        """With consent: the provider may phrase the next question or the suggestions."""
        state, update = response.state, {}
        if response.recommendations:
            recs, used = await phrase_recommendations(
                self.personalizer,
                response.recommendations,
                state.confirmed_profile.model_dump(),
                state.habit_notes,
            )
            if used:
                message = response.message.replace(
                    response.recommendations[0].message, recs[0].message
                )
                update = {"recommendations": recs, "message": message}
        elif state.phase == "asking" and state.current_field in BY_FIELD:
            question = self._question(state, state.current_field, plain=True)
            if response.message.endswith(question):
                said = state.steer_lead if state.steer_field == state.current_field else None
                line = await phrase_question(self.personalizer, question, said)
                if line:
                    update = {"message": response.message[: -len(question)] + line}
        if not update:
            return response
        message = update.get("message", response.message)[:1500]
        events = [event.model_copy(update={"caption": message}) for event in response.mascot_events]
        return response.model_copy(
            update={
                **update,
                "message": message,
                "mascot_events": events,
                "phrased_by": self.personalizer.name,
            }
        )

    async def _turn(self, request: TurnRequest) -> TurnResponse:
        state = request.state.model_copy(deep=True)
        mode = "guided"
        configured = self.extractor is not None and self.extractor.configured
        provider_status = "not_needed" if configured else "not_configured"
        action = request.action
        # Fillers, stutters and transcript punctuation go first; meaning stays.
        text = clean_reply(normalize_text(request.text or ""))
        raw_text = text
        today = self.clock()
        # Checked on the whole reply, before chatter is filtered: "I have chest pain.
        # Female." must pause, not answer the question.
        urgent_reply = action in {"reply", "correct"} and emergency(text)
        was_small_talk = state.small_talk
        if not urgent_reply:
            state.small_talk = False
        was_ready = state.phase == "ready"
        # Ink also transcribes other people in the room: only a voice transcript is
        # held to "someone else's number beside yours is asked about".
        voice = request.input_mode == "transcript"
        if (
            action == "correct"
            and request.field is None
            and state.phase == "confirming"
            and getattr(control_intent(text), "kind", "skip") != "skip"
        ):
            # After "No, change it" the app sends the next words as a correction. "Go back",
            # "start over" or "what?" there are about the conversation, not a new value, so
            # they are read exactly as the same words said to the read-back.
            action = "reply"
        heard_for = state.current_field or next(
            iter(state.pending_profile.model_dump(exclude_none=True)), None
        )
        if action == "reply" and heard_for and state.phase in {"asking", "confirming"}:
            # Room chatter around the answer goes before anything else reads it.
            text = focus(
                text,
                heard_for,
                transcript=voice,
                confirming=state.phase == "confirming",
                # Other open questions: "I'm 72, female" keeps "female" for the sex question.
                also=tuple(f for f in ASKED if f != heard_for and state.phase == "asking"),
            )

        def respond(
            message: str,
            hint: str | None = None,
            urgent: bool = False,
            client_action: str | None = None,
        ) -> TurnResponse:
            if state.memory_consent is False:
                state.habit_notes = []  # nothing is kept for storage without consent
            if state.phase != "probing":
                state.current_probe = None
            reaction = {
                "idle": "idle",
                "remembering": "asking",
                "asking": "asking",
                "offering": "asking",
                "probing": "asking",
                "confirming": "confirming",
                "missing": "asking",
                "ready": "celebrating",
                "cancelled": "idle",
            }[state.phase]
            recommendations: list[Recommendation] = []
            if state.phase == "ready" and not was_ready and not urgent and state.ask_only is None:
                notes = state.habit_notes if state.memory_consent is not False else []
                recommendations = _safe(suggest, state.confirmed_profile, notes) or []
                if recommendations and message.endswith(DONE_LEAD):
                    # One idea is spoken; all of them are on the next screen.
                    more = " More ideas are on the next screen." if len(recommendations) > 1 else ""
                    message = (
                        message[: -len(DONE_LEAD)]
                        + "All done, thank you! One idea for you: "
                        + recommendations[0].message
                        + more
                    )
            return TurnResponse(
                state=state,
                message=message[:1500],
                guide_mode=mode,
                provider_status=provider_status,
                complete=state.phase == "ready",
                mascot_events=[
                    MascotEvent(state="concerned" if urgent else reaction, caption=message[:1500])
                ],
                speech_hint=hint,
                emergency=urgent,
                quick_replies=[] if urgent else self._quick_replies(state),
                client_action=client_action,
                model_inputs=model_inputs(
                    state.confirmed_profile,
                    state.unknown_fields,
                    state.skipped_fields,
                    state.estimated_fields,
                ),
                character_hints=character_hints(state.confirmed_profile, state.habit_notes),
                recommendations=recommendations,
            )

        if urgent_reply:
            # Nothing else happens this turn: no value, no next question, no cheer.
            return respond(EMERGENCY_MESSAGE, urgent=True)

        if action == "cancel":
            # Clear drafts and supplied health data from the returned session.
            state = ConversationState(phase="cancelled")
            return respond(
                "We can stop here. Your answers are cleared. Come back whenever you like."
            )
        if action == "start" and state.phase == "idle" and state.ask_only is not None:
            return respond(self._start_ask_only(state))
        if action == "start":
            if state.phase in {"cancelled", "idle"}:
                state = ConversationState(seed=self.seed(), phase="remembering")
            return respond(GREETING + self._prompt(state))
        if state.phase in {"idle", "cancelled"}:
            self._invalid("Please start the conversation first.")
        if action == "reply" and asks_for_ideas(text) and not urgent_reply:
            return respond(IDEAS_LEAD + " " + self._prompt(state), client_action="open_ideas")
        if action in {"reply", "skip"} and state.phase == "remembering":
            intent = control_intent(text) if action == "reply" else None
            # Politeness kept: "please do" is a yes here.
            plain = " ".join(re.sub(r"[^\w'\s]", " ", text.lower()).split())
            if intent and intent.kind in {"why", "private", "help"}:
                return respond(MEMORY_WHY + MEMORY_ASK)
            if intent is None or intent.kind == "skip":
                if (
                    action == "reply"
                    and YES_REPLY.fullmatch(plain)
                    or MEMORY_YES_REPLY.fullmatch(plain)
                ):
                    state.memory_consent = True
                    self._advance(state)
                    return respond(MEMORY_YES + " " + self._prompt(state))
                if (
                    action == "skip"
                    or NO_REPLY.fullmatch(plain)
                    or MEMORY_NO_REPLY.fullmatch(plain)
                ):
                    state.memory_consent = False
                    self._advance(state)
                    return respond(MEMORY_NO + " " + self._prompt(state))
                lead = CONSENT_LEAD.match(text)
                if action == "reply" and lead and self._says_answers(lead.group("rest"), today):
                    # "Yes, and I'm 72": the consent is answered, the rest is an answer.
                    state.memory_consent = lead.group("word").lower() not in CONSENT_NO_WORDS
                    self._advance(state)
                    answered = await self._turn(
                        TurnRequest(
                            action="reply",
                            state=state,
                            text=lead.group("rest"),
                            input_mode=request.input_mode,
                            provider_consent=request.provider_consent,
                        )
                    )
                    note = MEMORY_YES if state.memory_consent else MEMORY_NO
                    return answered.model_copy(update={"message": f"{note} {answered.message}"})
                return respond(NOT_CAUGHT + ' Just say "yes" or "no". ' + MEMORY_ASK)
        if action == "reply" and state.phase == "probing":
            intent = control_intent(text)
            if intent is None or intent.kind in {"skip", "ask"}:
                said = self._probe_reply(state, raw_text)
                if state.phase == "asking" and state.current_field:
                    # "I walk the dog, and I sit about 6 hours": the answer to a later
                    # question is read, recorded and its question skipped.
                    found = _safe(parse_reply, text, state.current_field, today=today) or {}
                    if not found:
                        # "About 20 years. I'm 5'7 by the way": the probe's answer, then
                        # another answer in a sentence of its own.
                        later = self._later_sentence(state, text, today)
                        if later:
                            text, found = later
                    # Only when it names the topic: "about 40 years" is no height or sleep.
                    # A unit counts ("I'm 5'7"); "years" does not.
                    units = _canonical(text)
                    if (
                        PROFILE_WORDS.search(text.lower())
                        or any(
                            f != "age" and re.search(TOPIC_UNITS.get(f, NOTHING), units)
                            for f in found
                        )
                    ) and any(self._open(state, f) for f in found):
                        answered = await self._turn(
                            TurnRequest(
                                action="reply",
                                state=state,
                                text=text,
                                input_mode=request.input_mode,
                                provider_consent=request.provider_consent,
                            )
                        )
                        lead = said.removesuffix(" " + self._prompt(state))
                        return answered.model_copy(update={"message": f"{lead} {answered.message}"})
                return respond(said)
        if action == "skip" and state.phase == "probing":
            return respond(self._end_probe(state, pick(PROBE_SKIPPED, state.seed, "skip")))
        if action == "resume" or (
            action == "reply"
            and resumes(text)
            and not (state.phase == "offering" and YES_REPLY.fullmatch(words_of(text)))
        ):
            # "Continue" after a pause: the same question or read-back again.
            return respond(RESUME_LEAD + self._prompt(state))
        if action in {"reply", "skip"} and state.phase == "missing":
            # Asked once: "yes" asks only the missing answers; anything else ends the intake.
            if action == "reply" and YES_REPLY.fullmatch(words_of(text)):
                missing = self._estimate_missing(state)
                state.ask_only = missing
                state.unknown_fields = [f for f in state.unknown_fields if f not in missing]
                state.skipped_fields = [f for f in state.skipped_fields if f not in missing]
                self._advance(state)
                return respond("Great. " + self._prompt(state))
            state.phase = "ready"
            return respond(MISSING_LATER + DONE_LEAD)
        if action == "reply" and state.phase == "offering":
            intent = control_intent(text)
            if intent and intent.kind in {"repeat", "help", "ask"}:
                # "What?", "huh": the offer is explained or repeated once, never forever.
                if state.health_reasked:
                    return respond(self._decline_health(state))
                state.health_reasked = True
            if intent is None or intent.kind == "skip":
                plain = words_of(text)
                if YES_REPLY.fullmatch(plain):
                    return respond(HEALTH_OPEN, client_action="open_health_import")
                answer = HEALTH_DECLINE_LEAD.sub("", text, count=1).strip()
                sentences = [p for p in re.split(r"(?<=[.!?])\s+", answer) if p.strip()]
                while len(sentences) > 1 and not PROFILE_TALK.search(sentences[0].lower()):
                    sentences.pop(0)  # "I don't have a watch." declines; the rest answers
                answer = " ".join(sentences)
                if answer and PROFILE_TALK.search(answer.lower()):
                    # They would rather tell Mochi (or already are, after "yes" opened the
                    # import): not a yes to Apple Health, so the answer is read as usual.
                    state.health_offered = True
                    self._advance(state)
                    answered = await self._turn(
                        TurnRequest(
                            action="reply",
                            state=state,
                            text=answer,
                            input_mode=request.input_mode,
                            provider_consent=request.provider_consent,
                        )
                    )
                    lead = pick(HEALTH_DECLINED, state.seed, "health")
                    return answered.model_copy(update={"message": f"{lead} {answered.message}"})
                if (
                    (intent and intent.kind == "skip")
                    or NO_REPLY.fullmatch(plain)
                    or HEALTH_DECLINE.search(plain)
                    or state.health_reasked
                ):
                    return respond(self._decline_health(state))
                state.health_reasked = True
                return respond(NOT_CAUGHT + " " + self._prompt(state))
        if action == "skip" and state.phase == "offering":
            return respond(self._decline_health(state))
        read_back = None  # how a reply to a read-back is read, when not left to the reply
        if action == "reply" and state.phase == "ready" and WHAT_NOW.fullmatch(words_of(text)):
            return respond(DONE_LEAD)
        if action == "reply":
            if HOW_ARE_YOU_ASKED.fullmatch(words_of(text)):
                return respond(HOW_ARE_YOU + " " + self._prompt(state))
            if SUPPLEMENTS.search(words_of(text)) and ASKING.search(text.lower()):
                # Mochi never suggests a supplement: one fixed reply, then back.
                return respond(SUPPLEMENT_REPLY + " " + self._prompt(state))
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
                if not (state.skipped_fields or state.unknown_fields) and not any(
                    value is not None for profile in answers.values() for value in profile.values()
                ):
                    return respond(
                        "We're just getting started, so there's nothing to clear. "
                        + self._prompt(state)
                    )
                if kind == "restart_confirmed":
                    kept = {}
                    if state.ask_only is not None:
                        # "Start over" in "Answer N more questions" clears only those answers.
                        kept = {
                            "confirmed_profile": state.confirmed_profile.model_copy(
                                update={field: None for field in state.ask_only}
                            ),
                            "ask_only": state.ask_only,
                            "missing_offered": True,
                            "health_offered": True,
                        }
                    state = ConversationState(
                        seed=state.seed, memory_consent=state.memory_consent, **kept
                    )
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
            if kind == "jump":
                field = self._topic(state, intent.field)
                if state.phase == "confirming" and field in state.pending_profile.model_dump(
                    exclude_none=True
                ):
                    read_back = "no"
                else:
                    note = self._unsaved_note(state)
                    if self._saved(state, field):
                        return respond(note + self._reopen(state, field))
                    state.pending_profile = HealthProfile()
                    state.pending_estimate = None
                    state.current_probe = None
                    state.phase, state.current_field = "asking", field
                    state.proxy_field = None
                    lead = f"Sure, let's talk about your {self._label(field)}. "
                    return respond(note + lead + self._question(state, field))
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
                    note = self._unsaved_note(state)
                    field = field or self._previous(state)
                    if field is None:
                        return respond(
                            "This is the first question, so there's nothing to go back to. "
                            + self._prompt(state)
                        )
                    state.current_probe = None
                    message = note + self._reopen(state, field)
                    if intent.rest:
                        # "Change my age to 47": the new answer is read back as usual.
                        answered = await self._turn(
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
        if action == "reply" and state.phase == "confirming" and read_back is None:
            # Before room chatter is filtered: "correct, and I never smoked" to the sex
            # read-back is not chatter about sex.
            early = YES_AND.match(raw_text) or YES_AND.match(text)
            if early and self._says_answers(early.group("rest"), today):
                # "Yes, and I also sleep 7 hours": the yes confirms, the rest is an answer.
                confirmed = await self._turn(
                    TurnRequest(action="confirm", state=state, input_mode=request.input_mode)
                )
                if confirmed.state.phase in {"asking", "offering"}:
                    return await self._turn(
                        TurnRequest(
                            action="reply",
                            state=confirmed.state,
                            text=early.group("rest"),
                            input_mode=request.input_mode,
                            provider_consent=request.provider_consent,
                        )
                    )
                return confirmed
        if action == "reply" and state.phase == "confirming":
            # Only an unmistakable yes confirms; a no never does, and a correction
            # replaces only the answer being read back.
            heard_, rest = (read_back, "") if read_back else read_back_reply(text)
            if read_back == "correction":
                rest = text
            pending = state.pending_profile.model_dump(exclude_none=True)
            if heard_ == "yes_value":
                # "Yes, 46" to "Age: 46" confirms; "yes, 47" is a question, not a yes.
                asked = "systolic_bp" if list(pending) == BOTH_BP else next(iter(pending))
                said = _safe(parse_reply, rest, asked, today=today) or {}
                heard_ = "yes" if said == pending else "unsure"
            if heard_ == "yes":
                action = "confirm"
            elif heard_ == "unsure":
                return respond(UNSURE_LEAD + self._prompt(state))
            elif heard_ == "no":
                pending_fields = list(pending)
                state.pending_estimate = None
                if len(pending_fields) == 1:
                    field = pending_fields[0]
                    return respond(
                        NO_LEAD + "What is the right answer for "
                        f"your {FRIENDLY_LABELS[field]}? For example, {EXAMPLES[field]}."
                    )
                if pending_fields == BOTH_BP:
                    return respond(NO_LEAD + BOTH_BP_MESSAGE)
                return respond(
                    NO_LEAD + "Which answer should I change? "
                    'Please say its name and the right answer, like "my weight is 150 pounds".'
                )
            else:
                text = rest if heard_ == "correction" else text
                action, from_read_back = "correct", True
        if action == "confirm":
            if state.phase != "confirming":
                self._invalid("There is nothing to confirm right now.")
            additions = state.pending_profile.model_dump(exclude_none=True)
            self._save(state, additions)
            if state.pending_estimate and state.proxy_field in additions:
                field = state.proxy_field
                if field not in state.estimated_fields:
                    state.estimated_fields.append(field)
                if state.memory_consent is not False:
                    topic = {
                        "sedentary_min_day": "sitting",
                        "general_health": "health",
                        "sleep_hours": "sleep",
                    }.get(field, "exercise")
                    estimate = HabitNote(
                        topic=topic, estimate_for=field, estimate=state.pending_estimate
                    )
                    # Estimates are their own notes, beside what the person told Mochi.
                    state.habit_notes = [*state.habit_notes, estimate][-10:]
            state.pending_estimate = None
            state.proxy_field = None
            ack = pick(ACKS, state.seed, "ack", len(self._settled(state)))
            return respond(self._after_answer(state, set(additions), ack))
        if action == "import":
            if state.phase == "confirming":
                self._invalid(CONFIRM_FIRST)
            asked = state.current_field
            additions = request.values.model_dump(exclude_none=True)
            state.health_offered = True
            state.current_probe = None
            self._save(state, additions)
            follow_up = self._after_answer(state, set(additions), "")
            # Stay on the question the person was answering if it is still open,
            # rather than jumping back to an earlier one.
            if asked and self._open(state, asked) and state.phase != "probing":
                state.current_field, state.phase = asked, "asking"
                follow_up = self._prompt(state)
            names = list(dict.fromkeys(self._label(name) for name in additions))
            named = ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else names[0]
            # Asking the same question again without saying why feels like being stuck.
            document = request.import_source == "document"
            missing = (
                ("Your document didn't show" if document else "Apple Health didn't have")
                + f" your {FRIENDLY_LABELS[asked]}, so I still need it. "
                if asked and state.current_field == asked
                else ""
            )
            source = (
                "your document"
                if document
                else "your activity band"
                if request.import_source == "wristband"
                else "Apple Health"
            )
            return respond(
                f"Thank you. I added your {named} from {source}. " + missing + follow_up.strip()
            )
        if action == "skip":
            target = request.field or state.current_field
            if target is None:
                self._invalid("Please pick which question to skip.")
            if state.phase == "confirming":
                self._invalid(CONFIRM_FIRST)
            if getattr(state.confirmed_profile, target) is not None:
                if target == state.current_field and request.field is None:
                    # Skipping a question reopened by "go back" keeps the saved answer.
                    self._advance(state)
                    return respond("Okay, I kept your answer. " + self._prompt(state))
                self._invalid("I can't skip an answer you already confirmed.")
            self._skip(state, target)
            self._advance(state)
            return respond(SKIPPED + self._prompt(state))
        if state.phase == "ready" and action == "reply":
            late = self._late_field(state, raw_text, today)
            if late:
                # "Oh, I do know my weight, it's 160 pounds": read back like any answer.
                asked = state.model_copy(deep=True)
                asked.phase, asked.current_field = "asking", late[0]
                answered = await self._turn(
                    TurnRequest(
                        action="reply",
                        state=asked,
                        text=late[1],
                        input_mode=request.input_mode,
                        provider_consent=request.provider_consent,
                    )
                )
                if answered.state.phase == "confirming":
                    return answered
        if state.phase == "ready" and action == "reply":
            # "Thank you", "ok", "bye", "what now?": a kind word, never an error.
            thanks = "You're welcome! " if THANKS.search(text) else ""
            return respond(thanks + DONE_LEAD)
        if state.phase == "ready" and action != "correct":
            self._invalid("We're all done. You can still change an answer if you like.")
        if state.phase == "confirming" and action != "correct":
            self._invalid(CONFIRM_FIRST)
        if (
            state.phase in {"offering", "probing", "remembering"}
            and action == "correct"
            and not request.field
        ):
            self._invalid("Please pick which answer you want to change.")
        target = request.field or state.current_field
        if action == "correct" and state.phase == "confirming" and request.field is None:
            pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
            if pending_fields == BOTH_BP:
                # A pending reading is corrected as a whole pair, never one guessed half.
                if len(_safe(parse_reply, text, "systolic_bp", today=today) or {}) != 2:
                    return respond(BOTH_BP_MESSAGE)
                pending_fields = ["systolic_bp"]
            if len(pending_fields) != 1:
                # "The age is wrong, I'm 46": the answer it names and gives is replaced.
                named = [
                    field
                    for field in pending_fields
                    if (
                        re.search(TOPICS.get(field, NOTHING), text.lower())
                        or (field == "age" and re.search(SELF_AGE, text.lower()))
                    )
                    and field in (_safe(parse_reply, text, field, today=today) or {})
                ]
                if len(named) == 1:
                    pending_fields = named
            if len(pending_fields) != 1:
                return respond(
                    "I'm waiting on more than one answer: "
                    + ", ".join(FRIENDLY_LABELS[field] for field in pending_fields)
                    + ". Which one do you want to change?"
                )
            target = pending_fields[0]
        if target is None:
            self._invalid("Please pick which answer you want to change.")
        asking = action == "reply" and state.phase == "asking"
        reopened = asking and self._saved(state, target)
        declined = is_skip(text, target) or (
            not asking and words_of(text) in UNKNOWN_WORDS and target != "smoking_status"
        )
        if reopened and (keeps_answer(text) or declined or dont_know(text)):
            # A question reopened by "go back": "keep it" or "skip" leaves the saved answer.
            self._advance(state)
            return respond("Okay, I kept your answer. " + self._prompt(state))
        if declined:
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
                        f"Okay, I removed your {FRIENDLY_LABELS[target]} answer. "
                        "If that was a mistake, just tell me the answer again. "
                        + self._prompt(state)
                    )
                return respond("Nothing has changed. " + self._prompt(state))
            self._skip(state, target)
            self._advance(state)
            return respond(SKIPPED + self._prompt(state))
        hedged = False
        estimate = None
        candidates: dict = {}
        if asking:
            if state.proxy_field == target:
                # The plain words: "okay, I suppose" keeps its "okay" here.
                proxied = self._proxy_answer(state, target, request.text or text)
                if proxied == "unknown":
                    return respond(self._unknown(state, target))
                if proxied == "yes":
                    state.proxy_field = None
                    return respond("Lovely. " + self._question(state, target, plain=True))
                if proxied:
                    candidates, estimate = proxied
            rest = None if candidates else hedged_answer(text)
            if rest:
                found = _safe(parse_reply, rest, target, today=today, strict=voice) or {}
                if found:
                    text, hedged, candidates = rest, True, found
            split = None if candidates else unknown_beside_answer(text)
            if split:
                # "I don't know my weight, but I'm 5'4": the doubt is recorded for the
                # field it names (else the open question) and the fact beside it is kept.
                doubt, rest = split
                found = _safe(parse_reply, rest, target, today=today, strict=voice) or {}
                named = [
                    f for f, cue in TOPICS.items() if f in ASKED and re.search(cue, doubt.lower())
                ] or [target]
                left = [f for f in named if f not in found]
                if found and left and target in {*named, *found}:
                    for name in left:
                        if (
                            name not in state.unknown_fields
                            and getattr(state.confirmed_profile, name) is None
                        ):
                            state.unknown_fields.append(name)
                    state.skipped_fields = [f for f in state.skipped_fields if f not in left]
                    text, candidates = rest, found
            if (
                not candidates
                and dont_know(text)
                and not (_safe(parse_reply, text, target, today=today, strict=voice) or {})
            ):
                if (
                    target in BY_FIELD
                    and BY_FIELD[target].proxy
                    and target not in (state.proxies_asked)
                ):
                    state.proxy_field = target
                    state.proxies_asked.append(target)
                    return respond(self._prompt(state))
                return respond(self._unknown(state, target))
        if asking and not from_read_back and state.memory_consent is not False:
            notes = (
                []
                if _safe(_others, raw_text)
                else (_safe(read_notes, raw_text, asked=target) or [])
            )
            if notes:
                state.habit_notes = merge(state.habit_notes, notes)
        if not candidates:
            candidates = _safe(parse_reply, text, target, today=today, strict=voice) or {}
        if target == "vigorous_recreation_min_week" and asking:
            candidates = self._health_split(state, candidates)
        if target not in BP_FIELDS and candidates.keys() & BP_FIELDS:
            # Onboarding asks for a diagnosis, not numbers: a reading said in passing is
            # kept as context in the habit notes and never saved as a value.
            reading = _safe(blood_pressure_reading, text)
            mine = _safe(_others, raw_text) is False
            if (
                reading
                and mine
                and state.memory_consent is not False
                and target != "hypertension_diagnosed"
            ):
                state.habit_notes = merge(state.habit_notes, [reading])
            candidates = {k: v for k, v in candidates.items() if k not in BP_FIELDS}
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
                    f"Is {likely} right?"
                )
        hint = None if candidates else _safe(clarify, text, target, today=today)
        if not candidates and not hint and target == "general_health":
            hint = _safe(health_either, text)
        if not candidates and asking and target == "hypertension_diagnosed":
            reading = (
                None
                if _safe(_others, raw_text) is not False
                else (_safe(blood_pressure_reading, text))
            )
            if reading:
                said_before = any(note.reading for note in state.habit_notes) or (
                    "hypertension_diagnosed" in state.proxies_asked
                )
                if not said_before:
                    state.proxies_asked.append("hypertension_diagnosed")
                if state.memory_consent is not False:
                    state.habit_notes = merge(state.habit_notes, [reading])
                if said_before:
                    return respond(self._unknown(state, target))
                return respond(
                    BP_READING.format(reading=reading.reading) + _lower_first(QUESTIONS[target])
                )
        if not candidates and asking and not hint:
            candidates = self._elsewhere(state, text, target, today, voice)
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
        heard_all = dict(candidates)
        candidates = {
            field: value
            for field, value in candidates.items()
            if field not in saved
            or field == request.field
            or corrects(text, field)
            or corrects(raw_text, field)
            or (reopened and field in asked)
        }
        # "I sleep 7 hours, I'm 74" with 72 saved: a different value for a saved answer.
        conflicts = (
            {
                field: value
                for field, value in heard_all.items()
                if field not in candidates
                and field in saved
                and field not in BP_FIELDS
                and not _same_value(saved[field], value)
            }
            if asking and not reopened
            else {}
        )
        conflict_lead = ""
        if conflicts and not candidates:
            # Nothing else was said: the new value is read back, and only a yes changes it.
            candidates = conflicts
            conflict_lead = (
                "Earlier you told me "
                + " and ".join(_facts({field: saved[field] for field in conflicts}))
                + ". "
            )
        elif conflicts:
            # Read back the rest; the saved answer stays until the person asks to change it.
            field = next(iter(conflicts))
            conflict_lead = (
                f"You also said {_facts({field: conflicts[field]})[0]}, but earlier you told me "
                f"{_facts({field: saved[field]})[0]}. If that has changed, just say "
                f'"change my {self._label(field)}" after this. '
            )
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
            if (
                asking
                and not hint
                and not was_small_talk
                and provider_status != "consent_required"
                and self._small_talk(raw_text, target)
            ):
                state.small_talk = True
                back = pick(STEER_BACK, state.seed, "back", len(self._settled(state)))
                self._steer(state, raw_text, target, set())
                if state.steer_lead and state.steer_field != target:
                    # "I walk my dog every morning" said to the sitting question: kept for
                    # the activity question, which comes next.
                    later = pick(LATER, state.seed, "later", state.steer_field)
                    question = ConversationService._question(state, target, plain=True)
                    return respond(f"{state.steer_lead} {later} {back}{_lower_first(question)}")
                lead = pick(SMALL_TALK, state.seed, "chat", len(self._settled(state)))
                return respond(f"{lead} {back}{_lower_first(self._prompt(state))}")
            notice = ""
            if provider_status == "consent_required":
                notice = "I couldn't read that. You can let the AI helper try. "
            elif provider_status == "unavailable":
                notice = "The AI helper isn't available right now, but we can keep going. "
            hint = BOTH_BP_MESSAGE if lone_bottom else hint
            lead = hint or ("" if notice and provider_status == "consent_required" else NOT_CAUGHT)
            if asking and not hint and not notice:
                if is_filler(raw_text):
                    lead = TAKE_YOUR_TIME
                elif _safe(_others, raw_text):
                    lead = OTHER_PERSON_LEAD
            ask = (
                self._prompt(state)
                if state.phase == "confirming"
                else self._question(state, target, plain=True)
                if target in BY_FIELD
                else QUESTIONS[target]
            )
            if hint and state.phase != "confirming":
                ask = ""
            return respond(notice + (lead + " " if lead else "") + ask)
        if action == "correct" and request.field and request.field not in candidates:
            return respond(
                "What is the right answer for your "
                + FRIENDLY_LABELS[request.field]
                + "? "
                + QUESTIONS[request.field]
            )
        # Corrections replace affected pending values; unrelated pending values stay visible.
        pending = state.pending_profile.model_dump(exclude_none=True)
        pending.update(candidates)
        if not self._bp_ordered(state, pending):
            return respond(
                BP_ORDER_MESSAGE
                + (" " + self._prompt(state) if state.phase == "confirming" else "")
            )
        too_long = self._over_a_day(state, pending)
        if too_long:
            return respond(too_long)
        if asking:
            self._steer(state, raw_text, target, set(pending))
        state.pending_profile = HealthProfile.model_validate(pending)
        state.phase = "confirming"
        state.current_field = next(iter(pending)) if len(pending) == 1 else None
        state.pending_estimate = estimate
        if birth_note and len(pending) == 1:
            return respond(conflict_lead + birth_note)
        # A middle of a range ("7 or 8 hours") is read back as "about".
        about = set(candidates) if (hedged or estimate or _safe(approximate, text)) else set()
        return respond(conflict_lead + self._prompt(state, about=about))

    # -- answers, unknowns and estimates ---------------------------------------------

    def _save(self, state: ConversationState, additions: dict) -> None:
        merged = state.confirmed_profile.model_dump()
        merged.update(additions)
        state.confirmed_profile = HealthProfile.model_validate(merged)
        state.pending_profile = HealthProfile()
        for name in ("skipped_fields", "unknown_fields", "estimated_fields"):
            setattr(state, name, [f for f in getattr(state, name) if f not in additions])
        if state.steer_field in additions:
            state.steer_field = state.steer_lead = None

    def _after_answer(self, state: ConversationState, just: set[str], ack: str) -> str:
        """The next line after a saved answer: a habit follow-up, or the next topic."""
        probe = (
            None
            if state.memory_consent is False or state.ask_only is not None
            else choose_probe(
                state.confirmed_profile,
                just,
                self._settled(state),
                state.probes_asked,
                state.habit_notes,
                self.max_probes,
            )
        )
        if probe:
            state.phase, state.current_field = "probing", None
            state.current_probe = probe.id
            state.probes_asked.append(probe.id)
            return ack + " " + self._prompt(state)
        self._advance(state)
        return ack + " " + self._prompt(state)

    def _probe_reply(self, state: ConversationState, text: str) -> str:
        probe = PROBES[state.current_probe]
        if MOVE_ON.fullmatch(words_of(text)):
            return self._end_probe(state, pick(PROBE_SKIPPED, state.seed, "skip", probe.id))
        notes = [] if _safe(_others, text) else (_safe(read_notes, text, topic=probe.topic) or [])
        if notes:
            state.habit_notes = merge(state.habit_notes, notes)
        mine = next((note for note in notes if note.topic == probe.topic), None)
        return self._end_probe(state, self._probe_thanks(state, mine))

    def _end_probe(self, state: ConversationState, lead: str) -> str:
        state.current_probe = None
        self._advance(state)
        return lead + " " + self._prompt(state)

    @staticmethod
    def _probe_thanks(state: ConversationState, note: HabitNote | None) -> str:
        """A short, kind echo of their own words; never a value read back."""
        if note is None:
            return pick(PROBE_THANKS, state.seed, "thanks")
        if note.barrier:
            return f"I'm sorry about the {note.barrier}. Thank you for telling me."
        if note.topic == "exercise" and note.kind:
            company = f" with your {note.with_}" if note.with_ and note.with_ != "alone" else ""
            return f"{note.kind[:1].upper()}{note.kind[1:]}{company}, that sounds lovely."
        if note.topic == "smoking" and note.tried_quitting == "yes":
            return "Thank you for sharing that. Trying to quit takes courage."
        if note.topic == "health" and note.feeling in {"worried", "not great", "down", "tired"}:
            return "Thank you for telling me. That's a lot to carry."
        if note.topic == "health" and note.feeling in {"good", "great", "lucky", "grateful"}:
            return "I'm glad to hear it."
        if note.topic == "sitting" and note.kind:
            return f"Got it, mostly {note.kind.replace('tv', 'TV')}."
        return pick(PROBE_THANKS, state.seed, "thanks")

    def _unknown(self, state: ConversationState, field: str) -> str:
        """Recorded as unknown, never asked again this session; the model gives no number."""
        first = not state.unknown_fields
        names = BOTH_BP if field == "systolic_bp" else [field]
        for name in names:
            if name not in state.unknown_fields and getattr(state.confirmed_profile, name) is None:
                state.unknown_fields.append(name)
        state.skipped_fields = [f for f in state.skipped_fields if f not in names]
        state.proxy_field = None
        if state.ask_only is not None:
            # Allowed, and never a loop: the estimate needs it, it is offered once more later
            # (the app's "Answer N more questions"), and the talk moves on or ends.
            self._advance(state)
            return ASK_ONLY_UNKNOWN + " " + self._prompt(state)
        ack = pick(UNKNOWN_ACKS, state.seed, "unknown", field)
        self._advance(state)
        return ack + (UNKNOWN_FIRST if first else "") + " " + self._prompt(state)

    def _start_ask_only(self, state: ConversationState) -> str:
        """ "Answer N more questions": the saved profile is confirmed; only the fields in
        `ask_only` that still have no value are asked, in the usual order."""
        ask = [f for f in ESTIMATE_FIELDS if f in state.ask_only]
        ask += [f for f in state.ask_only if f not in ask]
        state.ask_only = [f for f in ask if getattr(state.confirmed_profile, f) is None]
        for name in ("skipped_fields", "unknown_fields", "proxies_asked"):
            setattr(state, name, [f for f in getattr(state, name) if f not in state.ask_only])
        state.seed = state.seed or self.seed()
        state.missing_offered = state.health_offered = True
        self._advance(state)
        if state.phase == "ready":
            return ASK_ONLY_NOTHING
        n = len(state.ask_only)
        lead = f"I just need {n} more {'answer' if n == 1 else 'answers'} for your estimate. "
        return ASK_ONLY_LEAD + lead + self._prompt(state)

    @staticmethod
    def _estimate_missing(state: ConversationState) -> list[ProfileField]:
        """The estimate's fields with no value, in asking order; none when the age is
        outside what the estimate covers."""
        age = state.confirmed_profile.age
        if age is not None and not 18 <= age <= 85:
            return []
        return [f for f in ESTIMATE_FIELDS if getattr(state.confirmed_profile, f) is None]

    @staticmethod
    def _missing_offer(state: ConversationState) -> str:
        missing = ConversationService._estimate_missing(state)
        n = len(missing)
        names = [_estimate_label(f) for f in missing]
        listed = names[0] if n == 1 else ", ".join(names[:-1]) + " and " + names[-1]
        return (
            f"I still need {n} {'answer' if n == 1 else 'answers'} for your estimate: your "
            f"{listed}. Want to answer {'it' if n == 1 else 'them'} now?"
        )

    @staticmethod
    def _proxy_answer(state: ConversationState, field: str, text: str):
        """The simpler question's answer: (values, what they said) for an estimate,
        "yes" (then ask the real question), "unknown", or None (read it normally)."""
        plain = words_of(text)
        if dont_know(text) or plain in UNKNOWN_WORDS:
            return "unknown"
        # Someone else, doubt or a number: read normally, which asks again if unsure.
        if re.search(r"\d", plain) or _safe(_others, text) is not False:
            return None
        estimate = field in {"sedentary_min_day", "general_health"}
        if estimate and _safe(_doubtful, _canonical(plain)) is not False:
            return None  # an estimate needs a plain answer; "no, not really" is still a no
        if field == "sedentary_min_day":
            if re.search(r"\b(?:not|never)\b|n't\b", plain) and not re.search(
                r"\bnot much\b", plain
            ):
                return None
            sleep = state.confirmed_profile.sleep_hours or 8
            for pattern, share, said in SITTING_SHARES:
                if re.search(pattern, plain):
                    hours = int((24 - min(max(sleep, 4), 12)) * share + 0.5)
                    return {field: hours * 60}, said
            return None
        if field == "general_health":
            for pattern, rating, said in HEALTH_WORDS:
                if re.search(pattern, plain):
                    # "I'm not fine": a negation is only safe in "not so good".
                    if rating != "fair" and re.search(r"\b(?:not|never)\b|n't\b", plain):
                        return None
                    return {field: rating}, said
            return None
        if field in {"moderate_recreation_min_week", "vigorous_recreation_min_week"}:
            no = re.search(NO_WORDS, plain) or re.search(r"\b(?:hardly|rarely|seldom)\b", plain)
            yes = re.search(YES_WORDS, plain) or re.search(r"\b(?:i do|sometimes|a bit)\b", plain)
            if no and not yes:
                return {field: 0}, None
            return "yes" if yes and not no else None
        if field == "sleep_hours":
            values = parse_value("sleep_hours", text)
            return (values, "from bedtime to waking") if values else None
        return None

    @staticmethod
    def _health_split(state: ConversationState, candidates: dict) -> dict:
        """With Apple Health's weekly total, harder exercise leaves the rest as lighter."""
        total = state.confirmed_profile.exercise_minutes_weekly
        vigorous = candidates.get("vigorous_recreation_min_week")
        if (
            total is None
            or vigorous is None
            or vigorous > total
            or state.confirmed_profile.moderate_recreation_min_week is not None
            or "moderate_recreation_min_week" in candidates
        ):
            return candidates
        return {**candidates, "moderate_recreation_min_week": total - vigorous}

    @staticmethod
    def _over_a_day(state: ConversationState, pending: dict) -> str | None:
        sleep = pending.get("sleep_hours", state.confirmed_profile.sleep_hours)
        sitting = pending.get("sedentary_min_day", state.confirmed_profile.sedentary_min_day)
        if sleep is not None and sitting is not None and sleep * 60 + sitting > 1440:
            return (
                "That plus your sleep comes to more than a whole day. About how many hours "
                "are you sitting while you're awake?"
            )
        return None

    @staticmethod
    def _says_answers(text: str, today) -> bool:
        """The reply carries a profile answer (a value, or talk of height, sleep, activity)."""
        if not text:
            return False
        if PROFILE_TALK.search(text.lower()):
            return True
        return any(
            _safe(parse_reply, text, field, today=today)
            for field in ("age", "sex", "smoking_status", "general_health")
        )

    def _later_sentence(self, state: ConversationState, text: str, today):
        """(sentence, values) for a sentence that answers an open question by itself."""
        sentences = [p.strip() for p in re.split(SENTENCE_END, text) if p.strip()]
        if len(sentences) < 2:
            return None
        for sentence in sentences[1:]:
            found = _safe(parse_reply, sentence, state.current_field, today=today) or {}
            if any(self._open(state, f) for f in found):
                return sentence, found
        return None

    @staticmethod
    def _elsewhere(state: ConversationState, text: str, target: str, today, voice: bool) -> dict:
        """A reply that plainly gives a saved answer differently and nothing else ("I'm 74"
        to the sleep question, with 72 saved). It is read back; only a yes changes it."""
        found = {}
        for field in ASKED:
            if field == target or getattr(state.confirmed_profile, field) is None:
                continue
            said = re.search(TOPICS.get(field, NOTHING), text.lower()) or (
                field == "age" and re.search(SELF_AGE, text.lower())
            )
            value = (_safe(parse_reply, text, field, today=today, strict=voice) or {}).get(field)
            if said and value is not None:
                found[field] = value
        return found if len(found) == 1 else {}

    def _late_field(self, state: ConversationState, text: str, today) -> tuple[str, str] | None:
        """(question, words) a reply at the end answers: one still open, or a saved answer
        said differently ("I sleep 9 hours actually"). None for "thanks" or "bye"."""
        if not self._says_answers(text, today):
            return None
        # The whole reply first, then from each clause on ("Thanks! I'd say very good").
        pieces = re.split(r"(?<=[,.!?;])\s+", text)
        for start in range(len(pieces)):
            words = " ".join(pieces[start:])
            for field in ASKED:
                found = _safe(parse_reply, words, field, today=today) or {}
                cue = TOPICS.get(field, NOTHING) + "|" + TOPIC_UNITS.get(field, NOTHING)
                if field == "age":
                    cue += "|" + SELF_AGE
                if field not in found or not re.search(cue, words.lower()):
                    continue
                saved = getattr(state.confirmed_profile, field)
                if saved is None or not _same_value(saved, found[field]):
                    return field, words
        return None

    def _decline_health(self, state: ConversationState) -> str:
        state.health_offered = True
        self._advance(state)
        return pick(HEALTH_DECLINED, state.seed, "health") + " " + self._prompt(state)

    @staticmethod
    def _small_talk(text: str, field: str) -> bool:
        """A friendly aside with nothing for the question: one kind turn, then back."""
        words = words_of(text).split()
        if len(words) < 3 or re.search(r"\d", text) or "?" in text or dont_know(text):
            return False
        return not _on_topic(text, field, False)

    # -- steering ----------------------------------------------------------------

    def _open(self, state: ConversationState, field: str) -> bool:
        return (
            getattr(state.confirmed_profile, field) is None
            and field not in state.skipped_fields
            and field not in state.unknown_fields
            and (state.ask_only is None or field in state.ask_only)
        )

    def _settled(self, state: ConversationState) -> set[str]:
        return {field for field in FIELDS if not self._open(state, field)}

    def _topic(self, state: ConversationState, field: str) -> str:
        """The question a named topic opens: activity goes to the part still open."""
        if field == "moderate_recreation_min_week" and not self._open(state, field):
            if self._open(state, "vigorous_recreation_min_week"):
                return "vigorous_recreation_min_week"
        return field

    def _steer(self, state: ConversationState, text: str, asked: str, answered: set[str]) -> None:
        """Remember a topic the person brought up beside their answer, with their words."""
        for clause in re.split(r"[.!?;,]|\bbut\b|\band\b", text):
            for cue, field in STEERS:
                if not re.search(cue, clause, re.I):
                    continue
                field = self._topic(state, field)
                if field == asked or field in answered or not self._open(state, field):
                    continue
                said = re.sub(
                    r"^\W*(?:and|but|so|though|also|oh)\b\s*", "", clause.strip(), flags=re.I
                )
                said = re.sub(r"\s+(?:though|too|as well|anyway)$", "", said, flags=re.I).strip()
                if not said or len(said) > 120:
                    continue
                lead = pick(STEER_LEADS, state.seed, "steer", field)
                state.steer_field = field
                state.steer_lead = lead.format(said=_flip(said))
                return

    # -- order, prompts and read-backs -------------------------------------------------

    def _advance(self, state: ConversationState) -> None:
        state.current_probe = None
        if state.steer_field and not self._open(state, state.steer_field):
            state.steer_field = state.steer_lead = None
        if state.steer_field:
            state.current_field, state.phase = state.steer_field, "asking"
            return
        for step in ORDER:
            if step == HEALTH_STEP:
                if not state.health_offered and any(
                    self._open(state, field) for field in HEALTH_FIELDS[:3]
                ):
                    state.current_field, state.phase = None, "offering"
                    return
                continue
            if not self._open(state, step):
                continue
            if (
                step == "moderate_recreation_min_week"
                and state.confirmed_profile.exercise_minutes_weekly is not None
                and self._open(state, "vigorous_recreation_min_week")
            ):
                step = "vigorous_recreation_min_week"  # Health's total: ask the harder part first
            state.current_field, state.phase = step, "asking"
            return
        if state.ask_only is None and not state.missing_offered and self._estimate_missing(state):
            # Said once at the end of the intake; "yes" asks only those, "not now" finishes.
            state.missing_offered = True
            state.current_field, state.phase = None, "missing"
            return
        # Finished once: a later change never brings the offer back.
        state.missing_offered = True
        state.current_field, state.phase = None, "ready"

    @staticmethod
    def _question(state: ConversationState, field: str, plain: bool = False) -> str:
        question = BY_FIELD[field]
        if state.proxy_field == field and question.proxy and not plain:
            return question.proxy
        total = state.confirmed_profile.exercise_minutes_weekly
        if (
            question.with_health
            and total is not None
            and state.confirmed_profile.moderate_recreation_min_week is None
        ):
            return question.with_health.format(total=_duration(total))
        text = pick(question.ask, state.seed, "ask", field)
        if state.steer_lead and state.steer_field == field and not plain:
            return f"{state.steer_lead} {text}"
        return text

    @staticmethod
    def _prompt(state: ConversationState, about: set[str] | None = None) -> str:
        if state.phase == "confirming":
            pending = state.pending_profile.model_dump(exclude_none=True)
            note = ESTIMATE_NOTE if state.pending_estimate else ""
            return heard(pending, about or set()) + note + " Is that right?"
        if state.phase == "ready" and state.ask_only is not None:
            left = [f for f in state.ask_only if getattr(state.confirmed_profile, f) is None]
            if not left:
                return ASK_ONLY_DONE
            names = " and ".join(_estimate_label(f) for f in left)
            return f"Thank you. Your estimate still needs your {names}. Tap Continue to go back."
        if state.phase == "ready":
            return DONE_LEAD
        if state.phase == "missing":
            return ConversationService._missing_offer(state)
        if state.phase == "offering":
            return HEALTH_OFFER
        if state.phase == "remembering":
            return MEMORY_ASK
        if state.phase == "probing":
            probe = PROBES[state.current_probe]
            optional = PROBE_OPTIONAL if len(state.probes_asked) <= 1 else ""
            return pick(probe.ask, state.seed, "probe", probe.id) + optional
        if state.current_field in BY_FIELD:
            return ConversationService._question(state, state.current_field)
        return QUESTIONS[state.current_field]

    @staticmethod
    def _quick_replies(state: ConversationState) -> list[str]:
        if state.phase == "confirming":
            return ["Yes", "No"]
        if state.phase == "offering":
            return list(HEALTH_OFFER_REPLIES)
        if state.phase == "missing":
            return list(MISSING_REPLIES)
        if state.phase == "remembering":
            return list(MEMORY_REPLIES)
        if state.phase == "probing":
            return ["Let's move on"]
        if state.phase == "asking" and state.current_field in BY_FIELD:
            question = BY_FIELD[state.current_field]
            if state.proxy_field == state.current_field and question.proxy_replies:
                return list(question.proxy_replies)
            return list(question.quick_replies)
        return []

    def _unsaved_note(self, state: ConversationState) -> str:
        pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
        if state.phase != "confirming" or not pending_fields:
            return ""
        # Unsaved answers are asked again later; saved ones never change here.
        return (
            "I haven't saved your "
            + " and ".join(dict.fromkeys(self._label(name) for name in pending_fields))
            + " answer yet, so I'll ask again later. "
        )

    @staticmethod
    def _saved(state: ConversationState, field: str) -> bool:
        fields = BP_FIELDS if field in BP_FIELDS else {field}
        return any(getattr(state.confirmed_profile, name) is not None for name in fields)

    @staticmethod
    def _label(field: str) -> str:
        return "blood pressure" if field in BP_FIELDS else FRIENDLY_LABELS[field]

    def _previous(self, state: ConversationState) -> str | None:
        """The answered question before this one ("go back"), or the last one when done."""
        steps = [*ASKED, *(f for f in FIELDS if f not in ASKED)]
        answered = [field for field in steps if not self._open(state, field)]
        if state.ask_only is not None:
            answered = [field for field in answered if field in state.ask_only]
        if state.phase == "asking" and state.current_field in steps:
            here = steps.index(state.current_field)
            answered = [f for f in answered if steps.index(f) < here]
        if not answered:
            return None
        field = answered[-1]
        return "systolic_bp" if field == "diastolic_bp" and "systolic_bp" in answered else field

    def _reopen(self, state: ConversationState, field: str) -> str:
        """Ask a question again; its saved answer stays until a new one is confirmed."""
        state.current_probe = None
        state.pending_profile = HealthProfile()
        state.pending_estimate = None
        state.proxy_field = None
        state.phase, state.current_field = "asking", field
        names = BOTH_BP if field == "systolic_bp" else [field]
        saved = {
            name: getattr(state.confirmed_profile, name)
            for name in names
            if getattr(state.confirmed_profile, name) is not None
        }
        label = self._label(field)
        if saved:
            fact = _facts(saved)[0]
            have = fact if fact.startswith("no ") else f"that {fact}"  # "I have no harder exercise"
            return (
                f"Okay, let's go back to your {label}. Right now I have {have}. "
                + QUESTIONS[field]
                + ' If that was right, say "keep it".'
            )
        if field in state.skipped_fields:
            return (
                f"Okay, let's go back to your {label}. You skipped it before. " + QUESTIONS[field]
            )
        if field in state.unknown_fields:
            return (
                f"Okay, let's go back to your {label}. You weren't sure before. " + QUESTIONS[field]
            )
        return f"Okay, let's do your {label}. " + QUESTIONS[field]

    def _help(self, state: ConversationState) -> str:
        if state.phase == "confirming":
            pending = state.pending_profile.model_dump(exclude_none=True)
            return (
                "I'm checking that I heard you right before I save anything. "
                + heard(pending)
                + ' If that\'s right, say "yes". If not, say "no" and then the right answer.'
            )
        if state.phase == "ready":
            return (
                "We're all done. To change an answer, say what to change, like \"change my "
                'weight". To clear everything and begin again, say "start over".'
            )
        if state.phase == "offering":
            return (
                "Apple Health may already know your height, weight, sleep and activity. "
                'Say "yes" to fill them in from it, or "no" and I\'ll ask you.'
            )
        if state.phase == "probing":
            return (
                "I'm just getting to know your habits, so I can make better suggestions. "
                'Tell me in your own words, or say "let\'s move on".'
            )
        return HELP[state.current_field] + " " + SKIP_NOTE

    @staticmethod
    def _skip(state: ConversationState, field: str) -> None:
        # The blood pressure question is one reading: skipping it skips both numbers.
        fields = BOTH_BP if field == "systolic_bp" else [field]
        for name in fields:
            if name not in state.skipped_fields and getattr(state.confirmed_profile, name) is None:
                state.skipped_fields.append(name)
        state.proxy_field = None

    @staticmethod
    def _bp_ordered(state: ConversationState, pending: dict) -> bool:
        systolic = pending.get("systolic_bp", state.confirmed_profile.systolic_bp)
        diastolic = pending.get("diastolic_bp", state.confirmed_profile.diastolic_bp)
        return systolic is None or diastolic is None or systolic > diastolic

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_conversation_transition", "message": message}
        )
