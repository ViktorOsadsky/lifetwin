"""Voice transcripts from a noisy room: other people's chatter around the answer.

Cartesia Ink transcribes everyone nearby, so a reply mixes room talk with the
person's answer. Chatter with nothing for the question is left out; anything that
could change the answer (doubt, someone else, the past, a goal, a second value)
still makes the turn a follow-up question.
"""

import asyncio
from datetime import date

import pytest

from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.models import ConversationState, TurnRequest

TODAY = date(2026, 10, 24)


def say(field: str, text: str, mode: str = "transcript", **state):
    request = TurnRequest(
        action="reply",
        input_mode=mode,
        state=ConversationState(phase="asking", current_field=field, **state),
        text=text,
    )
    return asyncio.run(ConversationService(clock=lambda: TODAY).turn(request))


def heard(result) -> dict:
    return result.state.pending_profile.model_dump(exclude_none=True)


def same(got: dict, expected: dict) -> bool:
    return got.keys() == expected.keys() and all(
        got[key] == pytest.approx(value) if isinstance(value, float) else got[key] == value
        for key, value in expected.items()
    )


# --- Real transcripts from on-phone testing ------------------------------------------

REAL = [
    ("sex", "Are we gonna include this, bro? Female.", {"sex": "female"}),
    ("sex", "certain position for Dexi. Female. So I can be", {"sex": "female"}),
    ("height_cm", "Wait, like, were you just getting brutally 5'4.", {"height_cm": 162.56}),
    ("weight_kg", "This is like the shittiest hardware. 145 pounds.", {"weight_kg": 65.7709}),
    ("sleep_hours", "Bro, the TTS is so ass. About 7 hours.", {"sleep_hours": 7.0}),
    (
        "sleep_hours",
        "like they're cracked. About 7 hours. Like nothing on you.",
        {"sleep_hours": 7.0},
    ),
    (
        "smoking_status",
        "next to me because she woke up at 8. I used to smoke, but I quit years ago.",
        {"smoking_status": "former"},
    ),
    (
        "alcohol_drinks_weekly",
        "per day 2 glasses of wine a week. How much of a day do you think",
        {"alcohol_drinks_weekly": 2.0},
    ),
    ("diabetes", "and standing up. No.", {"diabetes": False}),
    (
        "systolic_bp",
        "I I feel like it depends on the day, maybe like 130 over 85. Yeah, see, so like that's",
        {"systolic_bp": 130, "diastolic_bp": 85},
    ),
    ("age", "Who is it's listening to you. I was born in 1952.", {"age": 74}),
    ("age", "Oh, that's p I was born in 1952. What about the", {"age": 74}),
]


@pytest.mark.parametrize(("field", "text", "expected"), REAL)
def test_real_noisy_transcripts(field, text, expected):
    result = say(field, text)
    assert same(heard(result), expected), result.message
    assert result.state.confirmed_profile.model_dump(exclude_none=True) == {}  # read back first


def test_a_hedged_typical_reading_is_read_back_as_about():
    result = say("systolic_bp", REAL[9][1])
    assert "your blood pressure is about 130 over 85" in result.message


def test_born_in_1952_is_worked_out_and_checked():
    result = say("age", "Who is it's listening to you. I was born in 1952.")
    assert "73" in result.message and "74" in result.message


def test_read_back_correction_inside_chatter():
    service = ConversationService(clock=lambda: TODAY)
    pending = asyncio.run(
        service.turn(
            TurnRequest(
                action="reply",
                state=ConversationState(phase="asking", current_field="age"),
                text="72",
            )
        )
    ).state
    result = asyncio.run(
        service.turn(
            TurnRequest(
                action="reply",
                input_mode="transcript",
                state=pending,
                text="I know. No, 60. I think you have to like hold",
            )
        )
    )
    assert heard(result) == {"age": 60}
    assert result.state.confirmed_profile.age is None


# --- Synthetic chatter around answers, every question ----------------------------------

