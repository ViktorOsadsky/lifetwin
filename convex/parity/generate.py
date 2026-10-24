"""Generate FastAPI reference fixtures for the Convex port's differential tests.

Run from the repository root:

    uv run python convex/parity/generate.py [--server-root PATH]

It runs the existing Python suite in-process (unchanged) while recording

* every HTTP request the tests send through TestClient, and
* every call into the onboarding parser (parse_value, parse_reply, clarify,
  is_skip, grounded_candidates, describe),

then replays the recorded HTTP requests, plus the crafted edge cases below,
against a fresh keyless FastAPI app and stores status, selected headers and the
exact response body. The parser texts are also crossed with every field. The
Convex vitest suite replays the same inputs and requires identical output.

Nothing here changes server/. ``--server-root`` points at another checkout of
server/ (for example a PR branch extracted with ``git archive``) so the fixture
can follow intake changes before they merge.
"""

import argparse
import base64
import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "convex" / "tests" / "fixtures" / "parity.json"
OPENAPI_OUT = REPO / "convex" / "convex" / "content" / "openapi.ts"
FIELDS = [
    "age",
    "sex",
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "smoking_status",
    "alcohol_drinks_weekly",
    "diabetes",
    "systolic_bp",
    "diastolic_bp",
]
REQUEST_ID = re.compile(r'"request_id":"[0-9a-f]{32}"')

# Older-adult and edge answers the lead asked for explicitly, plus words that
# exercise the PR #18 phrase normalization. They are crossed with every field.
EXTRA_TEXTS = [
    "5'10",
    "5'10\"",
    "5’10”",
    "5 foot 8",
    "five foot eight",
    "5 feet, 10 inches",
    "5 ft 10 in",
    "6 feet",
    "5'13",
    "70 inches",
    "178 cm",
    "1.78 m",
    "about 170",
    "around 170 pounds",
    "160",
    "160 pounds",
    "a hundred and seventy pounds",
    "two hundred pounds",
    "I weigh 70",
    "I weigh 70 kg",
    "I weighed 200 pounds ten years ago",
    "120 over 80",
    "120/80",
    "80 over 120",
    "one twenty over eighty",
    "my blood pressure is 130 over 85 mmHg",
    "yes",
    "Yes.",
    "yeah",
    "no",
    "no, 36",
    "no it's 150 pounds",
    "nope",
    "I don’t know",
    "I'm not sure",
    "prefer not to say",
    "skip",
    "I'm 72",
    "I’m 72",
    "seventy two",
    "seventy-two years old",
    "oh well I'm 72",
    "um I think I'm 72",
    "I usually sleep 7 hours",
    "I get about 7 hours i think",
    "seven and a half hours",
    "7 and a half hours",
    "half an hour a day 5 days a week",
    "30 minutes a day",
    "30 minutes a day, 5 days a week",
    "two hours of walking a week",
    "I walk 150 minutes a week",
    "3 hours a week",
    "5",
    "I quit smoking back in 1990",
    "I stopped smoking years ago",
    "I gave up",
    "I used to smoke",
    "I never smoked",
    "maybe a glass of wine",
    "I have 3 drinks a week",
    "none",
    "I don't drink",
    "I have diabetes",
    "I don't have diabetes",
    "a woman",
    "female",
    "male",
    "age: 40; weight: 154 pounds; height: 1.75 m",
    "weight: 70 kg and 80 kg",
    "if I weighed 70 kg",
    "-5 kg",
    "7000 kg",
    "999999999 kg",
    "٣٥",
    "٣٥ years",
    "café 70 kg",
    "70 kg",
    "",
    "   ",
]

