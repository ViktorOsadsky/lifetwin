"""Changing a saved answer by talking it through with Mochi.

Every path of the change conversation, the development corpus in
data/change_requests.json (realistic older-adult change requests, typed and as voice
transcripts), and two held-out sets: data/change_heldout.json, written before the
change module, and data/change_heldout_independent.json, written by a separate agent
that never saw the code. Both were scored once before this guard was added. A wrong value
is worse than a miss, so no case may save a value other than the expected one.
"""

import json
import logging
import re
from datetime import date
from pathlib import Path

import pytest
from change_eval import run, score
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.change.models import (
    CHANGE_FIELDS,
    ChangeResponse,
    ChangeStartRequest,
    ChangeState,
    ChangeTurnRequest,
)
from lifetwin.change.scripts import (
    AGE_RULE,
    ALSO,
    BP_NO_READING,
    CANCELLED,
    CHOOSE_AGAIN,
    DELETE_NOTE,
    DIABETES_NO_DOCTOR,
    DIABETES_STAYS,
    DOCTOR_QUESTION,
    DONE_AGAIN,
    GREETING,
    HELP,
    KEPT,
    NOTED,
    NOTHING_CHANGED,
    OTHERS,
    PRIVATE_NOTE,
    PROBE,
    RESTART,
    SAME,
    SEX_FIXED,
    WHY_NOTE,
)
from lifetwin.change.service import ChangeService
from lifetwin.checkin.models import CheckinResponse
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.intents import EMERGENCY_MESSAGE, RESUME_LEAD
from lifetwin.onboarding.service import (
    LOUDER_LEAD,
    NO_LEAD,
    QUESTION_BACK_LEAD,
    REPEAT_LEAD,
    SLOWER_LEAD,
    UNSURE_LEAD,
)

DATA = Path(__file__).parent / "data"
DEV = json.loads((DATA / "change_requests.json").read_text())
TODAY = date(2026, 10, 24)
SERVICE = ChangeService(clock=lambda: TODAY)
PROFILE = DEV["base_profile"]  # 72, female, 5 ft 5, 160 lb, 6 h, 60 min, former, 3, no, 130/80
LB = 0.45359237


def begin(field=None, consent=False, **profile) -> ChangeResponse:
    return SERVICE.start(
        ChangeStartRequest(profile={**PROFILE, **profile}, field=field, memory_consent=consent)
    )


def talk(*said: str, field=None, consent=False, mode="text", **profile) -> list[ChangeResponse]:
    """Start, then send each reply ("@confirm", "@cancel", "@resume" are actions)."""
    profile = {**PROFILE, **profile}
    replies = [
        SERVICE.start(ChangeStartRequest(profile=profile, field=field, memory_consent=consent))
    ]
    for text in said:
        action = text[1:] if text.startswith("@") else "reply"
        replies.append(
            SERVICE.turn(
                ChangeTurnRequest(
                    action=action,
                    state=replies[-1].state,
                    profile=profile,
                    memory_consent=consent,
                    text=None if action != "reply" else text,
                    input_mode=mode,
                )
            )
        )
    return replies


def last(*said: str, **kwargs) -> ChangeResponse:
    return talk(*said, **kwargs)[-1]


def update(result: ChangeResponse) -> dict:
    return result.profile_update.model_dump(exclude_none=True)


def pending(result: ChangeResponse) -> dict:
    return result.state.pending.model_dump(exclude_none=True)


# --- Corpora ------------------------------------------------------------------------


@pytest.mark.parametrize(
    "case", DEV["cases"], ids=[f"{i}-{c['why']}" for i, c in enumerate(DEV["cases"])]
)
def test_development_change_request(case):
    outcome, details = run(case, DEV["base_profile"], SERVICE)
    assert outcome == "correct", f"{case['turns']} -> {details}"


