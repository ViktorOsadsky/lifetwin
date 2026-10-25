"""The quick (frequent) check-in: one to three short questions that fill the on-device
model's daily_logs, Apple Health read-backs, the optional catch-up, and the weekly
check-in's activity and sitting questions in the model's own names.

Replies here are the dev set. The held-out sets (data/quick_checkin_heldout*.json)
are scored once by tests/eval_quick_heldout.py and never used for tuning.
"""

import re
from datetime import date

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin.models import (
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
    DailyLogPart,
    QuickPlan,
)
from lifetwin.checkin.scripts import (
    CLOSINGS,
    GREETINGS,
    QUESTIONS,
    SITTING_PROXIES,
    WEEKLY,
    quick_script,
)
from lifetwin.checkin.service import CheckinService
from lifetwin.core.config import Settings
from lifetwin.onboarding.intents import EMERGENCY_MESSAGE, RESUME_LEAD
from lifetwin.onboarding.service import SKIPPED

TODAY = date(2026, 10, 24)
SERVICE = CheckinService(clock=lambda: TODAY)
V, M, S = "vigorous_recreation_min", "moderate_recreation_min", "sedentary_min_day"


def start(**plan) -> object:
    previous = plan.pop("previous", {})
    local_date = plan.pop("local_date", "2026-10-24")
    return SERVICE.start(
        CheckinStartRequest(
            kind="quick",
            local_date=local_date,
            previous=previous,
            quick=QuickPlan.model_validate(plan) if plan else None,
        )
    )


def turn(result, reply: str | None = None, action: str = "reply", mode: str = "text"):
    if reply in {"<skip>", "<confirm>", "<resume>"}:
        action, reply = reply.strip("<>"), None
    return SERVICE.turn(
        CheckinTurnRequest(action=action, state=result.state, text=reply, input_mode=mode)
    )


def run(replies: list[str], **plan):
    result = start(**plan)
    messages = [result.message]
    for reply in replies:
        result = turn(result, reply)
        messages.append(result.message)
    return result, messages


def pending(result) -> dict:
    return result.state.pending.model_dump(exclude_none=True)


def at(field: str, day: str = "yesterday", **values) -> CheckinState:
    questions = list(quick_script(["sleep", "activity", "sitting"], True))
    confirmed = values.get("confirmed", {})
    before = [n for n in questions[: questions.index(field)] if n not in confirmed]
    return CheckinState(
        kind="quick",
        questions=questions,
        current_field=field,
        skipped_fields=before,
        local_date="2026-10-24",
        activity_day=day,
        **values,
    )


def say(state: CheckinState, text: str, mode: str = "text"):
    return SERVICE.turn(CheckinTurnRequest(action="reply", state=state, text=text, input_mode=mode))


# --- The question rotation ---------------------------------------------------------------


def test_the_default_quick_check_in_asks_sleep_activity_and_sitting():
    result = start()
    assert result.state.questions == ["sleep_hours_last_night", V, M, S]
    assert result.message == (
        GREETINGS["quick"] + " " + QUESTIONS["quick"]["sleep_hours_last_night"]["ask"]
    )
    assert result.state.local_date == "2026-10-24" and result.state.activity_day == "yesterday"


def test_topics_are_asked_in_mochis_order_whatever_the_plan_says():
    result = start(topics=["feeling", "sitting"])
    assert result.state.questions == [S, "wellbeing"]


@pytest.mark.parametrize(
    "bad", [[], ["sleep", "sleep"], ["sleep", "activity", "sitting", "feeling"]]
)
def test_a_plan_asks_one_to_three_topics(bad):
    with pytest.raises(ValueError):
        QuickPlan(topics=bad)
    assert QuickPlan(topics=[], catch_up=True).catch_up


def test_the_sitting_question_rotates_its_everyday_examples_by_date():
    seen = set()
    for day in range(19, 25):
        result = start(topics=["sitting"], local_date=f"2026-10-{day}")
        seen.add(result.message.removeprefix(GREETINGS["quick"] + " "))
    assert seen == {proxy.format(day="yesterday") for proxy in SITTING_PROXIES}


