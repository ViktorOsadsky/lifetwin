"""Daily and weekly check-ins with Mochi: scripts, phrase types, dialogues and the API.

The replies in data/checkin_replies.json are realistic older-adult answers, typed
and as voice transcripts. A held-out set is kept outside the repository and was
never used for tuning. A wrong value is worse than a miss, so every case either
reads exactly the expected value or asks again ("known_miss").
"""

import json
import logging
import math
import re
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin.models import (
    CheckinResponse,
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
)
from lifetwin.checkin.scripts import (
    CLOSINGS,
    DAILY,
    DAILY_WITH_HABIT,
    GREETINGS,
    HELP,
    HOW_ARE_YOU,
    NO_PREVIOUS,
    PRIVATE_NOTE,
    QUESTIONS,
    SAME_LEAD,
    SCRIPTS,
    WEEKLY,
    WHY_NOTES,
)
from lifetwin.checkin.service import UNKNOWN_LEAD, CheckinService
from lifetwin.core.config import Settings
from lifetwin.core.models import CheckinValues, HealthProfile
from lifetwin.onboarding.intents import EMERGENCY_MESSAGE, RESUME_LEAD, same_as_before
from lifetwin.onboarding.service import (
    LOUDER_LEAD,
    NO_LEAD,
    NOT_CAUGHT,
    REPEAT_LEAD,
    SKIPPED,
    SLOWER_LEAD,
    UNSURE_LEAD,
)

TODAY = date(2026, 10, 24)  # a Saturday: the daily habit question is asked
SERVICE = CheckinService(clock=lambda: TODAY)
CASES = json.loads((Path(__file__).parent / "data" / "checkin_replies.json").read_text())
LAST_WEEK = {
    "sleep_hours": 7,
    "exercise_minutes_weekly": 150,
    "alcohol_drinks_weekly": 3,
    "smoking_status": "former",
    "weight_kg": 72.57,
    "systolic_bp": 130,
    "diastolic_bp": 80,
    "wellbeing": "good",
}
YESTERDAY = {
    "sleep_hours_last_night": 6.5,
    "exercise_minutes_today": 30,
    "alcohol_drinks_yesterday": 1,
    "wellbeing": "okay",
}


def script_for(kind: str, field: str) -> tuple:
    if kind == "weekly":
        return WEEKLY
    return DAILY_WITH_HABIT if field == "alcohol_drinks_yesterday" else DAILY


def at(kind: str, field: str, previous: dict | None = None, **values) -> CheckinState:
    """A check-in at ``field``; the questions before it were skipped."""
    questions = list(script_for(kind, field))
    before = questions[: questions.index(field)]
    skipped = [*before, *(["diastolic_bp"] if "systolic_bp" in before else [])]
    return CheckinState(
        kind=kind,
        questions=questions,
        current_field=field,
        previous=previous or {},
        skipped_fields=values.pop("skipped_fields", skipped),
        **values,
    )


def say(state: CheckinState, text: str, mode: str = "text") -> CheckinResponse:
    return SERVICE.turn(CheckinTurnRequest(action="reply", state=state, text=text, input_mode=mode))


def pending(result: CheckinResponse) -> dict:
    return result.state.pending.model_dump(exclude_none=True)


def confirmed(result: CheckinResponse) -> dict:
    return result.state.confirmed.model_dump(exclude_none=True)


def same(got: dict, expected: dict) -> bool:
    if got.keys() != expected.keys():
        return False
    return all(
        got[k] == v
        if isinstance(v, str) or isinstance(got[k], str)
        else math.isclose(got[k], v, rel_tol=0.006, abs_tol=0.06)
        for k, v in expected.items()
    )


# --- The conversation corpus ---------------------------------------------------------


@pytest.mark.parametrize(
    "case", CASES, ids=[f"{c['script']}-{c['field']}-{i}" for i, c in enumerate(CASES)]
)
def test_corpus_reply(case):
    state = at(case["script"], case["field"], case["previous"])
    result = say(state, case["text"], case["mode"])
    got = pending(result)
    if case["expected"] is None or case.get("known_miss"):
        # Nothing may be taken: the reply is asked about again.
        assert got == {}, f"{case['text']!r} -> {got} ({case['why']})"
        assert result.state.phase == "asking"
    else:
        assert same(got, case["expected"]), f"{case['text']!r} -> {got} != {case['expected']}"
        assert result.state.phase == "confirming"
        assert result.message.endswith("Is that right?")


def test_corpus_size_and_coverage():
    assert len(CASES) >= 150
    transcripts = [c for c in CASES if c["mode"] == "transcript"]
    assert len(transcripts) >= 60
    fields = {(c["script"], c["field"]) for c in CASES}
    for kind, (script, *_) in SCRIPTS.items():
        questions = set(DAILY_WITH_HABIT) if kind == "daily" else set(script)
        assert {(kind, field) for field in questions} <= fields
    assert sum(c["expected"] is None for c in CASES) >= 40
    assert sum("same" in c["text"].lower() for c in CASES) >= 15
    # A known miss is a reply asked about again, never a wrong value.
    assert sum(bool(c.get("known_miss")) for c in CASES) <= 10


# --- Scripts -------------------------------------------------------------------------


def test_every_script_question_has_text_and_help():
    for kind, scripts in SCRIPTS.items():
        for script in scripts:
            for field in script:
                assert "ask" in QUESTIONS[kind][field]
                assert field in HELP[kind]


def test_question_text_is_short_and_plain():
    for questions in QUESTIONS.values():
        for forms in questions.values():
            for text in forms.values():
                assert len(text) <= 170, text
                assert not re.search(r"\b(?:forecast|predict\w*|score|risk|lifespan)\b", text, re.I)