def test_development_corpus_covers_every_answer():
    cases = DEV["cases"]
    assert len(cases) >= 50
    fields = {c["field"] for c in cases} | {f for c in cases for f in c["expected"]}
    assert set(CHANGE_FIELDS) <= fields
    assert sum(c["field"] is None for c in cases) >= 20  # "What would you like to update?"
    assert sum(not c["expected"] for c in cases) >= 15  # nothing may change
    assert sum(c["mode"] == "transcript" for c in cases) >= 5


@pytest.mark.parametrize("name", ["change_heldout.json", "change_heldout_independent.json"])
def test_held_out_sets_have_no_wrong_values(name):
    # Scored once before this guard: misses (asked again) are allowed, wrong values never.
    result = score(DATA / name)
    assert result["total"] >= 50
    wrong = [f[2]["turns"] for f in result["failures"] if f[1] == "wrong"]
    assert result["counts"]["wrong"] == 0, wrong


# --- Starting -----------------------------------------------------------------------


def test_free_start_asks_what_to_update():
    result = begin()
    assert result.message == GREETING
    assert result.state.phase == "choosing" and result.state.field is None
    assert not result.complete and update(result) == {}


@pytest.mark.parametrize(
    ("field", "said"),
    [
        ("weight_kg", "Right now I have you at 160 pounds. What's changed?"),
        ("height_cm", "Right now I have you at 5 feet 5 inches tall. What's changed?"),
        ("sleep_hours", "Right now I have you sleeping 6 hours a night. What's changed?"),
        (
            "exercise_minutes_weekly",
            "Right now I have you exercising 60 minutes a week. What's changed?",
        ),
        ("alcohol_drinks_weekly", "Right now I have you at 3 drinks a week. What's changed?"),
        (
            "smoking_status",
            "Right now I have that you used to smoke but don't now. What's changed?",
        ),
        (
            "diabetes",
            "Right now I have that a doctor hasn't told you that you have diabetes. "
            "What's changed?",
        ),
        (
            "systolic_bp",
            "Right now I have your blood pressure at 130 over 80. What's changed?",
        ),
        ("age", "Right now I have your age as 72. Have you had a birthday?"),
    ],
)
def test_start_says_the_current_value_first(field, said):
    result = begin(field)
    assert result.message.endswith(said)
    assert result.state.phase == "asking" and result.state.field == field


def test_start_without_a_saved_value_asks_the_question():
    result = begin("weight_kg", weight_kg=None)
    assert "I don't have your weight yet. How much do you weigh?" in result.message


def test_start_on_a_saved_sex_explains_it_cannot_change():
    result = begin("sex")
    assert result.message.startswith(SEX_FIXED)
    assert result.state.phase == "choosing" and update(result) == {}


# --- Read back, then save only after a yes -----------------------------------------


def test_new_value_is_read_back_and_saved_only_after_yes():
    asked, heard, saved = talk("I weigh 150 pounds now", "yes", field="weight_kg")
    assert heard.message == "I heard you weigh 150 pounds now, down from 160. Is that right?"
    assert heard.state.phase == "confirming" and not heard.complete
    assert update(heard) == {} and pending(heard) == {"weight_kg": pytest.approx(150 * LB)}
    assert saved.complete and saved.state.phase == "done"
    assert update(saved) == {"weight_kg": pytest.approx(150 * LB)}
    assert saved.message == "Got it. I've updated your weight."
    assert asked.message.startswith("Let's update your weight.")


def test_confirm_action_saves_what_was_read_back():
    result = last("7 hours", "@confirm", field="sleep_hours")
    assert update(result) == {"sleep_hours": 7}


def test_profile_update_has_the_check_in_shape():
    change = ChangeResponse.model_fields["profile_update"]
    checkin = CheckinResponse.model_fields["profile_update"]
    assert change.annotation is checkin.annotation is HealthProfile


@pytest.mark.parametrize("reply", ["I guess", "okay", "yes?", "probably"])
def test_a_doubtful_yes_is_asked_again(reply):
    result = last("150 pounds", reply, field="weight_kg")
    assert result.message.startswith(UNSURE_LEAD)
    assert result.state.phase == "confirming" and update(result) == {}


