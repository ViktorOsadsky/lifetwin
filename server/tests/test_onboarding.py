"""Behavioral intake tests: confirmation, ambiguity, transitions and providers."""

import asyncio
import json

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding import (
    ChatCompletionsExtractor,
    ConversationService,
    OpenAIExtractor,
    router,
)
from lifetwin.onboarding.models import ConversationState, ExtractionResult, TurnRequest
from lifetwin.onboarding.parsing import QUESTIONS, grounded_candidates, parse_reply, parse_value
from lifetwin.onboarding.providers import ExtractionUnavailable
from lifetwin.onboarding.service import heard


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(router, prefix="/api")
    return TestClient(app)


def turn(client, action, state=None, **values):
    response = client.post(
        "/api/onboarding/turn",
        json={"action": action, **({"state": state} if state else {}), **values},
    )
    assert response.status_code == 200, response.text
    return response.json()


def begin(client):
    """Start, and say yes to Mochi's first question (may it remember the little things)."""
    return turn(client, "reply", turn(client, "start")["state"], text="yes")


def test_first_turn_uses_guided_mascot_instead_of_fake_voice_or_llm(client):
    result = turn(client, "start")
    # v2: Mochi first asks whether it may remember the little things; then the age.
    assert result["state"]["phase"] == "remembering"
    assert begin(client)["state"]["current_field"] == "age"
    assert result["guide_mode"] == "guided"
    assert result["provider_status"] == "not_configured"
    assert result["voice_status"] == "deferred"
    assert result["accepted_input_modes"] == ["text", "transcript"]
    assert result["mascot_events"][0]["caption"] == result["message"]


def test_confirmation_and_correction_keep_candidates_separate(client):
    state = begin(client)["state"]
    result = turn(client, "reply", state, text="35 years old")
    assert result["state"]["confirmed_profile"]["age"] is None
    assert result["state"]["pending_profile"]["age"] == 35
    result = turn(client, "correct", result["state"], text="36")
    assert result["state"]["confirmed_profile"]["age"] is None
    result = turn(client, "confirm", result["state"])
    assert result["state"]["confirmed_profile"]["age"] == 36
    assert result["state"]["pending_profile"]["age"] is None
    assert result["state"]["current_field"] == "sex"


def test_labeled_multi_answer_and_metric_conversion_are_explicit(client):
    result = turn(
        client,
        "reply",
        begin(client)["state"],
        text="age: 40; weight: 154 pounds; height: 1.75 m",
    )
    pending = result["state"]["pending_profile"]
    assert pending["age"] == 40
    assert pending["weight_kg"] == pytest.approx(69.8532)
    assert pending["height_cm"] == 175
    assert result["state"]["confirmed_profile"]["weight_kg"] is None
    confirmed = turn(client, "confirm", result["state"])["state"]["confirmed_profile"]
    assert confirmed["age"] == 40
    assert confirmed["weight_kg"] == pytest.approx(69.8532)


@pytest.mark.parametrize(
    "text", ["70", "about 70", "I lost 5 kg", "-5 kg", "7000 kg", "if I weighed 70 kg"]
)
def test_ambiguous_out_of_range_or_hypothetical_weight_stays_unknown(client, text):
    state = ConversationState(phase="asking", current_field="weight_kg").model_dump()
    result = turn(client, "reply", state, text=text)
    assert result["state"]["phase"] == "asking"
    assert result["state"]["pending_profile"]["weight_kg"] is None
    assert result["state"]["confirmed_profile"]["weight_kg"] is None


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("height_cm", "5 ft 10 in", {"height_cm": 177.8}),
        ("weight_kg", "0 kg", {}),
        ("height_cm", "5 ft 14 in", {}),
        ("age", "35.5", {}),
        ("exercise_minutes_weekly", "2 hours per week", {"exercise_minutes_weekly": 120}),
        ("exercise_minutes_weekly", "30 minutes per day", {"exercise_minutes_weekly": 210}),
        ("alcohol_drinks_weekly", "I don't drink", {"alcohol_drinks_weekly": 0.0}),
        ("smoking_status", "I don't smoke", {}),
        ("smoking_status", "I quit smoking", {"smoking_status": "former"}),
        ("diabetes", "I feel tired", {}),
        ("diabetes", "no", {"diabetes": False}),
        ("systolic_bp", "120/80 mmHg", {"systolic_bp": 120, "diastolic_bp": 80}),
    ],
)
def test_targeted_measurement_parser(field, text, expected):
    assert parse_value(field, text) == expected


def test_transcript_has_identical_confirmation_semantics(client):
    state = begin(client)["state"]
    assert turn(client, "reply", state, text="35", input_mode="text") == turn(
        client, "reply", state, text="35", input_mode="transcript"
    )


def test_skip_unknown_completion_and_ready_correction(client):
    result = begin(client)
    for _ in range(40):
        if result["complete"]:
            break
        # The Apple Health offer is declined; every question is answered "I don't know".
        text = "no thanks" if result["state"]["phase"] == "offering" else "I don't know"
        result = turn(client, "reply", result["state"], text=text)
    assert result["complete"] is True
    assert all(value is None for value in result["state"]["confirmed_profile"].values())
    assert result["state"]["skipped_fields"] == []
    assert result["model_inputs"]["status"] == "still_learning"
    result = turn(client, "correct", result["state"], field="weight_kg", text="70 kg")
    assert result["complete"] is False
    result = turn(client, "confirm", result["state"])
    assert result["state"]["confirmed_profile"]["weight_kg"] == 70
    assert "weight_kg" not in result["state"]["unknown_fields"]
    assert result["complete"] is True


