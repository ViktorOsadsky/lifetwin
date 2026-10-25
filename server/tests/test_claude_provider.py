"""Claude by Anthropic as an optional provider: selection, request shape, fallbacks, consent.

No live calls: the SDK client is replaced by a fake that records the request.
"""

import asyncio
import json
import logging
from datetime import date
from types import SimpleNamespace

import anthropic
import httpx2
import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin import CheckinService
from lifetwin.core import claude as claude_module
from lifetwin.core.config import Settings
from lifetwin.documents.models import DocumentExtractRequest
from lifetwin.documents.service import DocumentService
from lifetwin.onboarding import AnthropicExtractor, ChatCompletionsExtractor, OpenAIExtractor
from lifetwin.onboarding.intents import SAFETY_PHRASE
from lifetwin.onboarding.providers import ExtractionUnavailable
from lifetwin.personalize.providers import (
    ClaudePersonalizer,
    MusePersonalizer,
    PhrasingUnavailable,
)
from lifetwin.personalize.service import consented, phrase_question

PROVIDER_ENV = (
    "ANTHROPIC_API_KEY",
    "CLAUDE_MODEL",
    "LLM_PROVIDER",
    "PERSONALIZE_PROVIDER",
    "LLM_API_KEY",
    "LLM_MODEL",
    "LLM_BASE_URL",
    "OPENAI_API_KEY",
    "OPENAI_MODEL",
    "LLM_ALLOW_CONTRIBUTOR",
)
REQUEST = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for name in PROVIDER_ENV:
        monkeypatch.delenv(name, raising=False)


def message(text: str | None, stop_reason: str = "end_turn"):
    content = [SimpleNamespace(type="thinking", thinking="", signature="s")]
    if text is not None:
        content.append(SimpleNamespace(type="text", text=text))
    return SimpleNamespace(stop_reason=stop_reason, content=content, stop_details=None)


class FakeClient:
    def __init__(self, reply):
        self.calls: list[dict] = []
        self.messages = self
        self._reply = reply

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if isinstance(self._reply, BaseException):
            raise self._reply
        if callable(self._reply):
            return await self._reply()
        return self._reply


def app_for(**env):
    return create_app(Settings(_env_file=None, **env))


def capabilities(app) -> dict:
    with TestClient(app) as client:
        return client.get("/api/capabilities").json()


# -- selection -------------------------------------------------------------------


def test_without_an_anthropic_key_the_defaults_are_unchanged():
    settings = Settings(_env_file=None)
    assert (settings.llm_provider, settings.personalize_provider) == ("openai", "muse")
    app = app_for()
    assert isinstance(app.state.personalizer, MusePersonalizer)
    assert isinstance(app.state.conversation_service.extractor, OpenAIExtractor)
    assert app.state.document_service.extractor is None
    assert capabilities(app)["personalize"]["provider"] == "muse"


def test_an_anthropic_key_makes_claude_the_default_when_providers_are_unset():
    settings = Settings(_env_file=None, ANTHROPIC_API_KEY="k")
    assert (settings.llm_provider, settings.personalize_provider) == ("anthropic", "claude")
    assert settings.claude_model == "claude-haiku-5-5"
    assert settings.llm_configured is True
    # Blank counts as unset.
    blank = Settings(
        _env_file=None, ANTHROPIC_API_KEY="k", LLM_PROVIDER="", PERSONALIZE_PROVIDER=""
    )
    assert (blank.llm_provider, blank.personalize_provider) == ("anthropic", "claude")
    app = app_for(ANTHROPIC_API_KEY="k")
    assert isinstance(app.state.personalizer, ClaudePersonalizer)
    assert isinstance(app.state.conversation_service.extractor, AnthropicExtractor)
    assert app.state.document_service.provider == "claude"
    assert app.state.checkin_service.personalizer is app.state.personalizer


