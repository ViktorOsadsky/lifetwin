"""Answers hunt C (#244) found lost: self-corrections, qualifiers, a compound frequency, a
vague weight and the check-in's provider status. Rules only: no test reaches the network."""

from datetime import date

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin.models import (
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
    QuickPlan,
)
from lifetwin.checkin.scripts import quick_script
from lifetwin.checkin.service import CheckinService
from lifetwin.core.config import Settings
from lifetwin.core.intent import IntentResult
from lifetwin.core.quantities import read_quantity
from lifetwin.onboarding.parsing import approximate, parse_reply
from lifetwin.onboarding.script import SMALL_TALK

TODAY = date(2026, 10, 25)
HEIGHT_5_3_HALF = 161.29


@pytest.fixture(scope="module")
def client():
    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            rate_limit_per_minute=10000,
            llm_api_key="",
            openai_api_key="",
            openai_model="",
        )
    )
    return TestClient(app)


def reply(client, field, text):
    body = {"action": "reply", "state": {"phase": "asking", "current_field": field}, "text": text}
    response = client.post("/api/onboarding/turn", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def read(text, field):
    return parse_reply(text, field, today=TODAY, strict=True)


# 1. A self-correction: the last value said wins, and a hedge is still an answer.


@pytest.mark.parametrize(
    "text",
    [
        "five four… probably five three and a half now",
        "five four... probably five three and a half now",
        "I'm five foot four, well ... probably five three and a half now",
        "5 foot 4, well, probably 5 foot 3 and a half",
        "five four, well, five three and a half",
        "I was five four but I've shrunk, probably five three and a half now",
    ],
)
def test_the_last_height_said_wins(text):
    assert read(text, "height_cm") == {"height_cm": HEIGHT_5_3_HALF}


def test_a_hedged_correction_is_read_back_for_a_yes(client):
    out = reply(client, "height_cm", "five four… probably five three and a half now")
    assert out["state"]["phase"] == "confirming"
    assert out["state"]["pending_profile"]["height_cm"] == HEIGHT_5_3_HALF
    assert "about 5 feet 3 and a half inches" in out["message"]
    assert approximate("five four… probably five three and a half now")


def test_the_reader_never_picks_one_of_two_heights():
    # The rules read the correction; the reader checking Claude's arithmetic used to
    # return the first height said (162.6 cm).
    text = "I'm five foot four, well, five three and a half"
    assert read_quantity(text, "height_cm").status == "ambiguous"
    assert read_quantity("5 foot 10", "height_cm").value == 177.8


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("sleep_hours", "about 6 hours, maybe 7"),  # which? still asked about
        ("weight_kg", "about 170, maybe 175"),
        ("sleep_hours", "7 hours... 8 on weekends"),  # a second value, not a correction
    ],
)
def test_two_values_without_a_correction_are_still_asked_about(field, text):
    assert field not in read(text, field)


# 2. A qualifier beside the value is kept out of the way of the value.


@pytest.mark.parametrize(
    ("field", "text", "value"),
    [
        ("sleep_hours", "7 hours, sometimes less", 7),
        ("sleep_hours", "seven hours but sometimes less", 7),
        ("weight_kg", "170 lbs but I'm trying to lose 10", 77.1107),
        ("weight_kg", "170 pounds, and I want to lose ten", 77.1107),
        ("exercise_minutes_weekly", "about 2 hours a week, more in summer", 120),
        ("moderate_recreation_min_week", "about 2 hours a week, more in summer", 120),
        ("moderate_recreation_min_week", "an hour, sometimes more", 60),
    ],
)
def test_a_qualifier_does_not_block_the_value(field, text, value):
    assert read(text, field) == {field: value}


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("sleep_hours", "7 hours, no, less"),  # the number itself is taken back
        ("sleep_hours", "7 hours, sometimes 5"),  # a second amount
        ("exercise_minutes_weekly", "2 hours a week in the summer"),  # the value is seasonal
        ("weight_kg", "I'm trying to lose 10 pounds"),  # a goal, no weight
    ],
)
def test_a_qualifier_that_changes_the_value_is_still_not_read(field, text):
    assert field not in read(text, field)


def test_a_qualified_answer_is_heard_over_http(client):
    out = reply(client, "sleep_hours", "7 hours, sometimes less")
    assert out["state"]["pending_profile"]["sleep_hours"] == 7 or (
        out["state"]["confirmed_profile"]["sleep_hours"] == 7
    )
    out = reply(client, "weight_kg", "170 lbs but I'm trying to lose 10")
    assert out["state"]["pending_profile"]["weight_kg"] == pytest.approx(77.11, abs=0.01)


# 3. One session's length and the days it happens on are a week's minutes.


@pytest.mark.parametrize(
    ("field", "text", "minutes"),
    [
        ("exercise_minutes_weekly", "my swim takes forty-five, I do it Monday and Thursday", 90),
        (
            "moderate_recreation_min_week",
            "my swim takes forty-five, I do it Monday and Thursday",
            90,
        ),
        ("exercise_minutes_weekly", "my walk takes 30, I go Monday, Wednesday and Friday", 90),
    ],
)
def test_a_session_and_its_days_add_up(field, text, minutes):
    assert read(text, field) == {field: minutes}


