"""Flexible intake: everyday wording is understood, and nothing unsafe is accepted.

The acceptance corpus lives in test_intake_variants.py. These tests pin the
individual rules: each refusal of a provider quote, the wrong-value traps found
while hardening the parser, and the conversation-level follow-ups.
"""

import asyncio
from datetime import date

import pytest

from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.models import ConversationState, ExtractionResult, TurnRequest
from lifetwin.onboarding.parsing import QUESTIONS, grounded_candidates, parse_reply

TODAY = date(2026, 10, 24)


def extraction(*candidates: tuple[str, str]) -> ExtractionResult:
    return ExtractionResult.model_validate(
        {"candidates": [{"field": field, "quote": quote} for field, quote in candidates]}
    )


def reply(field: str, text: str, service: ConversationService | None = None, **state):
    request = TurnRequest(
        action="reply",
        state=ConversationState(phase="asking", current_field=field, **state),
        text=text,
    )
    return asyncio.run((service or ConversationService(clock=lambda: TODAY)).turn(request))


# --- Provider grounding: what the loosened rule now accepts -----------------------


def test_grounding_accepts_every_quoted_value_of_a_multi_answer_reply():
    text = "Well, I'm 72, five foot six, and I weigh 150 pounds"
    assert parse_reply(text, "age") == {}  # "Well" answers nothing: the parser asks again
    quotes = extraction(
        ("age", "I'm 72"), ("height_cm", "five foot six"), ("weight_kg", "150 pounds")
    )
    assert grounded_candidates(text, quotes, "age") == {
        "age": 72,
        "height_cm": pytest.approx(167.64),
        "weight_kg": pytest.approx(68.0389),
    }


def test_grounding_accepts_a_value_beside_unrelated_chatter():
    text = "Well, my grandson keeps asking, but I'm 76 and proud of it"
    assert parse_reply(text, "age") == {}  # someone else is mentioned
    assert grounded_candidates(text, extraction(("age", "I'm 76")), "age") == {"age": 76}


def test_grounding_accepts_a_number_that_belongs_to_another_named_topic():
    text = "I'm 72 years old and I weigh 70 kg"
    assert grounded_candidates(text, extraction(("weight_kg", "70 kg")), "weight_kg") == {
        "weight_kg": 70.0
    }


# --- Provider grounding: every refusal ----------------------------------------------


@pytest.mark.parametrize(
    ("text", "field", "quote"),
    [
        # The quote must be an exact, whole-word substring of the reply.
        ("I weigh 150 pounds", "weight_kg", "160 pounds"),
        ("I weigh 150 pounds", "weight_kg", "50 pounds"),
        # It must parse to the same field with the flexible parser.
        ("I weigh 150 pounds", "height_cm", "150 pounds"),
        ("I weigh 150 pounds", "weight_kg", "150"),
        # The measurement must be complete: a unit may not be left behind.
        ("My weight is 70 kg", "age", "70"),
        # Negation, past, change or someone else in the quote's clause.
        ("I don't weigh 150 pounds", "weight_kg", "150 pounds"),
        ("I weighed 150 pounds in my prime", "weight_kg", "150 pounds"),
        ("I was 150 pounds", "weight_kg", "150 pounds"),
        ("I've lost weight, down to 150 pounds", "weight_kg", "150 pounds"),
        ("My husband weighs 150 pounds", "weight_kg", "150 pounds"),
        # A hypothetical, uncertainty or question anywhere in the reply.
        ("If I lose weight I'll be 150 pounds", "weight_kg", "150 pounds"),
        ("I weigh 150 pounds, if the scale is right", "weight_kg", "150 pounds"),
        ("I weigh 150 pounds, but I'm not sure", "weight_kg", "150 pounds"),
        ("Is 150 pounds a lot?", "weight_kg", "150 pounds"),
        # A second number in the clause, or a competing value in another clause.
        ("I weigh 150 pounds give or take 10", "weight_kg", "150 pounds"),
        ("I weigh 150 pounds; my weight is 160 pounds", "weight_kg", "150 pounds"),
        ("I weigh 150 pounds, 160", "weight_kg", "150 pounds"),
        ("I'm a woman, well, a man", "sex", "woman"),
        # A categorical quote cut out of a longer statement about the same topic.
        ("I never smoke at home", "smoking_status", "never"),
    ],
)
def test_grounding_refuses_quotes_the_reply_does_not_support(text, field, quote):
    assert grounded_candidates(text, extraction((field, quote)), field) == {}


def test_grounding_still_needs_a_named_cue_for_a_field_nobody_asked():
    quotes = extraction(("systolic_bp", "160"))
    assert grounded_candidates("160", quotes, "weight_kg") == {}
    assert grounded_candidates("160 pounds", quotes, "weight_kg") == {}
    assert grounded_candidates(
        "my systolic is 160", extraction(("systolic_bp", "my systolic is 160")), "weight_kg"
    ) == {"systolic_bp": 160}