def test_explicit_env_selects_either_provider():
    app = app_for(ANTHROPIC_API_KEY="k", LLM_PROVIDER="anthropic", PERSONALIZE_PROVIDER="claude")
    assert isinstance(app.state.personalizer, ClaudePersonalizer)
    assert isinstance(app.state.conversation_service.extractor, AnthropicExtractor)
    # Muse stays a config option even with an Anthropic key present.
    app = app_for(
        ANTHROPIC_API_KEY="k",
        LLM_PROVIDER="chat_completions",
        PERSONALIZE_PROVIDER="muse",
        LLM_API_KEY="m",
        LLM_MODEL="muse-model",
    )
    assert isinstance(app.state.personalizer, MusePersonalizer)
    assert isinstance(app.state.conversation_service.extractor, ChatCompletionsExtractor)
    assert app.state.document_service.provider == "muse"
    # Claude selected without a key: unconfigured, so nothing is ever sent.
    app = app_for(LLM_PROVIDER="anthropic", PERSONALIZE_PROVIDER="claude")
    assert app.state.personalizer.configured is False
    assert app.state.conversation_service.extractor.configured is False
    assert capabilities(app)["llm_configured"] is False


def test_capabilities_name_claude_and_contributor_mode_does_not_apply():
    app = app_for(ANTHROPIC_API_KEY="k", LLM_ALLOW_CONTRIBUTOR="true")
    caps = capabilities(app)
    expected = {
        "provider": "claude",
        "display_name": "Claude by Anthropic",
        "company": "Anthropic",
        "configured": True,
        "may_train_on_content": False,
    }
    assert caps["personalize"] == expected
    assert {k: caps["coach"]["personalize"][k] for k in expected} == expected
    assert caps["llm_configured"] is True
    assert "retention" not in json.dumps(caps).lower()


# -- request shape ---------------------------------------------------------------


def _objects(schema):
    if isinstance(schema, dict):
        if schema.get("type") == "object":
            yield schema
        for value in schema.values():
            yield from _objects(value)
    elif isinstance(schema, list):
        for value in schema:
            yield from _objects(value)


async def test_request_shape_has_no_forbidden_params_and_caches_the_system_prompt():
    reply = {"candidates": [{"field": "weight_kg", "quote": "72 kilos"}]}
    fake = FakeClient(message(json.dumps(reply)))
    extractor = AnthropicExtractor(api_key="k", client=fake)
    result = await extractor.extract("The scale said 72 kilos today", "weight_kg")
    assert [(c.field, c.quote) for c in result.candidates] == [("weight_kg", "72 kilos")]
    (call,) = fake.calls
    assert call["model"] == "claude-haiku-5-5"
    assert 0 < call["max_tokens"] <= 1000
    # Sampling parameters 400 on this model; Haiku 5.5 has no server-side fallback; no prefill.
    for forbidden in ("temperature", "top_p", "top_k", "fallbacks", "betas", "tool_choice"):
        assert forbidden not in call
    assert [m["role"] for m in call["messages"]] == ["user"]
    assert call["messages"][0]["content"] == "The scale said 72 kilos today"
    assert call["thinking"] == {"type": "disabled"}
    assert call["output_config"]["effort"] == "low"
    (system,) = call["system"]
    assert system["cache_control"] == {"type": "ephemeral"}
    assert "weight_kg" in system["text"]
    fmt = call["output_config"]["format"]
    assert fmt["type"] == "json_schema"
    text = json.dumps(fmt["schema"])
    for keyword in ("maxLength", "minLength", "maxItems", "minItems"):
        assert keyword not in text
    objects = list(_objects(fmt["schema"]))
    assert objects and all(o["additionalProperties"] is False for o in objects)


async def test_the_sdk_client_gets_the_key_a_short_timeout_and_no_retries(monkeypatch):
    built = {}

    def factory(**kwargs):
        built.update(kwargs)
        return FakeClient(message('{"line": "How tall are you?"}'))

    monkeypatch.setattr(claude_module.anthropic, "AsyncAnthropic", factory)
    personalizer = ClaudePersonalizer(api_key=" k ")
    assert await personalizer.phrase("rules", {"line": "x"}) == {"line": "How tall are you?"}
    assert built == {"api_key": "k", "timeout": 6, "max_retries": 0}


