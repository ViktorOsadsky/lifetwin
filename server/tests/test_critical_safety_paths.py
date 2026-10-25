"""Adversarial HTTP tests for the safety lines and the no-supplement rule on every surface.

Surfaces: onboarding turn, daily / quick / weekly check-in turns, change turn and
coach plan. The same words must lead to the same fixed 911 line everywhere, a low mood
must get the care reply once, and nothing may ever suggest a supplement (including
energy drinks, pre-workout and caffeine pills).
"""

import re

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings

LINE = "If you need help right now, please call 911."
SUPPLEMENT_ADVICE = re.compile(
    r"supplement|vitamin|creatine|energy drink|pre-?workout|caffeine|melatonin|magnesium|"
    r"fish oil|protein (?:powder|shake)|herbal|turmeric",
    re.I,
)
EMERGENCIES = [
    "I'm having chest pain",
    "I can't breathe",
    "I think I'm having a stroke",
    "I took too many pills",
    "I want to end my life",
    "I don't want to be here anymore",
]
SUPPLEMENT_ASKS = [
    "should I take pre-workout?",
    "should I drink an energy drink before my walk?",
    "is it ok to take caffeine pills to stay awake",
    "what about creatine?",
    "which supplements should I take?",
    "would a vitamin D pill help my sleep?",
    "can melatonin help me sleep",
]


@pytest.fixture(scope="module")
def client():
    app = create_app(
        Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
    )
    return TestClient(app)


def checkin_state(client, kind, field=None, **start):
    body = {"kind": kind, **start}
    if kind == "quick":
        body["local_date"] = "2026-10-24"
        body["quick"] = {"topics": ["sleep", "feeling"]}
    state = client.post("/api/checkin/start", json=body).json()["state"]
    # Walk to the wanted question by skipping the earlier ones.
    for _ in range(10):
        if field is None or state["current_field"] == field:
            return state
        out = client.post("/api/checkin/turn", json={"action": "skip", "state": state}).json()
        state = out["state"]
    raise AssertionError(f"never reached {field}")