@pytest.mark.parametrize("mode", ["text", "transcript"])
def test_a_session_and_its_days_are_heard_in_a_voice_transcript(client, mode):
    body = {
        "action": "reply",
        "state": {"phase": "asking", "current_field": "exercise_minutes_weekly"},
        "text": "my swim takes forty-five, I do it Monday and Thursday",
        "input_mode": mode,
    }
    out = client.post("/api/onboarding/turn", json=body).json()
    assert out["state"]["pending_profile"]["exercise_minutes_weekly"] == 90


@pytest.mark.parametrize("mode", ["text", "transcript"])
def test_a_session_and_its_days_are_heard_in_the_weekly_check_in(client, mode):
    state = client.post("/api/checkin/start", json={"kind": "weekly"}).json()["state"]
    state = client.post("/api/checkin/turn", json={"action": "skip", "state": state}).json()
    body = {
        "action": "reply",
        "state": state["state"],
        "text": "nothing hard, but my swim takes forty-five, I do it Monday and Thursday",
        "input_mode": mode,
    }
    out = client.post("/api/checkin/turn", json=body).json()
    assert out["state"]["pending"]["moderate_recreation_min_week"] == 90


# 4. A vague comparison to the weight question asks gently for the number.


@pytest.mark.parametrize(
    "text", ["less than I used to", "more than I'd like", "a bit less than before"]
)
def test_a_vague_weight_asks_for_the_number_instead_of_small_talk(client, text):
    out = reply(client, "weight_kg", text)
    assert out["state"]["phase"] == "asking"
    assert not any(line in out["message"] for line in SMALL_TALK)
    assert "rough" in out["message"].lower()
    assert "weigh" in out["message"]


# 5. The check-in reports the provider status it really had.


class _Reader:
    configured = True

    def __init__(self, result):
        self.result = result
        self.calls = 0

    async def read(self, text, question):
        self.calls += 1
        return self.result


class _Rewriter:
    name = "claude"
    configured = True
    may_train_on_content = False

    def __init__(self, line=None, fail=False):
        self.line, self.fail = line, fail

    async def phrase(self, instructions, facts):
        if self.fail:
            from lifetwin.personalize.providers import PhrasingUnavailable

            raise PhrasingUnavailable("down")
        return {"line": self.line or facts["approved_wordings"][0]}


def _mood_state():
    return CheckinState(
        kind="quick",
        questions=list(quick_script(["feeling"], False)),
        current_field="wellbeing",
        local_date="2026-10-24",
        activity_day="yesterday",
    )


def _read_back_state():
    service = CheckinService(clock=lambda: date(2026, 10, 24))
    start = service.start(
        CheckinStartRequest(
            kind="quick", local_date="2026-10-24", quick=QuickPlan(topics=["sleep"])
        )
    )
    out = service.turn(CheckinTurnRequest(action="reply", state=start.state, text="7 hours"))
    assert out.state.phase == "confirming"
    return out.state


def test_checkin_with_no_provider_is_not_configured():
    service = CheckinService(clock=lambda: date(2026, 10, 24))
    request = CheckinTurnRequest(action="reply", state=_mood_state(), text="good")
    assert service.turn(request).provider_status == "not_configured"


async def test_checkin_reports_claude_used_for_a_read_back():
    reader = _Reader(IntentResult(intent="yes", confidence=0.9, source="claude"))
    service = CheckinService(clock=lambda: date(2026, 10, 24), intent_reader=reader)
    request = CheckinTurnRequest(
        action="reply",
        state=_read_back_state(),
        text="aye aye captain",
        outside_ai_consent={"claude": True},
    )
    out = await service.aturn(request)
    assert reader.calls == 1
    assert out.provider_status == "used"
    no_consent = await service.aturn(request.model_copy(update={"outside_ai_consent": {}}))
    assert no_consent.provider_status == "consent_required"
    assert reader.calls == 1


async def test_checkin_reports_an_unavailable_read_back():
    reader = _Reader(None)
    service = CheckinService(clock=lambda: date(2026, 10, 24), intent_reader=reader)
    request = CheckinTurnRequest(
        action="reply",
        state=_read_back_state(),
        text="aye aye captain",
        outside_ai_consent={"claude": True},
    )
    assert (await service.aturn(request)).provider_status == "unavailable"


async def test_checkin_reports_claude_used_for_the_care_line():
    request = CheckinTurnRequest(
        action="reply", state=_mood_state(), text="awful", outside_ai_consent={"claude": True}
    )
    used = CheckinService(clock=lambda: date(2026, 10, 24), personalizer=_Rewriter())
    assert (await used.aturn(request)).provider_status == "used"
    down = CheckinService(clock=lambda: date(2026, 10, 24), personalizer=_Rewriter(fail=True))
    assert (await down.aturn(request)).provider_status == "unavailable"
    # A plain answer needs no provider.
    plain = request.model_copy(update={"text": "good"})
    assert (await used.aturn(plain)).provider_status == "not_needed"