def test_cancel_clears_health_context(client):
    state = ConversationState(
        phase="asking", current_field="sex", confirmed_profile=HealthProfile(age=35)
    ).model_dump()
    result = turn(client, "cancel", state)
    assert result["state"]["phase"] == "cancelled"
    assert result["state"]["confirmed_profile"]["age"] is None
    assert result["state"]["skipped_fields"] == []


def test_bad_transitions_and_oversized_or_inconsistent_inputs_are_rejected(client):
    assert client.post("/api/onboarding/turn", json={"action": "confirm"}).status_code == 409
    assert (
        client.post(
            "/api/onboarding/turn", json={"action": "reply", "text": "x" * 2001}
        ).status_code
        == 422
    )
    assert (
        client.post("/api/onboarding/turn", json={"action": "reply", "text": " "}).status_code
        == 422
    )
    assert (
        client.post(
            "/api/onboarding/turn",
            json={"action": "start", "state": {"pending_profile": {"age": 35}}},
        ).status_code
        == 422
    )
    state = turn(client, "reply", begin(client)["state"], text="35")["state"]
    assert (
        client.post("/api/onboarding/turn", json={"action": "skip", "state": state}).status_code
        == 409
    )


# The keyless parser reads "My current weight is 70 kg" by itself now, so the provider
# path is exercised with a reply it does not read alone: the age is a second number.
# Chatter the keyless parser refuses (someone else is mentioned), so the provider is asked.
# (A leading "Well," is now dropped as filler, after which the parser reads this alone.)
PROVIDER_TEXT = "Funny, my grandson keeps asking, but I weigh 70 kg"


class FakeExtractor:
    configured = True

    def __init__(self, *, quote="70 kg", error=False, field="weight_kg"):
        self.calls = 0
        self.quote = quote
        self.error = error
        self.field = field

    async def extract(self, text, field):
        self.calls += 1
        if self.error:
            raise ExtractionUnavailable()
        return ExtractionResult.model_validate(
            {"candidates": [{"field": self.field, "quote": self.quote}]}
        )


def service_turn(service, **kwargs):
    return asyncio.run(service.turn(TurnRequest.model_validate(kwargs)))


def test_provider_is_consent_gated_and_still_needs_confirmation():
    provider = FakeExtractor()
    service = ConversationService(provider)
    state = {"phase": "asking", "current_field": "weight_kg"}
    result = service_turn(service, action="reply", state=state, text=PROVIDER_TEXT)
    assert result.provider_status == "consent_required"
    assert provider.calls == 0
    result = service_turn(
        service,
        action="reply",
        state=state,
        text=PROVIDER_TEXT,
        provider_consent=True,
    )
    assert provider.calls == 1
    assert result.guide_mode == "llm"
    assert result.state.pending_profile.weight_kg == 70
    assert result.state.confirmed_profile.weight_kg is None


@pytest.mark.parametrize(("quote", "error"), [("90 kg", False), ("70 kg", True)])
def test_provider_failure_or_non_evidence_never_fills_profile(quote, error):
    service = ConversationService(FakeExtractor(quote=quote, error=error))
    result = service_turn(
        service,
        action="reply",
        state={"phase": "asking", "current_field": "weight_kg"},
        text=PROVIDER_TEXT,
        provider_consent=True,
    )
    assert result.provider_status == ("unavailable" if error else "used")
    assert result.guide_mode == "guided"
    assert result.state.pending_profile.weight_kg is None


def test_provider_has_overall_deadline():
    class SlowExtractor(FakeExtractor):
        async def extract(self, text, field):
            await asyncio.sleep(1)

    service = ConversationService(SlowExtractor(), timeout_seconds=0.1)
    result = service_turn(
        service,
        action="reply",
        state={"phase": "asking", "current_field": "weight_kg"},
        text=PROVIDER_TEXT,
        provider_consent=True,
    )
    assert result.provider_status == "unavailable"


def test_openai_adapter_uses_structured_outputs_no_storage_and_validates_completion():
    requests = []

    async def run():
        def handle(request):
            requests.append(json.loads(request.content))
            return httpx.Response(
                200,
                json={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {
                                    "type": "output_text",
                                    "text": '{"candidates":[{"field":"weight_kg","quote":"70 kg"}]}',
                                }
                            ],
                        }
                    ],
                },
            )

        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            provider = OpenAIExtractor(
                api_key="test-only", model="injected-test-model", client=client
            )
            result = await provider.extract("I weigh 70 kg", "weight_kg")
            assert result.candidates[0].quote == "70 kg"

    asyncio.run(run())
    assert requests[0]["store"] is False
    assert requests[0]["text"]["format"]["type"] == "json_schema"
    assert requests[0]["text"]["format"]["strict"] is True
    assert requests[0]["input"] == "I weigh 70 kg"
    assert QUESTIONS["weight_kg"] in requests[0]["instructions"]


@pytest.mark.parametrize(
    "body",
    [
        {"status": "incomplete", "output": []},
        {"status": "completed", "output": [{"content": [{"type": "refusal", "refusal": "No"}]}]},
        {
            "status": "completed",
            "output": [
                {
                    "content": [
                        {
                            "type": "output_text",
                            "text": '{"candidates":[{"field":"weight_kg","quote":"70 kg","invented":true}]}',
                        }
                    ]
                }
            ],
        },
    ],
)
def test_openai_adapter_handles_incomplete_refusal_and_invalid_shape(body):
    async def run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, json=body))
        ) as client:
            provider = OpenAIExtractor(
                api_key="test-only", model="injected-test-model", client=client
            )
            with pytest.raises(ExtractionUnavailable):
                await provider.extract("70 kg", "weight_kg")

    asyncio.run(run())


