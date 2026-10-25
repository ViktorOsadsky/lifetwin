"""Asking for ideas ("any ideas?") opens today's idea in the app: client_action "open_ideas"."""

from datetime import date

import pytest
from test_conversation_v2 import Dialogue

from lifetwin.checkin.models import CheckinStartRequest, CheckinTurnRequest
from lifetwin.checkin.service import CheckinService
from lifetwin.onboarding.intents import asks_for_ideas
from lifetwin.onboarding.script import SUPPLEMENT_REPLY
from lifetwin.onboarding.service import IDEAS_LATER, IDEAS_LEAD

SERVICE = CheckinService(clock=lambda: date(2026, 10, 24))

PHRASES = [
    "any ideas?",
    "Any ideas what I should do today?",
    "what should I do?",
    "What should I do today?",
    "give me an idea",
    "Do you have any suggestions?",
    "what can I do to be healthier",
    "ideas for today",
    "what do you recommend I do",
    "Could you give me some ideas, please?",
]
NOT_IDEAS = [
    "no idea",
    "I have no idea",
    "I don't have any idea",
    "7 hours",
    "what supplements should I take",
    "any suggestions for vitamins?",
    "should I take melatonin, any ideas?",
    "what medication do you recommend",
    "I have chest pain, any ideas?",
    "I can't breathe, what should I do?",
]


@pytest.mark.parametrize("text", PHRASES)
def test_matches_requests_for_ideas(text):
    assert asks_for_ideas(text)


@pytest.mark.parametrize("text", NOT_IDEAS)
def test_does_not_match_answers_supplements_or_emergencies(text):
    assert not asks_for_ideas(text)


def turn(kind, text):
    start = SERVICE.start(CheckinStartRequest(kind=kind, previous={}))
    request = CheckinTurnRequest(action="reply", state=start.state, text=text)
    return start, SERVICE.turn(request)


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
@pytest.mark.parametrize("text", PHRASES)
def test_checkin_opens_ideas_and_reasks_the_question(kind, text):
    start, reply = turn(kind, text)
    assert reply.client_action == "open_ideas"
    assert reply.message.startswith(IDEAS_LEAD)
    assert reply.message.endswith(SERVICE._prompt(start.state))
    assert reply.state == start.state
    assert not reply.emergency


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
def test_checkin_ideas_later_in_the_check_in_changes_nothing(kind):
    start = SERVICE.start(CheckinStartRequest(kind=kind, previous={}))
    state = start.state
    first = SERVICE.turn(CheckinTurnRequest(action="reply", state=state, text="7 hours"))
    ask = SERVICE.turn(CheckinTurnRequest(action="reply", state=first.state, text="any ideas?"))
    assert ask.client_action == "open_ideas"
    assert ask.state == first.state


@pytest.mark.parametrize("kind", ["daily", "quick", "weekly"])
def test_checkin_negatives_have_no_action(kind):
    for text in ["no idea", "what supplements should I take", "I have chest pain"]:
        _, reply = turn(kind, text)
        assert reply.client_action is None
    _, reply = turn(kind, "what supplements should I take?")
    assert SUPPLEMENT_REPLY in reply.message
    _, reply = turn(kind, "I have chest pain")
    assert reply.emergency


def adult() -> Dialogue:
    d = Dialogue()
    d.say("Sure")
    d.say("I'm 72, female, and I've never smoked")
    d.say("yes")
    assert d.state["confirmed_profile"]["age"] == 72
    return d


@pytest.mark.parametrize("text", PHRASES)
def test_onboarding_opens_ideas_with_age_known(text):
    d = adult()
    before = d.state
    prompt_field = before["current_field"]
    reply = d.say(text)
    assert reply["client_action"] == "open_ideas"
    assert reply["message"].startswith(IDEAS_LEAD)
    assert reply["state"] == before
    assert reply["state"]["current_field"] == prompt_field
    assert not reply["emergency"]


def test_onboarding_before_age_is_known_keeps_going_without_action():
    d = Dialogue()
    d.say("Sure")
    before = d.state
    reply = d.say("any ideas?")
    assert reply.get("client_action") is None
    assert reply["message"].startswith(IDEAS_LATER)
    assert reply["state"] == before


def test_onboarding_under_18_has_no_action():
    d = adult()
    d.state["confirmed_profile"]["age"] = 15
    reply = d.say("any ideas?")
    assert reply.get("client_action") is None
    assert IDEAS_LEAD not in reply["message"]


@pytest.mark.parametrize(
    "text", ["no idea", "what supplements should I take?", "I have chest pain, any ideas?"]
)
def test_onboarding_negatives_have_no_action(text):
    d = adult()
    reply = d.say(text)
    assert reply.get("client_action") is None
    assert IDEAS_LEAD not in reply["message"]


def test_onboarding_emergency_and_supplement_replies_are_kept():
    d = adult()
    assert d.say("I have chest pain")["emergency"] is True
    d = adult()
    assert SUPPLEMENT_REPLY in d.say("what supplements should I take?")["message"]
