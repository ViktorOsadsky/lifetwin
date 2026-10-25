"""Spoken math (owner, 2026-10-25): "the voice agents need to be able to do math. It has
been a consistent thing such that 2 hours cannot be translated into 120 minutes."

Every duration, height and weight question gets the same spoken matrix, through the
deterministic reader and through the real routes. Claude's computed value is re-checked
by the reader, and Claude is never reached without the person's yes for Claude.
"""

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.core.quantities import read_quantity
from lifetwin.onboarding.models import ConversationState, ExtractionResult, TurnRequest
from lifetwin.onboarding.providers import claude_instructions
from lifetwin.onboarding.service import ConversationService

SLEEP, VIG, MOD, SED = (
    "sleep_hours",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
    "sedentary_min_day",
)
TODAY_MIN, LAST_NIGHT = "exercise_minutes_today", "sleep_hours_last_night"

# (said, {field: expected value, or None for "asked again, never stored"})
MATRIX = [
    ("2 hours", {SLEEP: 2, VIG: 120, MOD: 120, SED: 120, TODAY_MIN: 120}),
    ("two hours", {SLEEP: 2, VIG: 120, MOD: 120, SED: 120, TODAY_MIN: 120}),
    ("an hour and a half", {VIG: 90, MOD: 90, SED: 90, TODAY_MIN: 90, LAST_NIGHT: 1.5}),
    ("90 mins", {VIG: 90, MOD: 90, SED: 90, TODAY_MIN: 90, SLEEP: None}),
    ("1.5 hrs", {VIG: 90, MOD: 90, SED: 90, TODAY_MIN: 90, LAST_NIGHT: 1.5}),
    ("half an hour", {VIG: 30, MOD: 30, SED: 30, TODAY_MIN: 30, SLEEP: None}),
    ("7 and a half hours of sleep", {SLEEP: 7.5, LAST_NIGHT: 7.5, MOD: None, SED: None}),
    ("about 2 hours a week", {VIG: 120, MOD: 120, SLEEP: None, SED: None, TODAY_MIN: None}),
    ("30 minutes three times a week", {VIG: 90, MOD: 90, SLEEP: None, SED: None}),
    ("2 hours a day", {VIG: 840, MOD: 840, SED: 120}),
    ("5 foot 10", {"height_cm": 177.8, SLEEP: None, MOD: None, "weight_kg": None}),
    ("170 lbs", {"weight_kg": 77.11, SLEEP: None, MOD: None, "height_cm": None}),
]
CASES = [(said, field, value) for said, expected in MATRIX for field, value in expected.items()]


@pytest.mark.parametrize(("said", "field", "value"), CASES)
def test_the_reader_does_the_math_and_never_guesses(said, field, value):
    reading = read_quantity(said, field)
    if value is None:
        assert not reading.ok, reading
    else:
        assert reading.ok and reading.value == pytest.approx(value, abs=0.01), reading


@pytest.fixture(scope="module")
def client():
    settings = Settings(_env_file=None, rate_limit_per_minute=10000)
    with TestClient(create_app(settings)) as c:
        yield c


def _onboarding(client, field: str, said: str) -> dict:
    state = client.post("/api/onboarding/turn", json={"action": "start"}).json()["state"]
    state.update(phase="asking", current_field=field)
    r = client.post(
        "/api/onboarding/turn",
        json={"action": "reply", "state": state, "text": said, "input_mode": "transcript"},
    )
    assert r.status_code == 200
    return r.json()["state"]["pending_profile"]


ONBOARDING = [
    (said, field, value)
    for said, field, value in CASES
    if field in {SLEEP, VIG, MOD, SED, "height_cm", "weight_kg"}
]


@pytest.mark.parametrize(("said", "field", "value"), ONBOARDING)
def test_onboarding_turns_store_the_field_unit(client, said, field, value):
    pending = _onboarding(client, field, said)
    if value is None:
        assert pending.get(field) is None
    else:
        assert pending[field] == pytest.approx(value, abs=0.01)


def _checkin(client, kind: str, field: str, said: str) -> dict:
    start = client.post("/api/checkin/start", json={"kind": kind, "local_date": "2026-10-25"})
    state = start.json()["state"]
    assert field in state["questions"]
    state.update(current_field=field, phase="asking")
    r = client.post(
        "/api/checkin/turn",
        json={"action": "reply", "state": state, "text": said, "input_mode": "transcript"},
    )
    assert r.status_code == 200
    body = r.json()["state"]
    return {
        k: v
        for part in (body["confirmed"], body["pending"])
        for k, v in part.items()
        if v is not None
    }