# --- Keyless parser: traps that must never become a value ---------------------------


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("age", "I have 3 kids"),
        ("age", "I retired at 65"),
        ("age", "I'm in my seventies"),
        ("age", "I'm going on 80"),
        ("age", "I weigh 70"),
        # The old height alone; with "now I'm 5 foot 8" the now value is read back.
        ("height_cm", "I used to be 5 foot 10"),
        ("height_cm", "just under 6 feet"),
        ("weight_kg", "150 lb, down from 170"),
        ("weight_kg", "-70 kg"),
        ("sleep_hours", "I take a nap for 2 hours"),
        ("sleep_hours", "7 hours on weekends"),
        ("exercise_minutes_weekly", "20 minutes every morning and evening"),
        ("exercise_minutes_weekly", "I walk 2 miles a day"),
        ("exercise_minutes_weekly", "3 hours a week but not lately"),
        ("alcohol_drinks_weekly", "14 units a week"),
        ("alcohol_drinks_weekly", "a glass of wine"),
        ("alcohol_drinks_weekly", "1 drink a month"),
        ("smoking_status", "I started again but quit last year"),
        ("smoking_status", "I smoked a pack a day"),
        ("smoking_status", "I smoke marijuana"),
        ("smoking_status", "I don't smoke"),
        ("diabetes", "I take metformin"),
        ("diabetes", "I have the sugar"),
        ("diabetes", "my sugar is a little high"),
        ("diabetes", "I don't think so"),
        ("diabetes", "no thanks"),
        ("systolic_bp", "140 over 90 at the doctor but 120 over 80 at home"),
        ("systolic_bp", "it was 150 over 95 before I started pills"),
        ("diastolic_bp", "the top number is 130"),
    ],
)
def test_wrong_value_traps_stay_unanswered(field, text):
    assert parse_reply(text, field, today=TODAY) == {}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "I just had my 70th birthday", {"age": 70}),
        ("age", "I'll be 80 in two weeks", {"age": 79}),
        ("age", "born on 5 December 1950", {"age": 75}),
        ("height_cm", "one metre sixty eight", {"height_cm": 168.0}),
        ("height_cm", "5'4''", {"height_cm": 162.56}),
        ("weight_kg", "165, in pounds", {"weight_kg": 74.8427}),
        ("sleep_hours", "between 7 and 8 hours", {"sleep_hours": 7.5}),
        ("sleep_hours", "I go to bed at 10:30 and get up at 6:30", {"sleep_hours": 8.0}),
        ("sleep_hours", "I sleep from midnight to 7", {"sleep_hours": 7.0}),
        (
            "exercise_minutes_weekly",
            "an hour and fifteen minutes twice a week",
            {"exercise_minutes_weekly": 150},
        ),
        (
            "exercise_minutes_weekly",
            "I walk 20 minutes twice a day, every day",
            {"exercise_minutes_weekly": 280},
        ),
        ("exercise_minutes_weekly", "30 minutes on weekdays", {"exercise_minutes_weekly": 150}),
        (
            "exercise_minutes_weekly",
            "I walk for 30 mins 3x a week",
            {"exercise_minutes_weekly": 90},
        ),
        ("alcohol_drinks_weekly", "a glass of wine 3 days a week", {"alcohol_drinks_weekly": 3}),
        ("alcohol_drinks_weekly", "two beers a night", {"alcohol_drinks_weekly": 14}),
        ("alcohol_drinks_weekly", "Nope, never touch it", {"alcohol_drinks_weekly": 0}),
        ("smoking_status", "I used to smoke a pack a day", {"smoking_status": "former"}),
        ("smoking_status", "I was a smoker", {"smoking_status": "former"}),
        ("smoking_status", "never smoked a day in my life", {"smoking_status": "never"}),
        ("diabetes", "I've had diabetes for 20 years", {"diabetes": True}),
        (
            "systolic_bp",
            "The doctor said it was 140 over 90",
            {
                "systolic_bp": 140,
                "diastolic_bp": 90,
            },
        ),
        (
            "systolic_bp",
            "The top number is 130 and the bottom is 85",
            {
                "systolic_bp": 130,
                "diastolic_bp": 85,
            },
        ),
        ("sex", "I'm a grandmother", {"sex": "female"}),
    ],
)
def test_more_everyday_wording_is_understood(field, text, expected):
    got = parse_reply(text, field, today=TODAY)
    assert got.keys() == expected.keys()
    for key, value in expected.items():
        assert got[key] == (pytest.approx(value) if isinstance(value, float) else value)


# --- Conversation-level behavior -------------------------------------------------------


def test_birth_date_is_read_against_the_injected_clock():
    text = "I was born on December 5th, 1950"
    before = ConversationService(clock=lambda: date(2026, 12, 4))
    after = ConversationService(clock=lambda: date(2026, 12, 5))
    assert reply("age", text, before).state.pending_profile.age == 75
    assert reply("age", text, after).state.pending_profile.age == 76


def test_lone_bottom_number_without_a_top_number_asks_for_both():
    result = reply("diastolic_bp", "120")
    assert result.state.phase == "asking"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {}
    assert "both blood pressure numbers" in result.message
    known = reply("diastolic_bp", "80", confirmed_profile={"systolic_bp": 120})
    assert known.state.pending_profile.diastolic_bp == 80


def test_declining_the_smoking_question_records_unknown():
    result = reply("smoking_status", "I'd rather not say")
    assert result.state.pending_profile.smoking_status == "unknown"
    assert "smoking_status" not in result.state.skipped_fields


@pytest.mark.parametrize(
    ("field", "text", "hint"),
    [
        ("diabetes", "I have the sugar", "Has a doctor told you"),
        ("diabetes", "pre-diabetic", "Prediabetes"),
        ("smoking_status", "not a smoker", "Did you ever smoke in the past?"),
        ("alcohol_drinks_weekly", "a glass of wine", "How many days a week"),
        ("exercise_minutes_weekly", "an hour", "How often"),
    ],
)
def test_close_answers_get_a_specific_follow_up(field, text, hint):
    result = reply(field, text)
    assert result.state.phase == "asking"
    assert hint in result.message


def test_yes_with_a_correction_while_confirming_changes_nothing():
    service = ConversationService(clock=lambda: TODAY)
    pending = reply("height_cm", "5 ft 10 in", service).state
    request = TurnRequest(action="reply", state=pending, text="yes but 6 ft")
    result = asyncio.run(service.turn(request))
    assert result.state == pending
    assert result.message.endswith("Is that right?")


