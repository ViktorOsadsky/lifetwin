"""An answer given early, inside another reply, is recorded and its question is skipped.

One test per phase where free text is accepted, onboarding and check-ins. A value that
disagrees with one already given is never written over silently.
"""

from datetime import date

import pytest
from test_conversation_v2 import Dialogue

from lifetwin.checkin.models import CheckinStartRequest, CheckinTurnRequest
from lifetwin.checkin.service import CheckinService
from lifetwin.onboarding.service import NOT_CAUGHT

TODAY = date(2026, 10, 24)


def asked_after(d: Dialogue) -> list[str]:
    """Answer 'no'/'I don't know' to everything left; return the fields asked."""
    asked = []
    for _ in range(40):
        if d.result["complete"]:
            break
        state = d.state
        if state["phase"] == "confirming":
            d.say("yes")
        elif state["phase"] == "offering":
            d.say("no thanks")
        elif state["phase"] == "probing":
            d.say("let's move on")
        else:
            asked.append(state["current_field"])
            d.say("I don't know")
    return asked


def known(d: Dialogue) -> dict:
    both = {**d.state["confirmed_profile"]}
    both.update({k: v for k, v in d.state["pending_profile"].items() if v is not None})
    return both


# -- onboarding ---------------------------------------------------------------------------


def test_consent_question_with_answers_records_both():
    d = Dialogue()
    reply = d.say("Yes, and I'm 72 and female")
    assert d.state["memory_consent"] is True
    assert NOT_CAUGHT not in reply["message"]
    assert known(d)["age"] == 72 and known(d)["sex"] == "female"
    d.say("yes")
    assert d.state["current_field"] == "smoking_status"  # age and sex are not asked again


def test_consent_no_with_answer_keeps_the_no():
    d = Dialogue()
    d.say("No thanks, I'm 72")
    assert d.state["memory_consent"] is False
    assert known(d)["age"] == 72


def test_asking_phase_records_extras_and_skips_their_questions():
    d = Dialogue()
    d.say("Sure")
    d.say("I'm 72 and I sleep 7 hours and I weigh 150 pounds")
    d.say("yes")
    assert known(d)["sleep_hours"] == 7 and known(d)["weight_kg"] == pytest.approx(68, abs=0.1)
    asked = asked_after(d)
    assert "sleep_hours" not in asked and "weight_kg" not in asked


def test_read_back_yes_and_another_answer():
    d = Dialogue()
    d.say("Sure")
    d.say("72")
    assert d.state["phase"] == "confirming"
    d.say("yes, and I also sleep 7 hours")
    assert known(d)["age"] == 72
    assert known(d)["sleep_hours"] == 7
    assert d.state["phase"] in {"confirming", "asking"}
    d.say("yes") if d.state["phase"] == "confirming" else None
    assert "sleep_hours" not in asked_after(d)


def test_read_back_plain_yes_still_confirms():
    d = Dialogue()
    d.say("Sure")
    d.say("72")
    d.say("yes")
    assert d.state["confirmed_profile"]["age"] == 72
    assert d.state["current_field"] == "sex"


def test_offering_phase_records_the_answer_and_skips_the_question():
    d = Dialogue()
    d.say("Sure")
    d.say("I'm 72, female, and I've never smoked")
    d.say("yes")
    assert d.state["phase"] == "offering"
    d.say("I'd rather tell you, I sleep about 7 hours")
    d.say("yes") if d.state["phase"] == "confirming" else None
    assert known(d)["sleep_hours"] == 7
    assert "sleep_hours" not in asked_after(d)


def test_probing_phase_records_an_answer_to_a_later_question():
    d = Dialogue()
    d.say("Sure")
    d.say("I'm 72, female, and I've never smoked")
    d.say("yes")
    d.say("yes")  # opens the import
    d.health(height_cm=162.6, weight_kg=68, sleep_hours=6.5, exercise_minutes_weekly=90)
    assert d.state["phase"] == "probing"
    d.say("I walk the dog every morning and I sit about 6 hours a day")
    assert known(d)["sedentary_min_day"] == 360
    d.say("yes") if d.state["phase"] == "confirming" else None
    assert "sedentary_min_day" not in asked_after(d)


def test_a_later_value_for_an_answered_field_never_overwrites_it():
    d = Dialogue()
    d.say("Sure")
    d.say("72")
    d.say("yes")
    d.say("female")
    d.say("yes")
    d.say("never smoked, and I'm 80")
    assert d.state["confirmed_profile"]["age"] == 72
    assert d.state["pending_profile"]["age"] is None or d.state["pending_profile"]["age"] == 72


# -- check-ins ----------------------------------------------------------------------------

SERVICE = CheckinService(clock=lambda: TODAY)


def start(kind: str, **extra):
    return SERVICE.start(
        CheckinStartRequest(kind=kind, local_date="2026-10-24", previous={}, **extra)
    )


def say(result, text: str):
    return SERVICE.turn(
        CheckinTurnRequest(action="reply", state=result.state, text=text, input_mode="text")
    )


def test_daily_sleep_reply_with_activity_and_feeling_skips_those_questions():
    r = say(start("daily"), "slept 6 hours, walked 30 minutes, feeling good")
    pending = r.state.pending.model_dump(exclude_none=True)
    assert pending == {
        "sleep_hours_last_night": 6.0,
        "exercise_minutes_today": 30,
        "wellbeing": "good",
    }
    assert r.state.current_field == "alcohol_drinks_yesterday"


def test_daily_final_read_back_yes_and_a_skipped_answer():
    r = start("daily")
    for text in ["slept 6", "skip", "skip", "good"]:
        r = say(r, text)
    assert r.state.phase == "confirming"
    r = say(r, "yes, and I walked 20 minutes")
    assert r.state.phase == "confirming"  # read back again, nothing saved yet
    assert r.state.pending.exercise_minutes_today == 20
    assert r.state.confirmed.exercise_minutes_today is None
    r = say(r, "yes")
    assert r.state.phase == "ready"
    assert r.state.confirmed.exercise_minutes_today == 20
    assert r.state.confirmed.sleep_hours_last_night == 6


def test_daily_final_read_back_conflict_is_not_overwritten():
    r = start("daily")
    for text in ["slept 6", "20 minutes", "none", "good"]:
        r = say(r, text)
    r = say(r, "yes, and I also slept 7 hours")
    assert r.state.phase == "confirming"
    assert r.state.pending.sleep_hours_last_night == 6


def test_daily_probe_reply_can_answer_an_open_question():
    r = say(start("daily", memory_consent=True), "slept 4 hours")
    assert r.state.phase == "probing"
    r = say(r, "tossing and turning, and I walked 20 minutes today")
    assert r.state.pending.exercise_minutes_today == 20
    assert r.state.current_field != "exercise_minutes_today"


def test_weekly_reply_with_a_later_answer_reads_it_back_and_skips_the_question():
    r = say(start("weekly"), "I slept about 7 hours a night and I sit 5 hours a day")
    assert r.state.pending.sleep_hours == 7
    assert r.state.early.sedentary_min_day == 300
    r = say(r, "yes")  # the sleep answer is saved
    assert r.state.confirmed.sleep_hours == 7
    for text in ["skip", "skip"]:  # the activity questions
        r = say(r, text) if r.state.phase == "asking" else r
    assert r.state.phase == "confirming" and r.state.current_field == "sedentary_min_day"
    assert r.state.pending.sedentary_min_day == 300
    r = say(r, "yes")
    assert r.state.confirmed.sedentary_min_day == 300
    assert r.state.current_field == "alcohol_drinks_weekly"