CHECKIN = [
    ("weekly", said, field, value)
    for said, field, value in CASES
    if field in {SLEEP, MOD, SED} and not (field == SLEEP and value is not None and value < 2)
] + [("daily", said, field, value) for said, field, value in CASES if field == TODAY_MIN]


@pytest.mark.parametrize(("kind", "said", "field", "value"), CHECKIN)
def test_checkin_turns_store_the_field_unit(client, kind, said, field, value):
    got = _checkin(client, kind, field, said)
    if value is None:
        assert got.get(field) is None
    else:
        assert got[field] == pytest.approx(value, abs=0.01)


def test_the_weekly_checkin_reads_two_hours_as_the_weeks_total(client):
    # Before: 'Was that all week, or each time?' for any hours without "a week".
    assert _checkin(client, "weekly", MOD, "2 hours")[MOD] == 120


@pytest.mark.parametrize(("said", "minutes"), [("2 hours", 120), ("an hour and a half", 90)])
def test_change_turns_store_minutes(client, said, minutes):
    start = client.post("/api/change/start", json={"field": VIG, "profile": {}}).json()
    r = client.post(
        "/api/change/turn",
        json={"action": "reply", "state": start["state"], "profile": {}, "text": said},
    )
    assert r.json()["state"]["pending"][VIG] == minutes


# -- Claude's computed value, re-checked ----------------------------------------------


class FakeClaude:
    provider = "claude"
    configured = True

    def __init__(self, candidates, off_topic=False):
        self.candidates = candidates
        self.off_topic = off_topic
        self.calls = 0

    async def extract(self, text, field):
        self.calls += 1
        return ExtractionResult.model_validate(
            {"candidates": self.candidates, "off_topic": self.off_topic}
        )


def _ask(service, field, said, consent):
    state = ConversationState(phase="asking", current_field=field, memory_consent=False)
    request = TurnRequest(
        action="reply",
        state=state,
        text=said,
        provider_consent=True,
        outside_ai_consent=consent,
    )
    import asyncio

    return asyncio.run(service.turn(request))


# The rule-based parser leaves this to the AI helper; the reader can still add it up.
HARD = "swimming, forty five on Mondays and again on Thursdays"
QUOTE = "forty five on Mondays and again on Thursdays"


def test_claude_is_never_reached_without_a_yes_for_claude():
    fake = FakeClaude([{"field": MOD, "quote": QUOTE, "value": 90}])
    for consent in ({}, {"muse": True}, {"claude": False}):
        response = _ask(ConversationService(fake), MOD, HARD, consent)
        assert response.provider_status == "consent_required"
        assert response.state.pending_profile.moderate_recreation_min_week is None
    assert fake.calls == 0


@pytest.mark.parametrize("claimed", [90, 100, 45])
def test_the_reader_wins_and_the_value_is_read_back(claimed):
    fake = FakeClaude([{"field": MOD, "quote": QUOTE, "value": claimed}])
    response = _ask(ConversationService(fake), MOD, HARD, {"claude": True})
    assert fake.calls == 1
    assert response.state.phase == "confirming"
    assert response.state.pending_profile.moderate_recreation_min_week == 90
    assert "Is that right" in response.message


def test_a_computed_value_needs_an_exact_quote_with_a_number():
    for candidate in (
        {"field": MOD, "quote": "ninety minutes", "value": 90},
        {"field": MOD, "quote": "Mondays", "value": 90},
        {"field": SED, "quote": QUOTE, "value": 90},
    ):
        response = _ask(ConversationService(FakeClaude([candidate])), MOD, HARD, {"claude": True})
        assert response.state.pending_profile.moderate_recreation_min_week is None


def test_claude_is_told_to_do_the_math_in_the_fields_unit():
    text = claude_instructions(MOD)
    assert "minutes per week" in text and "2 hours = 120 minutes" in text
    assert "Never rewrite, convert, add up" not in text


# -- routing ----------------------------------------------------------------------------


def test_conversation_turns_go_to_claude_even_when_the_rest_names_muse(monkeypatch):
    for name in ("CONVERSATION_PROVIDER", "LLM_PROVIDER", "PERSONALIZE_PROVIDER"):
        monkeypatch.delenv(name, raising=False)
    settings = Settings(
        _env_file=None,
        ANTHROPIC_API_KEY="k",
        LLM_PROVIDER="chat_completions",
        PERSONALIZE_PROVIDER="muse",
        LLM_API_KEY="m",
        LLM_MODEL="muse-spark-1.3-contributor",
        LLM_ALLOW_CONTRIBUTOR=True,
    )
    assert settings.conversation_provider == "claude"
    app = create_app(settings)
    assert app.state.conversation_service.extractor.provider == "claude"
    assert app.state.conversation_service.personalizer.name == "claude"
    assert app.state.checkin_service.personalizer.name == "claude"
    # Ideas, coach and recommendations stay on Muse.
    assert app.state.personalizer.name == "muse"
    assert app.state.coach_phraser.name == "muse"
    with TestClient(app) as c:
        caps = c.get("/api/capabilities").json()
    assert caps["conversation"]["display_name"] == "Claude by Anthropic"
    assert caps["conversation"]["may_train_on_content"] is False
    assert caps["personalize"]["provider"] == "muse"


