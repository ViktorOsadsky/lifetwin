"""Bug hunt C: the server and the Claude path under demo load (failure injection, consent,
validation, startup). Every provider here is a stub: no test reaches the network."""

import json
import threading
from datetime import date
from types import SimpleNamespace

import anthropic
import httpx2
import pytest
from fastapi.testclient import TestClient
from test_documents_pdf import b64, make_pdf

from lifetwin.app import create_app
from lifetwin.coach.safety import is_emergency
from lifetwin.core import claude as claude_module
from lifetwin.core.config import Settings
from lifetwin.documents import pdf as pdf_module
from lifetwin.onboarding.intents import emergency
from lifetwin.onboarding.models import TurnRequest
from lifetwin.onboarding.parsing import normalize_text
from lifetwin.onboarding.providers import ExtractionUnavailable
from lifetwin.onboarding.service import ConversationService

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
    "CONVERSATION_PROVIDER",
    "DOCUMENT_PROVIDER",
)
REQUEST = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
# Raw provider error text: it must never reach a response.
RAW = "provider-internal-detail-7731"
PROFILE = {
    "age": 68,
    "sex": "female",
    "height_cm": 162.6,
    "weight_kg": 77.1,
    "sleep_hours": 7.5,
    "exercise_minutes_weekly": 90,
    "smoking_status": "former",
    "alcohol_drinks_weekly": 2,
    "diabetes": False,
    "systolic_bp": 128,
    "diastolic_bp": 82,
}
VISIT = make_pdf(
    [
        "Visit Summary\nDate of visit: 2026-09-14\nVitals\nHeight: 165 cm\nWeight: 78 kg\n"
        "Blood pressure: 132/78\nSmoking status: former smoker\nProblem List\nType 2 diabetes"
    ]
)


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for name in PROVIDER_ENV:
        monkeypatch.delenv(name, raising=False)


def message(text, stop_reason="end_turn", content=None):
    blocks = content if content is not None else [SimpleNamespace(type="text", text=text)]
    return SimpleNamespace(stop_reason=stop_reason, content=blocks)


FAILURES = {
    "timeout": lambda: anthropic.APITimeoutError(request=REQUEST),
    "rate_limited_429": lambda: anthropic.RateLimitError(
        RAW, response=httpx2.Response(429, request=REQUEST), body=None
    ),
    "overloaded_529": lambda: anthropic.InternalServerError(
        RAW, response=httpx2.Response(529, request=REQUEST), body={"type": "overloaded_error"}
    ),
    "refusal": lambda: message(json.dumps({"line": RAW, "lines": [RAW]}), "refusal"),
    "malformed_json": lambda: message('{"candidates": [{"field": "age", "quo'),
    "empty_content": lambda: message("", content=[]),
    "max_tokens": lambda: message('{"lines": ["' + RAW, "max_tokens"),
    "wrong_shape": lambda: message("[1, 2, 3]"),
}


class SpySDK:
    """Stands in for anthropic.AsyncAnthropic: records every client and every request."""

    def __init__(self, reply=None):
        self.clients = 0
        self.calls: list[dict] = []
        self.reply = reply

    def __call__(self, **kwargs):
        self.clients += 1
        return SimpleNamespace(messages=self)

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        reply = self.reply() if callable(self.reply) else self.reply
        if isinstance(reply, BaseException):
            raise reply
        return reply or message("{}")


def demo_app(monkeypatch, spy: SpySDK, **env) -> TestClient:
    monkeypatch.setattr(claude_module.anthropic, "AsyncAnthropic", spy)
    settings = Settings(_env_file=None, api_rate_limit_per_minute=10000, **env)
    return TestClient(create_app(settings), raise_server_exceptions=False)