@pytest.mark.parametrize("kind", ["daily", "weekly"])
def test_closings_are_encouraging_and_never_advice_or_a_prediction(kind):
    for line in CLOSINGS[kind].values():
        assert len(line) <= 120
        assert not re.search(r"\d", line)
        assert not re.search(
            r"\b(?:forecast|predict\w*|score|risk|years?|doctor|should|must|try to|advice|"
            r"recommend\w*|lifespan|health)\b",
            line,
            re.I,
        ), line


def test_weekly_answers_keep_the_profile_units_and_ranges():
    profile, checkin = HealthProfile.model_fields, CheckinValues.model_fields
    for field in WEEKLY + ("diastolic_bp",):
        if field == "wellbeing":
            continue
        assert repr(checkin[field].metadata) == repr(profile[field].metadata), field
        assert checkin[field].annotation == profile[field].annotation, field
    # Daily answers have their own names, so they never pass for a usual week.
    assert not set(DAILY_WITH_HABIT) - {"wellbeing"} & set(profile)


@pytest.mark.parametrize(
    ("local_date", "habit"),
    [
        ("2026-10-19", False),  # Monday
        ("2026-10-20", True),  # Tuesday
        ("2026-10-22", False),  # Thursday
        ("2026-10-24", True),  # Saturday
        ("2026-10-25", False),  # Sunday
    ],
)
def test_daily_habit_question_rotates_by_the_phones_day(local_date, habit):
    result = SERVICE.start(CheckinStartRequest(kind="daily", local_date=local_date))
    assert result.state.questions == list(DAILY_WITH_HABIT if habit else DAILY)


def test_server_day_is_used_when_the_phone_sends_none():
    result = CheckinService(clock=lambda: date(2026, 10, 19)).start(
        CheckinStartRequest(kind="daily")
    )
    assert result.state.questions == list(DAILY)


def test_greeting_mentions_the_last_answer_when_there_is_one():
    result = SERVICE.start(CheckinStartRequest(kind="weekly", previous=LAST_WEEK))
    assert result.message == (
        GREETINGS["weekly"] + " Last week you said about 7 hours of sleep a night. How has "
        "sleep been this week? About how many hours on a usual night?"
    )
    first = SERVICE.start(CheckinStartRequest(kind="weekly"))
    assert first.message == GREETINGS["weekly"] + " " + QUESTIONS["weekly"]["sleep_hours"]["ask"]
    assert first.state.phase == "asking" and first.state.current_field == "sleep_hours"


@pytest.mark.parametrize(
    ("field", "previous", "said"),
    [
        ("exercise_minutes_weekly", {"exercise_minutes_weekly": 0}, "didn't get to exercise"),
        ("alcohol_drinks_weekly", {"alcohol_drinks_weekly": 0}, "no alcoholic drinks"),
        ("smoking_status", {"smoking_status": "current"}, "you told me you smoke"),
        ("smoking_status", {"smoking_status": "former"}, "you used to smoke"),
        ("smoking_status", {"smoking_status": "never"}, None),
        ("weight_kg", {"weight_kg": 72.57}, "about 160 pounds"),
        ("systolic_bp", {"systolic_bp": 130, "diastolic_bp": 80}, "was 130 over 80"),
        ("systolic_bp", {"systolic_bp": 130}, None),  # half a reading is not mentioned
        ("wellbeing", {"wellbeing": "not_great"}, "your week was not so great"),
    ],
)
def test_weekly_questions_mention_the_last_answer(field, previous, said):
    message = SERVICE._question(at("weekly", field, previous))
    if said is None:
        assert message == QUESTIONS["weekly"][field]["ask"]
    else:
        assert said in message


# --- "Same as last week" -------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "same as last week",
        "Same as usual.",
        "about the same",
        "pretty much the same as always",
        "no change",
        "nothing's changed",
        "oh yeah about the same I'd say",
        "my weight is the same",
        "same old same old",
        "the usual",
        "it hasn't changed",
        "Same.",
    ],
)
def test_same_as_before_phrases(text):
    assert same_as_before(text)


@pytest.mark.parametrize(
    "text",
    [
        "not the same",
        "the same but a bit less",
        "same as last week, seven hours",
        "about the same as my husband",
        "same as last week maybe",
        "I'm not sure, about the same",
        "more than last week",
        "same 7 hours",
    ],
)
def test_not_a_plain_same(text):
    assert not same_as_before(text)


@pytest.mark.parametrize(
    ("kind", "field", "previous", "expected"),
    [
        ("weekly", "sleep_hours", LAST_WEEK, {"sleep_hours": 7}),
        ("weekly", "exercise_minutes_weekly", LAST_WEEK, {"exercise_minutes_weekly": 150}),
        ("weekly", "alcohol_drinks_weekly", LAST_WEEK, {"alcohol_drinks_weekly": 3}),
        ("weekly", "smoking_status", LAST_WEEK, {"smoking_status": "former"}),
        ("weekly", "weight_kg", LAST_WEEK, {"weight_kg": 72.57}),
        ("weekly", "systolic_bp", LAST_WEEK, {"systolic_bp": 130, "diastolic_bp": 80}),
        ("weekly", "wellbeing", LAST_WEEK, {"wellbeing": "good"}),
        ("daily", "sleep_hours_last_night", YESTERDAY, {"sleep_hours_last_night": 6.5}),
        ("daily", "exercise_minutes_today", YESTERDAY, {"exercise_minutes_today": 30}),
        ("daily", "alcohol_drinks_yesterday", YESTERDAY, {"alcohol_drinks_yesterday": 1}),
        ("daily", "wellbeing", YESTERDAY, {"wellbeing": "okay"}),
    ],
)
def test_same_as_last_time_reads_back_the_previous_value(kind, field, previous, expected):
    result = say(at(kind, field, previous), "um, about the same as last time", "transcript")
    assert pending(result) == expected
    assert result.message.startswith(SAME_LEAD + "I heard ")
    assert result.message.endswith("Is that right?")
    # Still only saved after a yes.
    assert confirmed(result) == {}
    assert confirmed(say(result.state, "yes")) == expected


