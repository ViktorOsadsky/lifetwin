"""Claude's computed answers, re-checked by the deterministic reader before a read-back.

The grounded quote (parsing.grounded_candidates) stays first. A computed value is used
only for the asked field, from an exact quote of the reply, when the reply is the
person's own current answer. The reader's value wins whenever it can read the quote;
a value it cannot read at all is offered only when the quote holds a number and the
value is in range, and is always read back for a yes before it is kept.
"""

import re

from lifetwin.core.quantities import FIELDS, agrees, read_quantity
from lifetwin.onboarding.models import ExtractionResult
from lifetwin.onboarding.parsing import NOT_CURRENT, _canonical, _doubtful, _others

# Plausible ranges for a computed value the reader could not read (stricter than storage).
COMPUTED_RANGES = {
    "hours": (1, 20),
    "minutes_week": (0, 10080),
    "minutes_day": (0, 1439),
    "height": (100, 230),
    "weight": (25, 350),
}
NUMBER = re.compile(
    r"\d|\b(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"
    r"fifteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|half|"
    r"couple|hour)\b",
    re.I,
)


def _range(field: str) -> tuple[float, float]:
    unit, period = FIELDS[field]
    if unit == "minutes":
        return COMPUTED_RANGES["minutes_week" if period == "week" else "minutes_day"]
    return COMPUTED_RANGES[unit]


def _stored(field: str, value: float) -> float | int:
    return round(value) if FIELDS[field][0] == "minutes" else round(value, 2)


def checked_values(text: str, extraction: ExtractionResult, asked: str, grounded: dict) -> dict:
    """``grounded`` plus the asked field's computed value where the reader allows it."""
    if asked in grounded or asked not in FIELDS:
        return grounded
    plain = _canonical(text)
    if _doubtful(plain) or NOT_CURRENT.search(plain) or _others(text):
        return grounded
    whole = read_quantity(text, asked)
    if whole.status in {"period", "other_topic", "wrong_unit", "ambiguous", "range"}:
        return grounded  # the reply itself says it is not this answer, or is unsure
    for candidate in extraction.candidates:
        if candidate.field != asked or candidate.value is None:
            continue
        if candidate.quote not in text or not NUMBER.search(candidate.quote):
            continue
        if whole.ok and whole.value is not None:
            # Deterministic first: the reader's arithmetic on the whole reply wins.
            return {**grounded, asked: _stored(asked, whole.value)}
        reading = read_quantity(candidate.quote, asked)
        if reading.ok and reading.value is not None:
            if agrees(candidate.value, reading, asked):
                return {**grounded, asked: _stored(asked, reading.value)}
            continue  # they disagree and the reply is unclear: asked again, never guessed
        if reading.status != "none":
            continue
        low, high = _range(asked)
        if low <= candidate.value <= high:
            return {**grounded, asked: _stored(asked, candidate.value)}
    return grounded