def test_a_no_asks_for_the_right_value():
    result = last("150 pounds", "no", field="weight_kg")
    assert result.message == NO_LEAD + "What do you weigh now?"
    assert result.state.phase == "asking" and pending(result) == {}


def test_a_correction_replaces_the_value_read_back():
    heard = last("150 pounds", "no, 155", field="weight_kg")
    assert pending(heard) == {"weight_kg": pytest.approx(155 * LB)}
    assert last("150 pounds", "yes, 150", field="weight_kg").complete
    unsure = last("150 pounds", "yes, 155", field="weight_kg")
    assert unsure.message.startswith(UNSURE_LEAD) and unsure.state.phase == "confirming"


def test_the_same_value_changes_nothing():
    result = last("still 160 pounds", field="weight_kg")
    assert result.message == SAME and result.complete and update(result) == {}


# --- Big jumps get a gentle double-check -------------------------------------------


@pytest.mark.parametrize(
    ("field", "said", "check", "profile"),
    [
        (
            "weight_kg",
            "120 pounds",
            "That's quite a change from 160 to 120 pounds. Is 120 right?",
            {},
        ),
        (
            "systolic_bp",
            "185 over 110",
            "That's quite a change from 130 over 80 to 185 over 110. Is 185 over 110 right?",
            {},
        ),
        (
            "sleep_hours",
            "10 hours",
            "That's quite a change from 6 to 10 hours a night. Is 10 hours right?",
            {},
        ),
        (
            "height_cm",
            "5 feet",
            "That's quite a change from 5 feet 5 inches to 5 feet. Is 5 feet right?",
            {},
        ),
        (
            "smoking_status",
            "I used to smoke years ago",
            "Before, you told me you had never smoked. So you used to smoke, but you don't "
            "now. Is that right?",
            {"smoking_status": "never"},
        ),
    ],
)
def test_big_jumps_are_double_checked_not_refused(field, said, check, profile):
    heard, saved = talk(said, "yes", field=field, **profile)[1:]
    assert heard.message == check
    assert saved.complete and update(saved)


def test_ordinary_changes_get_the_plain_read_back():
    assert last("150 pounds", field="weight_kg").message.startswith("I heard")
    assert last("I quit", field="smoking_status", smoking_status="current").message == (
        "I heard you don't smoke now, but you used to. Is that right?"
    )


def test_values_outside_the_onboarding_bounds_are_never_read():
    for said in ("I weigh 900", "I'm 4 feet 0 inches tall and 2 pounds"):
        result = last(said, field="weight_kg")
        assert pending(result) == {} and result.state.phase == "asking"
    assert pending(last("30 hours", field="sleep_hours")) == {}


# --- Age, sex at birth, diagnoses --------------------------------------------------


@pytest.mark.parametrize("said", ["I turned 73", "I had a birthday last week", "yes", "I'm 73 now"])
def test_age_moves_up_by_a_birthday(said):
    heard, saved = talk(said, "yes", field="age")[1:]
    assert heard.message == "Happy birthday! I heard you're 73 now. Is that right?"
    assert update(saved) == {"age": 73}


@pytest.mark.parametrize("said", ["I'm 75", "I'm 70", "actually I'm 71"])
def test_age_never_changes_by_more_than_a_birthday(said):
    result = last(said, field="age")
    new = int(re.search(r"\d+", said).group())
    assert result.message == AGE_RULE.format(old=72, new=new, next=73)
    assert result.state.phase == "asking" and pending(result) == {}


def test_a_no_to_the_birthday_keeps_the_age():
    result = last("yes", "no", field="age")
    assert result.message == KEPT and update(result) == {}


def test_a_blank_age_or_sex_may_be_filled_in():
    assert update(last("I'm 70", "yes", field="age", age=None)) == {"age": 70}
    assert update(last("male", "yes", field="sex", sex=None)) == {"sex": "male"}


