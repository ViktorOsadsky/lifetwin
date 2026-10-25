"""Spoken amounts in the asked field's unit: one small, deterministic reader.

"2 hours" to a minutes question is 120, "an hour and a half" is 90, "30 minutes three
times a week" is 90 a week, "5 foot 10" is 177.8 cm and "170 lbs" is 77.1 kg. It runs
before and after the conversation model (owner ruling 2026-10-25: "the voice agents need
to be able to do math"): a model's arithmetic is checked against it, and when the two
disagree the result here wins. It never guesses: a weight said to a sleep question, a
weekly amount said to a nightly question, a range or a vague amount reads as nothing.
The Supabase port mirrors it (supabase/functions/lifetwin-api/quantities.ts).
"""

import re
from dataclasses import dataclass
from typing import Literal

Status = Literal["ok", "none", "wrong_unit", "other_topic", "period", "ambiguous", "range"]

# field -> (dimension, the period its value covers)
FIELDS: dict[str, tuple[str, str]] = {
    "sleep_hours": ("hours", "night"),
    "sleep_hours_last_night": ("hours", "once"),
    "sleep_hours_night_before": ("hours", "once"),
    "exercise_minutes_weekly": ("minutes", "week"),
    "moderate_recreation_min_week": ("minutes", "week"),
    "vigorous_recreation_min_week": ("minutes", "week"),
    "sedentary_min_day": ("minutes", "day"),
    "exercise_minutes_today": ("minutes", "once"),
    "moderate_recreation_min": ("minutes", "once"),
    "vigorous_recreation_min": ("minutes", "once"),
    "height_cm": ("height", "once"),
    "weight_kg": ("weight", "once"),
}
RANGES: dict[str, tuple[float, float]] = {
    "hours": (0, 24),
    "height": (50, 280),
    "weight": (10, 700),
}
MINUTE_LIMITS = {"week": 10080, "day": 1439, "once": 1440, "night": 1440}
LB_PER_KG = 0.45359237

ONES = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19,
}  # fmt: skip
TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
    "eighty": 80, "ninety": 90,
}  # fmt: skip
_ONE = "|".join(ONES)
_TEN = "|".join(TENS)
_SIMPLE = rf"(?:(?P<{{t}}>{_TEN})(?:[\s-](?P<{{to}}>{_ONE}))?|(?P<{{o}}>{_ONE}))"
WORD_NUMBER = re.compile(
    r"\b(?P<h>a|one|two|three)\s+hundred(?:\s+and)?\s+"
    + _SIMPLE.format(t="t", to="to", o="o")
    + r"\b|\b(?P<bare>a|one|two|three)\s+hundred\b|\b"
    + _SIMPLE.format(t="t2", to="to2", o="o2")
    + r"\b"
)
HOURS = r"(?:hours?|hrs?|h)"
MINUTES = r"(?:minutes?|mins?)"
NUMBER = r"\d+(?:\.\d+)?"
DURATION = re.compile(
    rf"(?P<n>{NUMBER})\s*-?\s*(?P<u>{HOURS}|{MINUTES})\b"
    rf"(?:\s*(?:and\s+)?(?P<m>{NUMBER})\s*{MINUTES}\b)?"
)
FEET = re.compile(
    rf"(?P<f>[3-8])\s*(?:feet|foot|ft|')\s*(?:(?:and\s+)?(?P<i>{NUMBER})\s*"
    r"(?:inches|inch|in|\"|'')?)?(?![\d.])"
)
INCHES = re.compile(rf"(?P<n>{NUMBER})\s*(?:inches|inch|in|\")(?!\w)")
CM = re.compile(rf"(?P<n>{NUMBER})\s*(?:cm|centimet(?:er|re)s?)\b")
METRES = re.compile(r"(?P<n>[12](?:\.\d{1,2})?)\s*(?:m|met(?:er|re)s?)\b")
POUNDS = re.compile(rf"(?P<n>{NUMBER})\s*(?:lbs?|pounds?)\b")
KILOS = re.compile(rf"(?P<n>{NUMBER})\s*(?:kgs?|kilos?|kilograms?)\b")
STONE = re.compile(
    rf"(?P<s>{NUMBER})\s*(?:stone|st)\b(?:\s*(?:and\s+)?(?P<p>{NUMBER})\s*(?:lbs?|pounds?)?)?"
)
TIMES = re.compile(
    r"\b(?:(?P<n>\d+)\s+(?:times|days|sessions|mornings|evenings|nights)|(?P<w>once|twice))"
    r"\s+(?:a|per|each|every|in\s+a|this)\s+week\b"
    r"|\b(?P<d>\d)\s+days?\b"
)
DAILY = re.compile(r"\b(?:a|per|each|every)\s+day\b|\bdaily\b|\bevery\s+(?:morning|evening)\b")
WEEKLY = re.compile(r"\b(?:a|per|each|every|in\s+a)\s+week\b|\bweekly\b")
NIGHTLY = re.compile(r"\b(?:a|per|each|every)\s+night\b|\bnightly\b")
RANGE = re.compile(rf"{NUMBER}\s*(?:-|to|or)\s*{NUMBER}")
SLEEP_WORDS = re.compile(r"\b(?:sleep\w*|slept|asleep|in bed|naps?)\b")
AWAKE_WORDS = re.compile(
    r"\b(?:walk\w*|exercis\w*|gym|run\w*|jog\w*|swim\w*|bik\w*|cycl\w*|workout|"
    r"sit|sitting|sat|desk)\b"
)
VAGUE = re.compile(r"\b(?:a few|several|some|a lot|lots|many|a bit)\b")


