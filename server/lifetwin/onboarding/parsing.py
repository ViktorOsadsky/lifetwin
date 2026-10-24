"""Conservative keyless extraction: ambiguous values remain unconfirmed."""

import re

from pydantic import ValidationError

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import ExtractionResult, ProfileField

QUESTIONS: dict[ProfileField, str] = {
    "age": "How old are you in years? You can skip anything you don't know.",
    "sex": "Which sex category would you like to record: female, male, intersex, or prefer not to say?",
    "height_cm": "How tall are you? Please include cm, meters, or feet and inches.",
    "weight_kg": "What is your current weight? Please include kg or pounds.",
    "sleep_hours": "How many hours do you usually sleep per night?",
    "exercise_minutes_weekly": "How many minutes of exercise do you usually do per week?",
    "smoking_status": "Have you never smoked, formerly smoked, or do you currently smoke? Unknown is okay too.",
    "alcohol_drinks_weekly": "How many alcoholic drinks do you usually have per week?",
    "diabetes": "Have you been diagnosed with diabetes? Please say yes, no, or skip if unsure.",
    "systolic_bp": "Do you know your systolic blood pressure in mmHg, the top number? You can also give both as 120/80.",
    "diastolic_bp": "Do you know your diastolic blood pressure in mmHg, the bottom number?",
}

LABELS: dict[str, ProfileField] = {
    "age": "age",
    "sex": "sex",
    "height": "height_cm",
    "height_cm": "height_cm",
    "weight": "weight_kg",
    "weight_kg": "weight_kg",
    "sleep": "sleep_hours",
    "sleep_hours": "sleep_hours",
    "exercise": "exercise_minutes_weekly",
    "exercise_minutes_weekly": "exercise_minutes_weekly",
    "smoking": "smoking_status",
    "smoking_status": "smoking_status",
    "alcohol": "alcohol_drinks_weekly",
    "alcohol_drinks_weekly": "alcohol_drinks_weekly",
    "diabetes": "diabetes",
    "systolic": "systolic_bp",
    "systolic_bp": "systolic_bp",
    "diastolic": "diastolic_bp",
    "diastolic_bp": "diastolic_bp",
}
SKIP_WORDS = {"skip", "unknown", "i don't know", "i do not know", "not sure", "unsure"}
# Bound numeric tokens before conversion, as well as validating profile ranges.
# Every admitted measurement fits these limits; enormous spoken-number tokens
# cannot overflow feet conversions or create non-finite intermediates.
NUMBER = r"(\d{1,6}(?:\.\d{1,6})?)"
PREFIXES: dict[ProfileField, str] = {
    "age": r"(?:i am|i'm|my age is)",
    "sex": r"(?:i am|i'm|my sex is)",
    "height_cm": r"(?:i am|i'm|my height is)",
    "weight_kg": r"(?:i weigh|my weight is)",
    "sleep_hours": r"(?:i sleep|my sleep is)",
    "exercise_minutes_weekly": r"(?:i exercise)",
    "alcohol_drinks_weekly": r"(?:i drink)",
    "smoking_status": r"(?!)",
    "diabetes": r"(?!)",
    "systolic_bp": r"(?:my systolic blood pressure is|my systolic is)",
    "diastolic_bp": r"(?:my diastolic blood pressure is|my diastolic is)",
}


def _number(value: str, suffix: str = "") -> float | None:
    match = re.fullmatch(NUMBER + suffix, value)
    return float(match.group(1)) if match else None


