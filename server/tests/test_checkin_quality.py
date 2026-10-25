"""Check-in quality (owner audit, 2026-10): the daily check-ins should feel active and good.

Each test here failed before the change it guards:
- activity misreadings (the gym and sport are out of breath, "each way" doubles, a time
  without a pace is never added to another part's pace);
- texting shorthand and notes beside an answer ("7h", "like 5ish", "4, couldn't stop
  worrying", "Pretty good, my knee is sore");
- a gentle check question for unusual values instead of silent acceptance;
- extra facts carried forward, "go back, I slept 5 not 7", and one read-back at the end
  of the quick and daily check-ins instead of one per answer;
- everyday examples by age, and an encouraging closing line.
The held-out set (data/checkin_quality_heldout.json) is scored by
tests/eval_checkin_quality.py and never used here.
"""

import re
from datetime import date

import pytest

from lifetwin.checkin.models import CheckinStartRequest, CheckinState, CheckinTurnRequest, QuickPlan
from lifetwin.checkin.scripts import CLOSINGS, DAILY, quick_script
from lifetwin.checkin.service import CheckinService
from lifetwin.checkin.understanding import read_activity
from lifetwin.onboarding.parsing import parse_reply

TODAY = date(2026, 10, 24)
SERVICE = CheckinService(clock=lambda: TODAY)
V, M, S = "vigorous_recreation_min", "moderate_recreation_min", "sedentary_min_day"
SLEEP = "sleep_hours_last_night"
QUICK = list(quick_script(["sleep", "activity", "sitting"], False))


def activity(text: str) -> dict:
    return read_activity(
        text, open_paces=["vigorous", "moderate"], week=False, day="yesterday"
    ).values


def at(field: str, kind: str = "quick", **values) -> CheckinState:
    questions = QUICK if kind == "quick" else list(DAILY)
    extra = {"local_date": "2026-10-24", "activity_day": "yesterday"} if kind == "quick" else {}
    return CheckinState(
        kind=kind,
        questions=questions,
        current_field=field,
        skipped_fields=questions[: questions.index(field)],
        **extra,
        **values,
    )


def say(state: CheckinState, text: str):
    return SERVICE.turn(CheckinTurnRequest(action="reply", state=state, text=text))


def heard(result) -> dict:
    values = result.state.pending.model_dump(exclude_none=True)
    return {k: v for k, v in values.items() if k not in result.state.checking}


def start(kind: str = "quick", age: int | None = None, **plan):
    return SERVICE.start(
        CheckinStartRequest(
            kind=kind,
            local_date="2026-10-24",
            age=age,
            quick=QuickPlan.model_validate(plan) if kind == "quick" else None,
        )
    )


def run(replies: list[str], kind: str = "quick", **plan):
    result = start(kind, **plan)
    messages = [result.message]
    for reply in replies:
        result = say(result.state, reply)
        messages.append(result.message)
    return result, messages


# --- Activity: the gym and sport, each way, and a time without a pace -----------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("45 min HIIT at the gym, and I walked 20 min to work", {V: 45, M: 20}),
        ("an hour and a half of tennis", {V: 90}),
        ("spin class for 45 minutes", {V: 45}),
        ("played football for an hour", {V: 60}),
        ("an hour at the gym", {V: 60}),
        ("30 minute run", {V: 30}),
        ("chased the kids for like an hour", {M: 60}),
        ("walked 15 min each way to work", {M: 30}),
        ("45 minutes with my trainer, and I walked 20 min", {}),  # never "65 minutes easy"
        ("did the school run, 20 minutes", {}),  # not running
    ],
)
def test_activity_paces(text, expected):
    assert activity(text) == expected


