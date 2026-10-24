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
from lifetwin.onboarding.parsing import grounded_candidates, parse_reply

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
    text = "I'm 72, five foot six, and I weigh 150 pounds"
    assert parse_reply(text, "age") == {}  # three numbers: the keyless parser asks again
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
        ("age", "76 years old next month"),
        ("age", "I'm in my seventies"),
        ("age", "I'm going on 80"),
        ("age", "I weigh 70"),
        ("height_cm", "I used to be 5 foot 10, now I'm 5 foot 8"),
        ("height_cm", "just under 6 feet"),
        ("weight_kg", "150 lb, down from 170"),
        ("weight_kg", "-70 kg"),
        ("sleep_hours", "I take a nap for 2 hours"),
        ("sleep_hours", "7 hours on weekends"),
        ("sleep_hours", "I sleep 7 hours, my husband sleeps 9"),
        ("exercise_minutes_weekly", "I walk the dog twice a day for 20 minutes"),
        ("exercise_minutes_weekly", "30 minutes, every other day"),
        ("exercise_minutes_weekly", "20 minutes every morning and evening"),
        ("exercise_minutes_weekly", "I walk 2 miles a day"),
        ("exercise_minutes_weekly", "3 hours a week but not lately"),
        ("alcohol_drinks_weekly", "14 units a week"),
        ("alcohol_drinks_weekly", "a bottle of wine a week"),
        ("alcohol_drinks_weekly", "a glass of wine"),
        ("alcohol_drinks_weekly", "1 drink a month"),
        ("smoking_status", "I quit 10 years ago but started again"),
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
        ("sex", "I'm a woman but I was born male"),
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
    assert "Nothing has changed" in result.message


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