@pytest.mark.parametrize("text", ["yup", "Exactly.", "uh huh", "you got it"])
def test_more_spoken_confirmations_confirm(text):
    service = ConversationService(clock=lambda: TODAY)
    pending = reply("height_cm", "5 ft 10 in", service).state
    result = asyncio.run(service.turn(TurnRequest(action="reply", state=pending, text=text)))
    assert result.state.confirmed_profile.height_cm == pytest.approx(177.8)


def test_bare_top_number_asks_for_the_whole_reading():
    """Held-out finding: a bare "120" to the blood-pressure question was taken as the top number."""
    from fastapi.testclient import TestClient

    from lifetwin.app import create_app

    result = (
        TestClient(create_app())
        .post(
            "/api/onboarding/turn",
            json={
                "action": "reply",
                "state": {"phase": "asking", "current_field": "systolic_bp"},
                "text": "120",
            },
        )
        .json()
    )
    assert result["state"]["pending_profile"]["systolic_bp"] is None
    assert result["state"]["phase"] == "asking"


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("I was born male but I'm a woman now", "male"),
        ("I'm a woman but I was born male", "male"),
        ("assigned female at birth", "female"),
        ("born a girl", "female"),
        ("female", "female"),
    ],
)
def test_sex_is_sex_at_birth(text, expected):
    assert "at birth" in QUESTIONS["sex"]
    assert parse_reply(text, "sex") == {"sex": expected}


@pytest.mark.parametrize("text", ["yea that's right", "Yes.", "yeah, that's me", "that's right"])
def test_yes_to_the_example_offers_the_example_for_confirmation(text):
    result = reply("height_cm", text)
    assert result.state.phase == "confirming"
    assert result.state.pending_profile.height_cm == 177.8
    assert result.state.confirmed_profile.height_cm is None  # saved only after a second yes


@pytest.mark.parametrize(
    ("field", "text"), [("height_cm", "yes but shorter"), ("height_cm", "I guess"), ("age", "yes")]
)
def test_other_replies_do_not_take_the_example(field, text):
    result = reply(field, text)
    assert result.state.pending_profile.height_cm is None
    assert result.state.pending_profile.age is None


# --- Simple and indirect answers (adults 65+) -----------------------------------------
# One likely reading is proposed (and still read back before saving); two readings
# get a short question naming both; past, other people's, vague or goal values,
# and diagnoses inferred from medicine, stay unanswered.


def confirm(field: str, text: str, service: ConversationService | None = None, **state):
    result = reply(field, text, service, **state)
    assert result.state.phase == "confirming", result.message
    return result


@pytest.mark.parametrize(
    "text", ["I was born in 1980", "1980", "nineteen eighty", "born in '80", "I was born 1980."]
)
def test_birth_year_alone_works_out_the_age_and_checks_it(text):
    # Late October: most 1980 birthdays have passed, so 46 is offered and 45 named.
    result = reply("age", text)
    assert result.state.phase == "confirming"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {"age": 46}  # never 80
    assert result.state.confirmed_profile.age is None  # saved only after a yes
    assert (
        "Born in 1980: that makes you 46, or 45 if your birthday hasn't come yet" in result.message
    )
    fixed = asyncio.run(
        ConversationService(clock=lambda: TODAY).turn(
            TurnRequest(action="reply", state=result.state, text="45")
        )
    )
    assert fixed.state.pending_profile.age == 45


def test_birth_year_early_in_the_year_offers_the_younger_age():
    result = reply(
        "age", "born in 1980", service=ConversationService(clock=lambda: date(2026, 2, 1))
    )
    assert result.state.pending_profile.age == 45
    assert "or 46 if your birthday has already passed" in result.message


@pytest.mark.parametrize(
    ("text", "low", "high"),
    [
        ("I'm 46 this year", 45, 46),
        ("I turn 46 this year", 45, 46),
        ("I'm 70 this month", 69, 70),
        ("born in October 1980", 45, 46),  # the current month: the birthday may be to come
        ("born on 10/30/1950", 75, 75),  # one age after all; asked only when the readings differ
    ],
)
def test_birthday_this_year_offers_the_likelier_age(text, low, high):
    result = reply("age", text)
    if low == high:
        assert result.state.pending_profile.age == low
        return
    assert result.state.pending_profile.age == high  # late in the year: offered, then checked
    assert f"makes you {high}, or {low}" in result.message


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("born 3/3/1980", 46),
        ("3/3/1980", 46),
        ("born 3/3/80", 46),
        ("1950-12-05", 75),
        ("born 24/10/1950", 76),  # only day-first is a real date
        ("March 1980", 46),
        ("I was born in March of 1980", 46),
        ("born in December 1950", 75),
        ("born on the 4th of July 1950", 76),
        ("born on the fourth of July 1950", 76),
        ("my birthday is October the twenty first, 1950", 76),
        ("I'll be 70 in March", 69),
        ("I turn 46 in December", 45),
        ("turned 70 last month", 70),
        ("turned 70 in March", 70),
        ("70 next week", 69),
        ("I'm 70 next week", 69),
        ("76 years old next month", 75),
        ("I'm 72, born in 1954", 72),  # the stated age settles the birth year
        ("actually I'm 71 not 72", 71),
        ("not 72, 71", 71),
    ],
)
def test_birth_dates_and_relative_ages(text, expected):
    assert parse_reply(text, "age", today=TODAY) == {"age": expected}