def test_same_without_a_last_answer_asks_the_question():
    result = say(at("weekly", "weight_kg"), "same as last week")
    assert pending(result) == {}
    assert result.message == NO_PREVIOUS + QUESTIONS["weekly"]["weight_kg"]["ask"]


def test_same_blood_pressure_needs_both_previous_numbers():
    result = say(at("weekly", "systolic_bp", {"systolic_bp": 130}), "same as last time")
    assert pending(result) == {}
    assert result.message.startswith(NO_PREVIOUS)


# --- Comparisons, bad nights and zeros ------------------------------------------------


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("sleep_hours_last_night", "a bit more than usual"),
        ("sleep_hours_last_night", "less than last night"),
        ("exercise_minutes_today", "a little less than usual"),
        ("alcohol_drinks_yesterday", "more than usual I'm afraid"),
    ],
)
def test_more_or_less_than_usual_asks_for_a_number(field, text):
    result = say(at("daily", field, YESTERDAY), text)
    assert pending(result) == {}
    assert result.message.startswith("More or less is fine, but I need a number. ")


@pytest.mark.parametrize("text", ["a bit more than last week", "not as much as usual"])
def test_weekly_comparisons_ask_for_a_number(text):
    result = say(at("weekly", "exercise_minutes_weekly", LAST_WEEK), text)
    assert pending(result) == {}
    assert result.message.startswith("More or less is fine, but I need a number.")


def test_weight_change_asks_what_the_scale_says():
    result = say(at("weekly", "weight_kg", LAST_WEEK), "I lost two pounds")
    assert pending(result) == {}
    assert result.message.endswith("What do you weigh now? For example, 160 pounds.")


@pytest.mark.parametrize(
    "text", ["I had a bad night", "tossed and turned all night", "didn't sleep well at all"]
)
def test_bad_night_asks_for_hours(text):
    result = say(at("daily", "sleep_hours_last_night"), text)
    assert pending(result) == {}
    assert result.message == (
        "I'm sorry to hear that. About how many hours did you sleep last night?"
    )


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("exercise_minutes_today", "no", 0),
        ("exercise_minutes_today", "I didn't", 0),
        ("exercise_minutes_today", "not today", 0),
        ("exercise_minutes_today", "nope not today, my knee's acting up", 0),
        ("exercise_minutes_today", "not at all", 0),
        ("alcohol_drinks_yesterday", "none", 0),
        ("alcohol_drinks_yesterday", "no, I didn't have any", 0),
        ("alcohol_drinks_yesterday", "not a drop", 0),
        ("sleep_hours_last_night", "I didn't sleep a wink", 0),
    ],
)
def test_daily_zeros(field, text, expected):
    result = say(at("daily", field), text)
    assert pending(result) == {field: expected}


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("exercise_minutes_weekly", "I didn't exercise this week"),
        ("exercise_minutes_weekly", "none this week"),
        ("alcohol_drinks_weekly", "I didn't have any this week"),
        ("alcohol_drinks_weekly", "none"),
    ],
)
def test_weekly_zeros(field, text):
    assert pending(say(at("weekly", field), text)) == {field: 0}


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("exercise_minutes_today", "I didn't move much"),
        ("sleep_hours_last_night", "I didn't sleep well"),
        ("sleep_hours_last_night", "I hardly slept at all"),
        ("exercise_minutes_weekly", "I didn't do much this week"),
    ],
)
def test_not_much_is_not_zero(field, text):
    kind = "weekly" if field == "exercise_minutes_weekly" else "daily"
    assert pending(say(at(kind, field), text)) == {}


# --- Time words: last night, today, this week ------------------------------------------


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("sleep_hours_last_night", "last night I slept about six hours", 6),
        ("sleep_hours_last_night", "I slept seven hours", 7),
        ("sleep_hours_last_night", "from 11 till 6", 7),
        ("sleep_hours_last_night", "went to bed at ten and got up at six", 8),
        ("sleep_hours_last_night", "six, no, seven hours", 7),
        ("sleep_hours_last_night", "six or seven hours", 6.5),
        ("exercise_minutes_today", "I walked for an hour this morning", 60),
        ("exercise_minutes_today", "half an hour", 30),
        ("exercise_minutes_today", "twice, 20 minutes each", 40),
        ("exercise_minutes_today", "20 minutes this morning and half an hour after lunch", 50),
        ("exercise_minutes_today", "about 45", 45),
        ("alcohol_drinks_yesterday", "a glass of wine with dinner", 1),
        ("alcohol_drinks_yesterday", "half a glass of champagne", 0.5),
        ("alcohol_drinks_yesterday", "a beer and two glasses of wine", 3),
        ("alcohol_drinks_yesterday", "two beers last night", 2),
    ],
)
def test_daily_answers(field, text, expected):
    assert same(pending(say(at("daily", field), text)), {field: expected})


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("sleep_hours", "I slept about seven hours most nights this week", 7),
        ("sleep_hours", "seven and a half", 7.5),
        ("exercise_minutes_weekly", "I swam Monday and Wednesday, about an hour each", 120),
        ("exercise_minutes_weekly", "I walked Monday and Wednesday, about an hour each", 120),
        ("exercise_minutes_weekly", "this week I walked 90 minutes", 90),
        ("exercise_minutes_weekly", "30 minutes every day", 210),
        ("exercise_minutes_weekly", "an hour three times this week", 180),
        ("exercise_minutes_weekly", "about two hours this week", 120),
        ("alcohol_drinks_weekly", "a glass of wine every night", 7),
        ("alcohol_drinks_weekly", "two beers on Friday and two on Saturday", 4),
        ("alcohol_drinks_weekly", "Two gin and tonics on Thursday and one on Sunday", 3),
        ("alcohol_drinks_weekly", "a couple of beers two nights", 4),
        ("weight_kg", "one sixty", 72.57),
        ("weight_kg", "about 165 pounds", 74.84),
        ("weight_kg", "I weighed 158 this morning", 71.67),
    ],
)
def test_weekly_answers(field, text, expected):
    assert same(pending(say(at("weekly", field), text)), {field: expected})