@pytest.mark.parametrize(
    "said",
    ["I need to change my sex to male", "I want to change my gender", "change my sex"],
)
def test_sex_at_birth_cannot_be_changed(said):
    result = last(said)
    assert result.message == SEX_FIXED + " Is there anything else you'd like to update?"
    assert update(result) == {} and result.state.phase == "choosing"


def test_a_diagnosis_with_a_doctors_word_is_read_back():
    heard, saved = talk("My doctor told me I have type 2 diabetes", "yes", field="diabetes")[1:]
    assert heard.message == "I heard a doctor has told you that you have diabetes. Is that right?"
    assert update(saved) == {"diabetes": True}


def test_mochi_asks_whether_a_doctor_said_so():
    asked = last("I have diabetes now", field="diabetes")
    assert asked.message == DOCTOR_QUESTION and asked.state.phase == "confirming"
    assert update(last("I have diabetes now", "yes, last spring", field="diabetes")) == {
        "diabetes": True
    }
    declined = last("I have diabetes now", "no, I just think so", field="diabetes")
    assert declined.message == DIABETES_NO_DOCTOR and update(declined) == {}


def test_a_diagnosis_can_be_corrected_after_a_gentle_check():
    heard, saved = talk("I was wrong, I don't have diabetes", "yes", diabetes=True)[1:]
    assert heard.message.endswith(
        "Just to be sure: no doctor has ever told you that you have diabetes. Is that right?"
    )
    assert update(saved) == {"diabetes": False}
    assert update(last("I don't have diabetes", "no", field="diabetes", diabetes=True)) == {}


@pytest.mark.parametrize(
    "said",
    [
        "my sugar has been high",
        "my doctor says I'm prediabetic",
        "I'm borderline",
        "I'm on metformin for my weight",
    ],
)
def test_mochi_never_diagnoses(said):
    replies = talk(said, "yes", field="diabetes")
    assert all(update(reply) == {} for reply in replies)
    for reply in replies:
        assert not re.search(r"\b(?:you (?:may|might|probably) have|sounds like)\b", reply.message)


def test_diabetes_stays_when_it_is_well_managed():
    result = last("it's in remission now", field="diabetes", diabetes=True)
    assert result.message == DIABETES_STAYS and update(result) == {}


# --- Nothing changes ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("said", "message"),
    [
        ("I don't know", KEPT),
        ("not sure", KEPT),
        ("never mind", NOTHING_CHANGED),
        ("nothing's changed", NOTHING_CHANGED),
        ("same as before", NOTHING_CHANGED),
        ("forget it", NOTHING_CHANGED),
    ],
)
def test_dont_know_or_never_mind_changes_nothing(said, message):
    result = last(said, field="weight_kg")
    assert result.message == message
    assert result.complete and update(result) == {}


def test_no_new_blood_pressure_reading_changes_nothing():
    result = last("I haven't had it checked", field="systolic_bp")
    assert result.message == BP_NO_READING and update(result) == {}


def test_cancel_clears_the_conversation():
    result = last("150 pounds", "@cancel", field="weight_kg")
    assert result.message == CANCELLED and result.state == ChangeState(phase="cancelled")
    assert not result.complete and update(result) == {}


@pytest.mark.parametrize(
    ("said", "field"),
    [
        ("My husband lost 20 pounds", None),
        ("my wife's is 120 over 70", "systolic_bp"),
        ("My son weighs 200 pounds", "weight_kg"),
    ],
)
def test_other_peoples_values_are_refused(said, field):
    result = last(said, field=field)
    assert OTHERS in result.message and pending(result) == {}


# --- Understanding free answers -----------------------------------------------------