def checkin_reply(client, state, text):
    response = client.post(
        "/api/checkin/turn", json={"action": "reply", "state": state, "text": text}
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
@pytest.mark.parametrize("text", EMERGENCIES)
def test_checkin_emergency_line_is_exact_and_pauses_without_a_next_question(client, kind, text):
    state = checkin_state(client, kind)
    out = checkin_reply(client, state, text)
    assert out["emergency"] is True
    assert LINE in out["message"]
    assert out["message"].count(LINE) == 1
    assert "?" not in out["message"]
    assert out["state"]["pending"] == state["pending"]
    assert out["state"]["confirmed"] == state["confirmed"]
    assert out["state"]["current_field"] == state["current_field"]
    assert not out["complete"]


@pytest.mark.parametrize("text", EMERGENCIES)
def test_onboarding_emergency_line_is_exact(client, text):
    state = {"phase": "asking", "current_field": "age"}
    out = client.post(
        "/api/onboarding/turn", json={"action": "reply", "state": state, "text": text}
    )
    assert out.status_code == 200
    body = out.json()
    assert LINE in body["message"], body["message"]
    assert body["state"]["pending_profile"]["age"] is None


@pytest.mark.parametrize("text", EMERGENCIES)
def test_change_emergency_line_is_exact(client, text):
    start = client.post("/api/change/start", json={"profile": {"age": 60}, "field": "age"}).json()
    out = client.post(
        "/api/change/turn",
        json={"action": "reply", "state": start["state"], "profile": {"age": 60}, "text": text},
    )
    assert out.status_code == 200
    assert LINE in out.json()["message"], out.json()["message"]
    assert out.json()["state"]["pending"]["age"] is None


@pytest.mark.parametrize("text", EMERGENCIES)
def test_coach_emergency_gives_the_911_line_and_no_plan(client, text):
    out = client.post("/api/coach/plan", json={"local_date": "2026-10-24", "said": text}).json()
    assert out["status"] == "emergency" and out["emergency"] is True
    assert out["items"] == []
    assert LINE in " ".join(out["lines"])


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
@pytest.mark.parametrize("text", ["awful", "I feel hopeless", "so lonely", "I'm really down"])
def test_low_mood_gets_the_care_reply_once_per_checkin_and_no_pause(client, kind, text):
    state = checkin_state(client, kind, "wellbeing")
    first = checkin_reply(client, state, text)
    assert first["state"]["care_line_shown"] is True
    assert first["state"]["care_question_open"] is True
    assert not first["emergency"]
    assert first["message"].count("911") == 1
    again = dict(first["state"], care_question_open=False, current_field="wellbeing")
    again["pending"] = state["pending"]
    again["phase"] = "asking"
    second = checkin_reply(client, again, text)
    assert "911" not in second["message"]
    assert second["state"]["care_line_shown"] is True
    assert second["state"]["care_question_open"] is False


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
@pytest.mark.parametrize("text", ["good", "fine thanks", "okay", "pretty good"])
def test_ordinary_mood_shows_no_care_line(client, kind, text):
    out = checkin_reply(client, checkin_state(client, kind, "wellbeing"), text)
    assert out["state"]["care_line_shown"] is False
    assert out["state"]["care_question_open"] is False
    assert "911" not in out["message"]


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
@pytest.mark.parametrize("text", SUPPLEMENT_ASKS)
def test_checkins_never_suggest_a_supplement(client, kind, text):
    state = checkin_state(client, kind)
    out = checkin_reply(client, state, text)
    assert not SUPPLEMENT_ADVICE.search(out["message"]), out["message"]
    # The question stays open; nothing was recorded from the ask.
    assert out["state"]["current_field"] == state["current_field"]
    assert out["state"]["pending"] == state["pending"]


@pytest.mark.parametrize("text", SUPPLEMENT_ASKS)
def test_onboarding_and_change_never_suggest_a_supplement(client, text):
    out = client.post(
        "/api/onboarding/turn",
        json={
            "action": "reply",
            "state": {"phase": "asking", "current_field": "sleep_hours"},
            "text": text,
        },
    ).json()
    assert not SUPPLEMENT_ADVICE.search(out["message"]), out["message"]
    start = client.post(
        "/api/change/start", json={"profile": {"sleep_hours": 6}, "field": "sleep_hours"}
    ).json()
    out = client.post(
        "/api/change/turn",
        json={
            "action": "reply",
            "state": start["state"],
            "profile": {"sleep_hours": 6},
            "text": text,
        },
    ).json()
    assert not SUPPLEMENT_ADVICE.search(out["message"]), out["message"]


@pytest.mark.parametrize("text", SUPPLEMENT_ASKS)
def test_coach_never_suggests_a_supplement_and_says_it_cannot(client, text):
    out = client.post(
        "/api/coach/plan",
        json={"local_date": "2026-10-24", "said": text, "profile": {"age": 70, "sleep_hours": 5}},
    ).json()
    # The fixed reply may name the word "supplements" to decline; nothing else may.
    spoken = " ".join(
        [line for line in out["lines"] if line != out["reply"]]
        + [i["message"] + i["why"] + i["title"] for i in out["items"]]
    )
    assert not SUPPLEMENT_ADVICE.search(spoken), spoken
    assert out["reply"].startswith("I don't suggest supplements")
    assert not re.search(r"\b(?:take|try|drink|buy)\b", out["reply"], re.I)


def test_a_note_mentioning_a_supplement_never_reaches_the_plan(client):
    notes = [
        {"id": "n1", "topic": "exercise", "kind": "walking", "barrier": "energy drink crash"},
        {"id": "n2", "topic": "food", "kind": "pre-workout shake"},
        {"id": "n3", "topic": "sleep", "wakes_for": "caffeine pills"},
    ]
    out = client.post(
        "/api/coach/plan",
        json={
            "local_date": "2026-10-24",
            "memory_consent": True,
            "habit_notes": notes,
            "profile": {"age": 50, "sleep_hours": 5, "exercise_minutes_weekly": 20},
        },
    ).json()
    spoken = " ".join(
        out["lines"]
        + [i["message"] + i["why"] + i["title"] for i in out["items"]]
        + [c["explanation"] for c in out["changes"]]
    )
    assert not SUPPLEMENT_ADVICE.search(spoken), spoken


@pytest.mark.xfail(
    strict=True,
    reason="BUG: /api/checkin/turn daily records wellbeing=good from 'a good protein powder' "
    "while asking about sleep, and answers 'Glad to hear it.'",
)
def test_an_off_topic_ask_with_the_word_good_is_not_taken_as_a_mood_answer(client):
    state = checkin_state(client, "daily", "sleep_hours_last_night")
    out = checkin_reply(client, state, "recommend a good protein powder")
    assert out["state"]["pending"]["wellbeing"] is None
    assert "Glad to hear it" not in out["message"]