@pytest.mark.parametrize(
    ("field", "text", "lead"),
    [
        ("exercise_minutes_today", "yesterday I walked an hour", "And today? "),
        ("exercise_minutes_today", "I usually walk 30 minutes", "And today? "),
        ("alcohol_drinks_yesterday", "I'll have a glass of wine tonight", None),
        ("alcohol_drinks_yesterday", "two glasses today", "And yesterday? "),
        ("sleep_hours_last_night", "I usually sleep 7 hours", "And last night? "),
    ],
)
def test_another_day_is_not_the_answer(field, text, lead):
    result = say(at("daily", field), text)
    assert pending(result) == {}
    if lead:
        assert result.message.startswith(lead)


def test_last_week_is_asked_about_for_this_weeks_habits():
    result = say(at("weekly", "exercise_minutes_weekly"), "last week I walked about two hours")
    assert pending(result) == {}
    assert result.message.startswith("And this past week? ")


def test_steps_are_asked_as_minutes():
    result = say(at("daily", "exercise_minutes_today"), "about 5000 steps")
    assert pending(result) == {}
    assert result.message == "Thank you. About how many minutes did you move today?"


@pytest.mark.parametrize("text", ["yes", "I went for a walk", "did some gardening"])
def test_moving_without_minutes_asks_how_long(text):
    result = say(at("daily", "exercise_minutes_today"), text)
    assert pending(result) == {}
    assert result.message == "Good for you! About how many minutes did you move today?"


def test_an_hour_for_the_week_asks_how_often():
    result = say(at("weekly", "exercise_minutes_weekly"), "about an hour")
    assert pending(result) == {}
    assert "each time" in result.message


# --- Smoking and blood pressure ---------------------------------------------------------


@pytest.mark.parametrize(
    ("previous", "text", "expected"),
    [
        ("never", "no", "never"),
        ("former", "no I don't", "former"),
        ("current", "no", "former"),
        ("current", "not anymore", "former"),
        (None, "I quit smoking last month", "former"),
        ("never", "yes", "current"),
        ("former", "yes, I'm afraid so", "current"),
        ("current", "I still smoke", "current"),
        ("current", "I'm trying to quit", "current"),
        ("former", "only on holidays", "current"),
    ],
)
def test_smoking_now(previous, text, expected):
    state = at("weekly", "smoking_status", {"smoking_status": previous} if previous else {})
    assert pending(say(state, text)) == {"smoking_status": expected}


def test_a_plain_no_without_a_last_answer_asks_about_the_past():
    result = say(at("weekly", "smoking_status"), "no")
    assert pending(result) == {}
    assert result.message.startswith("Did you ever smoke in the past?")


@pytest.mark.parametrize("text", ["I vape now and then", "just the odd joint"])
def test_vaping_and_cannabis_are_not_tobacco(text):
    assert pending(say(at("weekly", "smoking_status", LAST_WEEK), text)) == {}


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("my doctor said 130 over 80 on Tuesday", (130, 80)),
        ("one twenty eight over seventy six", (128, 76)),
        ("It was 142/88 at the pharmacy", (142, 88)),
    ],
)
def test_blood_pressure_readings(text, expected):
    result = say(at("weekly", "systolic_bp"), text)
    assert pending(result) == {"systolic_bp": expected[0], "diastolic_bp": expected[1]}


@pytest.mark.parametrize(
    "text",
    ["no", "I haven't had it checked", "not lately", "nope, haven't checked it", "no new reading"],
)
def test_no_new_blood_pressure_reading_is_skipped(text):
    result = say(at("weekly", "systolic_bp", LAST_WEEK), text)
    assert result.message.startswith(SKIPPED)
    assert result.state.skipped_fields[-2:] == ["systolic_bp", "diastolic_bp"]
    assert result.state.current_field == "wellbeing"


def test_one_blood_pressure_number_asks_for_both():
    result = say(at("weekly", "systolic_bp"), "it was 130")
    assert pending(result) == {}
    assert "both blood pressure numbers" in result.message


def test_blood_pressure_in_the_wrong_order_is_asked_again():
    result = say(at("weekly", "systolic_bp"), "80 over 130")
    assert pending(result) == {}
    assert "bigger one" in result.message


# --- How the person feels --------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("good", "good"),
        ("pretty good, thanks", "good"),
        ("Wonderful!", "good"),
        ("doing well", "good"),
        ("couldn't be better", "good"),
        ("okay", "okay"),
        ("fine", "okay"),
        ("not bad", "okay"),
        ("not too bad", "okay"),
        ("can't complain", "okay"),
        ("so-so", "okay"),
        ("not great", "not_great"),
        ("not so good", "not_great"),
        ("a bit under the weather", "not_great"),
        ("I don't feel well", "not_great"),
        ("lousy", "not_great"),
        ("Good morning Mochi, I'm okay", "okay"),
    ],
)
def test_feelings(text, expected):
    assert pending(say(at("daily", "wellbeing"), text)) == {"wellbeing": expected}