def test_steps_ask_for_minutes():
    read = read_activity("12k steps", open_paces=["vigorous", "moderate"], week=False, day="today")
    assert read.values == {} and "minutes" in read.hint


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("exercise_minutes_today", "15 min each way", 30),
        ("exercise_minutes_today", "an hour and a half of tennis", 90),
        ("exercise_minutes_today", "an hour and fifteen minutes", 75),
        (SLEEP, "7h", 7),
        (SLEEP, "like 5ish", 5),
        (SLEEP, "like 4 lol", 4),
        ("sleep_hours", "5-ish", 5),
    ],
)
def test_shared_number_and_duration_reading(field, text, expected):
    """One reading for onboarding and check-ins (onboarding/parsing.py)."""
    assert parse_reply(text, field, today=TODAY) == {field: expected}


def test_a_wish_with_like_is_no_answer():
    assert parse_reply("I'd like 8 hours", SLEEP, today=TODAY) == {}


# --- Notes beside the answer --------------------------------------------------------------


def test_a_reason_beside_the_number_keeps_the_number():
    assert heard(say(at(SLEEP), "4, couldn't stop worrying")) == {SLEEP: 4}


def test_a_note_beside_the_feeling_is_kept_with_memory_consent():
    state = at("wellbeing", kind="daily", memory_consent=True)
    result = say(state, "Pretty good, my knee is sore")
    assert heard(result) == {"wellbeing": "good"}
    assert [n.concern for n in result.state.habit_notes] == ["knee pain"]
    assert (
        say(at("wellbeing", kind="daily"), "Pretty good, my knee is sore").state.habit_notes == []
    )


@pytest.mark.parametrize("text", ["good, no actually not great", "4, maybe 5", "seven and a bit"])
def test_a_second_clause_that_changes_the_answer_is_no_note(text):
    field = "wellbeing" if "good" in text else SLEEP
    assert heard(say(at(field, kind="daily"), text)) == {}


# --- Unusual values get a gentle check ----------------------------------------------------


@pytest.mark.parametrize(
    ("field", "text", "value"),
    [(SLEEP, "15 hours", 15), (S, "17 hours", 1020), (V, "400 minutes of walking", 400)],
)
def test_an_unusual_value_is_checked_once_gently(field, text, value):
    result = say(at(field), text)
    assert heard(result) == {}
    assert result.state.phase == "confirming" and result.state.current_field == field
    assert result.message.startswith("Did I hear ") and "That's a lot for one" in result.message
    assert not re.search(r"\b(?:should|unhealthy|risk|too much)\b", result.message)
    kept = say(result.state, "yes")
    assert value in heard(kept).values()
    assert kept.state.checking == [] and kept.message.startswith("Thanks for checking.")
    redo = say(say(result.state, "no").state, "7 hours" if field != V else "40 minutes of walking")
    assert value not in heard(redo).values() and heard(redo)


def test_unusual_daily_exercise_is_checked_too():
    result = say(at("exercise_minutes_today", kind="daily"), "six hours of hiking")
    assert result.state.checking == ["exercise_minutes_today"]


def test_the_weekly_read_back_says_why_it_checks():
    from lifetwin.checkin.scripts import WEEKLY

    state = CheckinState(kind="weekly", questions=list(WEEKLY), current_field="sleep_hours")
    result = say(state, "15 hours")
    assert result.message.startswith("That's quite a lot, so I just want to be sure.")


# --- Carried forward, and corrections later on ---------------------------------------------


def test_extra_facts_are_carried_forward_and_not_asked_again():
    result = say(at(SLEEP), "7 hours, and I walked 20 minutes to work")
    assert heard(result) == {SLEEP: 7, M: 20}
    assert result.message.startswith("7 hours of sleep and 20 minutes easy, got it.")
    # Only the part not said yet is asked: anything that got them out of breath.
    assert result.state.current_field == V and "out of breath" in result.message
    assert "easy, like" not in result.message


def test_extra_facts_about_someone_else_are_not_carried():
    result = say(at(SLEEP), "7 hours, my husband walked 30 minutes")
    assert heard(result) == {SLEEP: 7}


