"""Conservative keyless extraction: ambiguous values remain unconfirmed."""

import re

from pydantic import ValidationError

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import ExtractionResult, ProfileField

QUESTIONS: dict[ProfileField, str] = {
    "age": "How old are you? You can skip any question you don't know.",
    "sex": 'Are you a woman or a man? You can also say intersex, or "prefer not to say".',
    "height_cm": "How tall are you? For example, 5 feet 10 inches, or 178 cm.",
    "weight_kg": "How much do you weigh? For example, 160 pounds, or 72 kg.",
    "sleep_hours": "How many hours do you usually sleep each night? For example, 7 hours.",
    "exercise_minutes_weekly": (
        "How many minutes of exercise do you get in a whole week? "
        "For example, a 30-minute walk 5 days a week is 150 minutes."
    ),
    "smoking_status": "Do you smoke now, did you smoke in the past, or have you never smoked?",
    "alcohol_drinks_weekly": (
        "How many alcoholic drinks do you usually have in a week? "
        'For example, 3 drinks. If you don\'t drink, say "none".'
    ),
    "diabetes": (
        "Has a doctor ever told you that you have diabetes? Please say yes or no. "
        "If you're not sure, say \"I don't know\"."
    ),
    "systolic_bp": (
        "What is your blood pressure? For example, 120 over 80. "
        "If you don't know it, just say \"I don't know\"."
    ),
    "diastolic_bp": (
        "What is the bottom number of your blood pressure? For example, the 80 in 120 over 80. "
        "If you don't know it, just say \"I don't know\"."
    ),
}
# Plain names for messages; code identifiers never reach the person.
FRIENDLY_LABELS: dict[ProfileField, str] = {
    "age": "age",
    "sex": "sex",
    "height_cm": "height",
    "weight_kg": "weight",
    "sleep_hours": "sleep",
    "exercise_minutes_weekly": "exercise",
    "smoking_status": "smoking",
    "alcohol_drinks_weekly": "alcohol",
    "diabetes": "diabetes",
    "systolic_bp": "top blood pressure number",
    "diastolic_bp": "bottom blood pressure number",
}
EXAMPLES: dict[ProfileField, str] = {
    "age": '"I\'m 72"',
    "sex": '"a woman"',
    "height_cm": '"5 feet 10 inches"',
    "weight_kg": '"160 pounds"',
    "sleep_hours": '"7 hours"',
    "exercise_minutes_weekly": '"150 minutes a week"',
    "smoking_status": '"I never smoked"',
    "alcohol_drinks_weekly": '"3 drinks a week"',
    "diabetes": '"I don\'t have diabetes"',
    "systolic_bp": '"120 over 80"',
    "diastolic_bp": '"80"',
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
SKIP_WORDS = {
    "skip",
    "skip it",
    "skip this",
    "skip this one",
    "pass",
    "next",
    "unknown",
    "i don't know",
    "i do not know",
    "don't know",
    "dont know",
    "i dont know",
    "not sure",
    "i'm not sure",
    "im not sure",
    "i am not sure",
    "unsure",
    "no idea",
    "i have no idea",
    "i don't remember",
    "i do not remember",
    "don't remember",
    "i'd rather not say",
    "i would rather not say",
    "rather not say",
    "prefer not to say",
    "i prefer not to say",
}
# These record an answer for sex instead of skipping the question.
SEX_PREFER_NOT = {
    "prefer not to say",
    "i prefer not to say",
    "i'd rather not say",
    "i would rather not say",
    "rather not say",
}
# "Do you know your blood pressure?" is commonly answered with a plain no.
BP_NO = {"no", "nope", "no i don't", "no i do not", "i don't"}
BP_ORDER_MESSAGE = (
    "The top number is usually the bigger one. Could you check your reading? "
    "For example, 120 over 80."
)
# A provider may assign a quote to a field other than the one asked only when
# the clause itself names that field: bare "160" for weight is not systolic.
FIELD_CUES: dict[ProfileField, str] = {
    "age": r"\b(?:age|years?|yrs?|old)\b",
    "sex": r"\b(?:sex|female|male|intersex|woman|man)\b",
    "height_cm": r"height|tall|cm\b|centimet|met(?:er|re)|\d\s*m\b|ft\b|feet|foot|inch|\d\s*in\b|['\"]",
    "weight_kg": r"weigh|kg\b|kilo|lbs?\b|pound",
    "sleep_hours": r"sleep|night",
    "exercise_minutes_weekly": r"exercis|minutes?|mins?\b|workout|walk|week",
    "smoking_status": r"smok|cigar",
    "alcohol_drinks_weekly": r"drink|alcohol|beer|wine",
    "diabetes": r"diabet",
    "systolic_bp": r"systolic|blood pressure|mmhg|\btop\b|\d\s*(?:/|over)\s*\d",
    "diastolic_bp": r"diastolic|blood pressure|mmhg|\bbottom\b|\d\s*(?:/|over)\s*\d",
}
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
    "systolic_bp": r"(?:my systolic blood pressure is|my systolic is|my blood pressure is)",
    "diastolic_bp": r"(?:my diastolic blood pressure is|my diastolic is|my blood pressure is)",
}
QUOTES = str.maketrans(
    {"\u2019": "'", "\u2018": "'", "\u201c": '"', "\u201d": '"', "\u2032": "'", "\u2033": '"'}
)
BP_PAIR = r"(\d{2,3})\s*(?:/|over)\s*(\d{2,3})(?:\s*mmhg)?"


