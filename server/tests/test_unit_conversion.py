"""Hours and minutes: the question's own period, word numbers, ranges, minutes of sleep,
vague portions and implausible values (owner: "why can the onboarding not convert
between hours and minutes?")."""

from datetime import date

import pytest

from lifetwin.onboarding.parsing import approximate, clarify, parse_reply, parse_value

TODAY = date(2026, 10, 24)
MOD, VIG = "moderate_recreation_min_week", "vigorous_recreation_min_week"
SED, SLEEP = "sedentary_min_day", "sleep_hours"


def read(text: str, field: str) -> dict:
    return parse_reply(text, field, today=TODAY, strict=True)


# (a) No period said: the question's own (weekly activity per week, sitting per day).
@pytest.mark.parametrize(
    ("field", "text", "minutes"),
    [
        (MOD, "about 3 hours", 180),
        (MOD, "2 hours", 120),
        (VIG, "1 hour", 60),
        (VIG, "about two hours", 120),
        (MOD, "half an hour", 30),
        (SED, "about 8 hours", 480),
        (SED, "10 hours", 600),
        (SED, "300 minutes", 300),
    ],
)
def test_the_question_period_is_used_when_none_is_said(field, text, minutes):
    assert read(text, field) == {field: minutes}


def test_the_question_period_is_only_for_the_asked_question():
    # "I walk about 3 hours" said to the sleep question has no period of its own.
    assert MOD not in read("7 hours, and I walk about 3 hours", SLEEP)
    assert parse_value(MOD, "about 3 hours", today=TODAY) == {}
    # With a period it is read anywhere.
    assert read("7 hours, and I walk about 3 hours a week", SLEEP) == {SLEEP: 7, MOD: 180}


def test_a_frequency_without_a_count_is_still_asked_about():
    assert read("a 45 minute class", MOD) == {}
    assert read("an hour sometimes", MOD) == {}
    # A closing "sometimes more" qualifies the hour without blocking it (#244).
    assert read("an hour, sometimes more", MOD) == {MOD: 60}


# (b) Word numbers and fractions.
@pytest.mark.parametrize(
    ("field", "text", "minutes"),
    [
        (MOD, "two and a half hours", 150),
        (MOD, "three quarters of an hour a day", 315),
        (MOD, "a couple of hours", 120),
        (MOD, "an hour and fifteen minutes", 75),
        (VIG, "an hour and a half", 90),
        (MOD, "an hour and a half a week", 90),
        (SED, "eight and a half hours", 510),
    ],
)
def test_word_numbers_and_fractions(field, text, minutes):
    assert read(text, field) == {field: minutes}


# (c) Ranges: the middle, read back as "about".
@pytest.mark.parametrize(
    ("field", "text", "value"),
    [
        (SED, "six or seven hours", 390),
        (SED, "between 5 and 6 hours", 330),
        (MOD, "between 2 and 3 hours", 150),
        (MOD, "3-4 hours", 210),
        (VIG, "one or two hours", 90),
        (SLEEP, "six or seven hours", 6.5),
        (SLEEP, "between 6 and 7", 6.5),
    ],
)
def test_ranges_are_their_middle_and_read_back_as_about(field, text, value):
    assert read(text, field) == {field: value}
    assert approximate(text)


def test_a_wide_range_is_asked_about():
    assert read("2 to 5 hours", SED) == {}


# (d) Sleep said in minutes.
@pytest.mark.parametrize(
    ("text", "hours"),
    [("420 minutes", 7), ("about 450 minutes", 7.5), ("six hours and fifteen minutes", 6.25)],
)
def test_sleep_in_minutes_is_hours(text, hours):
    assert read(text, SLEEP) == {SLEEP: hours}


def test_a_short_number_of_minutes_is_no_night():
    assert read("90 minutes", SLEEP) == {}


# (e) Vague portions: no value, one gentle question for hours.
@pytest.mark.parametrize("text", ["half the day", "most of the day", "all day", "all day long"])
def test_vague_portions_are_never_guessed(text):
    assert read(text, SED) == {}
    assert "how many hours" in (clarify(text, SED, today=TODAY) or "").lower()


# (f) Implausible values stay out.
@pytest.mark.parametrize(
    ("field", "text"),
    [(SLEEP, "18 hours"), (SLEEP, "1200 minutes"), (SED, "21 hours"), (MOD, "200 hours")],
)
def test_implausible_values_are_rejected(field, text):
    assert read(text, field) == {}