# Crafted HTTP edge cases (method, path, body text or None, content type).
J = "application/json"
EXTRA_HTTP = [
    ("GET", "/health", None, None),
    ("GET", "/ready", None, None),
    ("GET", "/api/capabilities", None, None),
    ("GET", "/nope", None, None),
    ("POST", "/nope", "{}", J),
    ("GET", "/api/onboarding/turn", None, None),
    ("GET", "/api/advisor", None, None),
    ("POST", "/api/quiz/questions", "{}", J),
    ("POST", "/api/predict", None, None),
    ("POST", "/api/predict", "", J),
    ("POST", "/api/predict", "not json", J),
    ("POST", "/api/predict", "[]", J),
    ("POST", "/api/predict", '"text"', J),
    ("POST", "/api/predict", "null", J),
    ("POST", "/api/predict", "{}", J),
    ("POST", "/api/predict", "{}", "text/plain"),
    ("POST", "/api/predict", "{}", "application/merge-patch+json"),
    ("POST", "/api/predict", '{"age": 35.0}', J),
    ("POST", "/api/predict", '{"age": 35.5}', J),
    ("POST", "/api/predict", '{"age": "35"}', J),
    ("POST", "/api/predict", '{"age": true}', J),
    ("POST", "/api/predict", '{"age": NaN}', J),
    ("POST", "/api/predict", '{"age": 1e400}', J),
    ("POST", "/api/predict", '{"height_cm": 175}', J),
    ("POST", "/api/predict", '{"diabetes": 1}', J),
    ("POST", "/api/predict", '{"sex": "Female"}', J),
    ("POST", "/api/predict", '{"systolic_bp": 80, "diastolic_bp": 120}', J),
    ("POST", "/api/predict", '{"systolic_bp": 80, "diastolic_bp": 120, "age": 500}', J),
    ("POST", "/api/predict", '{"age": 500, "weight_kg": 1, "extra": 1}', J),
    ("POST", "/api/predict", '{"zzz": 1, "age": 500}', J),
    ("POST", "/api/compare", '{"baseline": {}}', J),
    ("POST", "/api/compare", '{"baseline": {"age": 999}, "scenario": {"age": -1}}', J),
    ("POST", "/api/sensitivity", '{"profile": {"sleep_hours": 25}}', J),
    ("POST", "/api/sensitivity", '{"profile": null}', J),
    ("POST", "/api/voice/token", '{"voice_consent": false}', J),
    ("POST", "/api/voice/token", '{"voice_consent": "yes"}', J),
    ("POST", "/api/voice/token", '{"voice_consent": true, "x": 1}', J),
    ("POST", "/api/voice/token", None, None),
    ("POST", "/api/advisor", "{}", J),
    ("POST", "/api/advisor", '{"topics": []}', J),
    ("POST", "/api/advisor", '{"topics": ["sleep", "nutrition", "smoking", "supplements"]}', J),
    ("POST", "/api/advisor", '{"topics": ["astrology"]}', J),
    ("POST", "/api/advisor", '{"topics": ["supplements"], "profile": {"age": 12}}', J),
    ("POST", "/api/advisor", '{"topics": ["smoking"], "profile": {"age": 30}}', J),
    ("POST", "/api/advisor", '{"profile": {"age": 999}, "age": 4}', J),
    ("POST", "/api/advisor", '{"schema_version": "2.0"}', J),
    ("POST", "/api/advisor", '{"use_web_research": 1}', J),
    ("POST", "/api/onboarding/turn", "{}", J),
    ("POST", "/api/onboarding/turn", '{"action": "dance"}', J),
    ("POST", "/api/onboarding/turn", '{"action": "skip", "text": "x"}', J),
    ("POST", "/api/onboarding/turn", '{"action": "start", "field": "age"}', J),
    ("POST", "/api/onboarding/turn", '{"action": "reply", "text": ""}', J),
    ("POST", "/api/onboarding/turn", '{"action": "reply", "text": "' + "x" * 2001 + '"}', J),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "reply", "text": "' + "\U0001f600" * 1500 + '"}',
        J,
    ),
    ("POST", "/api/onboarding/turn", '{"action": "start", "state": {"phase": "asking"}}', J),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "start", "state": {"phase": "ready", "current_field": "age"}}',
        J,
    ),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "start", "state": {"skipped_fields": ["age", "age"]}}',
        J,
    ),
    ("POST", "/api/onboarding/turn", '{"action": "start", "state": {"phase": "confirming"}}', J),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "start", "state": {"confirmed_profile": {"systolic_bp": 80, "diastolic_bp": 90}}}',
        J,
    ),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "start", "state": {"confirmed_profile": {"age": 300}, "pending_profile": {"weight_kg": 1}}}',
        J,
    ),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "start", "input_mode": "audio", "provider_consent": "yes"}',
        J,
    ),
    ("POST", "/api/onboarding/turn", '{"action": "reply", "text": 5}', J),
    ("GET", "/api/quiz/questions?limit=5", None, None),
    ("GET", "/api/quiz/questions?limit=+5", None, None),
    ("GET", "/api/quiz/questions?limit=%205", None, None),
    ("GET", "/api/quiz/questions?limit=5.0", None, None),
    ("GET", "/api/quiz/questions?limit=5.5", None, None),
    ("GET", "/api/quiz/questions?limit=1_0", None, None),
    ("GET", "/api/quiz/questions?limit=05", None, None),
    ("GET", "/api/quiz/questions?limit=1e1", None, None),
    ("GET", "/api/quiz/questions?limit=", None, None),
    ("GET", "/api/quiz/questions?limit=abc", None, None),
    ("GET", "/api/quiz/questions?limit=101", None, None),
    ("GET", "/api/quiz/questions?limit=100", None, None),
    ("GET", "/api/quiz/questions?limit=1&limit=3", None, None),
    ("GET", "/api/quiz/questions?topic=food_safety", None, None),
    ("GET", "/api/quiz/questions?topic=activity&difficulty=moderate", None, None),
    ("GET", "/api/quiz/questions?topic=astrology&difficulty=easy&limit=0", None, None),
    ("GET", "/api/quiz/questions?unknown=1", None, None),
    ("GET", "/api/quiz/questions/SOUP.v2", None, None),
    ("GET", "/api/quiz/questions/ab.v1", None, None),
    ("GET", "/api/quiz/questions/soup-serving-check.v2/extra", None, None),
    ("GET", "/api/quiz/questions/soup-serving-check.v9", None, None),
    ("GET", "/api/quiz/questions/", None, None),
    ("POST", "/api/advisor/", '{"topics": ["sleep"]}', J),
    ("HEAD", "/health", None, None),
    ("HEAD", "/api/capabilities", None, None),
    ("DELETE", "/api/advisor", None, None),
    ("PUT", "/api/onboarding/turn", "{}", J),
    ("POST", "/api/predict", "[" * 970 + "]" * 970, J),
    ("POST", "/api/predict", "[" * 971 + "]" * 971, J),
    ("POST", "/api/predict", "[" * 972 + "]" * 972, J),
    ("POST", "/api/predict", '{"age": 30, "age": 31}', J),
    ("POST", "/api/predict", ' \n{"age": 30}\n ', J),
    ("POST", "/api/predict", '{"age": 30} x', J),
    ("POST", "/api/predict", '{"__proto__": {"age": 1}}', J),
    ("POST", "/api/predict", '{"age": -Infinity}', J),
    (
        "POST",
        "/api/onboarding/turn",
        '{"action": "reply", "state": {"phase": "asking", "current_field": "age"}, "text": "\\ud83d\\ude00 72"}',
        J,
    ),
]