@pytest.mark.parametrize(
    "text",
    [
        "class of '98",
        "I graduated in 1980",
        "1980 was a good year",
        "my wife was born in 1950",
        "I was born in the fifties",
        "born in the 50s",
        "I'm 72, born in 1960",
        "born 13/13/1980",
        "born in 2030",
        "I was 60 in 1990",
        "for about ten years",
        "I'm not 70 yet",
    ],
)
def test_age_traps_stay_unanswered(text):
    assert parse_reply(text, "age", today=TODAY) == {}
    assert "Which one?" not in reply("age", text).message


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("six foot", 182.88),
        ("6 foot even", 182.88),
        ("5 and a half feet", 167.64),
        ("five ten", 177.8),
        ("5 10", 177.8),
        ("510", 177.8),  # speech to text for "five ten"
        ("511", 180.34),
        ("170", 170.0),  # only centimeters fit
        ("I'm 170", 170.0),
        ("5 foot 8 not 5 foot 10", 172.72),
    ],
)
def test_simple_heights(text, expected):
    assert parse_reply(text, "height_cm") == {"height_cm": pytest.approx(expected)}


@pytest.mark.parametrize(
    "text",
    ["a hair under six feet", "62", "66", "510 pounds", "just under 170", "I used to be 170"],
)
def test_height_traps_stay_unanswered(text):
    assert "height_cm" not in parse_reply(text, "height_cm")  # "510 pounds" is a weight


def test_two_digit_height_names_both_readings():
    result = reply("height_cm", "62")
    assert result.state.phase == "asking"
    assert "6 feet 2 inches, or 62 inches (5 feet 2 inches)" in result.message
    assert reply("height_cm", "6 feet 2").state.pending_profile.height_cm == pytest.approx(187.96)


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("160", 72.5748),  # US default: pounds, read back before saving
        ("one sixty", 72.5748),
        ("a buck sixty", 72.5748),
        ("about 160", 72.5748),
        ("11 stone 4", 71.6676),
        ("70 kilos", 70.0),
    ],
)
def test_simple_weights(text, expected):
    assert parse_reply(text, "weight_kg") == {"weight_kg": pytest.approx(expected)}


def test_bare_weight_is_read_back_in_pounds():
    result = confirm("weight_kg", "a buck sixty")
    assert "I heard you weigh 160 pounds" in result.message
    assert result.state.confirmed_profile.weight_kg is None


@pytest.mark.parametrize("text", ["70", "I'd like to be 160", "160 or 170", "500", "I'm 72"])
def test_weight_traps_stay_unanswered(text):
    assert parse_reply(text, "weight_kg") == {}


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("bed at 10 up at 6", 8.0),
        ("midnight to 7", 7.0),
        ("11 till 5:30", 6.5),
        ("10 to 6", 8.0),
        ("10pm to 6am", 8.0),
        ("7 or 8", 7.5),
        ("7 to 8", 7.5),  # counts up: a range of hours, not clock times
    ],
)
def test_bedtime_and_wake_time(text, expected):
    assert parse_reply(text, "sleep_hours") == {"sleep_hours": pytest.approx(expected)}


@pytest.mark.parametrize("text", ["from 3 to 8", "1 to 8", "10 to 6 on weekends"])
def test_sleep_traps_stay_unanswered(text):
    assert parse_reply(text, "sleep_hours") == {}


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("twice a day for 20 minutes", 280),
        ("I walk the dog twice a day for 20 minutes", 280),
        ("an hour monday wednesday friday", 180),
        ("30 minutes twice a day on weekends", 120),
        ("nothing really", 0),
        ("I don't", 0),
    ],
)
def test_exercise_frequency_times_duration(text, expected):
    assert parse_reply(text, "exercise_minutes_weekly") == {"exercise_minutes_weekly": expected}


@pytest.mark.parametrize(
    "text",
    [
        "10,000 steps a day",
        "I walk 3 miles",
        "I garden a lot",
        "twice a day",
        "I walk the dog twice a day",
    ],
)
def test_exercise_traps_stay_unanswered(text):
    assert parse_reply(text, "exercise_minutes_weekly") == {}


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("a six-pack on weekends", 6),
        ("a bottle of wine a week", 5),
        ("2 bottles of wine a week", 10),
        ("a bottle of red wine every Friday", 5),
        ("two glasses friday and saturday", 4),
        ("sober 20 years", 0),
        ("sober for 20 years now", 0),
        ("not a drop", 0),
    ],
)
def test_drinks_from_containers_and_days(text, expected):
    got = parse_reply(text, "alcohol_drinks_weekly")
    assert got == {"alcohol_drinks_weekly": pytest.approx(expected)}


@pytest.mark.parametrize(
    "text",
    [
        "two beers on weekends",
        "a couple of beers on weekends",
        "a bottle of wine",
        "sober 20 years but I have one at Christmas",
    ],
)
def test_alcohol_traps_stay_unanswered(text):
    assert parse_reply(text, "alcohol_drinks_weekly") == {}


@pytest.mark.parametrize(
    ("text", "hint"),
    [
        ("two beers on weekends", "2 drinks over the whole weekend, or 2 on each day (4 in all)"),
        ("a bottle of wine", "How many days a week"),
    ],
)
def test_alcohol_follow_ups_name_the_readings(text, hint):
    assert hint in reply("alcohol_drinks_weekly", text).message


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("quit when my daughter was born", "former"),
        ("I smoked until my wife got sick", "former"),
        ("I smoke when my husband does", "current"),
        ("pack a day", "current"),
        ("never touched them", "never"),
    ],
)
def test_smoking_dated_by_life_events(text, expected):
    assert parse_reply(text, "smoking_status") == {"smoking_status": expected}


@pytest.mark.parametrize(
    "text",
    [
        "quit when my daughter was born but I still have one now and then",
        "my husband quit when our son was born",
        "my daughter smokes",
    ],
)
def test_smoking_life_event_traps_stay_unanswered(text):
    assert parse_reply(text, "smoking_status") == {}


