"""Check a deployed full API using synthetic fixtures, without logging response bodies.

Run with the locked development environment (httpx and jsonschema required):
  uv run python scripts/deployment_smoke.py --base-url https://example/functions/v1/lifetwin

SUPABASE_ANON_KEY optionally supplies the public gateway key; actual provider keys
stay on the server. --verify-voice explicitly mints one short-lived Cartesia token,
validates it in memory and discards it. This does not verify audio playback.
"""

import argparse
import json
import os
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "contracts" / "fixtures" / "cases.json"
# These routes work with configured providers while making no outside-AI call.
SMOKE_CASES = (
    "prediction-supported",
    "prediction-unsupported-age",
    "quiz-bank",
    "mascot-start",
    "checkin-daily-start",
    "documents-extract-visit-summary",
    "voice-token-consent-missing",
    "predict-invalid-units",
)


class SmokeFailure(Exception):
    """Only fixed check names/statuses may enter this exception's message."""


def require(condition: bool, label: str) -> None:
    if not condition:
        raise SmokeFailure(f"{label}: check failed")


def validate_base_url(value: str) -> str:
    try:
        url = urlsplit(value)
        # Reading port also rejects malformed/non-numeric values.
        _ = url.port
    except ValueError:
        raise SmokeFailure("base URL: invalid URL") from None
    local = url.hostname in {"localhost", "127.0.0.1", "::1"}
    require(
        bool(url.hostname)
        and (url.scheme == "https" or (local and url.scheme == "http"))
        and url.username is None
        and url.password is None
        and not url.query
        and not url.fragment,
        "base URL",
    )
    return value.rstrip("/")


def auth_headers(anon_key: str = "", gateway_token: str = "") -> dict[str, str]:
    headers = {}
    if anon_key:
        headers["apikey"] = anon_key
        # verify_jwt gateways require a legacy anon JWT. Publishable keys can be
        # used with the gateway's own validation, but are not JWT bearer tokens.
        if anon_key.count(".") == 2:
            headers["Authorization"] = f"Bearer {anon_key}"
    if gateway_token:
        headers["X-LifeTwin-Gateway-Token"] = gateway_token
    return headers


def request_json(
    client: httpx.Client,
    base_url: str,
    label: str,
    method: str,
    path: str,
    *,
    expected_status: int = 200,
    payload: dict | None = None,
) -> dict:
    try:
        response = client.request(
            method, base_url + path, **({"json": payload} if payload is not None else {})
        )
    except httpx.HTTPError:
        raise SmokeFailure(f"{label}: network request failed") from None
    if response.status_code != expected_status:
        raise SmokeFailure(f"{label}: unexpected HTTP {response.status_code}")
    try:
        body = response.json()
    except ValueError:
        raise SmokeFailure(f"{label}: invalid JSON response") from None
    require(isinstance(body, dict), label)
    require("no-store" in response.headers.get("cache-control", ""), f"{label} cache policy")
    return body


def validate_schema(body: dict, schema_name: str, label: str) -> None:
    schema = json.loads((ROOT / "contracts" / schema_name).read_text())
    # is_valid avoids jsonschema exceptions whose strings include the instance.
    require(
        Draft202012Validator(schema, format_checker=FormatChecker()).is_valid(body),
        f"{label} response schema",
    )


