"""Spoken answers as older adults say them and Cartesia Ink writes them down.

Each rule here was found in real or realistic transcripts. A value is still only
proposed and read back; anything that leaves two readings stays a follow-up.
"""

import asyncio
from datetime import date

import pytest

from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.models import ConversationState, TurnRequest

TODAY = date(2026, 10, 24)


def say(field: str, text: str, mode: str = "transcript"):
    request = TurnRequest(
        action="reply",
        input_mode=mode,
        state=ConversationState(phase="asking", current_field=field),
        text=text,
    )
    return asyncio.run(ConversationService(clock=lambda: TODAY).turn(request))


def heard(field: str, text: str, mode: str = "transcript") -> dict:
    return say(field, text, mode).state.pending_profile.model_dump(exclude_none=True)


def check(field: str, text: str, expected: dict | None, mode: str = "transcript") -> None:
    got = heard(field, text, mode)
    if expected is None:
        assert got == {}, (text, got)
        return
    assert got.keys() == expected.keys(), (text, got)
    for key, value in expected.items():
        assert got[key] == (pytest.approx(value, abs=0.01) if isinstance(value, float) else value)


# A value said and corrected straight away: the later one is the answer.
SELF_CORRECTIONS = [
    ("age", "72, no, 73.", {"age": 73}),
    ("age", "65, I mean 66.", {"age": 66}),
    ("age", "I'm 74, 75 actually.", {"age": 75}),
    ("age", "i'm 79 no wait 78", {"age": 78}),
    ("age", "70, no, 71, no, 72.", {"age": 72}),
    ("sleep_hours", "6 hours, no, 7 hours.", {"sleep_hours": 7.0}),
    ("height_cm", "5 ft 6, sorry, 5 ft 7.", {"height_cm": 170.18}),
    ("weight_kg", "150, no wait, 155 pounds.", {"weight_kg": 70.307}),
    ("alcohol_drinks_weekly", "3 drinks, actually 4 drinks a week.", {"alcohol_drinks_weekly": 4}),
]
SELF_CORRECTION_TRAPS = [
    ("height_cm", "5 10 no 6 foot"),  # typed without punctuation: asked again
    ("systolic_bp", "130 over 80, no, 85."),  # half a reading corrected: asked again
    ("height_cm", "5 ft 10, sorry, 160 pounds."),  # a different kind of value
    ("age", "I'm 70, sorry, my wife is 72."),  # someone else's number
    ("sleep_hours", "7 hours, no, less."),  # no corrected value
    ("alcohol_drinks_weekly", "2 drinks a day, I mean 10 a week."),  # two different amounts
    ("sleep_hours", "7 hours, no, more like 6."),  # a comparison, not a value
]


@pytest.mark.parametrize(("field", "text", "expected"), SELF_CORRECTIONS)
def test_a_self_correction_keeps_the_later_value(field, text, expected):
    check(field, text, expected)
    check(field, text, expected, mode="text")


@pytest.mark.parametrize(("field", "text"), SELF_CORRECTION_TRAPS)
def test_an_unclear_self_correction_is_asked_about(field, text):
    check(field, text, None)


# Ink writes "one hundred and sixty" as "100 and 60" and "one eighty" as "1 80".
SPLIT_HUNDREDS = [
    ("weight_kg", "100 and 60 pounds.", {"weight_kg": 72.575}),
    ("weight_kg", "200 and 10 pounds.", {"weight_kg": 95.254}),
    ("height_cm", "100 and 70 centimeters.", {"height_cm": 170.0}),
    ("weight_kg", "I weigh 1 80.", {"weight_kg": 81.647}),
    ("weight_kg", "About 1 45 pounds.", {"weight_kg": 65.771}),
    # A range keeps its two numbers.
    ("weight_kg", "between 100 and 110 pounds", {"weight_kg": 47.627}),
]
SPLIT_HUNDRED_TRAPS = [
    ("weight_kg", "I weigh 1 80 kg"),  # 180 kg is no everyday split
    ("height_cm", "1 80"),  # only a weight reads "1 80" as pounds
    ("weight_kg", "1 80 over 90"),  # a blood pressure, not a weight
]


@pytest.mark.parametrize(("field", "text", "expected"), SPLIT_HUNDREDS)
def test_hundreds_split_by_the_transcript_are_joined(field, text, expected):
    check(field, text, expected)


@pytest.mark.parametrize(("field", "text"), SPLIT_HUNDRED_TRAPS)
def test_split_hundreds_that_could_mean_something_else_are_asked_about(field, text):
    check(field, text, None)


# "Five, ten" and "six, seven hours" come out of the transcript with a comma.
COMMA_PAIRS = [
    ("height_cm", "5, 11.", {"height_cm": 180.34}),
    ("height_cm", "6, 2", {"height_cm": 187.96}),
    ("sleep_hours", "6, 7 hours a night.", {"sleep_hours": 6.5}),
    ("alcohol_drinks_weekly", "2, 3 beers a week.", {"alcohol_drinks_weekly": 2.5}),
]
COMMA_PAIR_TRAPS = [
    ("height_cm", "5, 13"),  # no such inches
    ("sleep_hours", "4, 8 hours."),  # too wide to be one answer
    ("sleep_hours", "bed at 10, 6 hours"),  # a clock time and hours
]


@pytest.mark.parametrize(("field", "text", "expected"), COMMA_PAIRS)
def test_a_pair_written_with_a_comma_is_read_like_one_said_together(field, text, expected):
    check(field, text, expected)


@pytest.mark.parametrize(("field", "text"), COMMA_PAIR_TRAPS)
def test_a_comma_pair_that_is_not_one_answer_is_asked_about(field, text):
    check(field, text, None)


def test_a_comma_range_is_read_back_as_about():
    assert "about 6.5 hours" in say("sleep_hours", "6, 7 hours a night.").message
