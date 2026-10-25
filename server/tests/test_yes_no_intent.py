"""Every yes/no moment goes through one interpreter (lifetwin.core.intent).

The matrix runs each reply through the local rules and through the Claude path with a
stubbed provider. Consent questions (memory, outside AI, voice) never reach Claude.
"""

import asyncio
import json
from types import SimpleNamespace

import pytest

from lifetwin.core.claude import ClaudeJSON
from lifetwin.core.intent import (
    ALSO_UPDATE,
    ANYTHING_ELSE,
    HEALTH_OFFER,
    INTENT_PROMPT,
    KEEP_GOING,
    MEMORY,
    MISSING,
    OUTSIDE_AI,
    VOICE,
    ClaudeIntentReader,
    IntentResult,
    ack,
    read_back,
    read_intent,
    read_local,
    validate,
    widen_read_back,
)
from lifetwin.onboarding.models import ConversationState, TurnRequest
from lifetwin.onboarding.script import MEMORY_NO, MEMORY_YES
from lifetwin.onboarding.service import MEMORY_UNCLEAR, ConversationService

QUESTIONS = {
    "memory": MEMORY,
    "outside_ai": OUTSIDE_AI,
    "voice": VOICE,
    "health": HEALTH_OFFER,
    "missing": MISSING,
    "read_back": read_back("Height: 5 feet 10 inches. Is that right?"),
    "anything_else": ANYTHING_ELSE,
    "also_update": ALSO_UPDATE,
    "keep_going": KEEP_GOING,
}

