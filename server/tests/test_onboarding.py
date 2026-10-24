"""Behavioral intake tests: confirmation, ambiguity, transitions and providers."""

import asyncio
import json

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding import ConversationService, OpenAIExtractor, router
from lifetwin.onboarding.models import ConversationState, ExtractionResult, TurnRequest
from lifetwin.onboarding.parsing import grounded_candidates, parse_reply, parse_value
from lifetwin.onboarding.providers import ExtractionUnavailable


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


def test_first_turn_uses_guided_mascot_instead_of_fake_voice_or_llm(client):
    result = turn(client, "start")
    assert result["state"]["current_field"] == "age"
    assert result["guide_mode"] == "guided"
    assert result["provider_status"] == "not_configured"
    assert result["voice_status"] == "deferred"
    assert result["accepted_input_modes"] == ["text", "transcript"]
    assert result["mascot_events"][0]["caption"] == result["message"]


def test_confirmation_and_correction_keep_candidates_separate(client):
    state = turn(client, "start")["state"]
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
        turn(client, "start")["state"],
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
    "text", ["170", "about 170", "I lost 5 kg", "-5 kg", "7000 kg", "if I weighed 70 kg"]
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
        ("exercise_minutes_weekly", "30 minutes per day", {}),
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
    state = turn(client, "start")["state"]
    assert turn(client, "reply", state, text="35", input_mode="text") == turn(
        client, "reply", state, text="35", input_mode="transcript"
    )


def test_skip_unknown_completion_and_ready_correction(client):
    result = turn(client, "start")
    for _ in range(11):
        result = turn(client, "reply", result["state"], text="I don't know")
    assert result["complete"] is True
    assert all(value is None for value in result["state"]["confirmed_profile"].values())
    result = turn(client, "correct", result["state"], field="weight_kg", text="70 kg")
    assert result["complete"] is False
    result = turn(client, "confirm", result["state"])
    assert result["state"]["confirmed_profile"]["weight_kg"] == 70
    assert "weight_kg" not in result["state"]["skipped_fields"]
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
    state = turn(client, "reply", turn(client, "start")["state"], text="35")["state"]
    assert (
        client.post(
            "/api/onboarding/turn", json={"action": "reply", "state": state, "text": "36"}
        ).status_code
        == 409
    )


class FakeExtractor:
    configured = True

    def __init__(self, *, quote="70 kg", error=False):
        self.calls = 0
        self.quote = quote
        self.error = error

    async def extract(self, text, field):
        self.calls += 1
        if self.error:
            raise ExtractionUnavailable()
        return ExtractionResult.model_validate(
            {"candidates": [{"field": "weight_kg", "quote": self.quote}]}
        )


def service_turn(service, **kwargs):
    return asyncio.run(service.turn(TurnRequest.model_validate(kwargs)))


def test_provider_is_consent_gated_and_still_needs_confirmation():
    provider = FakeExtractor()
    service = ConversationService(provider)
    state = {"phase": "asking", "current_field": "weight_kg"}
    result = service_turn(service, action="reply", state=state, text="My current weight is 70 kg")
    assert result.provider_status == "consent_required"
    assert provider.calls == 0
    result = service_turn(
        service,
        action="reply",
        state=state,
        text="My current weight is 70 kg",
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
        text="My current weight is 70 kg",
        provider_consent=True,
    )
    assert result.provider_status == "unavailable"
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
        text="My current weight is 70 kg",
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
        "My current weight is about 70 kg.",
        "I might weigh 70 kg.",
        "Weight: 70 kg and 80 kg",
        "Weight: 70 kg; weight: 80 kg",
        "I used to weigh 70 kg, but I do not know my current weight.",
        "I weigh 170 kg.",
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
    assert result.provider_status == "unavailable"


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
    assert grounded_candidates(text, extraction) == {}


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
    result = turn(client, "reply", turn(client, "start")["state"], text=text)
    assert result["state"]["phase"] == "asking"
    assert result["state"]["pending_profile"]["weight_kg"] is None


def test_single_pending_correction_uses_pending_field_instead_of_old_question(client):
    result = turn(client, "reply", turn(client, "start")["state"], text="weight: 70 kg")
    assert result["state"]["current_field"] == "weight_kg"
    result = turn(client, "correct", result["state"], text="80 kg")
    assert result["state"]["pending_profile"]["weight_kg"] == 80
    assert result["state"]["confirmed_profile"]["weight_kg"] is None
    result = turn(client, "confirm", result["state"])
    assert result["state"]["confirmed_profile"]["weight_kg"] == 80
    assert result["state"]["current_field"] == "age"


def test_multi_pending_correction_requires_field_and_never_guesses(client):
    result = turn(client, "reply", turn(client, "start")["state"], text="age: 35; weight: 70 kg")
    assert result["state"]["current_field"] is None
    pending = result["state"]["pending_profile"]
    result = turn(client, "correct", result["state"], text="80 kg")
    assert "Choose the field" in result["message"]
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