def test_blank_provider_configuration_never_calls_network():
    async def run():
        def fail(_):
            pytest.fail("Blank keys must never trigger a network request")

        async with httpx.AsyncClient(transport=httpx.MockTransport(fail)) as client:
            provider = OpenAIExtractor(client=client)
            assert provider.configured is False
            with pytest.raises(ExtractionUnavailable):
                await provider.extract("70 kg", "weight_kg")

    asyncio.run(run())


@pytest.mark.parametrize(
    "text",
    [
        "If I weighed 70 kg, would I be healthier?",
        "I do not weigh 70 kg.",
        "I weighed 70 kg ten years ago.",
        "Maybe I weigh 70 kg.",
        "I might weigh 70 kg.",
        "Weight: 70 kg and 80 kg",
        "Weight: 70 kg; weight: 80 kg",
        "I used to weigh 70 kg, but I do not know my current weight.",
        "I weigh 170 kg, I'm told",
    ],
)
def test_provider_span_cannot_drop_context_or_select_numeric_substring(text):
    provider = FakeExtractor(quote="70 kg")
    service = ConversationService(provider)
    result = service_turn(
        service,
        action="reply",
        state={"phase": "asking", "current_field": "age"},
        text=text,
        provider_consent=True,
    )
    assert result.state.phase == "asking"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {}
    assert result.state.confirmed_profile.model_dump(exclude_none=True) == {}
    assert result.provider_status == "used"


@pytest.mark.parametrize(
    ("text", "field", "quote"),
    [
        ("My current sex is female", "sex", "male"),
        ("My current weight is 170 kg", "weight_kg", "70 kg"),
        ("My current weight is 70 kg", "age", "70"),
        ("My current weight is 70 kg, if I reach my goal", "weight_kg", "70 kg"),
    ],
)
def test_grounding_requires_field_context_full_tokens_and_all_clauses(text, field, quote):
    extraction = ExtractionResult.model_validate({"candidates": [{"field": field, "quote": quote}]})
    assert grounded_candidates(text, extraction, field) == {}


@pytest.mark.parametrize(
    "text",
    [
        "weight: 70 kg and 80 kg",
        "weight: 70 kg; 80 kg",
        "weight: 70 kg, maybe 80 kg",
        "weight: 70 kg; weight: 80 kg",
    ],
)
def test_keyless_contradictory_or_unaccounted_clauses_require_clarification(client, text):
    assert parse_reply(text, "age") == {}
    result = turn(client, "reply", begin(client)["state"], text=text)
    assert result["state"]["phase"] == "asking"
    assert result["state"]["pending_profile"]["weight_kg"] is None


def test_single_pending_correction_uses_pending_field_instead_of_old_question(client):
    result = turn(client, "reply", begin(client)["state"], text="weight: 70 kg")
    assert result["state"]["current_field"] == "weight_kg"
    result = turn(client, "correct", result["state"], text="80 kg")
    assert result["state"]["pending_profile"]["weight_kg"] == 80
    assert result["state"]["confirmed_profile"]["weight_kg"] is None
    result = turn(client, "confirm", result["state"])
    assert result["state"]["confirmed_profile"]["weight_kg"] == 80
    assert result["state"]["current_field"] == "age"


def test_multi_pending_correction_requires_field_and_never_guesses(client):
    result = turn(client, "reply", begin(client)["state"], text="age: 35; weight: 70 kg")
    assert result["state"]["current_field"] is None
    pending = result["state"]["pending_profile"]
    result = turn(client, "correct", result["state"], text="80 kg")
    assert "Which one do you want to change?" in result["message"]
    assert "age, weight" in result["message"]
    assert result["state"]["pending_profile"] == pending
    result = turn(client, "correct", result["state"], field="weight_kg", text="80 kg")
    assert result["state"]["pending_profile"]["weight_kg"] == 80
    assert result["state"]["pending_profile"]["age"] == 35


def test_generic_health_prefix_cannot_be_misread_as_another_field():
    assert parse_value("age", "I weigh 70") == {}
    assert parse_value("age", "My weight is 70") == {}
    assert parse_value("weight_kg", "My height is 170 kg") == {}


def test_enormous_numeric_token_clarifies_instead_of_overflowing(client):
    text = "9" * 500 + " ft"
    assert parse_value("height_cm", text) == {}
    state = ConversationState(phase="asking", current_field="height_cm").model_dump()
    result = turn(client, "reply", state, text=text)
    assert result["state"]["phase"] == "asking"
    assert result["state"]["pending_profile"]["height_cm"] is None


def test_deeply_nested_provider_json_falls_back_to_guided_clarification():
    async def run():
        nested = b"[" * 2000 + b"0" + b"]" * 2000
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, content=nested))
        ) as client:
            provider = OpenAIExtractor(api_key="test-only", model="test-only", client=client)
            response = await ConversationService(provider).turn(
                TurnRequest(
                    action="reply",
                    state=ConversationState(phase="asking", current_field="weight_kg"),
                    text=PROVIDER_TEXT,
                    provider_consent=True,
                )
            )
            assert response.guide_mode == "guided"
            assert response.provider_status == "unavailable"
            assert response.state.pending_profile.weight_kg is None

    asyncio.run(run())


def test_owned_extractor_client_does_not_trust_proxy_environment_and_is_closed(monkeypatch):
    clients = []
    original = httpx.AsyncClient

    def create_client(**kwargs):
        assert kwargs["trust_env"] is False
        assert kwargs["follow_redirects"] is False
        client = original(
            transport=httpx.MockTransport(
                lambda _: httpx.Response(200, json={"status": "incomplete"})
            ),
            **kwargs,
        )
        clients.append(client)
        return client

    async def run():
        monkeypatch.setattr(httpx, "AsyncClient", create_client)
        provider = OpenAIExtractor(api_key="test-only", model="test-only")
        with pytest.raises(ExtractionUnavailable):
            await provider.extract("70 kg", "weight_kg")

    asyncio.run(run())
    assert len(clients) == 1 and clients[0].is_closed