@dataclass(frozen=True)
class Reading:
    """A value in the field's unit (``status == "ok"``), or why there is none."""

    value: float | None
    status: Status

    @property
    def ok(self) -> bool:
        return self.status == "ok"


NONE = Reading(None, "none")


def _word(match: re.Match) -> str:
    def hundreds(word: str) -> int:
        return 100 * (1 if word in {"a", "one"} else ONES[word])

    if match.group("bare"):
        return str(hundreds(match.group("bare")))
    total = hundreds(match.group("h")) if match.group("h") else 0
    suffix = "" if match.group("h") else "2"
    tens, ones = match.group("t" + suffix), match.group("to" + suffix)
    total += TENS[tens] + ONES.get(ones or "", 0) if tens else ONES[match.group("o" + suffix)]
    return str(total)


def spoken_numbers(text: str) -> str:
    """Lower case, number words as digits and spoken fractions as decimals."""
    s = text.lower().replace("’", "'").replace("”", '"').replace("½", ".5")
    s = re.sub(r"(?<=\d),(?=\d{3}\b)", "", s)
    s = re.sub(r"[!?,;:()]", " ", s)
    s = re.sub(r"\.(?!\d)", " ", s)
    s = re.sub(r"\ba couple(?: of)?\b", "2", s)
    s = re.sub(r"\b(an?|one)\s+hour\s+and\s+a\s+half\b", "1.5 hours", s)
    s = re.sub(r"\b(an?|one)\s+hour\s+and\s+a\s+quarter\b", "1.25 hours", s)
    s = re.sub(r"\bthree\s+quarters\s+of\s+an?\s+hour\b", "45 minutes", s)
    s = re.sub(
        r"\b(?:a\s+)?quarter\s+(?:of\s+)?an?\s+hour\b|\ba\s+quarter\s+hour\b", "15 minutes", s
    )
    s = re.sub(r"\bhalf\s+(?:an?\s+)?hour\b", "30 minutes", s)
    s = re.sub(r"\b(?:an?|one)\s+hour\b", "1 hour", s)
    s = re.sub(r"\b(?:a\s+)?half\s+(?:a\s+)?(pound|kilo|foot|inch)\b", r"0.5 \1", s)
    s = WORD_NUMBER.sub(_word, s)
    s = re.sub(r"(\d+)\s+and\s+a\s+half\b", r"\1.5", s)
    s = re.sub(r"(\d+)\s+and\s+a\s+quarter\b", r"\1.25", s)
    s = re.sub(r"(\d+)\s+and\s+three\s+quarters\b", r"\1.75", s)
    s = re.sub(r"(\d+)\s*(?:and\s+)?(\d+)\s*/\s*(\d+)\b", _mixed, s)
    s = re.sub(r"(\d)\s+point\s+(\d+)", r"\1.\2", s)
    return " ".join(s.split())