@pytest.mark.parametrize(
    ("field", "text"), [("diabetes", "I take metformin"), ("diabetes", "borderline")]
)
def test_no_diagnosis_from_medicine_or_borderline(field, text):
    assert parse_reply(text, field) == {}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        (
            "age",
            "I'm 72, five foot six, and I weigh 150 pounds",
            {"age": 72, "height_cm": 167.64, "weight_kg": 68.0389},
        ),
        ("age", "I'm 72 and I never smoked", {"age": 72, "smoking_status": "never"}),
        ("weight_kg", "I'm 5 foot 6 and 150 pounds", {"height_cm": 167.64, "weight_kg": 68.0389}),
        (
            "sleep_hours",
            "7 hours and I walk 30 minutes every day",
            # v2: walking said beside another answer is lighter activity.
            {"sleep_hours": 7.0, "moderate_minutes_weekly": 210},
        ),
    ],
)
def test_several_fields_in_one_reply(field, text, expected):
    got = parse_reply(text, field, today=TODAY)
    assert got == {
        key: pytest.approx(value) if isinstance(value, float) else value
        for key, value in expected.items()
    }


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "I'm 72 and my wife is 70", {"age": 72}),  # her age is left out
        ("sleep_hours", "I sleep 7 hours, my husband sleeps 9", {"sleep_hours": 7.0}),
        ("sleep_hours", "my husband sleeps 9", {}),
        ("age", "weight: 70 kg and 80", {}),  # an unlabeled leftover is never another answer
        ("diabetes", "yes, for about ten years", {"diabetes": True}),  # how long, not an age
        ("sleep_hours", "I'm 72 and I sleep 7 hours", {"age": 72, "sleep_hours": 7.0}),
        ("age", "class of '98", {}),  # a number for an unasked field needs its unit
    ],
)
def test_several_fields_traps(field, text, expected):
    assert parse_reply(text, field, today=TODAY) == expected


def test_correction_of_an_earlier_answer_mid_conversation():
    service = ConversationService(clock=lambda: TODAY)
    result = reply("height_cm", "actually I'm 71 not 72", service, confirmed_profile={"age": 72})
    assert result.state.phase == "confirming"
    assert result.state.pending_profile.model_dump(exclude_none=True) == {"age": 71}
    assert result.state.confirmed_profile.age == 72  # nothing changes before a yes
    done = asyncio.run(service.turn(TurnRequest(action="reply", state=result.state, text="yes")))
    assert done.state.confirmed_profile.age == 71
    assert done.state.current_field == "sex"  # back to the first open question


def test_correction_while_confirming_replaces_the_pending_value():
    service = ConversationService(clock=lambda: TODAY)
    pending = reply("age", "72", service).state
    request = TurnRequest(action="reply", state=pending, text="actually I'm 71 not 72")
    assert asyncio.run(service.turn(request)).state.pending_profile.age == 71


# --- Round 2: missing apostrophes, cross-field replies, more indirect wording ----------


def approx(expected: dict) -> dict:
    return {k: pytest.approx(v) if isinstance(v, float) else v for k, v in expected.items()}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("alcohol_drinks_weekly", "i dont drink", {"alcohol_drinks_weekly": 0}),
        ("exercise_minutes_weekly", "i dont exercise", {"exercise_minutes_weekly": 0}),
        ("smoking_status", "i dont smoke anymore", {"smoking_status": "former"}),
        ("age", "im 72", {"age": 72}),
        ("age", "ill be 70 in march", {"age": 69}),
        (
            "alcohol_drinks_weekly",
            "none and i dont have diabetes",  # never "have diabetes" once the n't is lost
            {"alcohol_drinks_weekly": 0, "diabetes": False},
        ),
        ("age", "im ill", {}),  # "ill" is I'll only before a verb
    ],
)
def test_missing_apostrophes(field, text, expected):
    assert parse_reply(text, field, today=TODAY) == approx(expected)


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("height_cm", "5 10 no 6 foot"),  # a spoken self-correction is asked again
        ("sleep_hours", "i want 8 but get less"),  # a goal
        ("systolic_bp", "it was 150 over 95 last year but now its fine"),
        ("exercise_minutes_weekly", "an hour a day except weekends"),
        ("age", "the year I turned 65 I retired"),
        ("age", "Maybe I weigh 70 kg"),  # maybe doubts the statement, not one number
        ("weight_kg", "between 150 and 200"),  # too wide to read as one weight
        ("height_cm", "5 7 or 5 9"),
        ("systolic_bp", "120 80 or 140 90"),
        ("exercise_minutes_weekly", "I walk 30 minutes and swim 20 minutes"),  # how often?
        ("exercise_minutes_weekly", "30 to 60 minutes 3 times a week"),
    ],
)
def test_round_two_wrong_value_traps(field, text):
    assert parse_reply(text, field, today=TODAY) == {}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("smoking_status", "nope never", "never"),
        ("smoking_status", "not once in my life", "never"),
        ("smoking_status", "i smoked in the army", "former"),
        ("smoking_status", "i havent had one since 1988", "former"),
        ("smoking_status", "trying to quit", "current"),
        ("smoking_status", "used to smoke but started again", "current"),
        ("smoking_status", "I quit 10 years ago but started again", "current"),
    ],
)
def test_round_two_smoking(field, text, expected):
    assert parse_reply(text, field) == {field: expected}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("exercise_minutes_weekly", "one hour a day", 420),  # every day, read back
        ("exercise_minutes_weekly", "gym 3 times 45 minutes each", 135),
        ("exercise_minutes_weekly", "30 to 40 minutes 3 times", 105),
        ("exercise_minutes_weekly", "an hour and a half total", 90),
        ("exercise_minutes_weekly", "gardening a couple hours a week", 120),
        ("exercise_minutes_weekly", "maybe 60", 60),
        (
            "exercise_minutes_weekly",
            "a 30 minute walk 4 days and 1 hour of tai chi on saturday",
            180,
        ),
        ("alcohol_drinks_weekly", "two six packs", 12),
        ("alcohol_drinks_weekly", "a couple of drinks a day", 14),
        ("weight_kg", "a hundred 30", 58.967),
        ("weight_kg", "between 150 and 160", 70.3068),
        ("height_cm", "5 7 or 5 8", 171.45),
        ("sleep_hours", "half past nine to half past five", 8.0),
        ("sleep_hours", "ten thirty to six thirty", 8.0),
        ("age", "two years shy of 70", 68),
    ],
)
def test_round_two_numbers(field, text, expected):
    assert parse_reply(text, field, today=TODAY) == approx({field: expected})