def test_go_back_with_the_new_answer_on_a_later_question():
    first = say(at(SLEEP), "7 hours")
    later = say(first.state, "go back, I slept 5 not 7")
    assert heard(later) == {SLEEP: 5}
    assert later.state.current_field == V  # back where it was


def test_no_wait_corrects_the_answer_just_heard():
    first = say(at("exercise_minutes_today", kind="daily"), "40 minutes")
    fixed = say(first.state, "no wait, 45 minutes")
    assert heard(fixed) == {"exercise_minutes_today": 45}
    assert fixed.state.current_field == "wellbeing"


# --- One read-back at the end ---------------------------------------------------------------


def test_a_quick_check_in_reads_back_once_at_the_end():
    result, messages = run(
        ["7 hours", "45 min HIIT at the gym, and I walked 20 min to work", "about 9 hours"]
    )
    assert [m for m in messages if "Is that right?" in m] == [messages[-1]]
    assert result.state.phase == "confirming" and result.state.current_field is None
    assert "you slept 7 hours last night" in messages[-1]
    assert "you sat for 9 hours yesterday" in messages[-1]
    assert result.state.confirmed.model_dump(exclude_none=True) == {}  # nothing saved yet
    fixed = say(result.state, "no, my sleep was 6 hours")
    assert heard(fixed)[SLEEP] == 6 and fixed.state.current_field is None
    done = say(fixed.state, "yes")
    assert done.complete
    assert done.state.confirmed.model_dump(exclude_none=True) == {SLEEP: 6, V: 45, M: 20, S: 540}


def test_a_daily_check_in_reads_back_once_at_the_end():
    # 24 October 2026 is a Saturday: the drinks question is asked too.
    result, messages = run(["7h", "a 30 minute walk", "none", "good"], kind="daily")
    assert sum("Is that right?" in m for m in messages) == 1
    assert messages[1].startswith("7 hours of sleep, got it.")
    assert say(result.state, "yes").complete


def test_a_no_at_the_end_asks_what_to_change():
    result, _ = run(["7 hours", "no, nothing", "about 6 hours"])
    asked = say(result.state, "no")
    assert asked.message.startswith("Okay. What should I change?")
    unclear = say(asked.state, "it was more")
    assert unclear.message.endswith("your sleep, your activity, or your sitting?")


def test_tapped_and_spoken_answers_get_the_same_single_read_back():
    tapped, _ = run(["about 6 hours"], topics=["sitting"])  # the "About 6 hours" button
    spoken, _ = run(["um, about six hours I think"], topics=["sitting"])
    assert tapped.state.phase == spoken.state.phase == "confirming"
    assert tapped.state.current_field is None and spoken.state.current_field is None


# --- Examples by age, and the closing line ---------------------------------------------------


def test_younger_people_hear_the_gym_and_the_commute():
    asked = start(age=28, topics=["activity", "sitting"]).message
    assert re.search(r"\b(?:run|gym|spin|football|HIIT|cycling)\b", asked)
    assert not re.search(r"garden|potter", asked)
    sitting = say(start(age=28, topics=["sitting"]).state, "help").message
    assert "desk" in sitting


def test_gardening_and_pottering_stay_for_older_people_only():
    older = say(start(age=74, topics=["activity"]).state, "a 20 minute jog").message
    assert "pottering about" in older
    for age in (28, None):
        message = say(start(age=age, topics=["activity"]).state, "a 20 minute jog").message
        assert "easier" in message and "pottering" not in message
    daily = start("daily", age=74).message + start("daily").message
    assert daily.count("gardening") <= 1


def test_the_closing_line_encourages_without_claims_or_streaks():
    for kind in ("quick", "daily"):
        line = CLOSINGS[kind]["default"]
        assert not line.startswith("That's all")
        assert not re.search(r"streak|in a row|healthier|risk|improv|forecast", line, re.I)