def demo_script(client: TestClient, consent: dict, provider_consent: bool = True) -> list:
    """A short demo through every route that may reach Claude. Returns every response."""
    seen = []

    def post(path, body):
        response = client.post(path, json=body)
        seen.append(response)
        return response.json()

    talk = {"provider_consent": provider_consent, "outside_ai_consent": consent}
    d = post("/api/onboarding/turn", {"action": "start"})
    d = post(
        "/api/onboarding/turn", {**talk, "action": "reply", "state": d["state"], "text": "yes"}
    )
    for text in (
        "born the year the war ended, you work it out",
        "sixty-eight",
        "I reckon that's about it, mostly",
    ):
        d = post(
            "/api/onboarding/turn",
            {**talk, "action": "reply", "state": d["state"], "text": text},
        )
    ck = post("/api/checkin/start", {"kind": "daily", "local_date": "2026-10-25"})
    for text in ("six hours I think", "a short walk, twenty minutes", "lonely", "more or less"):
        if ck.get("complete"):
            break
        ck = post(
            "/api/checkin/turn",
            {"action": "reply", "state": ck["state"], "text": text, "outside_ai_consent": consent},
        )
    ch = post("/api/change/start", {"profile": PROFILE})
    post(
        "/api/change/turn",
        {"action": "reply", "state": ch["state"], "profile": PROFILE, "text": "my weight"},
    )
    post(
        "/api/recommendations",
        {"profile": PROFILE, "outside_ai_consent": consent, "local_date": "2026-10-25"},
    )
    post(
        "/api/coach/plan",
        {
            "profile": {"age": 68},
            "goals": ["keep up with my grandkids"],
            "outside_ai_consent": consent,
            "local_date": "2026-10-25",
        },
    )
    post(
        "/api/documents/extract",
        {
            "pages": ["Visit notes. The nurse wrote it down; ex-smoker."],
            "outside_ai_consent": consent,
        },
    )
    post("/api/documents/read", {"pdf_base64": b64(VISIT), "outside_ai_consent": consent})
    return seen


# -- failure injection --------------------------------------------------------------


@pytest.mark.parametrize("failure", sorted(FAILURES))
def test_every_route_degrades_to_the_rules_when_claude_fails(monkeypatch, failure):
    spy = SpySDK(FAILURES[failure])
    with demo_app(monkeypatch, spy, anthropic_api_key="k") as client:
        responses = demo_script(client, {"claude": True})
    assert spy.calls, "the demo script must reach Claude"
    for response in responses:
        assert response.status_code == 200, response.request.url.path
        assert RAW not in response.text
        assert "anthropic" not in response.text.lower()


# -- consent --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("consent", "provider_consent"),
    [({}, True), ({"claude": False}, True), ({"muse": True}, True), ({"claude": True}, False)],
)
def test_without_a_yes_for_claude_nothing_reaches_claude(monkeypatch, consent, provider_consent):
    spy = SpySDK()
    with demo_app(monkeypatch, spy, anthropic_api_key="k") as client:
        responses = demo_script(client, consent, provider_consent)
    assert all(r.status_code == 200 for r in responses)
    calls = [call["system"][0]["text"][:40] for call in spy.calls]
    if consent.get("claude"):
        # Without the AI helper's yes no onboarding reply is read by Claude (the wording,
        # and check-ins, which carry only outside_ai_consent, may still use it).
        assert [c for c in calls if "Extract" in c] == []
    else:
        assert calls == []


def test_consent_without_a_key_answers_by_the_rules_and_builds_no_client(monkeypatch):
    spy = SpySDK()
    with demo_app(monkeypatch, spy, anthropic_api_key="") as client:
        responses = demo_script(client, {"claude": True})
        assert client.get("/ready").json()["status"] == "ready"
    assert all(r.status_code == 200 for r in responses)
    assert spy.clients == 0 and spy.calls == []
    statuses = {r.json().get("provider_status") for r in responses}
    assert "used" not in statuses


# -- latency: one outage per turn -----------------------------------------------------


class DownExtractor:
    provider = "claude"
    configured = True

    def __init__(self):
        self.calls = 0

    async def extract(self, text, field):
        self.calls += 1
        raise ExtractionUnavailable()


class SpyPersonalizer:
    name = "claude"
    configured = True
    may_train_on_content = False

    def __init__(self):
        self.calls = 0

    async def phrase(self, instructions, facts):
        self.calls += 1
        return {"line": "How old are you, my friend?"}