def normalize_text(text: str) -> str:
    """Map smart punctuation (iOS default) and prime marks to ASCII; collapse spaces."""
    return " ".join(text.translate(QUOTES).split())


UNITS_WORDS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
}
TENS_WORDS = {
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
    "seventy": 70,
    "eighty": 80,
    "ninety": 90,
}
NUMBER_WORDS = re.compile(
    r"\b(?:(a|one|two) hundred(?: and)? )?(?:("
    + "|".join(TENS_WORDS)
    + r")(?:[ -]("
    + "|".join(UNITS_WORDS)
    + r"))?|("
    + "|".join(UNITS_WORDS)
    + r"))\b"
    r"|\b(a|one|two) hundred\b"
)


def _number_words(value: str) -> str:
    """Spoken answers arrive as words: "five foot eight" -> "5 foot 8"."""

    def digits(m: re.Match) -> str:
        hundreds = m.group(1) or m.group(5)
        total = {"a": 100, "one": 100, "two": 200}[hundreds] if hundreds else 0
        if m.group(2):
            total += TENS_WORDS[m.group(2)] + (UNITS_WORDS[m.group(3)] if m.group(3) else 0)
        elif m.group(4):
            total += UNITS_WORDS[m.group(4)]
        return str(total)

    value = re.sub(r"\b(?:half an hour|a half hour)\b", "30 minutes", value)
    return NUMBER_WORDS.sub(digits, value)


# Everyday speech around an otherwise explicit answer. Approximations ("about 170
# pounds") are accepted because every value is read back for confirmation; real
# uncertainty, negation and past or hypothetical tense ("maybe", "not", "used to",
# "if") are never stripped, so those answers still go to clarification.
FILLERS = r"^(?:(?:oh|well|um|uh|so|hmm|ok|okay)\s+)+"
HABIT = r"^(?:usually|normally|typically|generally)\s+"
# Only verbs that belong to the asked field: "I weigh 70" must never answer the age question.
HABIT_VERBS: dict[str, str] = {
    "sleep_hours": "get|sleep",
    "exercise_minutes_weekly": "do|get|walk|exercise",
    "weight_kg": "weigh",
    "alcohol_drinks_weekly": "have|drink",
}
APPROX = r"\b(?:about|around|roughly|approximately|close to|nearly|almost)\s+(?=\d)"
TRAILING = (
    r"\s+(?:i think|i guess|i believe|or so|give or take|more or less"
    r"|these days|nowadays|right now|at the moment)$"
)
# "two hours of walking a week": the activity name is not part of the measurement.
ACTIVITY = (
    r"\s+of\s+(?:walking|exercise|exercising|activity|swimming|biking|cycling|gardening|dancing)\b"
)


def _phrase(field: ProfileField, text: str) -> str:
    value = normalize_text(text).lower().rstrip(".!?").strip()
    # Commas are pauses inside one spoken answer ("no, I don't"; "5 feet, 10 inches").
    value = " ".join(value.replace(",", " ").split())
    value = re.sub(FILLERS, "", value)
    value = re.sub(r"^" + PREFIXES[field] + r"\s+", "", value)
    value = re.sub(HABIT, "", value)
    if field in HABIT_VERBS:
        value = re.sub(
            r"^i\s+(?:usually\s+|normally\s+|typically\s+)?(?:" + HABIT_VERBS[field] + r")\s+",
            "",
            value,
        )
    value = _number_words(value)
    value = re.sub(TRAILING, "", value)
    if field == "exercise_minutes_weekly":
        value = re.sub(ACTIVITY, "", value)
    value = re.sub(APPROX, "", value)
    return re.sub(r"(\d+) and a half\b", r"\1.5", value)