def test_activity_questions_name_the_day_the_app_chose():
    evening = start(topics=["activity"], activity_day="today")
    assert "today" in evening.message and "yesterday" not in evening.message
    morning = start(topics=["activity"])
    assert "yesterday" in morning.message


def test_quick_questions_are_short_and_never_mention_streaks_or_scores():
    for forms in QUESTIONS["quick"].values():
        for text in forms.values():
            assert len(text) <= 170, text
            assert not re.search(r"\b(?:streak|missed|forecast|score|risk|should)\b", text, re.I), (
                text
            )


# --- The owner's phrases --------------------------------------------------------------------


def test_out_of_breath_up_the_hill_is_vigorous():
    result = say(at(V), "I got out of breath walking up the hill for 20 minutes", "transcript")
    assert pending(result) == {V: 20}
    # Heard and echoed; the easy part is asked next, as its own short follow-up.
    assert result.state.current_field == M
    assert result.message == "20 minutes out of breath, got it. " + QUESTIONS["quick"][M][
        "follow"
    ].format(day="yesterday")


def test_pottering_all_afternoon_is_easy_activity_and_asks_how_long():
    result = say(at(V), "pottered in the garden all afternoon")
    assert pending(result) == {}
    assert result.state.current_field == M and result.state.one_pace
    assert result.message == (
        "That counts as easy activity. About how long was it, in minutes or hours?"
    )
    hours = turn(result, "oh, a good two hours")
    assert pending(hours) == {M: 120}
    # Then the out-of-breath part, which pottering didn't answer.
    assert hours.state.current_field == V
    assert "out of breath" in hours.message


def test_sitting_most_of_the_day_watching_the_game_asks_for_hours():
    result = say(at(S), "sat most of the day watching the game")
    assert pending(result) == {}
    assert result.message.startswith("About how many hours was that, all together?")
    assert pending(turn(result, "eight hours I suppose")) == {S: 480}


@pytest.mark.parametrize(
    ("field", "previous", "expected"),
    [
        (V, {V: 15, M: 40}, {V: 15, M: 40}),
        (S, {S: 420}, {S: 420}),
        ("sleep_hours_last_night", {"sleep_hours_last_night": 7}, {"sleep_hours_last_night": 7}),
    ],
)
def test_same_as_yesterday_offers_the_last_answer_back(field, previous, expected):
    result = say(at(field, previous=previous), "same as yesterday")
    assert pending(result) == expected
    assert result.message.startswith("Same as last time, then. ")


def test_same_as_yesterday_without_the_last_answer_asks():
    result = say(at(V, previous={V: 15}), "same as yesterday")
    assert pending(result) == {}
    assert result.message.startswith("I don't have your last answer to go by.")


# --- Activity: pace and time ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("an easy walk for half an hour", {M: 30}),
        ("no, nothing", {V: 0, M: 0}),
        ("I jogged for 20 minutes and then walked gently for 25", {V: 20, M: 25}),
        ("didn't get out of breath, walked the dog for 40 minutes", {V: 0, M: 40}),
        ("swam laps for 30 minutes", {V: 30}),
        ("tai chi for an hour", {M: 60}),
    ],
)
def test_activity_replies(text, expected):
    assert pending(say(at(V), text)) == expected


def test_a_time_without_a_pace_asks_about_the_pace_and_keeps_the_time():
    result = say(at(V), "about 20 minutes")
    assert pending(result) == {} and result.state.held_minutes == 20
    assert result.message == (
        "Did that get you out of breath, like brisk walking uphill, or was it at an easy pace?"
    )
    assert pending(turn(result, "out of breath")) == {V: 20, M: 0}
    assert pending(turn(result, "easy")) == {V: 0, M: 20}
    both = turn(result, "a bit of both")
    assert both.state.held_minutes == 20 and "how many minutes" in both.message
    assert pending(turn(both, "5 minutes")) == {V: 5, M: 15}


