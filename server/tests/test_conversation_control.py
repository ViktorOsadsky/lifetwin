"""What older adults say around answers: control requests, read-back replies, fillers.

The mini-dialogues in data/conversation_dialogues.json run through the keyless
guided service exactly as phone replies would. Each turn states the phase,
question, pending/confirmed values and the kind of prompt that must follow.
"""

import asyncio
import json
import math
from datetime import date
from pathlib import Path

import pytest

from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.intents import clean_reply, control_intent, read_back_reply
from lifetwin.onboarding.models import ConversationState, TurnRequest, TurnResponse
from lifetwin.onboarding.parsing import QUESTIONS, normalize_text
from lifetwin.onboarding.service import (
    DONE_LEAD,
    LOUDER_LEAD,
    NO_LEAD,
    PRIVATE_NOTE,
    QUESTION_BACK_LEAD,
    REPEAT_LEAD,
    RESTART_QUESTION,
    SKIPPED,
    SLOWER_LEAD,
    UNSURE_LEAD,
    WHY_NOTE,
)

TODAY = date(2026, 10, 24)
DIALOGUES = json.loads((Path(__file__).parent / "data" / "conversation_dialogues.json").read_text())
# Replies about the conversation itself never change anything but the prompt.
UNCHANGED_KINDS = {
    "repeat",
    "slower",
    "louder",
    "help",
    "why",
    "private",
    "question_back",
    "restart_question",
    "done",
    "done_thanks",
}


def kind_of(result: TurnResponse) -> str:
    message, state = result.message, result.state
    leads = [
        ("Okay, let's start over.", "restarted"),
        ("Okay, I kept your answer.", "kept_answer"),
        ("We're just getting started", "nothing_to_clear"),
        ("This is the first question", "first_question"),
        ("Okay, let's go back to your", "reopen"),
        ("Okay, let's do your", "reopen"),
        ("I haven't saved your", "reopen"),
        (REPEAT_LEAD, "repeat"),
        (SLOWER_LEAD, "slower"),
        (LOUDER_LEAD, "louder"),
        ("I'm asking", "help"),
        ("I'm checking", "help"),
        ("We're all done.", "help"),
        (WHY_NOTE, "why"),
        (PRIVATE_NOTE, "private"),
        (QUESTION_BACK_LEAD, "question_back"),
        (UNSURE_LEAD, "is_that_a_yes"),
        (NO_LEAD, "no"),
        ("Got it.", "confirmed"),
        (SKIPPED, "skipped"),
    ]
    if message.startswith(RESTART_QUESTION):
        return "restart_question"
    if message == DONE_LEAD:
        return "done"
    if message == "You're welcome! " + DONE_LEAD:
        return "done_thanks"
    for lead, kind in leads:
        if message.startswith(lead):
            return kind
    if state.phase == "confirming" and (
        (message.startswith("I heard ") and message.endswith("Is that right?"))
        or (" that makes you " in message and message.endswith(" right?"))
    ):
        return "read_back"
    if state.phase == "asking" and message == QUESTIONS[state.current_field]:
        return "question"
    return "clarify"


def build_state(start: dict) -> ConversationState:
    pending = start.get("pending", {})
    field = start.get("field")
    if field is None and start["phase"] == "confirming" and len(pending) == 1:
        field = next(iter(pending))
    return ConversationState(
        phase=start["phase"],
        current_field=field,
        confirmed_profile=start.get("confirmed", {}),
        pending_profile=pending,
        skipped_fields=start.get("skipped", []),
    )


def same(got: dict, expected: dict) -> bool:
    if got.keys() != expected.keys():
        return False
    for key, value in expected.items():
        if isinstance(value, bool | str) or isinstance(got[key], bool | str):
            if type(got[key]) is not type(value) or got[key] != value:
                return False
        elif not math.isclose(got[key], value, rel_tol=0.001, abs_tol=0.01):
            return False
    return True


