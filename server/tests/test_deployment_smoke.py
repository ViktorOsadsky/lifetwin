"""Deployment checks must detect routing/model/consent faults without exposing data."""

import importlib.util
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "deployment_smoke.py"
spec = importlib.util.spec_from_file_location("deployment_smoke", SCRIPT)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


@pytest.mark.parametrize("configured", [False, True])
def test_full_real_api_smoke_never_calls_a_provider_or_mints_a_token(monkeypatch, configured):
    async def unexpected_provider_request(*args, **kwargs):
        pytest.fail("Smoke checks without explicit live opt-in contacted a provider")

    monkeypatch.setattr(httpx.AsyncClient, "send", unexpected_provider_request)
    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            openai_api_key="",
            openai_model="",
            anthropic_api_key="synthetic-test-key" if configured else "",
            llm_api_key="",
            tavily_api_key="",
            cartesia_api_key="synthetic-test-key" if configured else "",
            cartesia_voice_id="synthetic-test-voice" if configured else "",
            rate_limit_per_minute=1000,
        )
    )
    calls = []
    original = app.state.voice_service.mint_token

    async def unexpected_token_mint():
        calls.append("mint")
        return await original()

    app.state.voice_service.mint_token = unexpected_token_mint
    with TestClient(app) as client:
        checks = smoke.run_checks(client, "http://testserver", require_providers=configured)
    assert len(checks) == 11
    assert "documents-extract-visit-summary" in checks
    assert calls == []


def test_live_voice_failure_does_not_fall_back_to_a_pass_or_log_provider_body(capsys):
    def respond(request):
        return httpx.Response(503, json={"detail": "secret-provider-value"})

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        with pytest.raises(smoke.SmokeFailure, match="unexpected HTTP 503") as exc:
            smoke.request_json(
                client,
                "https://example.test",
                "voice token mint",
                "POST",
                "/api/voice/token",
                payload={"voice_consent": True},
            )
    assert "secret-provider-value" not in str(exc.value)
    assert capsys.readouterr().out == ""


def test_redirect_does_not_send_gateway_credentials_to_a_different_host():
    seen = []

    def respond(request):
        seen.append(request)
        return httpx.Response(302, headers={"location": "https://other.test"})

    with httpx.Client(
        transport=httpx.MockTransport(respond),
        headers=smoke.auth_headers("a.b.c"),
        follow_redirects=False,
    ) as client:
        with pytest.raises(smoke.SmokeFailure, match="unexpected HTTP 302"):
            smoke.request_json(client, "https://example.test", "health", "GET", "/health")
    assert len(seen) == 1
    assert seen[0].url.host == "example.test"


@pytest.mark.parametrize(
    "value",
    [
        "http://remote.test",
        "https://u:password@example.test",
        "https://example.test?key=secret",
        "https://example.test#fragment",
        "https://example.test:bad",
        "not-a-url",
    ],
)
def test_unsafe_or_credential_bearing_target_is_rejected_without_echo(value):
    with pytest.raises(smoke.SmokeFailure) as exc:
        smoke.validate_base_url(value)
    assert value not in str(exc.value)
    assert "password" not in str(exc.value)
    assert "secret" not in str(exc.value)


def test_legacy_anon_jwt_and_publishable_key_are_distinguished():
    assert smoke.auth_headers("a.b.c") == {"apikey": "a.b.c", "Authorization": "Bearer a.b.c"}
    assert smoke.auth_headers("sb_publishable_fake") == {"apikey": "sb_publishable_fake"}
    assert smoke.auth_headers(gateway_token="gateway-fake") == {
        "X-LifeTwin-Gateway-Token": "gateway-fake"
    }


def test_cli_failure_never_prints_key_response_or_url_credentials(monkeypatch, capsys):
    monkeypatch.setenv("SUPABASE_ANON_KEY", "secret-public-key")
    assert smoke.main(["--base-url", "https://u:secret-password@example.test"]) == 1
    output = capsys.readouterr().out
    assert "FAIL deployment smoke" in output
    assert "secret" not in output


def test_deferred_prediction_needs_explicit_opt_in_and_never_claims_a_model(tmp_path):
    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            model_artifact_path=str(tmp_path),
            openai_api_key="",
            anthropic_api_key="",
            llm_api_key="",
            cartesia_api_key="",
            rate_limit_per_minute=1000,
        )
    )
    with TestClient(app) as client:
        with pytest.raises(smoke.SmokeFailure, match="prediction readiness"):
            smoke.run_checks(client, "http://testserver")
        checks = smoke.run_checks(client, "http://testserver", allow_deferred_prediction=True)
    assert len(checks) == 11
    assert any("explicitly deferred" in check for check in checks)
    assert sum("correctly unavailable (501)" in check for check in checks) == 2
    assert not any("packaged prediction model" in check for check in checks)