@pytest.mark.parametrize(
    ("said", "field", "message"),
    [
        (
            "I lost some weight",
            "weight_kg",
            "Thanks for telling me. Right now I have you at 160 pounds. What do you weigh now?",
        ),
        (
            "my doctor said I have high blood pressure now",
            "systolic_bp",
            "Thanks for telling me. I keep your blood pressure as its two numbers. Right now "
            "I have your blood pressure at 130 over 80. What was your latest blood pressure "
            "reading? For example, 135 over 85.",
        ),
        (
            "I've been sleeping better",
            "sleep_hours",
            "Thanks for telling me. Right now I have you sleeping 6 hours a night. About how "
            "many hours do you sleep on a usual night now?",
        ),
        (
            "I quit smoking",
            "smoking_status",
            "Right now I have that you smoke. I heard you don't smoke now, but you used to. "
            "Is that right?",
        ),
        ("my weight", "weight_kg", "Right now I have you at 160 pounds. What's changed?"),
    ],
)
def test_free_answers_find_what_to_change(said, field, message):
    result = last(said, smoking_status="current")
    assert result.state.field == field
    assert result.message == message


def test_a_free_answer_that_names_nothing_is_asked_again():
    result = last("I'm not feeling too bad")
    assert result.message == CHOOSE_AGAIN and result.state.phase == "choosing"


def test_several_answers_are_done_one_at_a_time():
    asked, chosen, read, saved, offered, heard = talk(
        "I quit drinking and smoking",
        "smoking",
        "I quit",
        "yes",
        "yes",
        "none",
        smoking_status="current",
    )[1:]
    assert asked.message == (
        "Let's do one at a time. Which would you like to update first: your drinks or your smoking?"
    )
    assert chosen.state.field == "smoking_status"
    assert saved.message.endswith(ALSO.format("drinks")) and update(saved) == {
        "smoking_status": "former"
    }
    assert offered.state.field == "alcohol_drinks_weekly" and update(offered) == {}
    assert pending(heard) == {"alcohol_drinks_weekly": 0}


def test_a_relative_weight_change_is_worked_out_and_read_back():
    result = last("I lost 10 pounds", field="weight_kg")
    assert result.message == "I heard you weigh about 150 pounds now, down from 160. Is that right?"
    assert last("I lost over 10 pounds", field="weight_kg").state.phase == "asking"


def test_metric_answers_are_read_back_in_metric():
    result = last("68 kg", field="weight_kg")
    assert result.message == "I heard you weigh 68 kg now, down from 72.6. Is that right?"
    assert "Is that right" in last("68 kg", "what?", field="weight_kg").message
    assert "68 kg" in last("68 kg", "what?", field="weight_kg").message


def test_room_chatter_is_left_out_of_a_transcript():
    result = last(
        "hold on honey I'm on the phone. I'm 158 pounds", field="weight_kg", mode="transcript"
    )
    assert pending(result) == {"weight_kg": pytest.approx(158 * LB)}


# --- The one gentle probe and the habit note ---------------------------------------


def test_with_memory_consent_one_probe_becomes_a_habit_note():
    asked, probe, heard, saved = talk(
        "150 pounds", "I've been walking every morning", "yes", field="weight_kg", consent=True
    )
    assert probe.message == PROBE and probe.state.phase == "probing"
    assert pending(probe) == {"weight_kg": pytest.approx(150 * LB)}  # held, not saved
    assert heard.message.startswith(NOTED) and heard.state.phase == "confirming"
    assert saved.habit_note.model_dump() == {
        "field": "weight_kg",
        "text": "I've been walking every morning",
    }
    assert update(saved) == {"weight_kg": pytest.approx(150 * LB)}


def test_without_memory_consent_there_is_no_probe_and_no_note():
    replies = talk("150 pounds, since I started walking", "yes", field="weight_kg")
    assert replies[1].state.phase == "confirming"
    assert all(reply.habit_note is None and reply.state.note is None for reply in replies)


def test_a_reason_in_the_answer_skips_the_probe():
    heard, saved = talk(
        "150 pounds, since I started walking", "yes", field="weight_kg", consent=True
    )[1:]
    assert heard.state.phase == "confirming"
    assert saved.habit_note.text == "150 pounds, since I started walking"


@pytest.mark.parametrize("said", ["no", "not really", "skip", "I'd rather not say"])
def test_the_probe_may_be_declined(said):
    heard, saved = talk("150 pounds", said, "yes", field="weight_kg", consent=True)[2:]
    assert heard.state.phase == "confirming" and saved.habit_note is None
    assert update(saved)