def asking(field, **values):
    return ConversationState(phase="asking", current_field=field, **values).model_dump()


# d-intake-1: a provider cannot move a bare number to a field nobody asked about.
@pytest.mark.parametrize(
    ("asked", "field", "text"),
    [
        ("height_cm", "age", "70"),
        ("weight_kg", "systolic_bp", "160"),
        ("sleep_hours", "alcohol_drinks_weekly", "7"),
        ("smoking_status", "diabetes", "no"),
    ],
)
def test_grounding_rejects_unnamed_quote_for_another_field(asked, field, text):
    extraction = ExtractionResult.model_validate({"candidates": [{"field": field, "quote": text}]})
    assert grounded_candidates(text, extraction, asked) == {}
    assert grounded_candidates(text, extraction, field) != {}


@pytest.mark.parametrize(
    ("asked", "field", "text", "expected"),
    [
        ("weight_kg", "systolic_bp", "my systolic is 160", {"systolic_bp": 160}),
        ("height_cm", "age", "I am 70 years old", {"age": 70}),
        ("sleep_hours", "alcohol_drinks_weekly", "7 drinks", {"alcohol_drinks_weekly": 7.0}),
    ],
)
def test_grounding_accepts_other_field_when_clause_names_it(asked, field, text, expected):
    extraction = ExtractionResult.model_validate({"candidates": [{"field": field, "quote": text}]})
    assert grounded_candidates(text, extraction, asked) == expected


def test_provider_cannot_turn_bare_weight_into_blood_pressure():
    service = ConversationService(FakeExtractor(quote="60", field="systolic_bp"))
    result = service_turn(
        service, action="reply", state=asking("weight_kg"), text="60", provider_consent=True
    )
    assert result.state.phase == "asking"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {}
    # The unit question is asked directly; the helper is not asked to guess.
    assert result.provider_status == "not_needed"
    assert "60 pounds or 60 kilograms" in result.message


# d-intake-2: the confirmation is readable and repeats the person's own unit.
@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("weight_kg", "160 lbs", "I heard you weigh 160 pounds (about 72.6 kg)."),
        ("weight_kg", "70 kg", "I heard you weigh 70 kg (about 154.3 pounds)."),
        ("height_cm", "5 ft 10 in", "I heard you are 5 feet 10 inches (about 178 cm) tall."),
        ("height_cm", "178 cm", "I heard you are 178 cm (about 5 feet 10 inches) tall."),
        ("systolic_bp", "120/80", "I heard your blood pressure is 120 over 80."),
        ("exercise_minutes_weekly", "150 minutes", "I heard you exercise 150 minutes a week."),
        ("smoking_status", "never", "I heard you have never smoked."),
    ],
)
def test_confirmation_message_is_plain_language(client, field, text, expected):
    message = turn(client, "reply", asking(field), text=text)["message"]
    assert expected in message
    assert "_" not in message
    assert "Metric fields" not in message
    assert message.endswith("Is that right?")


def test_several_pending_and_correction_messages_use_plain_labels(client):
    result = turn(client, "reply", asking("age"), text="age: 35; weight: 70 kg")
    assert "_" not in result["message"]
    message = turn(client, "correct", result["state"], text="80 kg")["message"]
    assert "age, weight" in message and "_" not in message
    message = turn(client, "correct", result["state"], field="systolic_bp", text="weight: 80 kg")[
        "message"
    ]
    assert "top blood pressure number" in message and "_" not in message


# d-intake-3: spoken yes/no while confirming never returns 409.
@pytest.mark.parametrize("text", ["yes", "Yes.", "yes, that's right", "Correct", "that’s right"])
def test_plain_yes_while_confirming_confirms(client, text):
    pending = turn(client, "reply", asking("height_cm"), text="5 ft 10 in")["state"]
    result = turn(client, "reply", pending, text=text)
    assert result["state"]["confirmed_profile"]["height_cm"] == pytest.approx(177.8)
    assert result["state"]["phase"] == "asking"


@pytest.mark.parametrize("text", ["No, it's 6 ft", "no 6 feet", "Nope, 6 foot"])
def test_no_with_value_while_confirming_corrects_pending(client, text):
    pending = turn(client, "reply", asking("height_cm"), text="5 ft 10 in")["state"]
    result = turn(client, "reply", pending, text=text)
    assert result["state"]["phase"] == "confirming"
    assert result["state"]["pending_profile"]["height_cm"] == pytest.approx(182.88)
    assert result["state"]["confirmed_profile"]["height_cm"] is None


@pytest.mark.parametrize("text", ["maybe", "no", "ok", "yes but 6 ft", "I think so"])
def test_ambiguous_reply_while_confirming_changes_nothing(client, text):
    pending = turn(client, "reply", asking("height_cm"), text="5 ft 10 in")["state"]
    result = turn(client, "reply", pending, text=text)
    # Only the one "Is that a yes?" check is noted; no answer changes.
    assert result["state"] == {**pending, "yes_no_checked": result["state"]["yes_no_checked"]}
    message = result["message"]
    assert message.endswith("Is that right?") or "right answer for your height" in message