def parse_value(field: ProfileField, text: str) -> dict:
    """Accept explicit single measurements; do not guess units or diagnoses."""
    value = text.strip().lower().rstrip(".!?").strip()
    value = re.sub(r"^" + PREFIXES[field] + r"\s+", "", value)
    result: float | int | str | bool | None = None
    if field == "age":
        result = _number(value, r"(?:\s*(?:years?(?: old)?|yrs?))?")
    elif field == "height_cm":
        cm = _number(value, r"\s*(?:cm|centimeters?|centimetres?)")
        meters = _number(value, r"\s*(?:m|meters?|metres?)")
        feet = re.fullmatch(
            r"(\d{1,2})\s*(?:ft|feet|foot|')\s*(?:(\d{1,2}(?:\.\d{1,6})?)\s*(?:in|inches|inch|\"))?",
            value,
        )
        if feet and (feet.group(2) is None or float(feet.group(2)) < 12):
            result = int(feet.group(1)) * 30.48 + float(feet.group(2) or 0) * 2.54
        elif cm is not None:
            result = cm
        elif meters is not None:
            result = meters * 100
    elif field == "weight_kg":
        kg = _number(value, r"\s*(?:kg|kilograms?|kilos?)")
        lb = _number(value, r"\s*(?:lb|lbs|pounds?)")
        result = kg if kg is not None else lb * 0.45359237 if lb is not None else None
    elif field == "sleep_hours":
        result = _number(value, r"(?:\s*(?:hours?|hrs?|h)(?:\s*(?:per|a|each)\s*night)?)?")
    elif field == "exercise_minutes_weekly":
        result = _number(value, r"(?:\s*(?:minutes?|mins?)(?:\s*(?:per|a|each|/)\s*week)?)?")
        hours = _number(value, r"\s*(?:hours?|hrs?)(?:\s*(?:per|a|each|/)\s*week)")
        if hours is not None:
            result = hours * 60
    elif field == "alcohol_drinks_weekly":
        result = _number(value, r"(?:\s*drinks?(?:\s*(?:per|a|each|/)\s*week)?)?")
        if value in {"none", "i don't drink", "i do not drink"}:
            result = 0.0
    elif field in {"systolic_bp", "diastolic_bp"}:
        pair = re.fullmatch(r"(\d{2,3})\s*/\s*(\d{2,3})(?:\s*mmhg)?", value)
        if pair:
            return _validated(
                {"systolic_bp": int(pair.group(1)), "diastolic_bp": int(pair.group(2))}
            )
        result = _number(value, r"(?:\s*mmhg)?")
    elif field == "sex":
        result = {
            "female": "female",
            "male": "male",
            "intersex": "intersex",
            "prefer not to say": "prefer_not_to_say",
            "prefer_not_to_say": "prefer_not_to_say",
        }.get(value)
    elif field == "smoking_status":
        result = {
            "never": "never",
            "never smoked": "never",
            "i have never smoked": "never",
            "former": "former",
            "formerly smoked": "former",
            "i quit smoking": "former",
            "current": "current",
            "currently smoke": "current",
            "i smoke": "current",
            "unknown": "unknown",
        }.get(value)
    elif field == "diabetes":
        if value in {"yes", "yes diagnosed", "i have been diagnosed with diabetes"}:
            result = True
        elif value in {"no", "no diagnosis", "i have not been diagnosed with diabetes"}:
            result = False
    if result is None:
        return {}
    if field in {"age", "exercise_minutes_weekly", "systolic_bp", "diastolic_bp"}:
        if not float(result).is_integer():
            return {}
        result = int(result)
    elif isinstance(result, float):
        result = round(result, 4)
    return _validated({field: result})


def _validated(values: dict) -> dict:
    try:
        return HealthProfile.model_validate(values).model_dump(exclude_none=True)
    except ValidationError:
        return {}


def parse_reply(text: str, field: ProfileField) -> dict:
    """Handle a short answer or several explicitly labeled clauses."""
    parts = re.split(r"[;,]|\s+and\s+", text.strip(), flags=re.I)
    values: dict = {}
    for part in parts:
        if not part.strip():
            continue
        label = re.fullmatch(r"\s*([a-z_]+)\s*[:=]\s*(.+)\s*", part, re.I)
        if label:
            target = LABELS.get(label.group(1).lower())
            if target is None:
                return {}
            parsed = parse_value(target, label.group(2))
        elif len(parts) == 1:
            parsed = parse_value(field, part)
        else:
            # Unlabeled leftovers may contradict a labeled measurement. Never
            # discard "80 kg" from "weight: 70 kg and 80 kg", for example.
            return {}
        if not parsed:
            return {}
        # Contradictory repeated values require clarification of the whole turn.
        if any(key in values and values[key] != val for key, val in parsed.items()):
            return {}
        values.update(parsed)
    return values


def grounded_candidates(text: str, extraction: ExtractionResult) -> dict:
    """Validate evidence boundaries AND the full context of every clause.

    A provider-selected span cannot remove a negation, past/hypothetical tense,
    uncertainty, or a contradictory second measurement. Conservative grammar
    leaves unfamiliar prose for clarification rather than trusting an LLM claim.
    """
    clauses = [
        clause.strip()
        for clause in re.split(r"[;,\n]|(?<!\d)[.!?]|[.!?](?!\d)|\s+and\s+", text, flags=re.I)
        if clause.strip()
    ]
    values: dict = {}
    covered: set[int] = set()
    for candidate in extraction.candidates:
        quote_values = parse_value(candidate.field, candidate.quote)
        if not quote_values:
            return {}
        matching_clauses = []
        for index, clause in enumerate(clauses):
            # Word boundaries stop "male" inside "female" and "70 kg"
            # inside "170 kg" from serving as evidence.
            if not re.search(r"(?<!\w)" + re.escape(candidate.quote) + r"(?!\w)", clause):
                continue
            # These two modifiers assert present time; stripping any other
            # prose would risk dropping negation, ambiguity, or historical context.
            normalized = re.sub(r"\b(?:current|currently)\s+", "", clause, flags=re.I)
            clause_values = parse_reply(normalized, candidate.field)
            if clause_values != quote_values:
                return {}
            matching_clauses.append(index)
        if not matching_clauses:
            return {}
        if any(key in values and values[key] != value for key, value in quote_values.items()):
            return {}
        covered.update(matching_clauses)
        values.update(quote_values)
    # Every complete clause must be accounted for. This prevents a provider
    # from ignoring an alternative answer or an attached contextual qualifier.
    return values if len(covered) == len(clauses) else {}