@pytest.mark.parametrize(
    "text",
    [
        "good this morning but awful now",
        "okay I guess, not really",
        "my wife is not great",
        "busy",
        "good but tired",
    ],
)
def test_mixed_or_unclear_feelings_are_asked_about(text):
    result = say(at("daily", "wellbeing"), text)
    assert pending(result) == {}
    assert result.state.phase == "asking"


def test_mixed_feelings_get_the_three_choices():
    result = say(at("daily", "wellbeing"), "good this morning but awful now")
    assert result.message == "Would you say good, okay, or not great?"


def test_a_feeling_and_a_question_back_get_a_kind_word():
    result = say(at("daily", "wellbeing"), "I'm good, how about you?")
    assert pending(result) == {"wellbeing": "good"}
    assert result.message.startswith(HOW_ARE_YOU + "I heard you're feeling good today.")


@pytest.mark.parametrize("text", ["how are you", "How are you, Mochi?", "and you?"])
def test_how_are_you_on_its_own(text):
    state = at("daily", "wellbeing")
    result = say(state, text)
    assert result.message == HOW_ARE_YOU + QUESTIONS["daily"]["wellbeing"]["ask"]
    assert result.state == state


def test_weekly_feeling_reads_back_the_week():
    result = say(at("weekly", "wellbeing"), "it was a rough week")
    assert pending(result) == {"wellbeing": "not_great"}
    assert result.message == "I heard your week was not great. Is that right?"


# --- Onboarding behaviours still hold ----------------------------------------------------


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("sleep_hours", "six hours, sorry, seven", 7),  # self-correction
        ("weight_kg", "one eighty", 81.65),  # split number
        ("weight_kg", "I'd say roughly 150 pounds", 68.04),  # hedge
        ("sleep_hours", "between 6 and 7 hours", 6.5),  # range
        ("exercise_minutes_weekly", "30 to 40 minutes three times", 105),  # close range
    ],
)
def test_onboarding_readings_still_work(field, text, expected):
    assert same(pending(say(at("weekly", field), text)), {field: expected})


def test_a_range_is_read_back_as_about():
    result = say(at("weekly", "sleep_hours"), "6 or 7 hours")
    assert (
        result.message
        == "I heard you slept about 6.5 hours on a usual night this week. Is that right?"
    )


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("sleep_hours", "my husband slept nine hours"),
        ("weight_kg", "my wife weighs 140"),
        ("exercise_minutes_weekly", "my daughter walks 200 minutes a week"),
        ("sleep_hours", "I used to sleep eight hours"),
        ("sleep_hours", "my doctor says I need 8 hours"),
        ("exercise_minutes_weekly", "I want to walk 200 minutes"),
        ("weight_kg", "is 160 a lot?"),
        ("sleep_hours", "five to eight hours"),
    ],
)
def test_someone_elses_old_or_wished_values_are_never_taken(field, text):
    assert pending(say(at("weekly", field), text)) == {}


def test_someone_elses_number_beside_your_own_is_asked_about_by_voice():
    result = say(
        at("daily", "sleep_hours_last_night"),
        "my husband says nine but i slept seven hours",
        "transcript",
    )
    assert pending(result) == {}


@pytest.mark.parametrize(
    "text",
    [
        "Honey, can you turn the TV down? Seven hours.",
        "who's at the door. um seven hours",
    ],
)
def test_room_chatter_is_left_out(text):
    result = say(at("daily", "sleep_hours_last_night"), text, "transcript")
    assert pending(result) == {"sleep_hours_last_night": 7}


@pytest.mark.parametrize(
    ("text", "lead", "hint"),
    [
        ("what?", REPEAT_LEAD, None),
        ("say that again", REPEAT_LEAD, None),
        ("slow down please", SLOWER_LEAD, "slower"),
        ("I can't hear you", LOUDER_LEAD, "louder"),
    ],
)
def test_repeat_slower_louder(text, lead, hint):
    state = at("weekly", "weight_kg", LAST_WEEK)
    result = say(state, text)
    assert result.message == lead + SERVICE._question(state)
    assert result.speech_hint == hint
    assert result.state == state


def test_help_why_and_privacy_keep_the_question():
    state = at("daily", "exercise_minutes_today")
    assert say(state, "help").message.startswith(HELP["daily"]["exercise_minutes_today"])
    assert say(state, "why do you need that").message.startswith(WHY_NOTES["daily"])
    assert say(state, "is this private?").message.startswith(PRIVATE_NOTE)
    assert say(state, "help").state == state


def test_a_question_back_is_never_an_answer():
    result = say(at("weekly", "weight_kg"), "is 160 too much?")
    assert pending(result) == {}
    assert result.message.startswith("That's a good question")


def test_not_caught_repeats_the_question():
    state = at("weekly", "weight_kg", LAST_WEEK)
    result = say(state, "the cat knocked the plant over")
    assert result.message == NOT_CAUGHT + " " + SERVICE._question(state)


@pytest.mark.parametrize("text", ["skip", "I'd rather not say"])
def test_skip_words(text):
    result = say(at("weekly", "weight_kg"), text)
    assert result.message.startswith(SKIPPED)
    assert result.state.skipped_fields[-1] == "weight_kg"
    assert result.state.current_field == "systolic_bp"


# Conversation v2: not knowing is recorded as unknown, distinct from skipping.
@pytest.mark.parametrize("text", ["pass", "I don't know", "not sure", "I'd have to check"])
def test_unknown_words(text):
    result = say(at("weekly", "weight_kg"), text)
    assert result.message.startswith(UNKNOWN_LEAD)
    assert result.state.unknown_fields == ["weight_kg"]
    assert "weight_kg" not in result.state.skipped_fields
    assert result.state.current_field == "systolic_bp"
    assert result.profile_update.weight_kg is None


