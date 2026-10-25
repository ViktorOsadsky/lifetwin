"""The Apple Health offer never locks the person in: they can always just answer."""

import pytest
from test_conversation_v2 import Dialogue

from lifetwin.onboarding.script import HEALTH_DECLINED, HEALTH_OFFER
from lifetwin.onboarding.service import NOT_CAUGHT


def offered() -> Dialogue:
    d = Dialogue()
    d.say("Sure")
    d.say("I'm 72, female, and I've never smoked")
    d.say("yes")
    assert d.state["phase"] == "offering"
    return d


def pivoted(d: Dialogue) -> None:
    assert d.state["phase"] != "offering"
    assert d.state["health_offered"] is True
    assert NOT_CAUGHT not in d.result["message"]
    assert HEALTH_OFFER not in d.result["message"]
    assert d.result.get("client_action") is None


def test_exact_yes_and_no_still_work():
    d = offered()
    assert d.say("yes")["client_action"] == "open_health_import"
    assert d.state["phase"] == "offering"
    d = offered()
    reply = d.say("no")
    pivoted(d)
    assert any(lead in reply["message"] for lead in HEALTH_DECLINED)
    assert d.state["current_field"] == "height_cm"


def test_profile_answers_decline_health_and_are_captured():
    d = offered()
    reply = d.say("I'd rather tell you, I'm 5'4 and 140 pounds")
    pivoted(d)
    assert any(lead in reply["message"] for lead in HEALTH_DECLINED)
    pending = d.state["pending_profile"]
    assert pending["height_cm"] == pytest.approx(162.56, abs=0.1)
    assert pending["weight_kg"] == pytest.approx(63.5, abs=0.1)


def test_a_sleep_answer_is_captured():
    d = offered()
    d.say("I sleep about 7 hours")
    pivoted(d)
    saved = {**d.state["confirmed_profile"], **d.state["pending_profile"]}
    assert saved["sleep_hours"] == 7


def test_a_habit_answer_pivots_without_a_not_caught():
    d = offered()
    reply = d.say("I walk every day")
    pivoted(d)
    assert any(lead in reply["message"] for lead in HEALTH_DECLINED)


@pytest.mark.parametrize(
    "text",
    [
        "I don't have Apple Health",
        "I'd rather just tell you",
        "I don't use that",
        "no watch",
        "let's just talk",
        "I prefer to answer myself",
    ],
)
def test_natural_declines_go_to_the_next_question(text):
    d = offered()
    d.say(text)
    pivoted(d)
    assert d.state["current_field"] == "height_cm"
    assert "height" in d.result["message"].lower() or "tall" in d.result["message"].lower()


@pytest.mark.parametrize("text", ["yes please", "sure, use it", "go ahead"])
def test_natural_yes_keeps_the_import(text):
    d = offered()
    assert d.say(text)["client_action"] == "open_health_import"
    assert d.state["phase"] == "offering"


def test_after_yes_a_spoken_answer_pivots_and_import_still_works():
    d = offered()
    assert d.say("yes")["client_action"] == "open_health_import"
    d.say("Actually I'm 5'4 and 140 pounds")
    pivoted(d)
    assert d.state["pending_profile"]["height_cm"] == pytest.approx(162.56, abs=0.1)
    # The import stays possible later, in the asking phase, and the offer is not repeated.
    d.say("yes") if d.state["phase"] == "confirming" else None
    d.health(sleep_hours=6.5)
    assert d.state["confirmed_profile"]["sleep_hours"] == 6.5
    assert HEALTH_OFFER not in d.result["message"]


def test_unclear_reply_reasks_once_then_declines():
    d = offered()
    reply = d.say("hmm")
    assert d.state["phase"] == "offering"
    assert NOT_CAUGHT in reply["message"] and HEALTH_OFFER in reply["message"]
    assert reply["quick_replies"]
    d.say("hmm")
    pivoted(d)
    assert d.state["current_field"] == "height_cm"


def test_what_reasks_once_then_declines():
    d = offered()
    reply = d.say("what?")
    assert d.state["phase"] == "offering" and HEALTH_OFFER in reply["message"]
    d.say("what?")
    pivoted(d)


def test_the_offer_is_never_repeated_after_a_decline():
    d = offered()
    d.say("no thanks")
    for _ in range(12):
        if d.result["complete"]:
            break
        if d.state["phase"] == "confirming":
            d.say("yes")
        else:
            d.say("hmm")
        assert d.state["phase"] != "offering"
        assert HEALTH_OFFER not in d.result["message"]