def is_skip(text: str, field: ProfileField) -> bool:
    phrase = " ".join(normalize_text(text).lower().replace(",", " ").rstrip(".!?").split())
    if field == "smoking_status" and phrase == "unknown":
        return False
    if field == "sex" and phrase in SEX_PREFER_NOT:
        return False
    if field in {"systolic_bp", "diastolic_bp"} and phrase in BP_NO:
        return True
    return phrase in SKIP_WORDS


def _number(value: str, suffix: str = "") -> float | None:
    match = re.fullmatch(NUMBER + suffix, value)
    return float(match.group(1)) if match else None


def parse_value(field: ProfileField, text: str) -> dict:
    """Accept explicit single measurements; do not guess units or diagnoses."""
    value = _phrase(field, text)
    result: float | int | str | bool | None = None
    if field == "age":
        result = _number(value, r"(?:\s*(?:years?(?: old)?|yrs?))?")
    elif field == "height_cm":
        value = re.sub(r"\s+tall$", "", value)
        cm = _number(value, r"\s*(?:cm|centimeters?|centimetres?)")
        meters = _number(value, r"\s*(?:m|meters?|metres?)")
        inches = _number(value, r"\s*(?:in|inches|inch|\")")
        feet = re.fullmatch(
            r"(\d{1,2})\s*(?:ft\.?|feet|foot|')"
            r"(?:\s*(?:and\s+)?(\d{1,2}(?:\.\d{1,6})?)\s*(?:in\.?|inches|inch|\")?)?",
            value,
        )
        if feet:
            if feet.group(2) is None or float(feet.group(2)) < 12:
                result = int(feet.group(1)) * 30.48 + float(feet.group(2) or 0) * 2.54
        elif cm is not None:
            result = cm
        elif meters is not None:
            result = meters * 100
        elif inches is not None:
            result = inches * 2.54
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
        # A bare small number is more likely days or hours than weekly minutes.
        if re.fullmatch(NUMBER, value) and 0 < float(value) < 15:
            result = None
        daily = re.fullmatch(
            NUMBER + r"\s*(minutes?|mins?|hours?|hrs?)\s*(?:a|per|each)\s*day"
            r"\s*(?:and\s+)?(?:([1-7])\s*days?\s*(?:a|per|each)\s*week|(every day))",
            value,
        )
        if daily:
            per_day = float(daily.group(1)) * (1 if daily.group(2).startswith("m") else 60)
            result = per_day * (7 if daily.group(4) else int(daily.group(3)))
        if value in {"none", "i don't exercise", "i do not exercise"}:
            result = 0
    elif field == "alcohol_drinks_weekly":
        result = _number(value, r"(?:\s*drinks?(?:\s*(?:per|a|each|/)\s*week)?)?")
        if value in {"none", "i don't drink", "i do not drink"}:
            result = 0.0
    elif field in {"systolic_bp", "diastolic_bp"}:
        pair = re.fullmatch(BP_PAIR, value)
        if pair:
            systolic, diastolic = int(pair.group(1)), int(pair.group(2))
            if systolic <= diastolic:
                return {}
            return _validated({"systolic_bp": systolic, "diastolic_bp": diastolic})
        result = _number(value, r"(?:\s*mmhg)?")
    elif field == "sex":
        result = {
            "female": "female",
            "woman": "female",
            "a woman": "female",
            "male": "male",
            "man": "male",
            "a man": "male",
            "intersex": "intersex",
            "prefer_not_to_say": "prefer_not_to_say",
            **dict.fromkeys(SEX_PREFER_NOT, "prefer_not_to_say"),
        }.get(value)
    elif field == "smoking_status":
        result = {
            "never": "never",
            "never smoked": "never",
            "i never smoked": "never",
            "i've never smoked": "never",
            "i have never smoked": "never",
            "former": "former",
            "formerly smoked": "former",
            "in the past": "former",
            "i smoked in the past": "former",
            "i used to smoke": "former",
            "i quit": "former",
            "i quit smoking": "former",
            "current": "current",
            "currently smoke": "current",
            "i smoke": "current",
            "i smoke now": "current",
            "yes i smoke": "current",
            "unknown": "unknown",
        }.get(value)
        # "I quit smoking back in 1990", "I stopped smoking years ago": quitting is the answer.
        if result is None and re.fullmatch(
            r"i(?: have|'ve)? (?:quit|stopped|gave up)(?: smoking)?(?: .+)?|i used to smoke(?: .+)?",
            value,
        ):
            result = "former"
    elif field == "diabetes":
        if value in {
            "yes",
            "yes diagnosed",
            "yes i do",
            "yes i have diabetes",
            "i have diabetes",
            "i have been diagnosed with diabetes",
        }:
            result = True
        elif value in {
            "no",
            "nope",
            "no i don't",
            "no i do not",
            "no diagnosis",
            "i don't have diabetes",
            "i do not have diabetes",
            "no i don't have diabetes",
            "i have not been diagnosed with diabetes",
        }:
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