def test_pending_blood_pressure_pair_is_corrected_as_a_pair(client):
    pending = turn(client, "reply", asking("systolic_bp"), text="120 over 80")["state"]
    result = turn(client, "reply", pending, text="no, 130 over 85")
    assert result["state"]["pending_profile"]["systolic_bp"] == 130
    assert result["state"]["pending_profile"]["diastolic_bp"] == 85
    result = turn(client, "reply", pending, text="no, 130")
    assert result["state"] == pending
    assert "both blood pressure numbers" in result["message"]


# d-intake-4: common US height forms.
@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("5'10", 177.8),
        ("5'10\"", 177.8),
        ("5 foot 10", 177.8),
        ("5 feet 10", 177.8),
        ("5 feet, 10 inches", 177.8),
        ("5 feet and 10 inches", 177.8),
        ("5 ft. 10 in.", 177.8),
        ("70 inches", 177.8),
        ("6 feet tall", 182.88),
        ("5′10″", 177.8),
        ("I'm 6 foot", 182.88),
    ],
)
def test_us_height_forms(text, expected):
    assert parse_reply(text, "height_cm") == {"height_cm": pytest.approx(expected)}


@pytest.mark.parametrize("text", ["5 feet 14", "5 ft 14 in", "5 feet, 10 inches, 6 feet"])
def test_impossible_or_contradictory_heights_still_clarify(text):
    assert parse_reply(text, "height_cm") == {}


def test_and_a_half_stays_one_measurement():
    assert parse_reply("6 and a half hours", "sleep_hours") == {"sleep_hours": 6.5}


# d-intake-5: iOS smart punctuation.
@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "I’m 75", {"age": 75}),
        ("height_cm", "I’m 5 ft 10 in", {"height_cm": 177.8}),
        ("alcohol_drinks_weekly", "I don’t drink", {"alcohol_drinks_weekly": 0.0}),
        ("sex", "I’m male", {"sex": "male"}),
    ],
)
def test_curly_apostrophes_parse(field, text, expected):
    assert parse_reply(text, field) == expected


def test_curly_apostrophe_unknown_word_is_unknown(client):
    result = turn(client, "reply", asking("systolic_bp"), text="I don’t know")
    assert "systolic_bp" in result["state"]["unknown_fields"]
    assert "systolic_bp" not in result["state"]["skipped_fields"]


# d-intake-6: natural ways to decline. v2: not knowing is recorded as unknown instead.
@pytest.mark.parametrize("text", ["next", "I'd rather not say", "skip this one"])
def test_expanded_skip_words(client, text):
    result = turn(client, "reply", asking("weight_kg"), text=text)
    assert "weight_kg" in result["state"]["skipped_fields"]


@pytest.mark.parametrize("text", ["don't know", "I'm not sure", "no idea", "pass"])
def test_unknown_words_are_unknown_not_skipped(client, text):
    result = turn(client, "reply", asking("weight_kg"), text=text)
    assert "weight_kg" in result["state"]["unknown_fields"]
    assert "weight_kg" not in result["state"]["skipped_fields"]


@pytest.mark.parametrize("field", ["systolic_bp", "diastolic_bp"])
def test_plain_no_to_blood_pressure_skips(client, field):
    result = turn(client, "reply", asking(field), text="No")
    assert field in result["state"]["skipped_fields"]
    assert "didn't understand" not in result["message"]


def test_prefer_not_to_say_skips_sex(client):
    # Sex at birth is female or male only (the training data has nothing else).
    result = turn(client, "reply", asking("sex"), text="I'd rather not say")
    assert result["state"]["pending_profile"].get("sex") is None
    assert "sex" in result["state"]["skipped_fields"]


def test_intersex_answer_explains_the_two_options(client):
    result = turn(client, "reply", asking("sex"), text="I was born intersex")
    assert result["state"]["pending_profile"].get("sex") is None
    assert "female or male at birth" in result["message"]


def test_blood_pressure_question_asks_for_a_value():
    assert QUESTIONS["systolic_bp"].startswith("What is your blood pressure?")
    assert "120 over 80" in QUESTIONS["systolic_bp"]


# d-intake-7: spoken pairs and impossible readings.
def test_spoken_blood_pressure_pair():
    assert parse_reply("120 over 80", "systolic_bp") == {"systolic_bp": 120, "diastolic_bp": 80}
    assert parse_reply("my blood pressure is 120 over 80", "systolic_bp") == {
        "systolic_bp": 120,
        "diastolic_bp": 80,
    }


@pytest.mark.parametrize("text", ["80/120", "80 over 120", "90/90"])
def test_reversed_blood_pressure_pair_asks_to_check(client, text):
    assert parse_reply(text, "systolic_bp") == {}
    result = turn(client, "reply", asking("systolic_bp"), text=text)
    assert result["state"]["phase"] == "asking"
    assert "top number is usually the bigger one" in result["message"]


def test_diastolic_must_be_below_confirmed_systolic(client):
    state = asking("diastolic_bp", confirmed_profile=HealthProfile(systolic_bp=70))
    result = turn(client, "reply", state, text="90")
    assert result["state"]["phase"] == "asking"
    assert result["state"]["pending_profile"]["diastolic_bp"] is None
    assert "top number is usually the bigger one" in result["message"]


# d-intake-8: a confirmed answer can be withdrawn without erasing everything.
def test_confirmed_answer_can_be_withdrawn_to_blank(client):
    others = [field for field in HealthProfile.model_fields if field != "diabetes"]
    state = ConversationState(
        phase="ready",
        confirmed_profile=HealthProfile(diabetes=True),
        skipped_fields=others,
        missing_offered=True,
    ).model_dump()
    result = turn(client, "correct", state, field="diabetes", text="not sure")
    assert result["state"]["confirmed_profile"]["diabetes"] is None
    assert "diabetes" in result["state"]["skipped_fields"]
    assert result["state"]["phase"] == "ready"
    assert "removed your diabetes answer" in result["message"]
    assert "cancel" not in result["message"]