# Bodies that are not valid UTF-8 text: (method, path, bytes, content type).
EXTRA_BINARY = [
    ("POST", "/api/predict", '{"age": 30}'.encode("utf-16"), J),
    ("POST", "/api/predict", '{"age": 30}'.encode("utf-16-le"), J),
    ("POST", "/api/predict", '{"age": 30}'.encode("utf-16-be"), J),
    ("POST", "/api/predict", '{"age": 30}'.encode("utf-32"), J),
    ("POST", "/api/predict", '{"age": 30}'.encode("utf-32-le"), J),
    ("POST", "/api/predict", b"\xef\xbb\xbf" + b'{"age": 30}', J),
    ("POST", "/api/predict", b'{"age": "\xff"}', J),
    ("POST", "/api/predict", b"\xff\xfe\x00", J),
]


def install_recorders(record):
    """Wrap parser functions and TestClient.send before any test module imports them."""
    import starlette.testclient

    import lifetwin.onboarding.parsing as parsing
    import lifetwin.onboarding.service as service

    def wrap(name, encode):
        original = getattr(parsing, name)

        def wrapper(*args):
            result = original(*args)
            try:
                record["parse"].setdefault(name, set()).add(json.dumps(encode(*args)))
            except TypeError:
                pass
            return result

        setattr(parsing, name, wrapper)
        if hasattr(service, name):
            setattr(service, name, wrapper)
        return original

    originals = {}
    originals["parse_value"] = wrap("parse_value", lambda field, text: [field, text])
    originals["parse_reply"] = wrap("parse_reply", lambda text, field: [text, field])
    originals["clarify"] = wrap("clarify", lambda text, field: [text, field])
    originals["is_skip"] = wrap("is_skip", lambda text, field: [text, field])
    originals["grounded_candidates"] = wrap(
        "grounded_candidates",
        lambda text, extraction, asked: [text, extraction.model_dump(mode="json"), asked],
    )
    original_describe = service.describe

    def describe(values):
        record["parse"].setdefault("describe", set()).add(json.dumps(values))
        return original_describe(values)

    service.describe = describe
    originals["describe"] = original_describe

    original_send = starlette.testclient.TestClient.send

    def send(self, request, *args, **kwargs):
        try:
            body = request.content.decode("utf-8")
        except (UnicodeDecodeError, Exception):
            body = None
        if body is not None and len(body) <= 40000:
            target = request.url.raw_path.decode("ascii")
            record["http"].add(
                json.dumps(
                    [request.method, target, body or None, request.headers.get("content-type")]
                )
            )
        return original_send(self, request, *args, **kwargs)

    starlette.testclient.TestClient.send = send
    return originals, (starlette.testclient.TestClient, original_send)


