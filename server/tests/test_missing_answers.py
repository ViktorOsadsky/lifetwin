"""Missing answers: one offer at the end of the intake, and "Answer N more questions"
(`state.ask_only`), which asks only the fields still without a value and never loops."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from lifetwin.onboarding import router
from lifetwin.onboarding.models import ConversationState

# Every field the estimate needs, answered (the on-device model's eleven inputs).
SAVED = {
    "age": 64,
    "sex": "female",
    "smoking_status": "never",
    "height_cm": 165,
    "weight_kg": 70,
    "sleep_hours": 7,
    "general_health": "good",
    "hypertension_diagnosed": False,
    "diabetes": False,
    "sedentary_min_day": 360,
    "moderate_recreation_min_week": 120,
    "vigorous_recreation_min_week": 30,
}
OTHERS = ["exercise_minutes_weekly", "alcohol_drinks_weekly", "systolic_bp", "diastolic_bp"]


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(router, prefix="/api")
    return TestClient(app)


def turn(client, action, state, **values):
    response = client.post(
        "/api/onboarding/turn", json={"action": action, "state": state, **values}
    )
    assert response.status_code == 200, response.text
    return response.json()


def without(*fields):
    return {k: v for k, v in SAVED.items() if k not in fields}


def last_question(missing="vigorous_recreation_min_week"):
    """The intake at its last open question, everything else answered or declined."""
    return ConversationState(
        phase="asking",
        current_field=missing,
        confirmed_profile=without(missing),
        skipped_fields=OTHERS,
        health_offered=True,
        memory_consent=False,
    ).model_dump()


def ask_only(profile, fields):
    return ConversationState(
        confirmed_profile=profile, ask_only=fields, memory_consent=False
    ).model_dump()


def answer(client, result, text):
    """Reply, and say yes to the read-back if there is one."""
    result = turn(client, "reply", result["state"], text=text)
    if result["state"]["phase"] == "confirming":
        result = turn(client, "confirm", result["state"])
    return result


def test_end_of_intake_offers_the_missing_answers_once(client):
    offer = turn(client, "skip", last_question())
    assert offer["state"]["phase"] == "missing" and offer["complete"] is False
    assert offer["message"].endswith(
        "I still need 1 answer for your estimate: your vigorous exercise. Want to answer it now?"
    )
    assert offer["quick_replies"] == ["Yes", "Not now"]
    assert offer["state"]["missing_offered"] is True


def test_yes_asks_only_the_missing_answer_then_finishes_with_the_estimate(client):
    offer = turn(client, "skip", last_question())
    asked = turn(client, "reply", offer["state"], text="yes")
    assert asked["state"]["phase"] == "asking"
    assert asked["state"]["current_field"] == "vigorous_recreation_min_week"
    assert asked["state"]["ask_only"] == ["vigorous_recreation_min_week"]
    done = answer(client, asked, "30 minutes a week")
    assert done["complete"] is True
    assert done["model_inputs"]["status"] == "ready"
    assert done["message"].endswith("Tap Continue to see your estimate.")


def test_not_now_finishes_and_never_offers_again(client):
    offer = turn(client, "skip", last_question())
    done = turn(client, "reply", offer["state"], text="Not now")
    assert done["complete"] is True and done["state"]["phase"] == "ready"
    assert done["message"].startswith("That's okay. You can answer them any time from Home.")
    again = turn(client, "reply", done["state"], text="okay thanks")
    assert again["state"]["phase"] == "ready"
    assert "I still need" not in again["message"]


def test_no_offer_when_nothing_the_estimate_needs_is_missing(client):
    state = last_question("vigorous_recreation_min_week")
    done = answer(client, {"state": state}, "30 minutes a week")
    assert done["complete"] is True
    assert "I still need" not in done["message"]


def test_ask_only_asks_exactly_the_missing_fields_in_order(client):
    result = turn(
        client,
        "start",
        ask_only(
            without("vigorous_recreation_min_week", "smoking_status"),
            ["vigorous_recreation_min_week", "smoking_status"],
        ),
    )
    assert result["message"].startswith("Hi again! I just need 2 more answers for your estimate.")
    asked = [result["state"]["current_field"]]
    result = answer(client, result, "I have never smoked")
    asked.append(result["state"]["current_field"])
    result = answer(client, result, "30 minutes a week")
    assert asked == ["smoking_status", "vigorous_recreation_min_week"]
    assert result["complete"] is True
    assert result["model_inputs"]["status"] == "ready"
    assert result["state"]["probes_asked"] == []  # no habit follow-ups here


def test_ask_only_never_reasks_an_answered_field(client):
    result = turn(
        client,
        "start",
        ask_only(without("sleep_hours"), ["sleep_hours", "age", "smoking_status"]),
    )
    assert result["state"]["ask_only"] == ["sleep_hours"]
    assert result["state"]["current_field"] == "sleep_hours"
    assert "1 more answer" in result["message"]
    done = answer(client, result, "7 hours")
    assert done["complete"] is True
    assert done["state"]["confirmed_profile"]["age"] == 64


def test_ask_only_with_nothing_left_finishes_at_once(client):
    result = turn(client, "start", ask_only(SAVED, ["sleep_hours"]))
    assert result["complete"] is True
    assert "already answered everything" in result["message"]


def test_i_dont_know_in_ask_only_is_kind_and_never_loops(client):
    result = turn(
        client,
        "start",
        ask_only(
            without("vigorous_recreation_min_week", "sleep_hours"),
            ["vigorous_recreation_min_week", "sleep_hours"],
        ),
    )
    assert result["state"]["current_field"] == "sleep_hours"
    seen = []
    for _ in range(3):  # a simpler question may come once; never more
        if result["state"]["current_field"] != "sleep_hours":
            break
        seen.append(result["message"])
        result = turn(client, "reply", result["state"], text="I don't know")
    assert result["state"]["current_field"] == "vigorous_recreation_min_week", seen
    assert "Your estimate needs this one, so I'll offer it once more later." in result["message"]
    result = turn(client, "reply", result["state"], text="I don't know")
    for _ in range(2):
        if result["complete"]:
            break
        result = turn(client, "reply", result["state"], text="I don't know")
    assert result["complete"] is True
    assert "Your estimate still needs your" in result["message"]
    assert result["message"].endswith("Tap Continue to go back.")
    assert result["model_inputs"]["status"] == "still_learning"


def test_start_over_in_ask_only_keeps_the_other_answers(client):
    result = turn(
        client,
        "start",
        ask_only(without("sleep_hours"), ["sleep_hours"]),
    )
    result = turn(client, "reply", result["state"], text="yes, start over")
    assert result["state"]["ask_only"] == ["sleep_hours"]
    assert result["state"]["current_field"] == "sleep_hours"
    assert result["state"]["confirmed_profile"]["age"] == 64