def _mixed(match: re.Match) -> str:
    whole, top, bottom = (int(group) for group in match.groups())
    return str(whole + top / bottom) if bottom and top < bottom else match.group(0)


def _minutes(text: str) -> list[tuple[float, tuple[int, int]]]:
    found = []
    for match in DURATION.finditer(text):
        n = float(match.group("n"))
        minutes = n * 60 if re.fullmatch(HOURS, match.group("u")) else n
        if match.group("m"):
            if not re.fullmatch(HOURS, match.group("u")):
                return []
            minutes += float(match.group("m"))
        found.append((minutes, match.span()))
    return found


def _frequency(rest: str, weekly: bool = False) -> tuple[str, int]:
    """(period said, sessions in a week) for the words around an amount."""
    times = TIMES.search(rest)
    if times:
        if times.group("w"):
            return "week", 1 if times.group("w") == "once" else 2
        return "week", int(times.group("n") or times.group("d"))
    if DAILY.search(rest):
        return "day", 7
    if WEEKLY.search(rest):
        return "week", 1
    if NIGHTLY.search(rest):
        return "night", 7
    # "on Mondays and again on Thursdays": one session on each day named (weekly only).
    days = set(re.findall(r"\b(mon|tues|wednes|thurs|fri|satur|sun)days?\b", rest))
    if days and weekly:
        return "week", len(days)
    return "none", 1


def _duration(text: str, field: str) -> Reading:
    unit, period = FIELDS[field]
    amounts = _minutes(text)
    if not amounts:
        if (
            POUNDS.search(text)
            or KILOS.search(text)
            or FEET.search(text)
            or CM.search(text)
            or METRES.search(text)
        ):
            return Reading(None, "wrong_unit")
        numbers = re.findall(NUMBER, text)
        if len(numbers) != 1 or re.search(r"\b(?:times|days|drinks?|steps|miles?|km)\b", text):
            return NONE
        n = float(numbers[0])
        # A bare number is in the asked unit, unless it cannot be ("2" minutes a week).
        if unit == "minutes" and n < 10:
            return Reading(None, "ambiguous")
        amounts = [(n * 60 if unit == "hours" else n, (0, 0))]
    rest = text
    for _, (start, end) in reversed(amounts):
        rest = rest[:start] + " " + rest[end:]
    said, sessions = _frequency(rest, weekly=period == "week")
    if len(amounts) > 1:
        # "an hour on Monday and an hour on Thursday": a week's parts add up.
        if period != "week" or said not in {"none", "week"} or sessions not in {1, len(amounts)}:
            return Reading(None, "ambiguous")
        minutes = sum(amount for amount, _ in amounts)
    else:
        minutes = amounts[0][0]
        if period == "week":
            minutes *= sessions
        elif said == "week":
            return Reading(None, "period")  # "2 hours a week" to a nightly or daily question
        elif said == "day" and period in {"once", "night"} and unit == "hours":
            pass  # "8 hours a day" of sleep
        elif said != "none" and period == "once" and unit == "minutes":
            return Reading(None, "period")
    if unit == "hours":
        value = round(minutes / 60, 2)
        # A usual night is 2 to 16 hours ("90 minutes" is no night); one night may be shorter.
        low, high = (2, 16) if period == "night" else (1, 20)
    else:
        value = round(minutes)
        low, high = 0, MINUTE_LIMITS[period]
    return Reading(value, "ok") if low <= value <= high else Reading(None, "range")