async def test_unconfigured_claude_never_builds_a_client(monkeypatch):
    def factory(**kwargs):
        raise AssertionError("no client without a key")

    monkeypatch.setattr(claude_module.anthropic, "AsyncAnthropic", factory)
    with pytest.raises(PhrasingUnavailable):
        await ClaudePersonalizer(api_key="").phrase("rules", {})
    with pytest.raises(ExtractionUnavailable):
        await AnthropicExtractor(api_key="").extract("70 kg", "weight_kg")


# -- fallbacks -------------------------------------------------------------------

FAILURES = [
    message(None, "refusal"),
    message('{"candidates": [', "max_tokens"),
    message('{"line": "x"}', "pause_turn"),
    message(None),
    message("not json"),
    anthropic.APITimeoutError(request=REQUEST),
    anthropic.APIConnectionError(request=REQUEST),
    anthropic.InternalServerError(
        "boom", response=httpx2.Response(500, request=REQUEST), body=None
    ),
    anthropic.RateLimitError("slow", response=httpx2.Response(429, request=REQUEST), body=None),
]


@pytest.mark.parametrize("reply", FAILURES)
async def test_refusal_cutoff_and_errors_fall_back(reply, caplog):
    caplog.set_level(logging.WARNING)
    said = "my private words about my heart"
    extractor = AnthropicExtractor(api_key="k", client=FakeClient(reply))
    with pytest.raises(ExtractionUnavailable):
        await extractor.extract(said, "weight_kg")
    personalizer = ClaudePersonalizer(api_key="k", client=FakeClient(reply))
    # The question keeps Mochi's own words.
    assert await phrase_question(personalizer, "How tall are you?", said) is None
    assert "private words" not in caplog.text and "heart" not in caplog.text


async def test_a_slow_reply_falls_back_to_the_template():
    async def slow():
        await asyncio.sleep(1)
        return message('{"line": "How tall are you, friend?"}')

    personalizer = ClaudePersonalizer(api_key="k", client=FakeClient(slow))
    assert await phrase_question(personalizer, "How tall are you?", None, timeout=0.05) is None


async def test_structured_reply_is_used_and_an_unsafe_line_falls_back():
    good = ClaudePersonalizer(
        api_key="k", client=FakeClient(message('{"line": "Take your time. How tall are you?"}'))
    )
    assert (
        await phrase_question(good, "How tall are you?", None)
        == "Take your time. How tall are you?"
    )
    unsafe = ClaudePersonalizer(
        api_key="k",
        client=FakeClient(message('{"line": "How tall are you? This adds years to your life?"}')),
    )
    assert await phrase_question(unsafe, "How tall are you?", None) is None
    new_number = ClaudePersonalizer(
        api_key="k", client=FakeClient(message('{"line": "Are you 6 feet tall?"}'))
    )
    assert await phrase_question(new_number, "How tall are you?", None) is None


# -- consent ---------------------------------------------------------------------


def test_the_consent_id_is_claude_and_a_muse_consent_never_carries_over():
    personalizer = ClaudePersonalizer(api_key="k")
    assert personalizer.name == "claude"
    assert consented({"muse": True}, personalizer) is False
    assert consented({"claude": True}, personalizer) is True
    assert consented({"claude": True}, ClaudePersonalizer(api_key="")) is False


def _care_client(app, reply):
    fake = FakeClient(reply)
    app.state.checkin_service = CheckinService(
        clock=lambda: date(2026, 10, 24),
        personalizer=ClaudePersonalizer(api_key="k", client=fake),
    )
    return fake