async def test_a_turn_whose_claude_call_failed_does_not_wait_on_claude_again():
    # Claude timing out on the reply must not be followed by a second Claude wait for the
    # wording: the person would sit through both time budgets in silence.
    extractor, personalizer = DownExtractor(), SpyPersonalizer()
    service = ConversationService(extractor=extractor, personalizer=personalizer)
    consent = {"provider_consent": True, "outside_ai_consent": {"claude": True}}
    start = await service.turn(TurnRequest(action="start"))
    asking = await service.turn(
        TurnRequest(action="reply", state=start.state, text="yes", **consent)
    )
    assert asking.state.current_field == "age"
    personalizer.calls = 0
    reply = await service.turn(
        TurnRequest(
            action="reply",
            state=asking.state,
            text="born the year the war ended, you work it out",
            **consent,
        )
    )
    assert extractor.calls == 1
    assert reply.provider_status == "unavailable"
    assert personalizer.calls == 0


# -- the event loop -------------------------------------------------------------------


async def test_checking_a_pdf_reading_runs_off_the_event_loop(monkeypatch):
    # verify() scans every line for every quote: ~0.5 s on a dense 20-page PDF, which
    # would stall every other person's voice turn if it ran on the loop.
    loop_thread = threading.get_ident()
    threads = []
    real_verify = pdf_module.verify

    def watched(*args, **kwargs):
        threads.append(threading.get_ident())
        return real_verify(*args, **kwargs)

    monkeypatch.setattr(pdf_module, "verify", watched)
    reply = message(
        json.dumps(
            {
                "findings": [
                    {
                        "field": "weight_kg",
                        "value": "78",
                        "unit": None,
                        "quote": "Weight: 78 kg",
                        "page": 1,
                        "section": "Vitals",
                        "date": "2026-09-14",
                    }
                ]
            }
        )
    )
    spy = SpySDK(reply)
    reader = pdf_module.ClaudeDocumentReader(
        api_key="k", model="m", client=SimpleNamespace(messages=spy)
    )
    request = pdf_module.DocumentReadRequest(
        pdf_base64=b64(VISIT), outside_ai_consent={"claude": True}
    )
    response, _ = await pdf_module.read_pdf(request, reader, today=date(2026, 10, 25))
    assert [c.field for c in response.candidates] == ["weight_kg"]
    assert threads and all(t != loop_thread for t in threads)


# -- validation -----------------------------------------------------------------------

ZERO_WIDTH = ["​", "‌", "‍", "⁠", "﻿", "­"]


@pytest.mark.parametrize("mark", ZERO_WIDTH)
def test_an_invisible_character_cannot_hide_an_emergency(mark):
    # Pasted or keyboard-inserted format characters split words for every rule.
    said = f"I have chest p{mark}ain right now"
    assert is_emergency(said)
    assert emergency(said)
    assert emergency(f"I don{mark}'t want to be here anymore")


@pytest.mark.parametrize("mark", ZERO_WIDTH)
def test_invisible_characters_are_dropped_before_the_rules_read_a_reply(mark):
    assert normalize_text(f"about 7{mark} hours") == "about 7 hours"
    assert normalize_text(f"s{mark}even hours") == "seven hours"


def test_an_invisible_character_in_a_spoken_emergency_pauses_every_conversation(monkeypatch):
    spy = SpySDK()
    said = "I have chest p​ain right now"
    with demo_app(monkeypatch, spy, anthropic_api_key="") as client:
        start = client.post("/api/onboarding/turn", json={"action": "start"}).json()
        onboarding = client.post(
            "/api/onboarding/turn",
            json={"action": "reply", "state": start["state"], "text": said},
        ).json()
        ck = client.post("/api/checkin/start", json={"kind": "daily"}).json()
        checkin = client.post(
            "/api/checkin/turn", json={"action": "reply", "state": ck["state"], "text": said}
        ).json()
        ch = client.post("/api/change/start", json={"profile": PROFILE}).json()
        change = client.post(
            "/api/change/turn",
            json={"action": "reply", "state": ch["state"], "profile": PROFILE, "text": said},
        ).json()
    assert onboarding["emergency"] and checkin["emergency"] and change["emergency"]