# question | reply | true intent | other intents the rules may give safely (a no or a
# check, never a yes that wasn't one).
MATRIX = """
memory|take all of my data, just take it all|yes|
memory|Take all my data. Just take it all!|yes|
memory|sure why not|yes|
memory|go for it|yes|
memory|I don't mind|yes|
memory|knock yourself out|yes|
memory|fine I guess|yes|
memory|yes|yes|
memory|yeah|yes|
memory|yep|yes|
memory|yup|yes|
memory|sure|yes|
memory|of course|yes|
memory|absolutely|yes|
memory|definitely|yes|
memory|please do|yes|
memory|go ahead|yes|
memory|okay|yes|
memory|ok|yes|
memory|alright|yes|
memory|that's fine|yes|
memory|sounds good|yes|
memory|yes please|yes|
memory|um, uh, yeah sure|yes|
memory|Yes, remember|yes|
memory|remember the little things? sure|yes|
memory|you can remember|yes|
memory|sure, remember everything|yes|
memory|no problem|yes|
memory|no worries|yes|
memory|I wouldn't say no|yes|
memory|can't hurt|yes|
memory|why not|yes|
memory|i dont mind at all|yes|
memory|be my guest|yes|
memory|help yourself|yes|
memory|yes yes yes|yes|
memory|of course!|yes|
memory|hell yeah|yes|
memory|100 percent|yes|
memory|ugh fine|yes|
memory|lol sure|yes|
memory|that would be nice|yes|
memory|i'm okay with that|yes|
memory|works for me|yes|
memory|i'd like that|yes|
memory|yeah go for it, remember whatever|yes|
memory|mhm|yes|
memory|uh huh|yes|
memory|yeah yeah sure|yes|
memory|if you must|yes|
memory|no wait, yes|yes|unsure
memory|no yeah|yes|unsure
memory|rather not|no|
memory|please don't|no|
memory|keep it private|no|
memory|nah|no|
memory|not really|no|
memory|I'd prefer you didn't|no|
memory|no|no|
memory|nope|no|
memory|no thanks|no|
memory|no thank you|no|
memory|i'd rather not|no|
memory|don't remember anything|no|
memory|just the answers|no|
memory|just the answers please|no|
memory|forget it|no|
memory|I'm not comfortable with that|no|
memory|i don't want that|no|
memory|absolutely not|no|
memory|no way|no|
memory|hell no|no|
memory|i'll pass|no|
memory|not now|no|
memory|maybe later|no|
memory|yeah no|no|unsure
memory|yes, actually no|no|unsure
memory|keep that to yourself|no|
memory|I don't think so|no|
memory|nothing extra|no|
memory|please dont|no|
memory|nah I'm good|no|
memory|what does that mean?|unsure|
memory|what are the little things?|unsure|
memory|I'm not sure|unsure|
memory|maybe|unsure|
memory|hmm|unsure|
memory|i don't know|unsure|
memory|like what?|unsure|
memory|why do you need that?|unsure|
memory|who can see it?|unsure|
memory|sure, but what would you keep?|unsure|yes
memory|remember the little things?|unsure|
memory|can you explain|unsure|
memory|let me think about it|unsure|
memory|yeah right, as if|unsure|no
memory|the dog is barking|off_topic|unsure
memory|turn the TV down|off_topic|unsure
outside_ai|sure go ahead|yes|
outside_ai|that's fine|yes|
outside_ai|take whatever you need|yes|
outside_ai|yes the AI helper can read them|yes|
outside_ai|fine by me|yes|
outside_ai|nope|no|
outside_ai|I'd rather you didn't|no|
outside_ai|keep it on my phone|no|unsure
outside_ai|i don't trust ai|no|
outside_ai|no AI please|no|
outside_ai|what's the AI helper?|unsure|
outside_ai|is that safe?|unsure|
outside_ai|who sees my answers?|unsure|
voice|sure, let's talk|yes|
voice|yeah out loud is fine|yes|
voice|of course|yes|
voice|i'll just type|no|
voice|no I'd rather type|no|
voice|not right now|no|
voice|nah|no|
voice|why?|unsure|
health|yes use apple health|yes|
health|sure, fill it in|yes|
health|go for it|yes|
health|yeah that'd be great|yes|
health|please do|yes|
health|knock yourself out|yes|
health|no thanks|no|
health|i'd rather just tell you|no|
health|i don't have an iphone|no|
health|i'm good thanks|no|
health|nah I'll just tell you|no|
health|not now|no|
health|skip|no|
health|what will it read?|unsure|
health|hmm, maybe|unsure|
missing|sure let's do it|yes|
missing|yeah go on|yes|
missing|okay fine|yes|
missing|yes please|yes|
missing|later|no|
missing|not right now|no|
missing|no thanks|no|
missing|another time|no|
missing|how many?|unsure|
missing|i guess?|unsure|yes
read_back|yes|yes|
read_back|that's right|yes|
read_back|spot on|yes|
read_back|you got it|yes|
read_back|correct|yes|
read_back|exactly|yes|
read_back|yep that's it|yes|
read_back|perfect|yes|
read_back|yes sir|yes|
read_back|sounds right|yes|
read_back|no problem|yes|
read_back|yeah you nailed it|yes|
read_back|no|no|
read_back|nope|no|
read_back|that's wrong|no|
read_back|not quite|no|
read_back|no that's not right|no|
read_back|okay|unsure|yes
read_back|i guess so|unsure|yes
read_back|maybe|unsure|
read_back|hmm|unsure|
read_back|no, it's 5'11|correction|
read_back|no it's 180 pounds|correction|
read_back|nope, 6 foot 1|correction|
anything_else|yes|yes|
anything_else|yeah one more thing|yes|
anything_else|no that's it|no|
anything_else|nope that's all|no|
anything_else|i'm done|no|
anything_else|nothing else|no|
anything_else|no thanks|no|
anything_else|that's everything|no|
also_update|sure|yes|
also_update|go for it|yes|
also_update|yes please|yes|
also_update|nah|no|
also_update|not now|no|
also_update|no thanks|no|
keep_going|sure|yes|
keep_going|yeah|yes|
keep_going|no|no|
keep_going|nope|no|
"""
ROWS = [line.split("|") for line in MATRIX.strip().splitlines()]
CASES = [(q, text, truth, set(filter(None, alt.split(",")))) for q, text, truth, alt in ROWS]


def test_matrix_is_big_and_covers_every_question():
    assert len(CASES) >= 150
    assert {q for q, *_ in CASES} == set(QUESTIONS)
    assert {truth for *_, truth, _ in CASES} >= {"yes", "no", "unsure", "correction"}


@pytest.mark.parametrize(("question", "text", "truth", "alternatives"), CASES)
def test_local_reading(question, text, truth, alternatives):
    result = read_local(text, QUESTIONS[question])
    assert result.intent in {truth} | alternatives, (text, result)
    if truth != "yes":
        # Safety: the rules never hear a clear yes that wasn't one.
        assert not result.clear_yes, (text, result)
    if truth == "yes" and not alternatives:
        assert result.clear_yes, (text, result)