def test_without_a_key_conversation_stays_claude_and_never_muse():
    # Owner ruling (2026-10-25): LLM_PROVIDER naming Muse is not a conversation opt-in.
    settings = Settings(_env_file=None, LLM_PROVIDER="chat_completions")
    assert settings.conversation_provider == "claude"
    app = create_app(settings)
    assert app.state.conversation_service.extractor.configured is False
    assert app.state.conversation_service.extractor.provider == "claude"
    local = create_app(
        Settings(_env_file=None, ANTHROPIC_API_KEY="k", CONVERSATION_PROVIDER="local")
    )
    assert local.state.conversation_service.extractor is None
    assert local.state.checkin_service.personalizer is None


# -- background speech (Claude's relevance call) -----------------------------------------

TV = "and now back to the studio, where the weather for the weekend looks mild"


def test_background_speech_keeps_the_question_open():
    fake = FakeClaude([], off_topic=True)
    response = _ask(ConversationService(fake), MOD, TV, {"claude": True})
    assert fake.calls == 1
    assert response.off_topic is True
    assert response.state.phase == "asking"
    assert response.state.current_field == MOD
    assert response.message.startswith("Sorry, I think I heard someone else.")
    # Without the yes for Claude nothing is judged: the rules answer, off_topic stays false.
    response = _ask(ConversationService(FakeClaude([], off_topic=True)), MOD, TV, {})
    assert response.off_topic is False


def test_an_answer_is_never_off_topic():
    # The parser reads "two hours" before any model; Claude is not even asked.
    fake = FakeClaude([], off_topic=True)
    response = _ask(ConversationService(fake), MOD, "two hours", {"claude": True})
    assert fake.calls == 0 and response.off_topic is False
    assert response.state.pending_profile.moderate_recreation_min_week == 120
    # An answer to another question counts as an answer, and is kept for that question.
    response = _ask(ConversationService(fake), MOD, "I'm 72 years old", {"claude": True})
    assert response.off_topic is False
    assert response.state.pending_profile.age == 72
    # A value found wins over an off_topic flag.
    fake = FakeClaude([{"field": MOD, "quote": QUOTE, "value": 90}], off_topic=True)
    response = _ask(ConversationService(fake), MOD, HARD, {"claude": True})
    assert response.off_topic is False
    assert response.state.pending_profile.moderate_recreation_min_week == 90


def test_checkin_and_change_replies_are_never_off_topic(client):
    state = client.post("/api/checkin/start", json={"kind": "weekly"}).json()["state"]
    body = client.post(
        "/api/checkin/turn", json={"action": "reply", "state": state, "text": TV}
    ).json()
    assert body["off_topic"] is False
    start = client.post("/api/change/start", json={"field": VIG, "profile": {}}).json()
    body = client.post(
        "/api/change/turn",
        json={"action": "reply", "state": start["state"], "profile": {}, "text": TV},
    ).json()
    assert body["off_topic"] is False


def test_claude_is_asked_to_judge_relevance_and_muse_is_not():
    from lifetwin.onboarding.providers import _instructions, _quote_schema

    assert "off_topic" in claude_instructions(MOD)
    assert "off_topic" not in _instructions(MOD)
    assert "off_topic" not in str(_quote_schema())


def test_a_model_quote_cannot_store_a_weekly_amount_as_a_night():
    # Found live: Claude quoted "2 hours" from "about 2 hours a week" to the sleep question.
    fake = FakeClaude([{"field": SLEEP, "quote": "2 hours", "value": 2}])
    response = _ask(ConversationService(fake), SLEEP, "about 2 hours a week", {"claude": True})
    assert response.state.pending_profile.sleep_hours is None


def test_an_off_topic_line_is_never_reworded():
    class Phraser:
        name, configured, may_train_on_content = "claude", True, False
        calls = 0

        async def phrase(self, instructions, facts):
            Phraser.calls += 1
            return {"line": "reworded"}

    service = ConversationService(FakeClaude([], off_topic=True), personalizer=Phraser())
    response = _ask(service, MOD, TV, {"claude": True})
    assert response.off_topic is True and Phraser.calls == 0