def test_the_probe_is_asked_only_once():
    replies = talk("150 pounds", "no", "no", "155 pounds", field="weight_kg", consent=True)
    assert [r.state.phase for r in replies[1:]] == ["probing", "confirming", "asking", "confirming"]


def test_a_new_value_in_the_probe_answer_replaces_the_old_one():
    result = last(
        "150 pounds", "actually it's 152, I've been walking", field="weight_kg", consent=True
    )
    assert pending(result) == {"weight_kg": pytest.approx(152 * LB)}
    assert result.state.note is not None


def test_withdrawn_consent_drops_the_note():
    probe = last("150 pounds", "I walk every day", field="weight_kg", consent=True)
    saved = SERVICE.turn(
        ChangeTurnRequest(
            action="reply", state=probe.state, profile=PROFILE, memory_consent=False, text="yes"
        )
    )
    assert saved.habit_note is None and saved.state.note is None and update(saved)


# --- The emergency line --------------------------------------------------------------


@pytest.mark.parametrize(
    "before", [(), ("my weight",), ("150 pounds",), ("150 pounds", "@confirm")]
)
def test_an_emergency_pauses_the_conversation(before):
    replies = talk("weight", *before, "I've got chest pain right now")
    paused, previous = replies[-1], replies[-2]
    assert paused.emergency and paused.message == EMERGENCY_MESSAGE
    assert [event.state for event in paused.mascot_events] == ["concerned"]
    assert paused.state == previous.state


def test_resume_goes_on_where_it_stopped():
    replies = talk("150 pounds", "I can't breathe", "@resume", field="weight_kg")
    assert replies[-1].message == RESUME_LEAD + replies[1].message
    assert not replies[-1].emergency
    assert last("150 pounds", "I can't breathe", "let's carry on", field="weight_kg").message == (
        replies[-1].message
    )


# --- Conversation control ----------------------------------------------------------


def test_repeat_slower_and_louder_say_the_prompt_again():
    asked = begin("weight_kg").message.removeprefix("Let's update your weight. ")
    assert last("what?", field="weight_kg").message == REPEAT_LEAD + asked
    slower = last("slow down please", field="weight_kg")
    assert slower.message == SLOWER_LEAD + asked and slower.speech_hint == "slower"
    louder = last("I can't hear you", field="weight_kg")
    assert louder.message == LOUDER_LEAD + asked and louder.speech_hint == "louder"


def test_help_why_and_privacy():
    assert last("help", field="weight_kg").message.startswith(HELP["weight_kg"])
    assert last("why do you need this", field="weight_kg").message.startswith(WHY_NOTE)
    assert last("is this private", field="weight_kg").message.startswith(PRIVATE_NOTE)
    assert last("150 pounds", "help", field="weight_kg").message.startswith(
        "I'm checking that I heard you right"
    )


def test_a_question_back_is_never_an_answer():
    result = last("is 150 a good weight for me?", field="weight_kg")
    assert result.message.startswith(QUESTION_BACK_LEAD) and pending(result) == {}


def test_start_over_and_go_back():
    assert last("150 pounds", "start over", field="weight_kg").message == RESTART
    cleared = last("clear everything")
    assert cleared.message == DELETE_NOTE + " " + RESTART and cleared.state == ChangeState()
    back = last("go back", field="weight_kg")
    assert back.state.phase == "choosing"
    switched = last("150 pounds", "change my sleep instead", field="weight_kg")
    assert switched.state.field == "sleep_hours" and pending(switched) == {}
    assert pending(last("change my sleep to 7 hours", field="weight_kg")) == {"sleep_hours": 7}


def test_after_done_a_kind_word_or_another_change():
    done = talk("7 hours", "yes", "thank you", field="sleep_hours")[-1]
    assert done.message == "You're welcome! " + DONE_AGAIN and done.complete
    again = last("7 hours", "yes", "can I change my weight too", field="sleep_hours")
    assert again.state.field == "weight_kg" and not again.complete and update(again) == {}