def test_skip_word_correction_without_saved_value_changes_nothing(client):
    state = asking("age")
    result = turn(client, "correct", state, field="weight_kg", text="not sure")
    assert result["state"] == state
    assert "Nothing has changed" in result["message"] and "cancel" not in result["message"]


# d-intake-9: a unitless number with two plausible units gets a unit follow-up.
# (A bare 90+ weight is proposed as pounds and a bare 120-219 height as cm; see
# test_flexible_intake.py.)
@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("weight_kg", "70", "Is that 70 pounds or 70 kilograms?"),
        ("weight_kg", "about 70", "Is that 70 pounds or 70 kilograms?"),
        ("height_cm", "70", "Is that inches or centimeters?"),
        ("height_cm", "about 70", "Is that inches or centimeters?"),
    ],
)
def test_unitless_or_approximate_number_gets_specific_follow_up(client, field, text, expected):
    result = turn(client, "reply", asking(field), text=text)
    assert result["state"]["phase"] == "asking"
    assert expected in result["message"]
    assert "units" not in result["message"]


def test_start_and_fallback_messages_avoid_jargon(client):
    start = turn(client, "start")["message"]
    assert "You can talk or type" in start and "skip anything" in start
    assert "transcript" not in start
    message = turn(client, "reply", asking("age"), text="purple")["message"]
    assert "listed category" not in message and "units" not in message


# d-intake-10: everyday categorical answers.
@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("sex", "woman", "female"),
        ("sex", "a woman", "female"),
        ("sex", "I'm a woman", "female"),
        ("sex", "man", "male"),
        ("smoking_status", "I never smoked", "never"),
        ("smoking_status", "I've never smoked", "never"),
        ("smoking_status", "I used to smoke", "former"),
        ("smoking_status", "I quit", "former"),
        ("diabetes", "nope", False),
        ("diabetes", "no, I don't", False),
        ("exercise_minutes_weekly", "none", 0),
        ("exercise_minutes_weekly", "I don't exercise", 0),
        ("exercise_minutes_weekly", "0", 0),
    ],
)
def test_everyday_categorical_answers(field, text, expected):
    assert parse_reply(text, field) == {field: expected}


# d-intake-11: "a day" is proposed as every day and read back; stated days win.
# (Superseded: "30 minutes a day" used to ask how many days a week.)
def test_daily_exercise_proposes_every_day_then_accepts_explicit_total(client):
    result = turn(client, "reply", asking("exercise_minutes_weekly"), text="30 minutes a day")
    assert result["state"]["phase"] == "confirming"
    assert result["state"]["confirmed_profile"]["exercise_minutes_weekly"] is None
    assert "210 minutes a week" in result["message"]
    result = turn(
        client,
        "reply",
        asking("exercise_minutes_weekly"),
        text="30 minutes a day, 5 days a week",
    )
    assert result["state"]["pending_profile"]["exercise_minutes_weekly"] == 150
    assert "150 minutes a week" in result["message"]


def test_bare_small_exercise_number_is_not_read_as_minutes(client):
    assert parse_reply("5", "exercise_minutes_weekly") == {}
    result = turn(client, "reply", asking("exercise_minutes_weekly"), text="5")
    assert result["state"]["phase"] == "asking"
    assert "5 minutes or 5 hours" in result["message"]


# d-muse: OpenAI-compatible Chat Completions adapter (Meta Muse first).
SECRET = "sk-test-secret-123"
GOOD = '{"candidates":[{"field":"weight_kg","quote":"70 kg"}]}'


def chat_body(content, finish="stop", **message):
    return {
        "choices": [
            {
                "finish_reason": finish,
                "message": {"role": "assistant", "content": content, **message},
            }
        ]
    }


def chat_provider(client):
    return ChatCompletionsExtractor(
        base_url="https://api.meta.ai/v1/",
        api_key=SECRET,
        model="muse-spark-1.3-contributor",
        allow_contributor=True,
        client=client,
    )


def run_chat(handler, text=PROVIDER_TEXT, asked="weight_kg"):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await ConversationService(chat_provider(client)).turn(
                TurnRequest(
                    action="reply",
                    state=ConversationState(phase="asking", current_field=asked),
                    text=text,
                    provider_consent=True,
                )
            )

    return asyncio.run(run())


def test_chat_completions_request_shape_and_good_extraction():
    seen = []

    def handle(request):
        seen.append(request)
        return httpx.Response(200, json=chat_body(GOOD))

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            return await chat_provider(client).extract("I weigh 70 kg", "weight_kg")

    result = asyncio.run(run())
    assert result.candidates[0].quote == "70 kg"
    request = seen[0]
    assert str(request.url) == "https://api.meta.ai/v1/chat/completions"
    assert request.headers["authorization"] == f"Bearer {SECRET}"
    body = json.loads(request.content)
    assert body["model"] == "muse-spark-1.3-contributor"
    assert [m["role"] for m in body["messages"]] == ["system", "user"]
    assert body["messages"][1]["content"] == "I weigh 70 kg"
    # The question gives a short reply its meaning; the reply itself stays the only user text.
    assert QUESTIONS["weight_kg"] in body["messages"][0]["content"]
    assert body["response_format"]["type"] == "json_schema"
    assert body["response_format"]["json_schema"]["schema"]["properties"]["candidates"]
    assert body["reasoning_effort"] == "minimal"
    assert SECRET not in request.content.decode()