@pytest.mark.parametrize(
    "text",
    [
        "my husband went for a run",
        "I'll go for a walk later",
        "I want to walk more",
        "I used to run 30 minutes",
        "today I walked for an hour",  # asked about yesterday
        "about 5000 steps",
        "a little bit",
    ],
)
def test_nothing_unsafe_is_taken(text):
    assert pending(say(at(V), text)) == {}


def test_another_day_says_which_day_is_asked_about():
    result = say(at(V), "today I walked for an hour")
    assert result.message.startswith("And yesterday? ")
    evening = say(at(V, day="today"), "yesterday I walked for an hour")
    assert evening.message.startswith("And today? ")


def test_a_correction_in_the_read_back_replaces_that_pace():
    result = say(at(V), "an easy walk for half an hour")
    # At the end: "no, it was 45 minutes" changes the one activity answer.
    end = turn(turn(turn(result, "no, nothing"), "<skip>"), "<skip>")
    assert end.state.phase == "confirming" and end.state.current_field is None
    corrected = turn(end, "no, the walk was 45 minutes")
    assert pending(corrected) == {V: 0, M: 45}
    # Right after the echo, an unclear change is asked about, never guessed.
    unclear = turn(result, "no, it was 45 minutes")
    assert pending(unclear) == {M: 30}
    back = turn(turn(result, "go back"), "45 minutes, all easy")
    assert pending(back) == {M: 45}


def test_skipping_the_activity_question_skips_both_paces():
    result = SERVICE.turn(CheckinTurnRequest(action="skip", state=at(V)))
    assert {V, M} <= set(result.state.skipped_fields)


def test_more_than_a_whole_day_is_asked_about():
    state = at(S, day="today", confirmed={"sleep_hours_last_night": 9, V: 60, M: 300})
    result = say(state, "about 12 hours")
    assert pending(result) == {}
    assert result.message.startswith("That adds up to more than a whole day.")


# --- Apple Health read-backs ---------------------------------------------------------------


def test_apple_health_sleep_is_offered_and_never_saved_without_a_yes():
    result = start(suggested={"sleep_hours_last_night": 7.5})
    # Offered in the question itself; only the read-back at the end saves it.
    assert result.state.phase == "asking" and result.state.from_health
    assert result.message.endswith(
        "Apple Health says you slept about 7.5 hours last night. Does that sound right?"
    )
    yes = turn(result, "yes")
    assert pending(yes) == {"sleep_hours_last_night": 7.5}
    assert yes.state.confirmed.sleep_hours_last_night is None
    assert not yes.state.from_health and yes.state.current_field == V
    tapped = turn(result, "<confirm>")  # the "Looks right" button
    assert pending(tapped) == {"sleep_hours_last_night": 7.5}
    other = turn(result, "more like 6 hours")
    assert pending(other) == {"sleep_hours_last_night": 6}


def test_a_no_to_apple_health_asks_the_question_itself():
    result = start(suggested={"sleep_hours_last_night": 7.5})
    no = turn(result, "no")
    assert no.state.phase == "asking" and not no.state.from_health
    assert no.state.pending.model_dump(exclude_none=True) == {}
    assert no.message.endswith(QUESTIONS["quick"]["sleep_hours_last_night"]["ask"])
    assert pending(turn(no, "about 6 hours")) == {"sleep_hours_last_night": 6}


def test_skip_during_an_apple_health_read_back_keeps_nothing():
    result = start(suggested={"sleep_hours_last_night": 7.5})
    skipped = turn(result, "<skip>")
    assert skipped.state.confirmed.sleep_hours_last_night is None
    assert "sleep_hours_last_night" in skipped.state.skipped_fields