def _wellbeing_state(client):
    state = client.post("/api/checkin/start", json={"kind": "daily"}).json()["state"]
    for _ in range(10):
        if state["current_field"] == "wellbeing":
            return state
        state = client.post("/api/checkin/turn", json={"action": "skip", "state": state}).json()[
            "state"
        ]
    raise AssertionError("never reached wellbeing")


CARE = (
    "I'm so sorry today feels awful. I'm right here with you, and we can go gently. "
    "If you're ever thinking about " + SAFETY_PHRASE
)


@pytest.mark.parametrize(
    ("consent", "reply", "choice"),
    [
        ({}, CARE, None),
        ({"muse": True}, CARE, None),
        ({"claude": True}, "approved:0", 0),
        ({"claude": True}, "approved:1", 1),
        ({"claude": True}, CARE, None),  # benign but unrecognized prose falls back
        ({"claude": True}, "I'm so sorry today feels awful. I'm right here with you.", None),
        ({"claude": True}, CARE.replace("gently", "gently, maybe try a supplement"), None),
    ],
)
def test_checkin_care_reply_is_reworded_only_with_claude_consent_and_the_safety_line(
    consent, reply, choice
):
    app = app_for(ANTHROPIC_API_KEY="k")
    with TestClient(app) as client:
        if choice is not None:

            async def choose():
                facts = json.loads(fake.calls[-1]["messages"][0]["content"])
                return message(json.dumps({"line": facts["approved_wordings"][choice]}))

            fake = _care_client(app, choose)
        else:
            fake = _care_client(app, message(json.dumps({"line": reply})))
        state = _wellbeing_state(client)
        body = {"action": "reply", "state": state, "text": "awful", "outside_ai_consent": consent}
        baseline = client.post("/api/checkin/turn", json={**body, "outside_ai_consent": {}}).json()
        out = client.post("/api/checkin/turn", json=body).json()
    assert out["state"] == baseline["state"]
    assert out["state"]["care_line_shown"] is True
    assert out["message"].count("911") == 1
    if choice is None:
        assert out["message"] == baseline["message"]
    else:
        facts = json.loads(fake.calls[0]["messages"][0]["content"])
        assert out["message"].startswith(facts["approved_wordings"][choice])
    assert len(fake.calls) == (1 if consent.get("claude") else 0)


TABLE = ["Patient: Ada Fakename\nVitals\nWeight\n150 lb"]


@pytest.mark.parametrize(
    ("consent", "status"),
    [
        (False, "consent_required"),
        (True, "consent_required"),  # the older app's bare yes was for Muse by Meta
        ({"muse": True}, "consent_required"),
        ({"claude": True}, "used"),
    ],
)
async def test_documents_go_to_claude_only_with_claude_consent_and_words_only(consent, status):
    reply = {"candidates": [{"field": "weight_kg", "quote": "Weight\n150 lb"}]}
    fake = FakeClient(message(json.dumps(reply)))
    service = DocumentService(AnthropicExtractor(api_key="k", client=fake), muse_enabled=True)
    response = await service.extract(
        DocumentExtractRequest(pages=TABLE, outside_ai_consent=consent), today=date(2026, 10, 24)
    )
    assert response.provider_status == status
    if status != "used":
        assert fake.calls == []
        return
    (candidate,) = response.candidates
    assert (candidate.field, candidate.method) == ("weight_kg", "claude")
    (call,) = fake.calls
    content = call["messages"][0]["content"]
    assert isinstance(content, str)  # text only: no image block, never the photo
    assert "Fakename" not in content and "Ada" not in content


async def test_a_bare_document_yes_still_reaches_muse():
    class Muse:
        configured = True

        async def complete_json(self, instructions, text, schema):
            return json.dumps({"candidates": []})

    service = DocumentService(Muse(), muse_enabled=True)
    response = await service.extract(
        DocumentExtractRequest(pages=TABLE, outside_ai_consent=True), today=date(2026, 10, 24)
    )
    assert response.provider_status == "used"