def _mask(text):
    return REQUEST_ID.sub('"request_id":"<id>"', text)


def provider_cases():
    """Configured-provider paths with mock upstreams: exact outbound requests and responses."""
    import httpx
    from fastapi.testclient import TestClient

    from lifetwin.app import create_app
    from lifetwin.core.config import Settings
    from lifetwin.onboarding import ChatCompletionsExtractor, ConversationService
    from lifetwin.research.tavily import TavilyResearch
    from lifetwin.voice import VoiceService

    def upstream(request):
        return {
            "method": request.method,
            "url": str(request.url),
            "authorization": request.headers.get("authorization"),
            "cartesia_version": request.headers.get("cartesia-version"),
            "json": json.loads(request.content) if request.content else None,
        }

    def chat(content, finish="stop", extra=None):
        message = {"role": "assistant", "content": content, **(extra or {})}
        return json.dumps({"choices": [{"index": 0, "message": message, "finish_reason": finish}]})

    good = json.dumps({"candidates": [{"field": "weight_kg", "quote": "70 kg"}]})
    wrong = json.dumps({"candidates": [{"field": "weight_kg", "quote": "80 kg"}]})
    foreign = json.dumps({"candidates": [{"field": "systolic_bp", "quote": "160"}]})
    invalid = json.dumps({"candidates": [{"field": "bmi", "quote": "70 kg"}]})
    reply = "I think I'm 70 kg"
    # The local parser cannot read this, but the grounded quote can (it may
    # drop "current"), so this is the successful helper path.
    grounded = "My current weight is 70 kg"
    llm_scenarios = [
        ("good-extraction", 200, chat(good), grounded, "weight_kg", "minimal"),
        ("good-extraction-no-effort", 200, chat(good), grounded, "weight_kg", ""),
        ("answered-but-locally-unparsed", 200, chat(good), reply, "weight_kg", "minimal"),
        ("ungrounded-quote", 200, chat(wrong), reply, "weight_kg", "minimal"),
        (
            "empty-candidates",
            200,
            chat(json.dumps({"candidates": []})),
            "hmm let me see",
            "age",
            "low",
        ),
        ("foreign-field-without-cue", 200, chat(foreign), "maybe 160", "weight_kg", "minimal"),
        ("http-500", 500, "upstream failure sk-secret", reply, "weight_kg", "minimal"),
        ("not-json", 200, "not json", reply, "weight_kg", "minimal"),
        ("truncated", 200, chat(None, finish="length"), reply, "weight_kg", "minimal"),
        ("refusal", 200, chat(good, extra={"refusal": "no"}), reply, "weight_kg", "minimal"),
        ("schema-invalid", 200, chat(invalid), reply, "weight_kg", "minimal"),
        ("two-choices", 200, json.dumps({"choices": [{}, {}]}), reply, "weight_kg", "minimal"),
        ("deep-json", 200, "[" * 5000 + "]" * 5000, reply, "weight_kg", "minimal"),
        ("oversized", 200, chat("x" * 70000), reply, "weight_kg", "minimal"),
    ]
    llm = []
    for name, status, body, text, field, effort in llm_scenarios:
        seen = []

        def handler(request, status=status, body=body, seen=seen):
            seen.append(upstream(request))
            return httpx.Response(status, content=body.encode("utf-8"))

        app = create_app(Settings(_env_file=None, app_env="test", API_RATE_LIMIT_PER_MINUTE=10000))
        app.state.conversation_service = ConversationService(
            extractor=ChatCompletionsExtractor(
                base_url="https://llm.example/v1/",
                api_key="test-llm-key",
                model="muse-test",
                reasoning_effort=effort,
                timeout_seconds=12,
                client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
            ),
            timeout_seconds=12,
        )
        state = {"phase": "asking", "current_field": field}
        rows = []
        with TestClient(app) as client:
            for consent in (True, False):
                request = {
                    "action": "reply",
                    "state": state,
                    "text": text,
                    "provider_consent": consent,
                }
                response = client.post("/api/onboarding/turn", json=request)
                rows.append(
                    {
                        "request": request,
                        "status": response.status_code,
                        "response": _mask(response.text),
                    }
                )
        llm.append(
            {
                "name": name,
                "effort": effort,
                "upstream_status": status,
                "upstream_body": body,
                "turns": rows,
                "upstream_requests": seen,
            }
        )

    def tavily_body(urls, failed=()):
        return json.dumps(
            {
                "results": [
                    {"url": url, "raw_content": "Reviewed public health page text."} for url in urls
                ],
                "failed_results": [{"url": url, "error": "x"} for url in failed],
            }
        )

    sleep = "https://www.cdc.gov/sleep/about/"
    food = "https://www.cdc.gov/nutrition/features/healthy-eating-tips.html"
    tavily_scenarios = [
        ("retrieved", 200, tavily_body([sleep + "index.html", food])),
        ("partial", 200, tavily_body([sleep], failed=[food])),
        ("unreviewed-url", 200, tavily_body(["https://evil.example/sleep/about/", sleep + "?x=1"])),
        ("short-content", 200, json.dumps({"results": [{"url": sleep, "raw_content": "tiny"}]})),
        ("http-429", 429, "slow down"),
        ("malformed", 200, json.dumps({"results": "nope"})),
        ("too-many-rows", 200, tavily_body([sleep] * 6)),
        ("redirect", 302, ""),
    ]
    tavily = []
    for name, status, body in tavily_scenarios:
        seen = []

        def handler(request, status=status, body=body, seen=seen):
            seen.append(upstream(request))
            return httpx.Response(
                status,
                content=body.encode("utf-8"),
                headers={"location": "https://elsewhere.example/"},
            )

        app = create_app(Settings(_env_file=None, app_env="test", API_RATE_LIMIT_PER_MINUTE=10000))
        app.state.research_client = TavilyResearch(
            api_key="tvly-test-key", transport=httpx.MockTransport(handler), timeout_seconds=12
        )
        request = {"topics": ["sleep", "nutrition"], "use_web_research": True}
        with TestClient(app) as client:
            response = client.post("/api/advisor", json=request)
        tavily.append(
            {
                "name": name,
                "upstream_status": status,
                "upstream_body": body,
                "request": request,
                "status": response.status_code,
                "response": _mask(response.text),
                "upstream_requests": seen,
            }
        )

    voice_scenarios = [
        ("success", 200, json.dumps({"token": "short-lived-token"})),
        ("empty-token", 200, json.dumps({"token": ""})),
        ("http-401", 401, json.dumps({"error": "bad key sk_car_test"})),
        ("not-json", 200, "nope"),
    ]
    voice = []
    for name, status, body in voice_scenarios:
        seen = []

        def handler(request, status=status, body=body, seen=seen):
            seen.append(upstream(request))
            return httpx.Response(status, content=body.encode("utf-8"))

        settings = Settings(
            _env_file=None,
            app_env="test",
            API_RATE_LIMIT_PER_MINUTE=10000,
            cartesia_api_key="sk_car_test",
            cartesia_voice_id="voice-123",
            cartesia_tts_speed=1.0,
        )
        app = create_app(settings)
        app.state.voice_service = VoiceService(settings, transport=httpx.MockTransport(handler))
        with TestClient(app) as client:
            response = client.post("/api/voice/token", json={"voice_consent": True})
            capabilities = client.get("/api/capabilities").text
        voice.append(
            {
                "name": name,
                "upstream_status": status,
                "upstream_body": body,
                "status": response.status_code,
                "response": _mask(response.text),
                "upstream_requests": seen,
                "capabilities": capabilities,
            }
        )
    return {"llm": llm, "tavily": tavily, "voice": voice}