@pytest.mark.parametrize("text", ["130 80", "130 slash 80", "130/80"])
def test_blood_pressure_without_over(text):
    assert parse_reply(text, "systolic_bp") == {"systolic_bp": 130, "diastolic_bp": 80}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "i weigh 160 pounds", {"weight_kg": 72.5748}),
        ("sex", "i'm 71", {"age": 71}),
        ("sex", "female and 68", {"sex": "female", "age": 68}),
        ("sex", "74 male", {"sex": "male", "age": 74}),
        ("weight_kg", "i'm 5 foot 6", {"height_cm": 167.64}),
        ("systolic_bp", "i'm female", {"sex": "female"}),
        ("exercise_minutes_weekly", "no diabetes", {"diabetes": False}),
        ("alcohol_drinks_weekly", "i quit smoking years ago", {"smoking_status": "former"}),
        ("smoking_status", "i have a drink or two a week", {"alcohol_drinks_weekly": 1.5}),
        ("diabetes", "no, i'm 70", {"diabetes": False, "age": 70}),
        (
            "exercise_minutes_weekly",
            "i'm 70 and walk an hour 3 times a week",
            {"age": 70, "exercise_minutes_weekly": 180},
        ),
        ("age", "im 70 and my wife is 66", {"age": 70}),
        ("age", "i weigh 70", {}),  # another field's bare number is still asked about
        ("height_cm", "I'm 70", {}),  # an age only beside another answer
    ],
)
def test_answers_to_another_question(field, text, expected):
    assert parse_reply(text, field, today=TODAY) == approx(expected)


def test_a_targeted_follow_up_skips_the_ai_helper_offer():
    class Never:
        configured = True

        async def extract(self, text, target):
            raise AssertionError("the helper should not be asked")

    service = ConversationService(Never(), clock=lambda: TODAY)
    for consent in (False, True):
        result = asyncio.run(
            service.turn(
                TurnRequest(
                    action="reply",
                    state=ConversationState(phase="asking", current_field="age"),
                    text="I was born in 1980",
                    provider_consent=consent,
                )
            )
        )
        assert "AI helper" not in result.message
        assert result.provider_status == "not_needed"


# --- Round 3: blind-review regressions -----------------------------------------------
# Every input below must end with no value recorded unless an expected value is given.

ROUND3_NO_VALUE = [
    # 1 sentence breaks
    ("diabetes", "No. My mother, yes."),
    ("sex", "Female. My husband, male"),
    # 2 other people without a possessive
    ("age", "The wife is 70"),
    ("age", "the missus is 70"),
    ("age", "my better half is 70"),
    ("age", "Bob is 75"),
    ("age", "Dad is 90"),
    ("age", "husband is 75"),
    ("weight_kg", "Mom weighs 140"),
    ("diabetes", "hubby has diabetes"),
    ("systolic_bp", "The wife's is 130 over 80"),
    # 3 two durations without a joiner (was a RecursionError)
    ("exercise_minutes_weekly", "I walk 30 minutes then swim 20 minutes"),
    ("exercise_minutes_weekly", "45 minutes or an hour"),
    # 4 not alcohol
    ("alcohol_drinks_weekly", "8 glasses of water a day"),
    ("alcohol_drinks_weekly", "2 sodas a day"),
    ("alcohol_drinks_weekly", "3 cups of coffee a day"),
    ("alcohol_drinks_weekly", "an espresso every morning"),
    ("alcohol_drinks_weekly", "a glass of milk a night"),
    ("alcohol_drinks_weekly", "tea, 4 cups a day"),
    ("alcohol_drinks_weekly", "a glass of juice a day"),
    ("sleep_hours", "8 glasses of water a day"),
    ("alcohol_drinks_weekly", "half a bottle of wine"),
    # 5 partial negations
    ("alcohol_drinks_weekly", "I don't drink beer, just wine"),
    ("alcohol_drinks_weekly", "I don't drink during the week"),
    ("alcohol_drinks_weekly", "don't drink on weekdays"),
    ("alcohol_drinks_weekly", "none on weekdays"),
    ("alcohol_drinks_weekly", "I never drink alone"),
    ("alcohol_drinks_weekly", "I don't drink and drive"),
    ("alcohol_drinks_weekly", "I don't drink water"),
    ("alcohol_drinks_weekly", "I'm not sober"),
    # 6 a past value in another clause
    ("weight_kg", "160 pounds, before my surgery"),
    ("weight_kg", "160 pounds, but that was a while back"),
    ("weight_kg", "160 pounds, I used to be"),
    ("weight_kg", "160 pounds, ages ago"),
    ("weight_kg", "160 at my wedding"),
    ("weight_kg", "160 in high school"),
    ("weight_kg", "160 in the army"),
    ("height_cm", "5'10 originally, I've shrunk"),
    ("exercise_minutes_weekly", "30 minutes a day but not since my fall"),
    ("exercise_minutes_weekly", "30 minutes a day until my fall"),
    ("exercise_minutes_weekly", "an hour 3 times a week before my surgery"),
    ("exercise_minutes_weekly", "I walked an hour every day and then I stopped"),
    ("alcohol_drinks_weekly", "3 a week and I quit"),
    # 7 diabetes
    ("diabetes", "yes, my dad"),
    ("diabetes", "yes, in my family"),
    ("diabetes", "yes, the doctor ruled it out"),
    ("diabetes", "diabetes insipidus"),
    ("diabetes", "yes, diabetes insipidus"),
    # 8 interjections and partners are not a sex
    ("sex", "man, that's personal"),
    ("sex", "oh man"),
    ("sex", "I have a wife"),
    ("sex", "I have a husband"),
    ("sex", "married to a man"),
    # 11 goals, advice, opinions
    ("sleep_hours", "I need 8 hours"),
    ("sleep_hours", "the doctor says 7 hours"),
    ("alcohol_drinks_weekly", "I'm allowed 7 a week"),
    ("systolic_bp", "normal is 120 over 80"),
    ("age", "I feel 50"),
    ("age", "I look 60"),
    ("weight_kg", "I weigh 160 pounds in my dreams"),
    # 12 comparisons
    ("age", "on the wrong side of 70"),
    ("height_cm", "shy of 6 ft"),
    # 13 seasonal
    ("exercise_minutes_weekly", "I swim an hour 3 times a week in summer"),
    ("alcohol_drinks_weekly", "2 beers a day in the summer"),
    # 14 quitting something else
    ("smoking_status", "I quit my job"),
]