def check_turn(before: ConversationState, step: dict, result: TurnResponse) -> list[str]:
    state = result.state
    problems = []
    kind = kind_of(result)
    if kind != step["kind"]:
        problems.append(f"kind {kind!r} != {step['kind']!r}")
    if "phase" in step and state.phase != step["phase"]:
        problems.append(f"phase {state.phase!r} != {step['phase']!r}")
    if "field" in step and state.current_field != step["field"]:
        problems.append(f"field {state.current_field!r} != {step['field']!r}")
    for key, attr in (("pending", "pending_profile"), ("confirmed", "confirmed_profile")):
        if key in step:
            got = getattr(state, attr).model_dump(exclude_none=True)
            if not same(got, step[key]):
                problems.append(f"{key} {got} != {step[key]}")
    if "skipped" in step and state.skipped_fields != step["skipped"]:
        problems.append(f"skipped {state.skipped_fields} != {step['skipped']}")
    if result.speech_hint != step.get("hint"):
        problems.append(f"hint {result.speech_hint!r} != {step.get('hint')!r}")
    if kind in UNCHANGED_KINDS:
        if state != before:
            problems.append("a control reply changed the state")
        prompt = ConversationService._prompt(before)
        if kind not in {"help", "done", "done_thanks"} and not result.message.endswith(prompt):
            problems.append("the current prompt was not repeated")
    return problems


@pytest.mark.parametrize("dialogue", DIALOGUES, ids=[d["id"] for d in DIALOGUES])
def test_mini_dialogue(dialogue):
    service = ConversationService(None, clock=lambda: TODAY)
    state = build_state(dialogue["start"])
    for number, step in enumerate(dialogue["turns"], 1):
        request = TurnRequest(action="reply", state=state, text=step["say"])
        result = asyncio.run(service.turn(request))
        problems = check_turn(state, step, result)
        assert not problems, f"turn {number} {step['say']!r}: {problems}\n{result.message}"
        state = result.state


def test_corpus_size_and_coverage():
    kinds = {step["kind"] for d in DIALOGUES for step in d["turns"]}
    assert len(DIALOGUES) >= 150
    assert {
        "repeat",
        "slower",
        "louder",
        "help",
        "why",
        "private",
        "reopen",
        "restart_question",
        "restarted",
        "done",
        "done_thanks",
        "confirmed",
        "no",
        "is_that_a_yes",
        "question_back",
        "read_back",
    } <= kinds


# --- Unit level: the same rules, phrase by phrase -----------------------------------


def clean(text: str) -> str:
    return clean_reply(normalize_text(text))


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("um, I'm I'm 72.", "I'm 72"),
        ("uh im im 72.", "i'm 72"),
        ("I I'm 72", "I'm 72"),
        ("it it's about 7 hours", "it's about 7 hours"),
        ("Well, let me think... about 7 hours.", "about 7 hours"),
        ("okay so I weigh 150 pounds", "I weigh 150 pounds"),
        ("so, 81", "81"),
        ("hold on, um, 150 minutes", "150 minutes"),
        ("Seventy two.", "Seventy two"),
        ("120/80.", "120/80"),
        ("5'10\".", "5'10\""),
        ("5 ft. 7 in.", "5 ft. 7 in"),
        ("6.5 hours", "6.5 hours"),
        ("yes dear", "yes"),
        ("72, thank you", "72"),
        ("what?", "what?"),
    ],
)
def test_clean_reply_removes_noise(text, expected):
    assert clean(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "uh huh",
        "uh uh",
        "mm hmm",
        "five five",
        "sixty sixty",
        "I sleep well, 8 hours",
        "oh man",
        "no no",
        "not so much",
        "hmm",
        "um",
    ],
)
def test_clean_reply_keeps_meaningful_words(text):
    cleaned = clean(text)
    if text in {"no no"}:
        assert cleaned == "no"
    else:
        assert cleaned == text