def _height(text: str) -> Reading:
    if _minutes(text) or POUNDS.search(text) or KILOS.search(text):
        return Reading(None, "wrong_unit")
    said = FEET.search(text) or CM.search(text) or METRES.search(text) or INCHES.search(text)
    if said and re.search(r"\d", text[: said.start()] + " " + text[said.end() :]):
        # "5 foot 4, well, probably 5 3 and a half": a second height. The rules read the
        # correction; the reader never picks one of the two.
        return Reading(None, "ambiguous")
    if feet := FEET.search(text):
        inches = float(feet.group("i") or 0)
        if inches >= 12:
            return Reading(None, "ambiguous")
        value = (int(feet.group("f")) * 12 + inches) * 2.54
    elif cm := CM.search(text):
        value = float(cm.group("n"))
    elif metres := METRES.search(text):
        value = float(metres.group("n")) * 100
    elif inches_only := INCHES.search(text):
        value = float(inches_only.group("n")) * 2.54
    else:
        numbers = re.findall(NUMBER, text)
        if len(numbers) == 2 and re.fullmatch(r"[4-7]\s+\d{1,2}", text.strip()):
            value = (int(numbers[0]) * 12 + int(numbers[1])) * 2.54  # "five ten"
            if int(numbers[1]) >= 12:
                return Reading(None, "ambiguous")
        elif len(numbers) == 1 and 120 <= float(numbers[0]) <= 230:
            value = float(numbers[0])  # the question asks in cm or feet: 120+ is cm
        else:
            return NONE
    value = round(value, 1)
    low, high = RANGES["height"]
    return Reading(value, "ok") if low <= value <= high else Reading(None, "range")


def _weight(text: str) -> Reading:
    if _minutes(text) or FEET.search(text) or CM.search(text):
        return Reading(None, "wrong_unit")
    if stone := STONE.search(text):
        value = (float(stone.group("s")) * 14 + float(stone.group("p") or 0)) * LB_PER_KG
    elif pounds := POUNDS.search(text):
        value = float(pounds.group("n")) * LB_PER_KG
    elif kilos := KILOS.search(text):
        value = float(kilos.group("n"))
    else:
        return NONE if not re.search(r"\d", text) else Reading(None, "ambiguous")
    value = round(value, 2)
    low, high = RANGES["weight"]
    return Reading(value, "ok") if low <= value <= high else Reading(None, "range")


def read_quantity(text: str, field: str) -> Reading:
    """The amount ``text`` states, in ``field``'s unit, or why it states none."""
    if field not in FIELDS or not text or len(text) > 500:
        return NONE
    s = spoken_numbers(text)
    if RANGE.search(s) or re.search(r"(?:^|\s)-\d", s):
        return Reading(None, "ambiguous")
    if VAGUE.search(s) and not re.search(r"\d", s):
        return NONE
    unit = FIELDS[field][0]
    # "7 and a half hours of sleep" to the exercise question answers another question.
    sleep_field = unit == "hours"
    if (SLEEP_WORDS.search(s) and not sleep_field) or (AWAKE_WORDS.search(s) and sleep_field):
        return Reading(None, "other_topic")
    if unit == "height":
        return _height(s)
    if unit == "weight":
        return _weight(s)
    if unit == "hours" and (POUNDS.search(s) or KILOS.search(s) or FEET.search(s)):
        return Reading(None, "wrong_unit")
    return _duration(s, field)


def agrees(value: float, reading: Reading, field: str) -> bool:
    """A model's value matches the deterministic reading, to the field's precision."""
    if not reading.ok or reading.value is None:
        return False
    tolerance = {"hours": 0.05, "height": 1.0, "weight": 0.5}.get(FIELDS[field][0], 0.5)
    return abs(float(value) - reading.value) <= tolerance


def contradicts(text: str, field: str) -> bool:
    """The reply's one amount is for another period or question than ``field``'s.

    "About 2 hours a week" to the nightly sleep question, "7 and a half hours of sleep"
    to the sitting question. A reply with several amounts is left to the parser, which
    reads each clause on its own ("7 hours, and I walk 3 hours a week").
    """
    if field not in FIELDS or FIELDS[field][0] not in {"hours", "minutes"}:
        return False
    reading = read_quantity(text, field)
    if reading.status == "period":
        return len(_minutes(spoken_numbers(text))) == 1
    return reading.status == "other_topic" and len(_minutes(spoken_numbers(text))) == 1