@pytest.mark.parametrize(("field", "text"), ROUND3_NO_VALUE)
def test_round_three_no_value(field, text):
    assert parse_reply(text, field, today=TODAY) == {}
    assert reply(field, text).state.pending_profile.model_dump(exclude_none=True) == {}


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "I'm 70. My wife, 72", {"age": 70}),
        ("sleep_hours", "7 hours, oh man", {"sleep_hours": 7.0}),
        ("sleep_hours", "7, man", {"sleep_hours": 7.0}),
        ("alcohol_drinks_weekly", "a 24 pack a week", {"alcohol_drinks_weekly": 24.0}),
        ("age", "almost 80", {"age": 79}),
        ("age", "nearly 80", {"age": 79}),
        ("age", "pushing 80", {"age": 79}),
        ("age", "I'm 73 on Friday", {"age": 72}),
        ("age", "72 on my next birthday", {"age": 71}),
        ("age", "80 come next Friday", {"age": 79}),
        ("exercise_minutes_weekly", "30 minutes every two days", {"exercise_minutes_weekly": 105}),
        ("exercise_minutes_weekly", "30 minutes every 3 days", {"exercise_minutes_weekly": 70}),
        (
            "exercise_minutes_weekly",
            "30 minutes, every other day",
            {"exercise_minutes_weekly": 105},
        ),
        (
            "exercise_minutes_weekly",
            "twice a day for 20 minutes every other day",
            {"exercise_minutes_weekly": 140},
        ),
        ("smoking_status", "never smoked cigarettes, only cigars", {"smoking_status": "current"}),
        ("smoking_status", "quit cigarettes, now cigars", {"smoking_status": "current"}),
        ("smoking_status", "Never cigarettes. Cigars, yes", {"smoking_status": "current"}),
        ("diabetes", "no but my husband does", {"diabetes": False}),
        ("age", "72 and a woman", {"age": 72, "sex": "female"}),
        ("age", "٧٢", {"age": 72}),  # Arabic-Indic digits
    ],
)
def test_round_three_values(field, text, expected):
    assert parse_reply(text, field, today=TODAY) == approx(expected)


def test_seasonal_and_non_alcohol_follow_ups():
    assert "usual week" in reply("exercise_minutes_weekly", "an hour a day in summer").message
    assert "alcoholic drinks" in reply("alcohol_drinks_weekly", "a glass of milk a night").message
    assert "pounds or" not in reply("weight_kg", "160 at my wedding").message


def test_parser_failure_is_a_follow_up_not_a_500(monkeypatch, caplog):
    from lifetwin.onboarding import service as service_module

    def broken(*args, **kwargs):
        raise RecursionError("boom: health text must not be logged")

    monkeypatch.setattr(service_module, "parse_reply", broken)
    result = reply("age", "I'm 72")
    assert result.state.phase == "asking"
    assert "didn't catch that" in result.message
    assert "RecursionError" in caplog.text and "boom" not in caplog.text


def run_turns(service: ConversationService, state: ConversationState, *texts: str):
    for text in texts:
        state = asyncio.run(service.turn(TurnRequest(action="reply", state=state, text=text))).state
    return state


def test_a_reply_never_overwrites_a_confirmed_answer_by_accident():
    service = ConversationService(clock=lambda: TODAY)
    saved = ConversationState(
        phase="asking", current_field="sleep_hours", confirmed_profile={"age": 72, "sex": "female"}
    )
    state = run_turns(service, saved, "7 hours, oh man", "yes")
    assert state.confirmed_profile.sex == "female"
    assert state.confirmed_profile.sleep_hours == 7.0
    asked_sex = ConversationState(
        phase="asking", current_field="sex", confirmed_profile={"age": 72}
    )
    assert run_turns(service, asked_sex, "no, 73").pending_profile.age is None
    # An explicit correction naming the field still works.
    corrected = run_turns(service, asked_sex, "actually I'm 71 not 72")
    assert corrected.pending_profile.age == 71


