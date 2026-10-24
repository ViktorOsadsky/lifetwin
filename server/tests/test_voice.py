import json

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.voice import VoiceService

KEY = "sk_car_test-key-not-real"
UPSTREAM_TOKEN = "short-lived-token-123"
PLAIN = "Voice isn't available right now. You can keep going by typing."


def settings(**overrides):
    return Settings(
        _env_file=None,
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        cartesia_api_key=overrides.pop("cartesia_api_key", ""),
        cartesia_voice_id=overrides.pop("cartesia_voice_id", ""),
        **overrides,
    )


def configured_client(handler, **overrides):
    config = settings(cartesia_api_key=KEY, cartesia_voice_id="voice-abc", **overrides)
    app = create_app(config)
    app.state.voice_service = VoiceService(config, transport=httpx.MockTransport(handler))
    return TestClient(app)


def ok_handler(calls):
    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"token": UPSTREAM_TOKEN})

    return handler


def test_consent_is_required():
    with configured_client(ok_handler([])) as client:
        for body in ({}, {"voice_consent": False}, {"voice_consent": "yes"}):
            response = client.post("/api/voice/token", json=body)
            assert response.status_code == 422
            assert response.json()["message"] == "Please agree to use your voice first."


def test_unconfigured_returns_503_without_network(monkeypatch):
    async def forbidden(*args, **kwargs):
        raise AssertionError("Keyless voice must never contact a provider")

    monkeypatch.setattr(httpx.AsyncClient, "send", forbidden)
    for config in (settings(), settings(cartesia_api_key=KEY), settings(cartesia_voice_id="v")):
        with TestClient(create_app(config)) as client:
            response = client.post("/api/voice/token", json={"voice_consent": True})
            assert response.status_code == 503
            body = response.json()
            assert body["code"] == "voice_unavailable"
            assert body["message"] == PLAIN


def test_success_shape_headers_and_exact_upstream_request():
    calls = []
    with configured_client(ok_handler(calls), cartesia_token_ttl_seconds=120) as client:
        response = client.post("/api/voice/token", json={"voice_consent": True})
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {
        "schema_version": "1.0",
        "token": UPSTREAM_TOKEN,
        "expires_in": 120,
        "cartesia_version": "2026-08-14",
        "stt": {
            "model": "ink-2",
            "encoding": "pcm_s16le",
            "sample_rate": 16000,
            "url": "wss://api.cartesia.ai/stt/websocket",
        },
        "tts": {
            "model": "sonic-3.6",
            "voice_id": "voice-abc",
            "encoding": "pcm_s16le",
            "sample_rate": 24000,
            "speed": 0.9,
            "emotion": "calm",
            "url": "wss://api.cartesia.ai/tts/websocket",
        },
    }
    assert KEY not in response.text
    assert len(calls) == 1
    request = calls[0]
    assert request.method == "POST"
    assert str(request.url) == "https://api.cartesia.ai/access-token"
    assert request.headers["authorization"] == f"Bearer {KEY}"
    assert request.headers["cartesia-version"] == "2026-08-14"
    assert json.loads(request.content) == {
        "grants": {"tts": True, "stt": True},
        "expires_in": 120,
    }


def test_capabilities_reports_voice_mode():
    with TestClient(create_app(settings())) as client:
        assert client.get("/api/capabilities").json()["voice"] == "unavailable"
    with configured_client(ok_handler([])) as client:
        capabilities = client.get("/api/capabilities")
        assert capabilities.json()["voice"] == "available"
        assert KEY not in capabilities.text


@pytest.mark.parametrize(
    "handler",
    [
        lambda request: httpx.Response(401, text=f"bad key {KEY} upstream secret"),
        lambda request: httpx.Response(500, text="upstream exploded"),
        lambda request: httpx.Response(200, text="not json upstream"),
        lambda request: httpx.Response(200, json={"nope": 1}),
        lambda request: (_ for _ in ()).throw(httpx.ConnectTimeout("timed out upstream")),
    ],
)
def test_upstream_failures_become_plain_503(handler, caplog):
    with configured_client(handler) as client:
        response = client.post("/api/voice/token", json={"voice_consent": True})
    assert response.status_code == 503
    assert response.json()["code"] == "voice_unavailable"
    assert response.json()["message"] == PLAIN
    for leaked in (KEY, "upstream", UPSTREAM_TOKEN):
        assert leaked not in response.text
        assert leaked not in caplog.text


@pytest.mark.parametrize(
    "first",
    [
        httpx.ConnectTimeout("slow venue network"),
        httpx.ConnectError("connection reset"),
        httpx.Response(503, text="busy"),
    ],
)
def test_one_transient_failure_is_retried(first):
    calls = []

    def handler(request):
        calls.append(request)
        if len(calls) == 1:
            if isinstance(first, Exception):
                raise first
            return first
        return httpx.Response(200, json={"token": UPSTREAM_TOKEN})

    with configured_client(handler) as client:
        response = client.post("/api/voice/token", json={"voice_consent": True})
    assert response.status_code == 200
    assert response.json()["token"] == UPSTREAM_TOKEN
    assert len(calls) == 2


def test_client_errors_are_not_retried():
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(401, text="bad key")

    with configured_client(handler) as client:
        response = client.post("/api/voice/token", json={"voice_consent": True})
    assert response.status_code == 503
    assert len(calls) == 1


def test_response_and_request_match_contract_schemas():
    from pathlib import Path

    root = Path(__file__).resolve().parents[2] / "contracts"
    request_schema = Draft202012Validator(
        json.loads((root / "voice.token.request.schema.json").read_text())
    )
    response_schema = Draft202012Validator(
        json.loads((root / "voice.token.schema.json").read_text())
    )
    assert request_schema.is_valid({"voice_consent": True})
    assert not request_schema.is_valid({"voice_consent": False})
    with configured_client(ok_handler([])) as client:
        body = client.post("/api/voice/token", json={"voice_consent": True}).json()
    assert response_schema.is_valid(body)


def test_ttl_and_speed_bounds():
    for bad in ({"cartesia_token_ttl_seconds": 59}, {"cartesia_tts_speed": 1.6}):
        with pytest.raises(ValueError):
            settings(**bad)