def test_chat_completions_reasoning_effort_can_be_omitted():
    """Observed live: without a limit, Muse spent all tokens reasoning and returned no content."""
    seen = []

    def handle(request):
        seen.append(json.loads(request.content))
        return httpx.Response(200, json=chat_body(GOOD))

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            provider = ChatCompletionsExtractor(
                base_url="https://api.meta.ai/v1",
                api_key=SECRET,
                model="m",
                reasoning_effort="",
                client=client,
            )
            return await provider.extract("I weigh 70 kg", "weight_kg")

    asyncio.run(run())
    assert "reasoning_effort" not in seen[0]


def test_chat_completions_truncated_reasoning_reply_falls_back():
    def handle(request):
        return httpx.Response(
            200,
            json={
                "choices": [
                    {"finish_reason": "length", "message": {"role": "assistant", "content": None}}
                ]
            },
        )

    response = run_chat(handle)
    assert response.provider_status != "used"
    assert response.state.pending_profile.weight_kg is None


def test_chat_completions_good_extraction_flows_through_service():
    result = run_chat(lambda _: httpx.Response(200, json=chat_body(GOOD)))
    assert result.provider_status == "used"
    assert result.state.phase == "confirming"
    assert result.state.pending_profile.weight_kg == 70
    assert SECRET not in result.model_dump_json()


def test_chat_completions_output_still_goes_through_grounding():
    bad = '{"candidates":[{"field":"systolic_bp","quote":"60"}]}'
    result = run_chat(
        lambda _: httpx.Response(200, json=chat_body(bad)), text="60", asked="weight_kg"
    )
    assert result.provider_status == "not_needed"  # the unit question comes first
    assert result.guide_mode == "guided"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {}


def _status(code):
    return lambda _: httpx.Response(code, json={"error": {"message": SECRET}})


def _timeout(request):
    raise httpx.ReadTimeout("slow", request=request)


@pytest.mark.parametrize(
    "handler",
    [
        lambda _: httpx.Response(200, content=b"not json"),
        lambda _: httpx.Response(200, json=chat_body("not json at all")),
        lambda _: httpx.Response(200, json=chat_body('{"candidates":[{"field":"x","quote":1}]}')),
        lambda _: httpx.Response(200, json=chat_body(GOOD, finish="length")),
        lambda _: httpx.Response(200, json=chat_body(GOOD, refusal="No")),
        lambda _: httpx.Response(200, json={"choices": []}),
        lambda _: httpx.Response(200, content=b"[" * 2000 + b"0" + b"]" * 2000),
        _status(401),
        _status(429),
        _status(500),
        _timeout,
    ],
)
def test_chat_completions_failures_fall_back_safely_without_leaking_key(handler):
    result = run_chat(handler)
    assert result.guide_mode == "guided"
    assert result.provider_status == "unavailable"
    assert result.state.pending_profile.weight_kg is None
    assert "AI helper isn't available" in result.message
    assert SECRET not in result.model_dump_json()


def test_chat_completions_error_text_does_not_expose_key_or_reply():
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(_status(401))) as client:
            with pytest.raises(ExtractionUnavailable) as caught:
                await chat_provider(client).extract("I weigh 70 kg", "weight_kg")
            return caught.value

    error = asyncio.run(run())
    assert SECRET not in repr(error) and "70 kg" not in repr(error) and str(error) == ""


def test_chat_completions_unconfigured_never_calls_network():
    def fail(_):
        pytest.fail("Unconfigured provider must not use the network")

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(fail)) as client:
            for kwargs in ({}, {"base_url": "https://x/v1", "api_key": "k"}):
                provider = ChatCompletionsExtractor(client=client, **kwargs)
                assert provider.configured is False
                with pytest.raises(ExtractionUnavailable):
                    await provider.extract("70 kg", "weight_kg")

    asyncio.run(run())


def test_llm_provider_selection_and_capabilities(monkeypatch):
    from lifetwin.app import create_app
    from lifetwin.core.config import Settings

    for name in ("OPENAI_API_KEY", "OPENAI_MODEL", "LLM_PROVIDER", "LLM_BASE_URL", "LLM_MODEL"):
        monkeypatch.delenv(name, raising=False)

    def caps(**env):
        app = create_app(Settings(_env_file=None, **env))
        with TestClient(app) as test_client:
            return app, test_client.get("/api/capabilities").json()

    app, body = caps()
    assert body["llm_configured"] is False
    assert isinstance(app.state.conversation_service.extractor, OpenAIExtractor)
    app, body = caps(OPENAI_API_KEY="k", OPENAI_MODEL="m")
    assert body["llm_configured"] is True
    app, body = caps(LLM_PROVIDER="chat_completions", LLM_MODEL="m")
    assert body["llm_configured"] is False
    app, body = caps(LLM_PROVIDER="chat_completions", LLM_MODEL="m", LLM_API_KEY="k")
    assert body["llm_configured"] is True
    extractor = app.state.conversation_service.extractor
    assert isinstance(extractor, ChatCompletionsExtractor)
    assert extractor._base_url == "https://api.meta.ai/v1"
    assert Settings(_env_file=None, LLM_PROVIDER="").llm_provider == "openai"