@pytest.mark.parametrize(
    ("text", "kind"),
    [
        ("what", "repeat"),
        ("What?", "repeat"),
        ("huh", "repeat"),
        ("eh?", "repeat"),
        ("say that again", "repeat"),
        ("say it again please", "repeat"),
        ("sorry I didn't catch that", "repeat"),
        ("sorry i didnt catch that", "repeat"),
        ("pardon", "repeat"),
        ("pardon me?", "repeat"),
        ("come again", "repeat"),
        ("can you repeat the question", "repeat"),
        ("could you repeat that", "repeat"),
        ("would you say that again", "repeat"),
        ("what was that", "repeat"),
        ("what did you say", "repeat"),
        ("I didn't hear you", "repeat"),
        ("once more", "repeat"),
        ("sorry, what?", "repeat"),
        ("huh what", "repeat"),
        ("slow down", "slower"),
        ("slower please", "slower"),
        ("you're going too fast", "slower"),
        ("not so fast", "slower"),
        ("can you speak more slowly", "slower"),
        ("I can't hear you", "louder"),
        ("i cant hear you", "louder"),
        ("speak up", "louder"),
        ("louder please", "louder"),
        ("a bit louder", "louder"),
        ("you're too quiet", "louder"),
        ("what? I can't hear you", "louder"),
        ("help", "help"),
        ("I don't understand", "help"),
        ("i dont understand the question", "help"),
        ("what do you mean", "help"),
        ("what does that mean?", "help"),
        ("I'm confused", "help"),
        ("I don't know what you mean", "help"),
        ("explain please", "help"),
        ("why do you need this", "why"),
        ("why do you need to know", "why"),
        ("why are you asking me that", "why"),
        ("what's that for", "why"),
        ("why", "why"),
        ("is this private", "private"),
        ("is this private?", "private"),
        ("is my information safe", "private"),
        ("who will see this", "private"),
        ("are you recording", "private"),
        ("start over", "restart"),
        ("let's start over", "restart"),
        ("can we start again", "restart"),
        ("start from the beginning", "restart"),
        ("I want to start over", "restart"),
        ("reset", "restart"),
        ("yes start over", "restart_confirmed"),
        ("Yes, start over please.", "restart_confirmed"),
        ("start over, yes", "restart_confirmed"),
        ("clear everything and start over", "restart_confirmed"),
        ("yes clear my answers and start again", "restart_confirmed"),
        ("yeah let's start over", "restart_confirmed"),
        ("go back", "back"),
        ("can we go back", "back"),
        ("back", "back"),
        ("I made a mistake", "back"),
        ("I made a mistake on the last one", "back"),
        ("the last one was wrong", "back"),
        ("previous question", "back"),
        ("can I skip this", "skip"),
        ("could we skip that one", "skip"),
        ("is 72 old?", "ask"),
        ("is 72 old", "ask"),
        ("what's a normal blood pressure, 120?", "ask"),
        ("whats a normal blood pressure 120 over 80", "ask"),
        ("how many hours should I sleep", "ask"),
        ("I'm 72, is that old?", "ask"),
        ("am I too old for this", "ask"),
        ("can you tell me if 72 is old", "ask"),
    ],
)
def test_control_intents(text, kind):
    intent = control_intent(clean(text))
    assert intent is not None and intent.kind == kind


@pytest.mark.parametrize(
    ("text", "field", "rest"),
    [
        ("change my age", "age", None),
        ("I want to change my weight", "weight_kg", None),
        ("can I fix my height", "height_cm", None),
        ("my age is wrong", "age", None),
        ("you got my weight wrong", "weight_kg", None),
        ("go back to the sleep question", "sleep_hours", None),
        ("I made a mistake on my smoking", "smoking_status", None),
        ("change my blood pressure", "systolic_bp", None),
        ("let me change my drinking", "alcohol_drinks_weekly", None),
        ("change my age to 47", "age", "47"),
        ("my weight is wrong, it's 150 pounds", "weight_kg", "it's 150 pounds"),
        ("change my sleep to 6.5 hours", "sleep_hours", "6.5 hours"),
        ("i made a mistake on my age, im 47", "age", "i'm 47"),
    ],
)
def test_named_go_back(text, field, rest):
    intent = control_intent(clean(text))
    assert intent is not None
    assert (intent.kind, intent.field, intent.rest) == ("back", field, rest)


@pytest.mark.parametrize(
    "text",
    [
        "72",
        "I'm 72",
        "seventy two",
        "female",
        "no",
        "yes",
        "never",
        "none",
        "skip",
        "I don't know",
        "can't remember",
        "not sure",
        "about 7 hours",
        "5 foot 10",
        "120 over 80",
        "my age is 72",
        "I walk 30 minutes 5 days a week",
        "I quit smoking years ago",
        "what I weigh is 160 pounds",
        "how about 7 hours",
        "who knows",
        "when I was 40 I weighed more",
        "my back hurts",
        "I'm not sure what to say about that, maybe 3 drinks",
        "I sleep well",
    ],
)
def test_answers_are_never_control_intents(text):
    assert control_intent(clean(text)) is None