@pytest.mark.parametrize(
    "text",
    [
        "😀" * 500,
        "unas siete horas cada noche",
        "七个小时",
        "مرحبا كيف حالك",
        "x" * 2000,
        "1," * 1000,
        "‮seven hours",
    ],
)
def test_odd_replies_get_a_gentle_answer_on_every_conversation(monkeypatch, text):
    with demo_app(monkeypatch, SpySDK(), anthropic_api_key="") as client:
        start = client.post("/api/onboarding/turn", json={"action": "start"}).json()
        asking = client.post(
            "/api/onboarding/turn",
            json={"action": "reply", "state": start["state"], "text": "yes"},
        ).json()
        ck = client.post("/api/checkin/start", json={"kind": "weekly"}).json()
        ch = client.post("/api/change/start", json={"profile": PROFILE}).json()
        replies = [
            client.post(
                "/api/onboarding/turn",
                json={"action": "reply", "state": asking["state"], "text": text},
            ),
            client.post(
                "/api/checkin/turn", json={"action": "reply", "state": ck["state"], "text": text}
            ),
            client.post(
                "/api/change/turn",
                json={"action": "reply", "state": ch["state"], "profile": PROFILE, "text": text},
            ),
            client.post("/api/coach/plan", json={"said": text[:500], "local_date": "2026-10-25"}),
        ]
    for response in replies:
        assert response.status_code == 200, response.request.url.path


# -- startup and readiness ------------------------------------------------------------


def test_a_broken_model_file_defers_prediction_instead_of_stopping_the_server(tmp_path):
    # A truncated copy or an unreadable artifact must not take onboarding down with it.
    for name in ("model.keras", "preprocessor.joblib", "baseline_hazard.csv", "metrics.json"):
        (tmp_path / name).write_bytes(b"not what it should be")
    app = create_app(Settings(_env_file=None, model_artifact_path=str(tmp_path)))
    with TestClient(app) as client:
        assert client.get("/ready").json()["prediction"] == "not_implemented"
        assert client.post("/api/predict", json=PROFILE).status_code == 501
        assert client.post("/api/onboarding/turn", json={"action": "start"}).status_code == 200


def test_ready_without_the_model_files_or_a_key(tmp_path):
    app = create_app(
        Settings(_env_file=None, model_artifact_path=str(tmp_path), anthropic_api_key="")
    )
    with TestClient(app) as client:
        ready = client.get("/ready")
        caps = client.get("/api/capabilities").json()
    assert ready.status_code == 200
    assert ready.json() == {"status": "ready", "prediction": "not_implemented", "voice": "deferred"}
    assert caps["conversation"]["configured"] is False
    assert caps["documents"]["pdf"]["configured"] is False


REFUSALS = [
    "I don't want to say",
    "I don't want to tell you",
    "I don't want to answer that",
    "none of your business",
    "I'm not telling",
    "not saying",
    "next question",
]


@pytest.mark.parametrize("text", REFUSALS)
def test_a_plain_refusal_skips_the_question_everywhere(monkeypatch, text):
    # Before: "That sounds nice. Back to you: how much do you weigh?" or "Sorry, I didn't
    # catch that", then the same question again.
    with demo_app(monkeypatch, SpySDK(), anthropic_api_key="") as client:
        start = client.post("/api/onboarding/turn", json={"action": "start"}).json()
        asking = client.post(
            "/api/onboarding/turn",
            json={"action": "reply", "state": start["state"], "text": "yes"},
        ).json()
        assert asking["state"]["current_field"] == "age"
        onboarding = client.post(
            "/api/onboarding/turn",
            json={"action": "reply", "state": asking["state"], "text": text},
        ).json()
        ck = client.post("/api/checkin/start", json={"kind": "daily"}).json()
        checkin = client.post(
            "/api/checkin/turn", json={"action": "reply", "state": ck["state"], "text": text}
        ).json()
        ch = client.post("/api/change/start", json={"profile": PROFILE, "field": "weight_kg"})
        change = client.post(
            "/api/change/turn",
            json={"action": "reply", "state": ch.json()["state"], "profile": PROFILE, "text": text},
        ).json()
    assert "age" in onboarding["state"]["skipped_fields"]
    assert checkin["state"]["current_field"] != "sleep_hours_last_night"
    assert change["state"]["phase"] == "done"
    for reply in (onboarding, checkin, change):
        assert "sounds nice" not in reply["message"]
        assert "glad you told me" not in reply["message"]