CHATTER = [
    "Bro, the TTS is so ass.",
    "Are we gonna include this, bro?",
    "This is like the shittiest hardware.",
    "Wait, hold on.",
    "Can you even hear me in here?",
    "Who is it's listening to you.",
    "Dude, the music is so loud.",
    "Is this thing on?",
    "Like they're cracked.",
    "Hey, pass me the charger.",
]
ANSWERS = {
    "age": [
        ("I'm 72", {"age": 72}),
        ("seventy two", {"age": 72}),
        ("I'll be 70 in March", {"age": 69}),
    ],
    "sex": [
        ("Female", {"sex": "female"}),
        ("I'm a man", {"sex": "male"}),
        ("male", {"sex": "male"}),
    ],
    "height_cm": [
        ("5'4", {"height_cm": 162.56}),
        ("five foot ten", {"height_cm": 177.8}),
        ("170 cm", {"height_cm": 170.0}),
    ],
    "weight_kg": [
        ("145 pounds", {"weight_kg": 65.7709}),
        ("70 kilos", {"weight_kg": 70.0}),
        ("one sixty", {"weight_kg": 72.5748}),
    ],
    "sleep_hours": [
        ("About 7 hours", {"sleep_hours": 7.0}),
        ("8 hours a night", {"sleep_hours": 8.0}),
        ("six and a half hours", {"sleep_hours": 6.5}),
    ],
    "exercise_minutes_weekly": [
        ("I walk 30 minutes every day", {"exercise_minutes_weekly": 210}),
        ("an hour three times a week", {"exercise_minutes_weekly": 180}),
        ("150 minutes a week", {"exercise_minutes_weekly": 150}),
    ],
    "smoking_status": [
        ("I never smoked", {"smoking_status": "never"}),
        ("I used to smoke, but I quit years ago", {"smoking_status": "former"}),
        ("I smoke a pack a day", {"smoking_status": "current"}),
    ],
    "alcohol_drinks_weekly": [
        ("2 glasses of wine a week", {"alcohol_drinks_weekly": 2.0}),
        ("I don't drink", {"alcohol_drinks_weekly": 0.0}),
        ("one beer a day", {"alcohol_drinks_weekly": 7.0}),
    ],
    "diabetes": [
        ("No", {"diabetes": False}),
        ("Yes, I have type 2", {"diabetes": True}),
        ("I'm diabetic", {"diabetes": True}),
    ],
    "systolic_bp": [
        ("130 over 85", {"systolic_bp": 130, "diastolic_bp": 85}),
        ("120 over 80", {"systolic_bp": 120, "diastolic_bp": 80}),
        ("maybe like 140 over 90", {"systolic_bp": 140, "diastolic_bp": 90}),
    ],
}
SYNTHETIC = [
    (
        field,
        f"{chatter} {answer}." if i % 2 == 0 else f"{answer}. {chatter}",
        expected,
    )
    for field, answers in ANSWERS.items()
    for answer, expected in answers
    for i, chatter in enumerate(CHATTER)
]


@pytest.mark.parametrize(("field", "text", "expected"), SYNTHETIC)
def test_chatter_around_an_answer_is_left_out(field, text, expected):
    result = say(field, text)
    assert same(heard(result), expected), result.message


# --- Traps: chatter that could change the answer still asks ----------------------------

TRAPS = [
    # Someone else's value for the same question.
    ("height_cm", "My brother is 6 foot. I'm 5'4."),
    ("height_cm", "my brother is 6 foot... I'm 5'4"),
    ("height_cm", "Brother's 6 foot tall. I'm 5'4."),
    ("age", "My wife is 70. I'm 72."),
    ("age", "She's 80. I'm 75."),
    ("weight_kg", "He weighs 200 pounds. I'm 145 pounds."),
    ("sleep_hours", "She sleeps 9 hours. I get about 7 hours."),
    ("alcohol_drinks_weekly", "He has 10 beers a week. I have 2 glasses of wine a week."),
    ("systolic_bp", "Hers is 150 over 95. Mine is 130 over 85."),
    # A second number in the chatter.
    ("height_cm", "The table is 6 foot. I'm 5'4."),
    ("weight_kg", "Gate 12 is that way. 145 pounds."),
    ("sleep_hours", "It's 8 o'clock already. About 7 hours."),
    # Doubt, the past, a goal or advice in another sentence.
    ("sleep_hours", "Bro, the TTS is so ass. I'm not sure. About 7 hours."),
    ("weight_kg", "Dude. I used to weigh 200 pounds."),
    ("sleep_hours", "Is this thing on? I want to sleep 8 hours."),
    ("weight_kg", "Hey, pass me the charger. 150 pounds. That's my goal."),
    ("sleep_hours", "Wait, hold on. The doctor says 8 hours."),
    ("weight_kg", "Like they're cracked. 160 pounds. That was years ago."),
    ("diabetes", "Bro, the TTS is so ass. Yes, my mother has it."),
    ("smoking_status", "Dude, the music is so loud. My husband smokes."),
    # A question about the asked field is still a question back.
    ("height_cm", "How tall should I be? 5'4"),
    # Nothing but chatter.
    ("sex", "Are we gonna include this, bro?"),
    ("age", "Who is it's listening to you."),
]


@pytest.mark.parametrize(("field", "text"), TRAPS)
def test_chatter_that_changes_the_answer_still_asks(field, text):
    result = say(field, text)
    assert heard(result) == {}, result.message
    assert result.state.phase == "asking"


def test_someone_elses_number_is_named_in_the_follow_up():
    assert "more than one number" in say("height_cm", "My brother is 6 foot. I'm 5'4.").message


def test_typed_replies_keep_their_own_value_beside_a_relative():
    # Typed text has no room chatter: "my wife is 66" is the person telling us about her.
    assert heard(say("age", "im 70 and my wife is 66", mode="text")) == {"age": 70}


def test_skipping_blood_pressure_skips_both_numbers():
    for text in ("skip", "I don't know"):
        result = say("systolic_bp", text)
        assert result.state.skipped_fields == ["systolic_bp", "diastolic_bp"]
        assert result.state.current_field != "diastolic_bp"