def test_local_accuracy():
    right = sum(read_local(t, QUESTIONS[q]).intent == truth for q, t, truth, _ in CASES)
    accuracy = right / len(CASES)
    print(f"local intent accuracy {right}/{len(CASES)} = {accuracy:.1%}")
    assert accuracy >= 0.95


# -- Claude with a stubbed provider -----------------------------------------------------


def message(text: str, stop_reason: str = "end_turn"):
    return SimpleNamespace(
        stop_reason=stop_reason, content=[SimpleNamespace(type="text", text=text)]
    )


class StubClaude:
    """Answers with the matrix's true intent, as a well-behaved Claude would."""

    def __init__(self, answers: dict[str, dict] | None = None, default: dict | None = None):
        self.calls: list[dict] = []
        self.messages = self
        self.answers = answers or {}
        self.default = default

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        reply = json.loads(kwargs["messages"][0]["content"])["reply"]
        answer = self.answers.get(reply, self.default)
        if answer is None:
            raise AssertionError(f"unexpected call for {reply!r}")
        return message(json.dumps(answer))


def reader(stub: StubClaude) -> ClaudeIntentReader:
    return ClaudeIntentReader(ClaudeJSON(api_key="test", client=stub))


def claude_answer(intent: str, tone: str = "neutral", value=None, confidence=0.95) -> dict:
    return {"intent": intent, "confidence": confidence, "tone": tone, "corrected_value": value}


def test_claude_path_matrix():
    stub = StubClaude(
        {
            t: claude_answer(truth, value=t if truth == "correction" else None)
            for q, t, truth, _ in CASES
        }
    )
    right = 0
    for question, text, truth, alternatives in CASES:
        before = len(stub.calls)
        result = asyncio.run(read_intent(text, QUESTIONS[question], reader(stub), allowed=True))
        if QUESTIONS[question].consent:
            assert len(stub.calls) == before, f"consent question sent to Claude: {text!r}"
        right += result.intent == truth
        assert result.intent in {truth} | alternatives, (text, result)
    accuracy = right / len(CASES)
    print(f"claude path accuracy {right}/{len(CASES)} = {accuracy:.1%}, calls {len(stub.calls)}")
    assert accuracy >= 0.97
    # Rules first: Claude is asked only for what they could not settle.
    assert len(stub.calls) < len(CASES) / 4


def test_claude_prompt_has_the_question_and_the_examples():
    stub = StubClaude(default=claude_answer("yes", "joking"))
    question = QUESTIONS["read_back"]
    result = asyncio.run(read_intent("I reckon so", question, reader(stub), allowed=True))
    assert result.intent == "yes" and result.source == "claude" and result.tone == "joking"
    (call,) = stub.calls
    sent = json.loads(call["messages"][0]["content"])
    assert sent["question"] == question.text and sent["reply"] == "I reckon so"
    assert sent["a_yes_means"] and sent["a_no_means"]
    system = call["system"][0]["text"]
    assert system == INTENT_PROMPT
    assert '"take all of my data, just take it all" -> yes, eager' in system
    assert call["output_config"]["format"]["type"] == "json_schema"


def test_no_claude_without_consent_or_when_rules_are_sure():
    stub = StubClaude(default=claude_answer("yes"))
    question = QUESTIONS["read_back"]
    assert asyncio.run(read_intent("I reckon so", question, reader(stub))).source == "rules"
    assert asyncio.run(read_intent("spot on", question, reader(stub), allowed=True)).clear_yes
    assert stub.calls == []


def test_claude_never_turns_a_no_into_a_yes():
    stub = StubClaude(default=claude_answer("yes", "eager"))
    question = QUESTIONS["health"]
    # The rules hear a no, though not a sure one; Claude's yes makes it unsure, never yes.
    result = asyncio.run(
        read_intent("nope I have no clue what you even said", question, reader(stub), allowed=True)
    )
    assert result.intent != "yes"