def run_checks(
    client: httpx.Client,
    base_url: str,
    *,
    verify_voice: bool = False,
    require_providers: bool = False,
    allow_deferred_prediction: bool = False,
) -> list[str]:
    """Return check names only; never return a profile, response, token or key."""
    checks = []
    health = request_json(client, base_url, "health", "GET", "/health")
    require(health == {"status": "ok", "service": "lifetwin-backend"}, "health identity")
    checks.append("health")
    ready = request_json(client, base_url, "readiness", "GET", "/ready")
    require(ready.get("status") == "ready", "readiness")
    prediction_state = "not_implemented" if allow_deferred_prediction else "available"
    require(ready.get("prediction") == prediction_state, "prediction readiness")
    checks.append(
        "readiness; server prediction explicitly deferred"
        if allow_deferred_prediction
        else "readiness and packaged prediction model"
    )
    caps = request_json(client, base_url, "capabilities", "GET", "/api/capabilities")
    require(caps.get("health_data_storage") == "none", "stateless health boundary")
    require(caps.get("prediction") == prediction_state, "prediction capability")
    documents = caps.get("documents")
    require(
        documents == "text_extraction"
        or (isinstance(documents, dict) and documents.get("text_extraction") is True),
        "document capability",
    )
    if require_providers:
        require(caps.get("llm_configured") is True, "configured intake provider")
        require(caps.get("personalize", {}).get("configured") is True, "configured personalizer")
        require(caps.get("voice") == "available", "configured voice provider")
    checks.append("capabilities")
    cases = {case["name"]: case for case in json.loads(FIXTURES.read_text())}
    for label in SMOKE_CASES:
        case = cases[label]
        deferred = (
            allow_deferred_prediction and case["path"] == "/api/predict" and case["status"] == 200
        )
        body = request_json(
            client,
            base_url,
            label,
            case["method"],
            case["path"],
            expected_status=501 if deferred else case["status"],
            payload=case.get("request"),
        )
        validate_schema(body, "compare.schema.json" if deferred else case["response_schema"], label)
        if deferred:
            require(body["status"] == "not_implemented", "deferred prediction status")
            require(
                body["prediction"] is None and body["model_version"] is None,
                "no invented prediction",
            )
        elif label == "prediction-supported":
            require(body["status"] == "supported" and bool(body["survival"]), label)
            values = [point["survival"] for point in body["curve"]]
            require(bool(values) and values == sorted(values, reverse=True), "monotone curve")
            require(all(p["years"] <= body["max_horizon_years"] for p in body["curve"]), label)
        elif label == "prediction-unsupported-age":
            require(
                body["status"] == "unsupported" and not body["survival"] and not body["curve"],
                label,
            )
        elif label == "quiz-bank":
            scoring = body["local_scoring"]
            require(scoring["state_scope"] == "game_health_only", label)
            require(scoring["affects_confirmed_profile"] is False, label)
            require(scoring["affects_prediction"] is False, label)
        elif label == "documents-extract-visit-summary":
            require(body["status"] == "found" and bool(body["candidates"]), label)
            require(body["provider_status"] == "not_requested", label)
            require(all(c["method"] == "parser" for c in body["candidates"]), label)
        elif label in {"mascot-start", "checkin-daily-start"}:
            require(body["complete"] is False and body["guide_mode"] == "guided", label)
        checks.append(f"{label}: correctly unavailable (501)" if deferred else label)
    if verify_voice:
        body = request_json(
            client,
            base_url,
            "voice token mint",
            "POST",
            "/api/voice/token",
            payload={"voice_consent": True},
        )
        validate_schema(body, "voice.token.schema.json", "voice token mint")
        require(bool(body["token"].strip()), "voice token mint")
        # Deliberately omit the token, its length, model IDs and voice ID from results.
        del body
        checks.append("live voice token mint (audio playback unverified)")
    return checks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--supabase-anon-key-env", default="SUPABASE_ANON_KEY")
    parser.add_argument("--gateway-token-env", default="LIFETWIN_GATEWAY_TOKEN")
    parser.add_argument(
        "--require-providers",
        action="store_true",
        help="Require configured keys; not a live AI test",
    )
    parser.add_argument(
        "--verify-voice", action="store_true", help="Mint and discard one real Cartesia token"
    )
    parser.add_argument(
        "--allow-deferred-prediction",
        action="store_true",
        help="Verify the Edge backend's explicit 501 prediction boundary; no model claim",
    )
    args = parser.parse_args(argv)
    try:
        base_url = validate_base_url(args.base_url)
        headers = auth_headers(
            os.environ.get(args.supabase_anon_key_env, "").strip(),
            os.environ.get(args.gateway_token_env, "").strip(),
        )
        with httpx.Client(
            headers=headers, timeout=30, follow_redirects=False, trust_env=False
        ) as client:
            checks = run_checks(
                client,
                base_url,
                verify_voice=args.verify_voice,
                require_providers=args.require_providers,
                allow_deferred_prediction=args.allow_deferred_prediction,
            )
    except SmokeFailure as exc:
        # SmokeFailure messages contain fixed check labels/statuses, never input.
        print(f"FAIL deployment smoke: {exc}")
        return 1
    except (ValueError, OSError):
        # Never print an unexpected exception: transports/JSON can embed key/body data.
        print("FAIL deployment smoke checks; no response bodies or credentials were logged.")
        return 1
    for check in checks:
        print(f"PASS {check}")
    print(f"Validated {len(checks)} deployed API checks using synthetic fixtures.")
    if not args.verify_voice:
        print("Live provider requests were not tested.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