def cors_cases():
    from fastapi.testclient import TestClient

    from lifetwin.app import create_app
    from lifetwin.core.config import Settings

    origins = "https://App.Example, http://localhost:5173,https://app.example:443"
    app = create_app(
        Settings(
            _env_file=None, app_env="test", API_RATE_LIMIT_PER_MINUTE=10000, cors_origins=origins
        )
    )
    allowed = "https://app.example"
    preflight = {"origin": allowed, "access-control-request-method": "POST"}
    scenarios = [
        ("OPTIONS", "/api/onboarding/turn", preflight),
        (
            "OPTIONS",
            "/api/onboarding/turn",
            {**preflight, "access-control-request-headers": "content-type"},
        ),
        ("OPTIONS", "/api/onboarding/turn", {**preflight, "access-control-request-method": "PUT"}),
        (
            "OPTIONS",
            "/api/onboarding/turn",
            {**preflight, "access-control-request-headers": "x-api-key"},
        ),
        ("OPTIONS", "/api/onboarding/turn", {**preflight, "origin": "https://evil.example"}),
        (
            "OPTIONS",
            "/nowhere",
            {"origin": "http://localhost:5173", "access-control-request-method": "GET"},
        ),
        ("OPTIONS", "/api/onboarding/turn", {"origin": allowed}),
        ("GET", "/api/capabilities", {"origin": allowed}),
        ("GET", "/api/capabilities", {"origin": "https://evil.example"}),
        ("GET", "/api/capabilities", {}),
        ("GET", "/health", {"origin": "http://localhost:5173"}),
    ]
    rows = []
    with TestClient(app) as client:
        for method, path, headers in scenarios:
            response = client.request(method, path, headers=headers)
            rows.append(
                {
                    "method": method,
                    "path": path,
                    "headers": headers,
                    "status": response.status_code,
                    "response": _mask(response.text),
                    "response_headers": {
                        key: value
                        for key, value in response.headers.items()
                        if key.startswith("access-control-")
                        or key in {"vary", "content-type", "allow"}
                    },
                }
            )
    return {"origins": origins, "cases": rows}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-root", default=str(REPO / "server"))
    parser.add_argument("--source-label", default="working tree server/")
    args = parser.parse_args()
    server_root = Path(args.server_root).resolve()
    sys.path.insert(0, str(server_root))
    for key in list(os.environ):
        # The reference must be keyless: no provider configuration may leak in.
        if key.startswith(("OPENAI_", "LLM_", "TAVILY_", "CARTESIA_", "API_", "CORS_")):
            del os.environ[key]
    import pytest

    import lifetwin

    if Path(lifetwin.__file__).resolve().parents[1] != server_root:
        raise SystemExit(f"lifetwin imported from {lifetwin.__file__}, not {server_root}")

    record = {"http": set(), "parse": {}}
    originals, (client_cls, original_send) = install_recorders(record)
    exit_code = pytest.main(
        [
            "-q",
            "-p",
            "no:cacheprovider",
            "-o",
            "asyncio_mode=auto",
            "--rootdir",
            str(server_root),
            str(server_root / "tests"),
        ]
    )
    if exit_code != 0:
        raise SystemExit(f"Python suite failed with exit code {exit_code}")
    client_cls.send = original_send
    import lifetwin.onboarding.parsing as parsing
    import lifetwin.onboarding.service as service

    for name, function in originals.items():
        if name == "describe":
            service.describe = function
        else:
            setattr(parsing, name, function)
            if hasattr(service, name):
                setattr(service, name, function)

    from fastapi.testclient import TestClient

    from lifetwin.app import create_app
    from lifetwin.core.config import Settings
    from lifetwin.onboarding.models import ExtractionResult

    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            API_RATE_LIMIT_PER_MINUTE=10000,
        )
    )
    http_inputs = {tuple(json.loads(item)) for item in record["http"]}
    http_inputs |= set(EXTRA_HTTP)
    http_cases = []
    with TestClient(app, raise_server_exceptions=False) as client:
        for method, target, body, content_type in sorted(
            http_inputs, key=lambda item: json.dumps(item)
        ):
            headers = {"content-type": content_type} if content_type else {}
            response = client.request(
                method,
                target,
                content=body.encode("utf-8") if body is not None else None,
                headers=headers,
                follow_redirects=False,
            )
            if response.status_code == 429:
                raise SystemExit("reference replay hit the rate limit")
            http_cases.append(
                {
                    "method": method,
                    "path": target,
                    "body": body,
                    "content_type": content_type,
                    "status": response.status_code,
                    "response_content_type": response.headers.get("content-type"),
                    "allow": response.headers.get("allow"),
                    "location": response.headers.get("location", "").removeprefix(
                        "http://testserver"
                    )
                    or None,
                    "response": REQUEST_ID.sub('"request_id":"<id>"', response.text),
                }
            )
        for method, target, raw, content_type in EXTRA_BINARY:
            response = client.request(
                method,
                target,
                content=raw,
                headers={"content-type": content_type},
                follow_redirects=False,
            )
            http_cases.append(
                {
                    "method": method,
                    "path": target,
                    "body": None,
                    "body_b64": base64.b64encode(raw).decode("ascii"),
                    "content_type": content_type,
                    "status": response.status_code,
                    "response_content_type": response.headers.get("content-type"),
                    "allow": response.headers.get("allow"),
                    "location": response.headers.get("location", "").removeprefix(
                        "http://testserver"
                    )
                    or None,
                    "response": REQUEST_ID.sub('"request_id":"<id>"', response.text),
                }
            )

    texts = set(EXTRA_TEXTS)
    for name in ("parse_value",):
        texts |= {json.loads(item)[1] for item in record["parse"].get(name, set())}
    for name in ("parse_reply", "clarify", "is_skip"):
        texts |= {json.loads(item)[0] for item in record["parse"].get(name, set())}
    texts = sorted(texts)

    parse = {
        "parse_value": [[f, t, parsing.parse_value(f, t)] for t in texts for f in FIELDS],
        "parse_reply": [[t, f, parsing.parse_reply(t, f)] for t in texts for f in FIELDS],
        "clarify": [[t, f, parsing.clarify(t, f)] for t in texts for f in FIELDS],
        "is_skip": [[t, f, parsing.is_skip(t, f)] for t in texts for f in FIELDS],
        "normalize_text": [[t, parsing.normalize_text(t)] for t in texts],
        "grounded_candidates": [],
        "describe": [],
    }
    for item in sorted(record["parse"].get("grounded_candidates", set())):
        text, extraction, asked = json.loads(item)
        result = parsing.grounded_candidates(
            text, ExtractionResult.model_validate(extraction), asked
        )
        parse["grounded_candidates"].append([text, extraction, asked, result])
    for item in sorted(record["parse"].get("describe", set())):
        values = json.loads(item)
        parse["describe"].append([values, service.describe(values)])
    # Synthetic coverage: every parsed value is read back, and every parsed
    # answer is offered as a provider quote for its own and a foreign field.
    seen_describe = {json.dumps(row[0]) for row in parse["describe"]}
    for text, field, values in parse["parse_reply"]:
        if not values:
            continue
        if json.dumps(values) not in seen_describe:
            seen_describe.add(json.dumps(values))
            parse["describe"].append([values, service.describe(values)])
        for asked in dict.fromkeys([field, "age", "systolic_bp"]):
            extraction = {"candidates": [{"field": field, "quote": text.strip() or "x"}]}
            result = parsing.grounded_candidates(
                text, ExtractionResult.model_validate(extraction), asked
            )
            parse["grounded_candidates"].append([text, extraction, asked, result])

    providers = provider_cases()
    cors = cors_cases()
    # Starlette renders /openapi.json with exactly these json.dumps options.
    openapi_text = json.dumps(
        app.openapi(), ensure_ascii=False, allow_nan=False, indent=None, separators=(",", ":")
    )
    OPENAPI_OUT.write_text(
        "// Generated by convex/parity/generate.py from the FastAPI reference app.\n"
        "// Served verbatim at GET /openapi.json; do not edit by hand.\n"
        f"export const OPENAPI_JSON = {json.dumps(openapi_text, ensure_ascii=False)};\n",
        encoding="utf-8",
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "source": args.source_label,
                "http": http_cases,
                "parse": parse,
                "providers": providers,
                "cors": cors,
            },
            ensure_ascii=False,
            indent=0,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {OUT.relative_to(REPO)}: {len(http_cases)} HTTP cases, "
        + ", ".join(f"{len(rows)} {name}" for name, rows in parse.items())
    )


if __name__ == "__main__":
    main()
