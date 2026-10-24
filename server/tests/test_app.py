import asyncio
import json

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from pydantic import ValidationError

from lifetwin.app import create_app
from lifetwin.core.config import Settings


def config(**overrides):
    return Settings(
        _env_file=None,
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        **overrides,
    )


@pytest.fixture
def client():
    with TestClient(create_app(config())) as instance:
        yield instance


def test_keyless_mascot_plan_and_quiz_work_without_external_calls(client, monkeypatch):
    async def forbidden(*args, **kwargs):
        raise AssertionError("Blank credentials must never contact a provider")

    monkeypatch.setattr(httpx.AsyncClient, "send", forbidden)
    response = client.post("/api/onboarding/turn", json={"action": "start"})
    assert response.status_code == 200
    turn = response.json()
    assert turn["guide_mode"] == "guided"
    assert turn["state"]["current_field"] == "age"
    response = client.post(
        "/api/onboarding/turn",
        json={
            "action": "reply",
            "state": turn["state"],
            "text": "I'm 35",
        },
    )
    assert response.status_code == 200
    pending = response.json()
    assert pending["state"]["pending_profile"]["age"] == 35
    assert pending["state"]["confirmed_profile"]["age"] is None
    confirmed = client.post(
        "/api/onboarding/turn",
        json={
            "action": "confirm",
            "state": pending["state"],
        },
    ).json()
    assert confirmed["state"]["confirmed_profile"]["age"] == 35
    profile = confirmed["state"]["confirmed_profile"]
    plan = client.post(
        "/api/advisor",
        json={
            "profile": profile,
            "topics": ["sleep", "nutrition"],
            "use_web_research": True,
        },
    )
    assert plan.status_code == 200
    assert plan.json()["research"]["status"] == "unconfigured"
    assert all(action["modeled_effect"] is None for action in plan.json()["actions"])
    quiz = client.get("/api/quiz/questions")
    assert quiz.status_code == 200
    assert quiz.json()["local_scoring"]["affects_prediction"] is False
    assert confirmed["state"]["confirmed_profile"] == profile


@pytest.mark.parametrize(
    "path,payload",
    [
        ("/api/predict", {"age": 35}),
        ("/api/compare", {"baseline": {"age": 35}, "scenario": {"age": 35, "sleep_hours": 8}}),
        ("/api/sensitivity", {"profile": {"age": 35}}),
    ],
)
def test_every_prediction_dependent_route_is_explicitly_unimplemented(client, path, payload):
    response = client.post(path, json=payload)
    assert response.status_code == 501
    body = response.json()
    assert body["status"] == "not_implemented"
    assert body["prediction"] is None
    assert body["model_version"] is None
    assert "survival_curve" not in body
    assert "death_date" not in body


def test_invalid_input_and_errors_never_echo_sensitive_values(client, caplog):
    secret_text = "health transcript that must not appear in logs"
    response = client.post("/api/predict", json={"age": secret_text})
    assert response.status_code == 422
    assert response.json()["code"] == "invalid_request"
    assert secret_text not in response.text
    assert secret_text not in caplog.text
    assert response.json()["request_id"] == response.headers["x-request-id"]
    assert response.headers["cache-control"] == "no-store"
    assert client.get("/missing").json()["code"] == "not_found"


def test_no_model_artifact_is_loaded_and_secrets_are_not_exposed():
    settings = config(model_artifact_path="/does/not/exist/model.joblib")
    with TestClient(create_app(settings)) as client:
        assert client.get("/ready").json()["prediction"] == "not_implemented"
        capabilities = client.get("/api/capabilities").json()
        assert capabilities["llm_configured"] is False
        assert capabilities["web_research_configured"] is False
        assert capabilities["health_data_storage"] == "none"
        assert "api_key" not in json.dumps(capabilities)
    assert "private-test-value" not in repr(Settings(openai_api_key="private-test-value"))


def test_body_limit_and_rate_limit_leave_health_probe_available():
    with TestClient(create_app(config(max_body_bytes=128, rate_limit_per_minute=2))) as client:
        response = client.post("/api/onboarding/turn", json={"action": "reply", "text": "a" * 200})
        assert response.status_code == 413
        assert client.get("/api/capabilities").status_code == 200
        limited = client.get("/api/capabilities")
        assert limited.status_code == 429
        assert limited.json()["code"] == "rate_limit_exceeded"
        assert limited.headers["retry-after"] == "60"
        assert client.get("/health").status_code == 200


@pytest.mark.asyncio
async def test_chunked_body_cannot_bypass_limit_with_small_declared_length():
    application = create_app(config(max_body_bytes=128))

    async def chunks():
        yield b'{"age":'
        yield b" " * 200
        yield b"35}"

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url="http://test"
    ) as client:
        response = await client.post(
            "/api/predict", content=chunks(), headers={"Content-Length": "1"}
        )
        assert response.status_code == 413


@pytest.mark.asyncio
async def test_concurrency_limit_does_not_block_health_or_leak_active_slots():
    application = create_app(config(max_concurrent_requests=1))
    entered, release = asyncio.Event(), asyncio.Event()

    @application.get("/slow")
    async def slow():
        entered.set()
        await release.wait()
        return {"ok": True}

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url="http://test"
    ) as client:
        first = asyncio.create_task(client.get("/slow"))
        await asyncio.wait_for(entered.wait(), timeout=1)
        try:
            assert (await client.get("/api/capabilities")).status_code == 429
            assert (await client.get("/health")).status_code == 200
        finally:
            release.set()
        assert (await first).status_code == 200
        assert (await client.get("/api/capabilities")).status_code == 200