def test_apple_health_exercise_minutes_ask_only_the_pace():
    result = start(topics=["activity"], suggested={"activity_minutes": 35})
    assert result.state.held_minutes == 35 and result.state.from_health
    assert result.message.endswith(
        "Apple Health shows about 35 minutes of exercise yesterday. Did any of it get you "
        "out of breath, or was it all at an easy pace?"
    )
    easy = turn(result, "all easy")
    assert pending(easy) == {V: 0, M: 35}
    assert easy.message.endswith("Is that right?")
    some = turn(result, "about 10 minutes of it")
    assert pending(some) == {V: 10, M: 25}


def test_suggestions_must_match_the_plan():
    with pytest.raises(ValueError):
        QuickPlan(topics=["sitting"], suggested={"sleep_hours_last_night": 7})
    with pytest.raises(ValueError):
        QuickPlan(topics=["sleep"], suggested={"sleep_hours_night_before": 7})


# --- Catch-up -----------------------------------------------------------------------------------


def test_the_catch_up_is_last_optional_and_kind():
    result, messages = run(["7 hours", "<skip>", "<skip>", "about six hours", "yes"], catch_up=True)
    assert messages[3] == SKIPPED + QUESTIONS["quick"]["sleep_hours_night_before"]["ask"]
    assert "Yesterday was a bit of a blank." in messages[3]
    assert not re.search(r"\bmissed\b|\bstreak\b", " ".join(messages))
    assert result.complete
    assert [row.model_dump(exclude_none=True) for row in result.daily_logs] == [
        {"date": "2026-10-23", "sleep_hours": 6},
        {"date": "2026-10-24", "sleep_hours": 7},
    ]


def test_a_catch_up_about_last_night_is_the_wrong_night():
    result = say(at("sleep_hours_night_before"), "last night I slept 8 hours")
    assert pending(result) == {}


# --- Whole check-ins and the daily_logs rows -----------------------------------------------------


def test_a_morning_check_in_fills_yesterdays_activity_and_todays_sleep():
    result, messages = run(
        [
            "~um about seven hours I think",
            "~I walked up the hill to the shops, got a bit puffed, maybe fifteen minutes",
            "~and then a gentle stroll back, twenty minutes",
            "about 6 hours",
            "that's right",  # the one read-back at the end
        ]
    )
    assert result.complete and result.state.phase == "ready"
    rows = [row.model_dump() for row in result.daily_logs]
    assert rows == [
        {
            "date": "2026-10-23",
            "sleep_hours": None,
            "vigorous_recreation_min": 15,
            "moderate_recreation_min": 20,
            "sedentary_min_day": 360,
        },
        {
            "date": "2026-10-24",
            "sleep_hours": 7,
            "vigorous_recreation_min": None,
            "moderate_recreation_min": None,
            "sedentary_min_day": None,
        },
    ]
    assert set(rows[0]) == {"date", *DailyLogPart.model_fields} - {"date"} | {"date"}
    assert result.profile_update.model_dump(exclude_none=True) == {}
    assert messages[-2].startswith("6 hours sitting, got it. Before I save anything, ")
    assert messages[-1] == CLOSINGS["quick"]["default"]


def test_an_evening_check_in_fills_one_row():
    result, _ = run(["7 hours", "no, nothing", "5 hours", "yes"], activity_day="today")
    assert [row.model_dump(exclude_none=True) for row in result.daily_logs] == [
        {
            "date": "2026-10-24",
            "sleep_hours": 7,
            "vigorous_recreation_min": 0,
            "moderate_recreation_min": 0,
            "sedentary_min_day": 300,
        }
    ]


def test_cancel_keeps_nothing_and_the_day():
    result = turn(start(), action="cancel")
    assert result.state.phase == "cancelled" and result.daily_logs == []
    assert result.state.local_date == "2026-10-24"


def test_emergency_pauses_and_resume_goes_on():
    state = at(V)
    paused = say(state, "I can't breathe, my chest hurts")
    assert paused.emergency and paused.message == EMERGENCY_MESSAGE
    assert "If you need help right now, please call 911" in paused.message
    assert [e.state for e in paused.mascot_events] == ["concerned"]
    assert paused.state == state
    resumed = turn(paused, "<resume>")
    assert resumed.message == RESUME_LEAD + SERVICE._question(state)