def clarify(text: str, field: ProfileField) -> str | None:
    """Field-specific follow-up for an answer that is close but not safe to read."""
    value = _phrase(field, text)
    about = re.fullmatch(r"(?:about|around|roughly|approximately|maybe)\s+(.+)", value)
    bare = re.fullmatch(NUMBER, about.group(1) if about else value)
    number = bare.group(1) if bare else None
    if field == "weight_kg":
        if about:
            return (
                "Your best guess is fine. Please say just the number with pounds or "
                'kilograms, like "160 pounds".'
            )
        if number:
            return (
                f"Is that {number} pounds or {number} kilograms? Please say the number "
                f'with the unit, like "{number} pounds".'
            )
    if field == "height_cm":
        if about:
            return (
                "Your best guess is fine. Please say just the number with the unit, "
                'like "5 feet 10 inches" or "178 cm".'
            )
        if number:
            return (
                "Is that inches or centimeters? Please say it with the unit, "
                'like "70 inches". You can also say "5 feet 10 inches".'
            )
    if field in {"systolic_bp", "diastolic_bp"}:
        pair = re.fullmatch(BP_PAIR, value)
        if pair and int(pair.group(1)) <= int(pair.group(2)):
            return BP_ORDER_MESSAGE
    if field == "exercise_minutes_weekly":
        if re.search(r"\b(?:a|per|each|every)\s+day\b", value):
            return (
                "How many days a week do you do that? You can say, for example, "
                '"30 minutes a day, 5 days a week".'
            )
        if number and not about and 0 < float(number) < 15:
            return (
                f"Is that {number} minutes or {number} hours in the whole week? Please say it "
                f'with minutes or hours, like "{number} hours a week".'
            )
    return None


def _validated(values: dict) -> dict:
    try:
        return HealthProfile.model_validate(values).model_dump(exclude_none=True)
    except ValidationError:
        return {}


def parse_reply(text: str, field: ProfileField) -> dict:
    """Handle a short answer or several explicitly labeled clauses."""
    text = normalize_text(text)
    # One measurement may contain commas or "and" ("5 feet, 10 inches").
    whole = parse_value(field, text)
    if whole:
        return whole
    parts = re.split(r"[;,]|\s+and\s+", text, flags=re.I)
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


def grounded_candidates(text: str, extraction: ExtractionResult, asked: ProfileField) -> dict:
    """Validate evidence boundaries AND the full context of every clause.

    A provider-selected span cannot remove a negation, past/hypothetical tense,
    uncertainty, or a contradictory second measurement. Conservative grammar
    leaves unfamiliar prose for clarification rather than trusting an LLM claim.
    A field other than the asked one needs a clause that names it, so a bare
    "160" given for weight can never become a blood pressure.
    """
    text = normalize_text(text)
    clauses = [
        clause.strip()
        for clause in re.split(r"[;,\n]|(?<!\d)[.!?]|[.!?](?!\d)|\s+and\s+", text, flags=re.I)
        if clause.strip()
    ]
    values: dict = {}
    covered: set[int] = set()
    for candidate in extraction.candidates:
        quote = normalize_text(candidate.quote)
        quote_values = parse_value(candidate.field, quote)
        if not quote_values:
            return {}
        matching_clauses = []
        for index, clause in enumerate(clauses):
            # Word boundaries stop "male" inside "female" and "70 kg"
            # inside "170 kg" from serving as evidence.
            if not re.search(r"(?<!\w)" + re.escape(quote) + r"(?!\w)", clause):
                continue
            if candidate.field != asked and not re.search(
                FIELD_CUES[candidate.field], clause, flags=re.I
            ):
                return {}
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