@pytest.mark.parametrize(
    "text",
    [
        "yes",
        "Yes.",
        "yeah",
        "yep",
        "yup",
        "uh huh",
        "Uh-huh",
        "mhm",
        "mm hmm",
        "that's it",
        "thats it",
        "you got it",
        "correct dear",
        "yes that's right",
        "yes, that's right",
        "sure is",
        "absolutely",
        "spot on",
        "right",
        "exactly",
        "of course",
        "that's correct",
        "yes it is",
        "yes indeed",
        "yeah yeah",
        "um yes",
        "okay yes",
        "yes thank you",
        "definitely",
        "you're right",
    ],
)
def test_read_back_yes(text):
    assert read_back_reply(clean(text)) == ("yes", "")


@pytest.mark.parametrize(
    "text",
    [
        "no",
        "No.",
        "nope",
        "nah",
        "uh uh",
        "not quite",
        "not exactly",
        "that's wrong",
        "thats wrong",
        "no that's not right",
        "No, that's not right.",
        "that isn't right",
        "wrong",
        "incorrect",
        "no no",
        "no it's not",
        "you got it wrong",
        "not at all",
        "no dear",
        "that's not it",
    ],
)
def test_read_back_no(text):
    assert read_back_reply(clean(text)) == ("no", "")


@pytest.mark.parametrize(
    ("text", "rest"),
    [
        ("no, 47", "47"),
        ("no 47", "47"),
        ("No I'm 47", "I'm 47"),
        ("no im 47", "i'm 47"),
        ("close, it's 47", "47"),
        ("nope, forty seven", "forty seven"),
        ("not quite, 47", "47"),
        ("no no, it's 47", "47"),
        ("wrong, I said 47", "47"),
        ("actually it's 47", "47"),
        ("no, it should be 47", "47"),
        ("that's wrong, it's 47", "47"),
    ],
)
def test_read_back_correction(text, rest):
    assert read_back_reply(clean(text)) == ("correction", rest)


@pytest.mark.parametrize(
    "text",
    [
        "I guess",
        "I guess so",
        "maybe",
        "I think so?",
        "I think so",
        "probably",
        "ok",
        "okay",
        "hmm",
        "yes?",
        "right?",
        "kind of",
        "sounds about right",
        "no, that's right",
        "No, it's correct",
        "yeah no",
        "yes but 6 ft",
        "yes and no",
        "if you say so",
    ],
)
def test_read_back_unsure(text):
    assert read_back_reply(clean(text))[0] == "unsure"


def test_not_46_47_is_left_to_the_value_reader():
    assert read_back_reply(clean("not 46, 47")) == ("other", "not 46, 47")


# --- Service details ----------------------------------------------------------------


def reply(state: ConversationState, text: str, service=None) -> TurnResponse:
    service = service or ConversationService(None, clock=lambda: TODAY)
    return asyncio.run(service.turn(TurnRequest(action="reply", state=state, text=text)))


def test_no_never_confirms_a_read_back():
    pending = ConversationState(
        phase="confirming", current_field="age", pending_profile={"age": 46}
    )
    for text in ["no", "nope", "no yes", "yes no", "not yes", "no that's right", "yes, not 46"]:
        result = reply(pending, text)
        assert result.state.confirmed_profile.age is None, text


def test_speech_hint_is_only_set_on_request():
    asking = ConversationState(phase="asking", current_field="age")
    assert reply(asking, "72").speech_hint is None
    assert reply(asking, "what?").speech_hint is None
    louder = reply(asking, "speak up")
    assert louder.speech_hint == "louder"
    assert louder.message == LOUDER_LEAD + QUESTIONS["age"]
    assert louder.model_dump()["speech_hint"] == "louder"


def test_help_explains_with_an_example_and_how_to_skip():
    for field in QUESTIONS:
        message = reply(ConversationState(phase="asking", current_field=field), "help").message
        assert "For example" in message or '"' in message
        assert 'say "skip"' in message


def test_privacy_answer_is_one_honest_sentence_then_the_question():
    asking = ConversationState(phase="asking", current_field="weight_kg")
    message = reply(asking, "is this private").message
    assert message == PRIVATE_NOTE + " " + QUESTIONS["weight_kg"]
    assert (
        "phone" in PRIVATE_NOTE and "server" in PRIVATE_NOTE and "until you say yes" in PRIVATE_NOTE
    )


def test_privacy_answer_mentions_the_ai_helper_when_one_is_configured():
    class Helper:
        configured = True

        async def extract(self, text, field):  # pragma: no cover - never called
            raise AssertionError("a control reply never reaches the helper")

    service = ConversationService(Helper(), clock=lambda: TODAY)
    asking = ConversationState(phase="asking", current_field="weight_kg")
    message = reply(asking, "why do you need this", service).message
    assert "AI helper reads an answer only if you say it's okay" in message