def test_the_skip_button():
    state = at("daily", "sleep_hours_last_night")
    result = SERVICE.turn(CheckinTurnRequest(action="skip", state=state))
    assert result.state.skipped_fields == ["sleep_hours_last_night"]
    assert result.state.current_field == "exercise_minutes_today"


# --- Read-backs -----------------------------------------------------------------------------


def read_back(field: str, value, kind: str = "daily") -> CheckinState:
    return at(kind, field, phase="confirming", pending={field: value})


def test_only_a_clear_yes_saves():
    state = read_back("sleep_hours_last_night", 7)
    assert confirmed(say(state, "yes")) == {"sleep_hours_last_night": 7}
    for text in ["ok", "I guess so", "maybe", "yes?"]:
        result = say(state, text)
        assert result.message.startswith(UNSURE_LEAD)
        assert confirmed(result) == {}


def test_no_asks_for_the_right_answer_then_reads_it_back():
    state = read_back("exercise_minutes_today", 30)
    result = say(state, "no")
    assert result.message.startswith(NO_LEAD + "What is the right answer?")
    assert pending(result) == {"exercise_minutes_today": 30}
    result = say(result.state, "45 minutes")
    assert pending(result) == {"exercise_minutes_today": 45}
    assert confirmed(result) == {}


def test_a_correction_to_a_read_back_replaces_it():
    result = say(read_back("alcohol_drinks_yesterday", 2), "no, three")
    assert pending(result) == {"alcohol_drinks_yesterday": 3}


def test_yes_with_another_value_is_not_a_yes():
    result = say(read_back("sleep_hours_last_night", 7), "yes, 8")
    assert result.message.startswith(UNSURE_LEAD)
    assert confirmed(result) == {}


def test_yes_with_the_same_value_confirms():
    result = say(read_back("sleep_hours_last_night", 7), "yes, 7 hours")
    assert confirmed(result) == {"sleep_hours_last_night": 7}


def test_confirm_and_skip_buttons_check_the_phase():
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as caught:
        SERVICE.turn(CheckinTurnRequest(action="confirm", state=at("daily", "wellbeing")))
    assert caught.value.status_code == 409
    with pytest.raises(HTTPException):
        SERVICE.turn(CheckinTurnRequest(action="skip", state=read_back("wellbeing", "good")))


# --- Privacy ----------------------------------------------------------------------------------


def test_privacy_replies_say_check_ins_stay_on_the_phone():
    for note in (PRIVATE_NOTE, *WHY_NOTES.values()):
        assert "stay on your phone" in note
        assert "Nothing is saved until you say yes." in note
    assert "doesn't keep them" in PRIVATE_NOTE
    assert "forecast" in WHY_NOTES["weekly"] and "forecast" not in WHY_NOTES["daily"]
    state = at("weekly", "weight_kg")
    assert say(state, "why do you ask").message.startswith(WHY_NOTES["weekly"])


# --- Weekly answers update the profile; daily answers are history only ---------------------


def test_a_weekly_check_in_returns_its_answers_as_a_profile_update():
    result, _ = run("weekly", LAST_WEEK, ["6 hours", "yes", "none", "yes", "<skip>"])
    assert result.profile_update.model_dump(exclude_none=True) == {
        "sleep_hours": 6,
        "exercise_minutes_weekly": 0,
    }
    result, _ = run(
        "weekly",
        LAST_WEEK,
        [
            "6 hours",
            "yes",
            "90 minutes",
            "yes",
            "2 drinks",
            "yes",
            "no",
            "yes",
            "158 pounds",
            "yes",
            "128 over 78",
            "yes",
            "good",
            "yes",
        ],
    )
    assert result.complete
    update = result.profile_update
    assert isinstance(update, HealthProfile)
    assert same(
        update.model_dump(exclude_none=True),
        {
            "sleep_hours": 6,
            "exercise_minutes_weekly": 90,
            "alcohol_drinks_weekly": 2,
            "smoking_status": "former",
            "weight_kg": 71.67,
            "systolic_bp": 128,
            "diastolic_bp": 78,
        },
    )
    # Applying it is a plain field-by-field replace on the confirmed profile.
    profile = HealthProfile(age=74, sex="female", height_cm=160, sleep_hours=7, diabetes=False)
    applied = HealthProfile.model_validate(
        profile.model_dump() | update.model_dump(exclude_none=True)
    )
    assert applied.age == 74 and applied.sleep_hours == 6 and applied.systolic_bp == 128


def test_a_daily_check_in_never_updates_the_profile():
    result, _ = run(
        "daily",
        YESTERDAY,
        ["7 hours", "yes", "30 minutes", "yes", "good", "yes"],
        local_date="2026-10-19",
    )
    assert result.complete
    assert confirmed(result) == {
        "sleep_hours_last_night": 7,
        "exercise_minutes_today": 30,
        "wellbeing": "good",
    }
    assert result.profile_update.model_dump(exclude_none=True) == {}


# --- Emergencies ------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "not great, I've had chest pain all morning",
        "i think im having a heart attack",
        "I can't breathe properly",
        "i cant catch my breath",
        "my chest hurts",
        "I fell and I can't get up",
        "I want to die",
        "i just want to end it all",
        "please call an ambulance",
        "my husband is having a stroke",
    ],
)
def test_an_emergency_pauses_the_check_in(text):
    state = at("daily", "wellbeing")
    result = say(state, text, "transcript")
    assert result.emergency
    assert result.message == EMERGENCY_MESSAGE
    assert "If you need help right now, please call 911." in result.message
    assert [event.state for event in result.mascot_events] == ["concerned"]
    # Paused: nothing taken, no next question.
    assert result.state == state
    assert "?" not in result.message


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        # History, read normally.
        # Read normally: a year beside the feeling is asked about, like any other number.
        ("wellbeing", "good, my heart attack was in 2015", None),
        ("wellbeing", "I'm dying to see my grandkids, I feel great", {"wellbeing": "good"}),
        ("wellbeing", "not great, this pain in my knee", {"wellbeing": "not_great"}),
        ("exercise_minutes_today", "no, I had chest pain years ago and I take it easy", None),
        (
            "sleep_hours_last_night",
            "seven hours, killing myself laughing at the tv",
            {"sleep_hours_last_night": 7},
        ),
    ],
)
def test_history_and_figures_of_speech_are_not_emergencies(field, text, expected):
    """Not paused: the reply goes through the normal reading."""
    result = say(at("daily", field), text)
    assert not result.emergency
    assert [event.state for event in result.mascot_events] != ["concerned"]
    if expected:
        assert pending(result) == expected
    else:
        assert pending(result) == {} and result.state.phase == "asking"