def test_feeling_closes_kindly():
    result, messages = run(["not great today", "yes"], topics=["feeling"])
    assert result.complete
    assert messages[-1] == CLOSINGS["quick"]["not_great"]


# --- Weekly: the model's own names, and "not sure" never overwrites -------------------------------


def test_weekly_asks_the_models_activity_and_sitting_inputs():
    assert WEEKLY[:4] == (
        "sleep_hours",
        "vigorous_recreation_min_week",
        "moderate_recreation_min_week",
        "sedentary_min_day",
    )
    assert "exercise_minutes_weekly" not in WEEKLY


def test_unknown_smoking_never_replaces_a_known_value():
    state = CheckinState(
        kind="weekly",
        questions=list(WEEKLY),
        current_field="smoking_status",
        confirmed={"sleep_hours": 7},
        skipped_fields=[
            "vigorous_recreation_min_week",
            "moderate_recreation_min_week",
            "sedentary_min_day",
            "alcohol_drinks_weekly",
        ],
        phase="confirming",
        pending={"smoking_status": "unknown"},
    )
    result = SERVICE.turn(CheckinTurnRequest(action="confirm", state=state))
    assert result.state.confirmed.smoking_status == "unknown"
    assert result.profile_update.smoking_status is None
    assert result.profile_update.sleep_hours == 7


# --- API --------------------------------------------------------------------------------------------


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


def test_quick_api_round_trip(client):
    body = {
        "kind": "quick",
        "local_date": "2026-10-24",
        "quick": {"topics": ["activity"], "activity_day": "yesterday"},
    }
    started = client.post("/api/checkin/start", json=body)
    assert started.status_code == 200
    state = started.json()["state"]
    reply = client.post(
        "/api/checkin/turn",
        json={"action": "reply", "text": "an easy walk, 30 minutes", "state": state},
    ).json()
    assert reply["state"]["pending"]["moderate_recreation_min"] == 30
    assert reply["state"]["current_field"] == "vigorous_recreation_min"  # the follow-up
    no = client.post(
        "/api/checkin/turn", json={"action": "reply", "text": "no", "state": reply["state"]}
    ).json()
    # The one read-back at the end: phase confirming, no open question.
    assert no["state"]["phase"] == "confirming" and no["state"]["current_field"] is None
    last = client.post("/api/checkin/turn", json={"action": "confirm", "state": no["state"]}).json()
    assert last["complete"]
    assert last["daily_logs"] == [
        {
            "date": "2026-10-23",
            "sleep_hours": None,
            "vigorous_recreation_min": 0,
            "moderate_recreation_min": 30,
            "sedentary_min_day": None,
        }
    ]


def test_quick_api_rejects_a_plan_for_another_kind(client):
    bad = client.post("/api/checkin/start", json={"kind": "daily", "quick": {"topics": ["sleep"]}})
    assert bad.status_code == 422


# --- Defects found by the one-time held-out scoring (new wording, not the held-out text) --------


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        (V, "walked for an hour and a half", {M: 90}),  # "1.5" was cut at the dot
        (S, "six and a half hours", {S: 390}),
        (V, "the kids ran me ragged, we gardened for an hour", {M: 60}),  # not running
        (V, "nothing too hard, a gentle walk for 10 minutes", {M: 10}),  # "too" hedges the no
        (V, "between 10 and 20 minutes of easy walking", {M: 15}),  # a close range, read as about
        (V, "got my heart going on the bike for 20 minutes", {}),  # heart rate alone: pace asked
        (S, "seven and a bit hours", {}),  # more than 7, by how much?
        (S, "about 6 hours, maybe 7", {}),  # which?
        (V, "nothing out of breath, an easy stroll for 25 minutes", {V: 0, M: 25}),
    ],
)
def test_held_out_defects_stay_fixed(field, text, expected):
    assert pending(say(at(field), text)) == expected