@pytest.mark.parametrize(
    "content",
    [
        "not json",
        "[]",
        '{"intent": "yes", "confidence": 0.9, "tone": "neutral"}',
        '{"intent": "yes", "confidence": 0.9, "tone": "neutral", "corrected_value": null, "x": 1}',
        '{"intent": "maybe", "confidence": 0.9, "tone": "neutral", "corrected_value": null}',
        '{"intent": "yes", "confidence": 1.5, "tone": "neutral", "corrected_value": null}',
        '{"intent": "yes", "confidence": true, "tone": "neutral", "corrected_value": null}',
        '{"intent": "yes", "confidence": 0.9, "tone": "smug", "corrected_value": null}',
        '{"intent": "correction", "confidence": 0.9, "tone": "neutral", "corrected_value": "6 foot"}',
        '{"intent": "correction", "confidence": 0.9, "tone": "neutral", "corrected_value": null}',
    ],
)
def test_claude_reply_is_validated_strictly(content):
    assert validate(content, "no, it's 5'11") is None


def test_claude_value_must_come_from_the_reply():
    ok = validate(json.dumps(claude_answer("correction", value="5'11")), "no, it's 5'11")
    assert ok is not None and ok.corrected_value == "5'11"
    # A yes keeps its intent but drops a value the person never said.
    yes = validate(json.dumps(claude_answer("yes", value="80 kg")), "yes but I'm 82 now")
    assert yes is not None and yes.intent == "yes" and yes.corrected_value is None


def test_claude_failure_keeps_the_local_reading():
    stub = StubClaude(default=None)

    async def boom(**kwargs):
        raise TimeoutError

    stub.create = boom
    result = asyncio.run(
        read_intent("I reckon so", QUESTIONS["read_back"], reader(stub), allowed=True)
    )
    assert result.source == "rules"


def test_consent_questions_never_reach_claude():
    stub = StubClaude(default=claude_answer("yes"))
    for question in (MEMORY, OUTSIDE_AI, VOICE):
        assert asyncio.run(reader(stub).read("hmm sure but what is it", question)) is None
        result = asyncio.run(read_intent("I reckon so", question, reader(stub), allowed=True))
        assert result.source == "rules" and not result.clear_yes
    assert stub.calls == []


# -- Corrections, tone and silence ------------------------------------------------------


def test_corrections():
    no = read_local("no, it's 5'11", QUESTIONS["read_back"])
    assert no.intent == "correction" and no.corrected_value == "it's 5'11"
    yes = read_local("yes but my weight is 80 now", QUESTIONS["read_back"])
    assert yes.intent == "yes" and yes.corrected_value == "my weight is 80 now"
    other = read_local("yes and I'm 72", MEMORY)
    assert other.intent == "yes" and other.corrected_value == "i'm 72"


def test_tone_changes_words_never_the_answer():
    reluctant = read_local("fine I guess", MEMORY)
    assert reluctant.intent == "yes" and reluctant.tone == "reluctant"
    assert ack(reluctant, MEMORY_YES, MEMORY_NO) == "No problem, you can change this anytime."
    assert read_local("take all of my data, just take it all", MEMORY).tone == "eager"
    assert read_local("knock yourself out", MEMORY).tone == "joking"
    annoyed = read_local("ugh no, I already said no", MEMORY)
    assert annoyed.intent == "no" and annoyed.tone == "annoyed"
    assert ack(annoyed, MEMORY_YES, MEMORY_NO).endswith(MEMORY_NO)
    assert ack(IntentResult(intent="yes", confidence=1), MEMORY_YES, MEMORY_NO) == MEMORY_YES


@pytest.mark.parametrize("text", ["", "   ", "...", None])
def test_silence_is_never_consent(text):
    result = read_local(text, MEMORY)
    assert result.intent == "off_topic" and not result.clear_yes


def test_read_back_widening_keeps_values_and_corrections():
    assert widen_read_back("other", "", "you nailed it") == ("yes", "")
    assert widen_read_back("correction", "problem", "no problem") == ("yes", "")
    # A value or a correction stays with the strict reader.
    assert widen_read_back("correction", "female", "no, female") == ("correction", "female")
    assert widen_read_back("other", "", "never") == ("other", "")
    assert widen_read_back("unsure", "", "okay") == ("unsure", "")
    assert widen_read_back("yes_value", "46", "yes 46") == ("yes_value", "46")


# -- The memory question in onboarding -------------------------------------------------