def test_continue_resumes_the_same_question():
    state = at("weekly", "weight_kg", LAST_WEEK)
    paused = say(state, "I have chest pain")
    assert paused.emergency
    for resumed in (
        SERVICE.turn(CheckinTurnRequest(action="resume", state=paused.state)),
        say(paused.state, "okay, let's continue"),
    ):
        assert not resumed.emergency
        assert resumed.message == RESUME_LEAD + SERVICE._question(state)
        assert resumed.state == state
    # A plain answer after the pause is read as usual.
    assert same(pending(say(paused.state, "158 pounds")), {"weight_kg": 71.67})


def test_an_emergency_during_a_read_back_keeps_the_read_back():
    state = read_back("sleep_hours_last_night", 7)
    paused = say(state, "yes but I can't breathe")
    assert paused.emergency and paused.state == state
    resumed = SERVICE.turn(CheckinTurnRequest(action="resume", state=paused.state))
    assert resumed.message == RESUME_LEAD + "I heard you slept 7 hours last night. Is that right?"


# --- Whole dialogues --------------------------------------------------------------------------


def run(kind: str, previous: dict, replies: list, local_date: str | None = None):
    result = SERVICE.start(CheckinStartRequest(kind=kind, previous=previous, local_date=local_date))
    messages = [result.message]
    for reply in replies:
        action, text, mode = "reply", reply, "text"
        if reply in {"<skip>", "<confirm>"}:
            action, text = reply.strip("<>"), None
        elif reply.startswith("~"):
            text, mode = reply[1:], "transcript"
        result = SERVICE.turn(
            CheckinTurnRequest(action=action, state=result.state, text=text, input_mode=mode)
        )
        messages.append(result.message)
    return result, messages


def test_a_full_weekly_check_in_with_corrections_go_back_skip_same_and_chatter():
    result, messages = run(
        "weekly",
        LAST_WEEK,
        [
            "~um about the same as last week",  # same -> 7 hours, read back
            "yes",
            "I swam Monday and Wednesday, about an hour each",  # 120
            "no, 90 minutes",  # corrected in the read-back
            "yes",
            "~honey can you turn the tv down. two glasses of wine on friday and one on saturday",
            "yeah",
            "go back",  # reopens drinks
            "it was 4 actually",
            "yes",
            "no",  # former smoker, still not smoking
            "yes",
            "my wife weighs 140 and I weigh 158",  # someone else's number: asked again
            "158 pounds",
            "that's right",
            "<skip>",  # blood pressure button
            "not great to be honest, my hip was sore",
            "yes",
        ],
    )
    assert result.complete and result.state.phase == "ready"
    assert same(
        confirmed(result),
        {
            "sleep_hours": 7,
            "exercise_minutes_weekly": 90,
            "alcohol_drinks_weekly": 4,
            "smoking_status": "former",
            "weight_kg": 71.67,
            "wellbeing": "not_great",
        },
    )
    assert result.state.skipped_fields == ["systolic_bp", "diastolic_bp"]
    assert messages[1].startswith(SAME_LEAD)
    assert messages[8].startswith("Okay, let's go back to your drinks.")
    assert messages[-1] == "Got it. " + CLOSINGS["weekly"]["not_great"]


def test_a_full_daily_check_in_on_a_habit_day():
    result, messages = run(
        "daily",
        YESTERDAY,
        [
            "~uh i had a bad night",
            "~maybe five hours",
            "yep",
            "a bit more than usual",
            "40 minutes",
            "no wait 45",
            "yes",
            "a glass of wine with dinner",
            "<confirm>",
            "~oh not too bad how are you",
            "yes",
        ],
        local_date="2026-10-24",
    )
    assert result.complete
    assert confirmed(result) == {
        "sleep_hours_last_night": 5,
        "exercise_minutes_today": 45,
        "alcohol_drinks_yesterday": 1,
        "wellbeing": "okay",
    }
    assert messages[0].startswith(GREETINGS["daily"] + " Last time you slept 6.5 hours.")
    assert messages[1].startswith("I'm sorry to hear that.")
    assert messages[4].startswith("More or less is fine")
    assert messages[-1] == "Got it. " + CLOSINGS["daily"]["default"]


def test_start_over_needs_an_explicit_yes_and_keeps_the_previous_answers():
    result, _ = run("daily", YESTERDAY, ["7 hours", "yes", "start over"], local_date="2026-10-19")
    assert result.message.startswith("Do you want to clear today's answers")
    assert confirmed(result) == {"sleep_hours_last_night": 7}
    result = say(result.state, "yes, start over")
    assert confirmed(result) == {}
    assert result.state.current_field == "sleep_hours_last_night"
    assert result.state.previous == CheckinValues.model_validate(YESTERDAY)


def test_change_a_named_answer_mid_check_in():
    result, _ = run(
        "daily", {}, ["7 hours", "yes", "change my sleep to 6 hours"], local_date="2026-10-19"
    )
    assert pending(result) == {"sleep_hours_last_night": 6}
    result = say(result.state, "yes")
    assert confirmed(result) == {"sleep_hours_last_night": 6}
    assert result.state.current_field == "exercise_minutes_today"