@pytest.mark.asyncio
async def test_timeout_cancels_work_and_recovers_request_capacity():
    application = create_app(config(request_timeout_seconds=0.01, max_concurrent_requests=1))
    cancelled = asyncio.Event()

    @application.get("/slow")
    async def slow():
        try:
            await asyncio.sleep(10)
        finally:
            cancelled.set()

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url="http://test"
    ) as client:
        response = await client.get("/slow")
        assert response.status_code == 504
        assert response.json()["code"] == "request_timeout"
        assert cancelled.is_set()
        assert (await client.get("/api/capabilities")).status_code == 200


@pytest.mark.asyncio
async def test_unexpected_exception_is_redacted():
    application = create_app(config())

    @application.get("/broken")
    async def broken():
        raise RuntimeError("private provider key and sensitive health data")

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url="http://test"
    ) as client:
        response = await client.get("/broken")
        assert response.status_code == 500
        assert response.json()["code"] == "internal_error"
        assert "private" not in response.text


def test_cors_uses_only_explicit_origins():
    with pytest.raises(ValidationError):
        config(cors_origins="*")
    with TestClient(create_app(config(cors_origins="https://demo.example"))) as client:
        allowed = client.options(
            "/api/onboarding/turn",
            headers={
                "Origin": "https://demo.example",
                "Access-Control-Request-Method": "POST",
            },
        )
        assert allowed.headers["access-control-allow-origin"] == "https://demo.example"
        blocked = client.options(
            "/api/onboarding/turn",
            headers={
                "Origin": "https://other.example",
                "Access-Control-Request-Method": "POST",
            },
        )
        assert "access-control-allow-origin" not in blocked.headers


@pytest.mark.parametrize(
    "origin",
    [
        "https://example.org:bad",
        "https://example.org:99999",
        "http://example.org:0",
        "https://exa\tmple.org",
        "https://example.org\n",
        "https://example.org/#",
        "https://example.org?",
        "https://user:password@example.org",
        "https://@example.org",
        "https://:@example.org",
        "https://example.org/path",
    ],
)
def test_cors_rejects_invalid_ports_and_non_origin_components(origin):
    with pytest.raises(ValidationError):
        config(cors_origins=origin)


def test_cors_canonicalizes_case_ports_idn_and_duplicates():
    settings = config(
        cors_origins=" https://EXAMPLE.org:443/,https://example.org,http://[::1]:8000,https://bücher.example "
    )
    assert settings.allowed_origins == [
        "https://example.org",
        "http://[::1]:8000",
        "https://xn--bcher-kva.example",
    ]
    with TestClient(create_app(settings)) as client:
        response = client.options(
            "/api/onboarding/turn",
            headers={
                "Origin": "https://example.org",
                "Access-Control-Request-Method": "POST",
            },
        )
        assert response.headers["access-control-allow-origin"] == "https://example.org"


def test_openapi_error_contract_matches_actual_redacted_bodies(client):
    spec = client.get("/openapi.json").json()
    operation = spec["paths"]["/api/onboarding/turn"]["post"]
    for payload, status in [({"action": "reply", "text": " "}, 422), ({"action": "confirm"}, 409)]:
        response = client.post("/api/onboarding/turn", json=payload)
        assert response.status_code == status
        schema = operation["responses"][str(status)]["content"]["application/json"]["schema"]
        assert schema["$ref"] == "#/components/schemas/ApiError"
        Draft202012Validator({**schema, "components": spec["components"]}).validate(response.json())


def test_http_error_handler_preserves_protocol_headers(client):
    response = client.get("/api/onboarding/turn")
    assert response.status_code == 405
    assert response.headers["allow"] == "POST"
    assert response.json()["status"] == "error"


@pytest.mark.asyncio
async def test_disconnect_after_body_cancels_research_and_releases_slot():
    application = create_app(config(max_concurrent_requests=1))
    entered, disconnected, cancelled = asyncio.Event(), asyncio.Event(), asyncio.Event()

    class SlowResearch:
        async def research(self, topics):
            entered.set()
            try:
                await asyncio.sleep(10)
            finally:
                cancelled.set()

    application.state.research_client = SlowResearch()
    delivered = False
    sent = []

    async def receive():
        nonlocal delivered
        if not delivered:
            delivered = True
            return {
                "type": "http.request",
                "more_body": False,
                "body": b'{"topics":["sleep"],"use_web_research":true}',
            }
        await disconnected.wait()
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": "/api/advisor",
        "raw_path": b"/api/advisor",
        "query_string": b"",
        "headers": [(b"content-type", b"application/json")],
        "server": ("test", 80),
        "client": ("127.0.0.1", 5555),
        "root_path": "",
    }
    request = asyncio.create_task(application(scope, receive, send))
    await asyncio.wait_for(entered.wait(), timeout=1)
    disconnected.set()
    await asyncio.wait_for(request, timeout=1)
    assert cancelled.is_set()
    assert not sent
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url="http://test"
    ) as client:
        assert (await client.get("/api/capabilities")).status_code == 200