def test_answered_but_no_value_does_not_claim_the_helper_is_unavailable():
    """Observed live with Muse: an empty extraction was reported as an outage."""
    service = ConversationService(FakeExtractor(quote="90 kg"))
    result = service_turn(
        service,
        action="reply",
        state={"phase": "asking", "current_field": "weight_kg"},
        text=PROVIDER_TEXT,
        provider_consent=True,
    )
    assert result.provider_status == "used"
    assert "isn't available" not in result.message


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("height_cm", "five foot eight", {"height_cm": 172.72}),
        ("sleep_hours", "seven hours", {"sleep_hours": 7.0}),
        ("sleep_hours", "seven and a half hours", {"sleep_hours": 7.5}),
        ("weight_kg", "a hundred and seventy pounds", {"weight_kg": 77.1107}),
        ("exercise_minutes_weekly", "half an hour a week", {"exercise_minutes_weekly": 30}),
        ("smoking_status", "I quit smoking back in 1990", {"smoking_status": "former"}),
        ("smoking_status", "I stopped smoking years ago", {"smoking_status": "former"}),
        ("smoking_status", "I never quit", {}),
    ],
)
def test_spoken_number_words_and_quitting_are_understood(field, text, expected):
    """Voice transcripts spell numbers out, and "I quit" answers the smoking question."""
    assert parse_value(field, text) == expected


@pytest.mark.parametrize(
    ("field", "text", "value"),
    [
        ("weight_kg", "about 160 pounds", 72.5748),
        ("height_cm", "Oh, I'm about five foot eight I think", 172.72),
        ("sleep_hours", "I usually get about seven hours", 7.0),
        ("weight_kg", "Hmm, I weigh around 170 pounds these days", 77.1107),
        ("exercise_minutes_weekly", "I do about two hours of walking a week", 120),
    ],
)
def test_everyday_approximate_answers_go_to_confirmation(client, field, text, value):
    """Older adults answer "about 160 pounds"; the read-back confirmation is the safety net."""
    result = turn(client, "reply", asking(field), text=text)
    assert result["state"]["phase"] == "confirming"
    assert result["state"]["pending_profile"][field] == value
    assert result["state"]["confirmed_profile"][field] is None


# Apple Health import: values confirmed one by one on the phone move the conversation on.
def test_import_adds_confirmed_values_and_moves_past_the_current_question(client):
    state = asking("weight_kg", confirmed_profile={"age": 76, "sex": "female", "height_cm": 160})
    result = turn(client, "import", state, values={"weight_kg": 68, "sleep_hours": 7.5})
    confirmed = result["state"]["confirmed_profile"]
    assert (
        confirmed["weight_kg"] == 68 and confirmed["sleep_hours"] == 7.5 and confirmed["age"] == 76
    )
    assert result["state"]["phase"] == "asking"
    assert result["state"]["current_field"] not in {
        "weight_kg",
        "sleep_hours",
        "age",
        "sex",
        "height_cm",
    }
    assert result["state"]["pending_profile"]["weight_kg"] is None
    assert "I added your weight and sleep from Apple Health." in result["message"]
    assert "68" not in result["message"]


def test_import_clears_a_previous_skip_for_the_same_field(client):
    state = asking("age", skipped_fields=["weight_kg"])
    result = turn(client, "import", state, values={"weight_kg": 70})
    assert "weight_kg" not in result["state"]["skipped_fields"]
    assert result["state"]["confirmed_profile"]["weight_kg"] == 70


@pytest.mark.parametrize(
    "values",
    [{}, {"weight_kg": 5}, {"systolic_bp": 80, "diastolic_bp": 120}, {"weight_kg": "heavy"}],
)
def test_import_validates_values_like_any_answer(client, values):
    response = client.post(
        "/api/onboarding/turn", json={"action": "import", "state": asking("age"), "values": values}
    )
    assert response.status_code == 422


def test_import_waits_for_a_pending_confirmation(client):
    state = ConversationState(
        phase="confirming", current_field="age", pending_profile={"age": 70}
    ).model_dump()
    response = client.post(
        "/api/onboarding/turn",
        json={"action": "import", "state": state, "values": {"weight_kg": 70}},
    )
    assert response.status_code == 409


def test_values_are_rejected_for_other_actions(client):
    response = client.post(
        "/api/onboarding/turn",
        json={"action": "skip", "state": asking("age"), "values": {"weight_kg": 70}},
    )
    assert response.status_code == 422


def test_import_says_when_the_current_question_was_not_in_the_health_app(client):
    result = turn(client, "import", asking("weight_kg"), values={"height_cm": 172.7})
    assert result["state"]["current_field"] == "weight_kg"
    assert "didn't have your weight" in result["message"]


def test_document_import_names_the_document_and_skips_those_questions(client):
    values = {"height_cm": 167.6, "smoking_status": "former", "diabetes": True}
    result = turn(
        client, "import", asking("smoking_status"), values=values, import_source="document"
    )
    confirmed = result["state"]["confirmed_profile"]
    assert confirmed["smoking_status"] == "former" and confirmed["diabetes"] is True
    assert result["state"]["current_field"] not in values
    assert "from your document" in result["message"]
    assert "Apple Health" not in result["message"]
    result = turn(client, "import", asking("weight_kg"), values=values, import_source="document")
    assert "Your document didn't show your weight" in result["message"]


def test_import_that_answers_the_current_question_does_not_repeat_it(client):
    result = turn(client, "import", asking("weight_kg"), values={"weight_kg": 70})
    assert result["state"]["current_field"] != "weight_kg"
    assert "didn't have" not in result["message"]


@pytest.mark.parametrize(
    ("values", "shown"),
    [
        ({"height_cm": 170.0}, "170 cm"),
        ({"height_cm": 180.0}, "180 cm"),
        ({"weight_kg": 100.0}, "100 kg"),
        ({"sleep_hours": 10.0}, "10 hours"),
        ({"height_cm": 172.7}, "about 173 cm"),
    ],
)
def test_read_back_keeps_whole_number_zeros(values, shown):
    """Found by the Convex port: 170 cm was read back as "17 cm" for confirmation."""
    text = heard(values)
    assert shown in text
    assert " 17 cm" not in text and " 18 cm" not in text