def test_go_back_on_the_first_question():
    result, _ = run("weekly", {}, ["go back"])
    assert result.message.startswith("This is the first question")


def test_cancel_clears_today_and_keeps_nothing():
    result, _ = run("daily", {}, ["7 hours", "yes"], local_date="2026-10-19")
    result = SERVICE.turn(CheckinTurnRequest(action="cancel", state=result.state))
    assert result.state.phase == "cancelled"
    assert confirmed(result) == {}
    assert "Nothing was saved" in result.message


def test_after_the_end_replies_are_kind():
    result, _ = run("daily", {}, ["<skip>", "<skip>", "<skip>"], local_date="2026-10-19")
    assert result.complete
    assert (
        say(result.state, "thank you").message
        == "You're welcome! We're all done for now. Thank you!"
    )


# --- State and API ----------------------------------------------------------------------------


def test_state_must_follow_a_script():
    with pytest.raises(ValueError):
        CheckinState(kind="daily", questions=["sleep_hours"], current_field="sleep_hours")
    with pytest.raises(ValueError):
        CheckinState(
            kind="weekly",
            questions=list(WEEKLY),
            current_field="sleep_hours",
            confirmed={"sleep_hours_last_night": 7},
        )


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


def test_api_round_trip(client):
    start = client.post("/api/checkin/start", json={"kind": "weekly", "previous": LAST_WEEK})
    assert start.status_code == 200
    state = start.json()["state"]
    turn = client.post(
        "/api/checkin/turn", json={"action": "reply", "text": "same as last week", "state": state}
    )
    assert turn.status_code == 200
    body = turn.json()
    assert body["state"]["pending"]["sleep_hours"] == 7
    assert body["state"]["phase"] == "confirming"
    done = client.post("/api/checkin/turn", json={"action": "confirm", "state": body["state"]})
    assert done.json()["state"]["confirmed"]["sleep_hours"] == 7


def test_api_errors(client):
    bad = client.post("/api/checkin/start", json={"kind": "daily", "local_date": "2026-13-40"})
    assert bad.status_code == 409
    assert client.post("/api/checkin/start", json={"kind": "monthly"}).status_code == 422
    state = SERVICE.start(CheckinStartRequest(kind="daily")).state.model_dump(mode="json")
    assert (
        client.post("/api/checkin/turn", json={"action": "reply", "state": state}).status_code
        == 422
    )


def test_health_values_never_reach_the_logs(monkeypatch, caplog):
    import lifetwin.checkin.service as service

    def broken(*args, **kwargs):
        raise RuntimeError("weight 158 pounds")

    monkeypatch.setattr(service, "parse_reply", broken)
    with caplog.at_level(logging.DEBUG):
        result = say(at("weekly", "weight_kg"), "I weigh 158 pounds")
    assert pending(result) == {}
    assert result.message.startswith(NOT_CAUGHT)
    logged = " ".join(record.getMessage() for record in caplog.records)
    assert "158" not in logged and "pounds" not in logged
    assert "RuntimeError" in logged


# -- Conversation v2, lightly: unknowns, one habit follow-up, supplements ----------------


def test_one_habit_follow_up_with_memory_and_none_without():
    state = at("daily", "exercise_minutes_today", memory_consent=True)
    asked = say(say(state, "a 20 minute walk").state, "yes")
    assert asked.state.phase == "probing" and asked.state.probe_topic == "exercise"
    assert asked.message.endswith("What did you do? Or we can just move on.")
    told = say(asked.state, "I walked with my neighbor after dinner")
    assert told.state.phase == "asking" and told.state.current_field == "wellbeing"
    note = told.state.habit_notes[0]
    assert (note.kind, note.with_, note.time_of_day) == ("walking", "neighbor", "after dinner")
    plain = say(say(at("daily", "exercise_minutes_today"), "a 20 minute walk").state, "yes")
    assert plain.state.phase == "asking" and plain.state.habit_notes == []


def test_the_follow_up_is_skippable_and_asked_once():
    state = at("daily", "sleep_hours_last_night", memory_consent=True)
    asked = say(say(state, "about 5 hours").state, "yes")
    assert asked.state.probe_topic == "sleep"
    moved = say(asked.state, "let's move on")
    assert moved.state.phase == "asking" and moved.state.habit_notes == []
    again = say(say(moved.state, "30 minutes").state, "yes")
    assert again.state.phase != "probing"


def test_checkin_supplement_question_gets_the_fixed_reply():
    from lifetwin.onboarding.script import SUPPLEMENT_REPLY

    result = say(at("weekly", "weight_kg"), "should I take fish oil?")
    assert result.message.startswith(SUPPLEMENT_REPLY)
    assert result.state.current_field == "weight_kg"


@pytest.mark.parametrize(
    "text", ["I don't understand", "say that again", "let's talk about my sleep", "go back"]
)
def test_controls_during_the_follow_up_never_crash(text):
    state = at("daily", "exercise_minutes_today", memory_consent=True)
    asked = say(say(state, "a 20 minute walk").state, "yes")
    assert asked.state.phase == "probing"
    result = say(asked.state, text)
    CheckinState.model_validate(result.state.model_dump())
    assert result.message


def test_restart_keeps_memory_consent():
    state = at("daily", "wellbeing", memory_consent=True)
    result = say(state, "yes, start over")
    assert result.message.startswith("Okay, let's start over.")
    assert result.state.memory_consent is True


def test_someone_elses_weight_given_possessively_is_refused():
    result = say(at("weekly", "weight_kg"), "her weight is 150 pounds")
    assert pending(result) == {}