def test_start_over_holds_nothing_over_to_the_next_turn():
    """The state after "start over" is unchanged, so a bare "yes" can only answer
    the read-back the message ends with."""
    pending = ConversationState(
        phase="confirming", current_field="weight_kg", pending_profile={"weight_kg": 70}
    )
    asked = reply(pending, "start over")
    assert asked.state == pending
    assert asked.message == RESTART_QUESTION + " " + ConversationService._prompt(pending)
    assert asked.message.endswith("Is that right?")
    assert "restart_requested" not in asked.state.model_dump()


@pytest.mark.parametrize("text", ["yes", "yeah", "start over", "ok", "sure"])
def test_only_an_explicit_phrase_clears_answers(text):
    state = ConversationState(
        phase="asking", current_field="sleep_hours", confirmed_profile={"age": 72}
    )
    assert reply(state, text).state.confirmed_profile.age == 72


@pytest.mark.parametrize("text", ["thank you", "ok", "bye", "what now?", "yes", "good"])
def test_done_phase_replies_are_kind_and_stay_ready(text):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from lifetwin.onboarding import router

    app = FastAPI()
    app.include_router(router, prefix="/api")
    state = {
        "phase": "ready",
        "confirmed_profile": {"age": 70},
        "skipped_fields": [field for field in QUESTIONS if field != "age"],
    }
    response = TestClient(app).post(
        "/api/onboarding/turn", json={"action": "reply", "state": state, "text": text}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["state"]["phase"] == "ready" and body["complete"] is True
    assert body["message"].endswith(DONE_LEAD)


def test_skip_button_on_a_reopened_question_keeps_the_saved_answer():
    state = ConversationState(phase="asking", current_field="age", confirmed_profile={"age": 72})
    service = ConversationService(None, clock=lambda: TODAY)
    result = asyncio.run(service.turn(TurnRequest(action="skip", state=state)))
    assert result.state.confirmed_profile.age == 72
    assert "age" not in result.state.skipped_fields
    assert result.state.current_field == "sex"


def test_reopened_question_keeps_its_answer_until_a_new_one_is_confirmed():
    service = ConversationService(None, clock=lambda: TODAY)
    state = ConversationState(
        phase="asking", current_field="sleep_hours", confirmed_profile={"age": 72, "sex": "male"}
    )
    reopened = reply(state, "change my age", service).state
    assert reopened.confirmed_profile.age == 72
    pending = reply(reopened, "73", service).state
    assert pending.confirmed_profile.age == 72
    assert pending.pending_profile.age == 73
    cancelled = reply(pending, "no", service).state
    assert cancelled.confirmed_profile.age == 72


def correct(state: ConversationState, text: str) -> TurnResponse:
    service = ConversationService(None, clock=lambda: TODAY)
    return asyncio.run(service.turn(TurnRequest(action="correct", state=state, text=text)))


@pytest.mark.parametrize(
    ("text", "lead"),
    [
        ("go back", NO_LEAD + "What is the right answer for your age?"),
        ("start over", RESTART_QUESTION),
        ("what?", REPEAT_LEAD),
        ("help", "I'm checking that I heard you right"),
    ],
)
def test_conversation_words_after_no_change_it_are_not_read_as_a_value(text, lead):
    """The app sends the words after "No, change it" as a correction; commands still work."""
    pending = ConversationState(
        phase="confirming", current_field="age", pending_profile={"age": 45}
    )
    result = correct(pending, text)
    assert result.message.startswith(lead)
    assert "couldn't read" not in result.message
    assert result.state.confirmed_profile.age is None
    assert result.state.pending_profile.age == 45


def test_yes_start_over_after_no_change_it_clears_and_a_value_still_corrects():
    pending = ConversationState(
        phase="confirming",
        current_field="sex",
        confirmed_profile={"age": 71},
        pending_profile={"sex": "male"},
    )
    cleared = correct(pending, "yes, start over").state
    assert cleared.confirmed_profile.age is None and cleared.current_field == "age"
    fixed = correct(pending, "female").state
    assert fixed.pending_profile.sex == "female" and fixed.confirmed_profile.sex is None
    changed = correct(pending, "change my sex to female").state
    assert changed.pending_profile.sex == "female" and changed.phase == "confirming"
    kept = correct(pending, "skip")
    assert kept.message.startswith("Nothing has changed.")