# --- Contracts, API and privacy -------------------------------------------------------


@pytest.fixture
def client():
    settings = Settings(
        _env_file=None,
        app_env="test",
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        cartesia_api_key="",
        cartesia_voice_id="",
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def test_a_whole_dialogue_over_the_api(client):
    profile = {**PROFILE, "smoking_status": "current"}
    start = client.post("/api/change/start", json={"profile": profile, "memory_consent": True})
    assert start.status_code == 200 and start.json()["message"] == GREETING
    state = start.json()["state"]
    for text in ["I quit smoking", "my doctor told me to", "yes"]:
        reply = client.post(
            "/api/change/turn",
            json={
                "action": "reply",
                "state": state,
                "profile": profile,
                "memory_consent": True,
                "text": text,
            },
        )
        assert reply.status_code == 200
        state = reply.json()["state"]
    body = reply.json()
    assert body["complete"] and body["profile_update"]["smoking_status"] == "former"
    assert body["profile_update"]["weight_kg"] is None
    assert body["habit_note"] == {"field": "smoking_status", "text": "my doctor told me to"}


def test_confirming_nothing_is_an_invalid_transition(client):
    response = client.post(
        "/api/change/turn",
        json={"action": "confirm", "state": {"phase": "choosing"}, "profile": PROFILE},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "invalid_change_transition"
    cancelled = client.post(
        "/api/change/turn",
        json={"action": "reply", "text": "150", "state": {"phase": "cancelled"}},
    )
    assert cancelled.status_code == 409


@pytest.mark.parametrize(
    "state",
    [
        {"phase": "asking"},  # no field
        {"phase": "choosing", "field": "weight_kg"},
        {"phase": "asking", "field": "weight_kg", "pending": {"weight_kg": 70}},
        {"phase": "confirming", "field": "weight_kg", "pending": {"sleep_hours": 7}},
        {"phase": "asking", "field": "weight_kg", "saved": {"weight_kg": 70}},
        {"phase": "asking", "field": "diastolic_bp"},
    ],
)
def test_inconsistent_states_are_rejected(client, state):
    response = client.post(
        "/api/change/turn", json={"action": "reply", "text": "150", "state": state}
    )
    assert response.status_code == 422 and response.json()["code"] == "invalid_request"


def test_nothing_is_logged_about_the_person(caplog):
    caplog.set_level(logging.DEBUG)
    talk("I lost some weight", "I'm about 150 now", "yes", consent=True)
    talk("My doctor said I have high blood pressure", "150 over 95", "yes")
    assert not re.search(r"\d|weigh|pressure|walk", caplog.text)


def test_a_parser_failure_is_asked_again_and_logs_only_its_type(monkeypatch, caplog):
    import lifetwin.change.service as service

    def broken(*args, **kwargs):
        raise RuntimeError("150 pounds")

    monkeypatch.setattr(service, "parse_reply", broken)
    caplog.set_level(logging.WARNING)
    result = last("I weigh 150 pounds", field="weight_kg")
    assert result.state.phase == "asking" and pending(result) == {}
    assert "RuntimeError" in caplog.text and "150" not in caplog.text


def test_messages_give_no_advice_or_forecast():
    dialogues = [
        talk("I lost some weight", "I'm about 150 now", "yes", consent=True),
        talk("my sugar has been high", "yes"),
        talk(
            "I quit smoking", "my doctor told me to", "yes", consent=True, smoking_status="current"
        ),
        talk("185 over 110", "yes", field="systolic_bp"),
    ]
    for reply in (reply for dialogue in dialogues for reply in dialogue):
        assert len(reply.message) <= 400
        assert not re.search(
            r"\b(?:should|must|risk|lifespan|predict\w*|years? (?:left|to live)|healthy|"
            r"unhealthy|dangerous|too high|too low)\b",
            reply.message,
            re.I,
        ), reply.message