def service(stub: StubClaude | None = None) -> ConversationService:
    return ConversationService(seed=lambda: 0, intent_reader=reader(stub) if stub else None)


def turn(svc: ConversationService, state: ConversationState, text: str, consent: bool = False):
    return asyncio.run(
        svc.turn(
            TurnRequest(
                action="reply",
                state=state,
                text=text,
                provider_consent=consent,
                outside_ai_consent={"claude": True} if consent else {},
            )
        )
    )


def remembering() -> ConversationState:
    return ConversationState(phase="remembering", seed=0)


@pytest.mark.parametrize("consent", [False, True])
def test_owner_example_on_the_memory_question(consent):
    stub = StubClaude(default=claude_answer("no"))  # would be wrong; must never be asked
    svc = service(stub)
    result = turn(svc, remembering(), "take all of my data, just take it all", consent)
    assert result.state.memory_consent is True
    assert result.state.phase == "asking"
    assert result.message.startswith("Love it, thank you!")
    assert stub.calls == []


@pytest.mark.parametrize("consent", [False, True])
def test_memory_question_is_never_sent_to_claude(consent):
    stub = StubClaude(default=claude_answer("yes", confidence=1.0))
    svc = service(stub)
    for text in ["hmm I reckon", "the dog is barking", "sure, but what would you keep?"]:
        result = turn(svc, remembering(), text, consent)
        assert result.state.memory_consent is None, text
    assert stub.calls == []


def test_reluctant_yes_gets_a_gentle_reply():
    result = turn(service(), remembering(), "fine I guess")
    assert result.state.memory_consent is True
    assert result.message.startswith("No problem, you can change this anytime.")


def test_unsure_asks_one_check_then_never_loops():
    svc = service()
    first = turn(svc, remembering(), "maybe")
    assert first.message == MEMORY.check
    assert first.state.yes_no_checked and first.state.phase == "remembering"
    second = turn(svc, first.state, "hmm, maybe")
    # Still unclear after the one check: nothing is remembered, and the intake goes on.
    assert second.state.memory_consent is False
    assert second.state.phase == "asking"
    assert second.message.startswith(MEMORY_UNCLEAR)
    assert not second.state.yes_no_checked


def test_check_then_a_clear_yes_is_a_yes():
    svc = service()
    first = turn(svc, remembering(), "sure, but what would you keep?")
    assert first.message == MEMORY.check
    second = turn(svc, first.state, "yes, go for it")
    assert second.state.memory_consent is True


def test_off_topic_is_never_consent():
    svc = service()
    first = turn(svc, remembering(), "turn the TV down")
    assert first.state.memory_consent is None and first.state.yes_no_checked
    second = turn(svc, first.state, "kids, quiet please")
    assert second.state.memory_consent is False


# -- Read-backs with Claude --------------------------------------------------------------


def age_read_back(svc: ConversationService) -> ConversationState:
    asked = ConversationState(phase="asking", current_field="age", seed=0, memory_consent=True)
    result = turn(svc, asked, "46")
    assert result.state.phase == "confirming"
    return result.state


def test_read_back_goes_to_claude_only_with_consent():
    stub = StubClaude(default=claude_answer("yes", confidence=0.95))
    svc = service(stub)
    state = age_read_back(svc)
    without = turn(svc, state, "I reckon so")
    assert without.state.phase == "confirming" and stub.calls == []
    saved = turn(svc, state, "I reckon so", consent=True)
    assert saved.state.confirmed_profile.age == 46
    assert len(stub.calls) == 1


def test_read_back_loose_yes_without_claude():
    svc = service()
    saved = turn(svc, age_read_back(svc), "yeah you nailed it")
    assert saved.state.confirmed_profile.age == 46


def test_read_back_unsure_checks_once():
    svc = service()
    state = age_read_back(svc)
    first = turn(svc, state, "maybe")
    assert first.message.startswith("Is that a yes?") and first.state.yes_no_checked
    second = turn(svc, first.state, "maybe")
    # Unclear again: nothing is saved; Mochi asks for the right answer.
    assert second.state.confirmed_profile.age is None
    assert "right answer" in second.message


def test_read_back_correction_still_replaces_the_value():
    svc = service()
    result = turn(svc, age_read_back(svc), "no, it's 47")
    assert result.state.pending_profile.age == 47