@pytest.mark.parametrize("text", ["No, it's correct", "no, that's right", "no, that's me"])
def test_no_during_read_back_never_swaps_in_the_example(text):
    service = ConversationService(clock=lambda: TODAY)
    pending = reply("weight_kg", "140 pounds", service).state
    after = run_turns(service, pending, text)
    assert after.pending_profile.weight_kg == pytest.approx(63.5029)
    assert after.confirmed_profile.weight_kg is None


@pytest.mark.parametrize(
    ("field", "text", "shown"),
    [
        ("sleep_hours", "7 or 8", "you sleep about 7.5 hours a night"),
        ("sleep_hours", "about 7 and a half hours", "you sleep about 7.5 hours a night"),
        ("weight_kg", "between 160 and 170", "you weigh about 165 pounds"),
        ("weight_kg", "about 165 pounds", "you weigh about 165 pounds"),
        (
            "exercise_minutes_weekly",
            "30 to 40 minutes 3 times",
            "you exercise about 105 minutes a week",
        ),
        ("sleep_hours", "7 hours", "you sleep 7 hours a night"),
    ],
)
def test_estimates_are_read_back_as_about(field, text, shown):
    assert shown in reply(field, text).message


@pytest.mark.parametrize(
    ("asked", "text", "quotes"),
    [
        ("weight_kg", "160 pounds. That's what my wife weighs.", [("weight_kg", "160 pounds")]),
        ("weight_kg", "160 pounds. That's what the wife weighs.", [("weight_kg", "160 pounds")]),
        ("weight_kg", "160 pounds. That's my wife's, not mine.", [("weight_kg", "160 pounds")]),
        ("weight_kg", "160 pounds - my husband's weight", [("weight_kg", "160 pounds")]),
        ("age", "72. That's my husband's age.", [("age", "72")]),
        ("age", "72. My wife's age, I mean.", [("age", "72")]),
        ("weight_kg", "160 pounds. Ten years ago.", [("weight_kg", "160 pounds")]),
        ("weight_kg", "160 pounds. Before the chemo.", [("weight_kg", "160 pounds")]),
        ("weight_kg", "I weigh 160 pounds in my dreams", [("weight_kg", "160 pounds")]),
        ("height_cm", "5'10. Before I shrank.", [("height_cm", "5'10")]),
        ("sleep_hours", "7 hours. Sometimes less.", [("sleep_hours", "7 hours")]),
        ("sleep_hours", "8 hours. In my youth.", [("sleep_hours", "8 hours")]),
        ("sleep_hours", "Doctor recommends: 8 hours", [("sleep_hours", "8 hours")]),
        (
            "exercise_minutes_weekly",
            "150 minutes a week. Or less.",
            [("exercise_minutes_weekly", "150 minutes a week")],
        ),
        ("alcohol_drinks_weekly", "3 a week. Used to be.", [("alcohol_drinks_weekly", "3 a week")]),
        (
            "alcohol_drinks_weekly",
            "8 glasses of water a day",
            [("alcohol_drinks_weekly", "8 glasses")],
        ),
        ("age", "80 come next Friday", [("age", "80")]),
        ("diabetes", "Yes, my mother has it", [("diabetes", "Yes")]),
        ("diabetes", "Nope. Borderline though", [("diabetes", "Nope")]),
        ("diabetes", "my sugar is high, yes", [("diabetes", "yes")]),
        ("smoking_status", "I quit cigarettes, now it's cigars", [("smoking_status", "quit")]),
        ("sex", "I married a woman", [("sex", "woman")]),
        ("sex", "Husband. Female, he is not", [("sex", "Female")]),
        (
            "systolic_bp",
            "Normal is 120 over 80; mine's higher",
            [("systolic_bp", "120 over 80"), ("diastolic_bp", "120 over 80")],
        ),
    ],
)
def test_grounding_applies_whole_reply_checks(asked, text, quotes):
    assert grounded_candidates(text, extraction(*quotes), asked, today=TODAY) == {}


def test_grounding_still_accepts_own_answers_beside_someone_else():
    assert grounded_candidates(
        "My son smokes, I never did", extraction(("smoking_status", "never did")), "smoking_status"
    ) == {"smoking_status": "never"}


def test_hedged_say_is_not_reported_advice():
    assert parse_reply("I'd say 6 hours a night", "sleep_hours") == {"sleep_hours": 6.0}


@pytest.mark.parametrize(
    ("text", "age"),
    [("Born in 52,", 74), ("I was born in 52.", 74), ("born 48", 78), ("born in the year 61", 65)],
)
def test_spoken_two_digit_birth_year_is_a_year_not_an_age(text, age):
    # Ink writes "born in fifty two" as "Born in 52," with no apostrophe.
    result = reply("age", text)
    assert result.state.pending_profile.age == age


def test_born_some_years_ago_is_never_read_as_a_birth_year():
    assert reply("age", "I was born 52 years ago").state.pending_profile.age != 74


# --- Fixes found while building the check-ins -----------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # Two parts for the same question are one answer, never the first part alone.
        ("two beers on Friday and two on Saturday", {}),
        ("a beer on Friday and a beer on Saturday", {}),
        # Half a drink is half, not one.
        ("half a glass of wine a day", {"alcohol_drinks_weekly": 3.5}),
        # "Before bed" is a time of day, not an old value.
        ("a small whiskey before bed every night", {"alcohol_drinks_weekly": 7.0}),
        ("a glass of wine 3 nights a week", {"alcohol_drinks_weekly": 3.0}),
    ],
)
def test_drink_counts_found_while_building_check_ins(text, expected):
    assert parse_reply(text, "alcohol_drinks_weekly", today=TODAY) == expected


def test_before_bed_never_turns_into_hours_of_sleep():
    assert parse_reply("I read for an hour before bed", "sleep_hours", today=TODAY) == {}
