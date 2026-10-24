"""Deterministic reading of everyday intake answers; anything unsafe is asked again.

A reply is first put in a canonical form: lower case, plain punctuation, number
words as digits ("one twenty" -> 120, "five foot ten and a half" -> "5 ft 10.5"),
fractions, and one spelling per unit. Each field's grammar then finds explicit
measurements anywhere in the reply, so everyday color around an answer
("Oh, I'm around 163 cm these days") does not matter.

A value is accepted only when nothing else in the reply could change it:
- no other number is left over (no second value, range or alternative);
- nowhere in the reply is there uncertainty, a hypothetical, a question, a
  vague amount or someone else ("my wife is 70");
- the clauses that carry the value contain no negation, no old or past
  reading, no change ("I lost 20 pounds"), no future, and no other field's
  topic ("I weigh 70" never answers age).

Approximations ("about 160 pounds") are accepted because every value is read
back for confirmation. Categorical answers use synonym families, and a
diagnosis is never inferred from casual language.
"""

import re
from datetime import date

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
    "bp": "systolic_bp",
    "blood pressure": "systolic_bp",
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
    "dunno",
    "i dunno",
    "not sure",
    "i'm not sure",
    "im not sure",
    "i am not sure",
    "unsure",
    "no idea",
    "i have no idea",
    "no clue",
    "i have no clue",
    "not a clue",
    "i don't remember",
    "i do not remember",
    "don't remember",
    "i can't remember",
    "can't remember",
    "i forget",
    "i'd rather not say",
    "i would rather not say",
    "rather not say",
    "i'd rather not",
    "prefer not to say",
    "i prefer not to say",
    "prefer not to answer",
    "i'd rather not answer",
}
# These record an answer (sex: prefer not to say; smoking: unknown) instead of skipping.
SEX_PREFER_NOT = {
    "prefer not to say",
    "i prefer not to say",
    "i'd rather not say",
    "i would rather not say",
    "rather not say",
    "i'd rather not",
    "prefer not to answer",
    "i'd rather not answer",
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
    "weight_kg": r"weigh|kg\b|kilo|lbs?\b|pound|stone",
    "sleep_hours": r"sleep|night",
    "exercise_minutes_weekly": r"exercis|minutes?|mins?\b|workout|walk|week",
    "smoking_status": r"smok|cigar",
    "alcohol_drinks_weekly": r"drink|alcohol|beer|wine",
    "diabetes": r"diabet",
    "systolic_bp": r"systolic|blood pressure|mmhg|\btop\b|\d\s*(?:/|over)\s*\d",
    "diastolic_bp": r"diastolic|blood pressure|mmhg|\bbottom\b|\d\s*(?:/|over)\s*\d",
}
BP_FIELDS = {"systolic_bp", "diastolic_bp"}
CATEGORICAL = {"sex", "smoking_status", "diabetes"}
NOTHING = r"(?!)"  # a pattern that never matches

# ---------------------------------------------------------------------------
# Canonical text
# ---------------------------------------------------------------------------

QUOTES = str.maketrans(
    {
        "\u2019": "'",
        "\u2018": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2032": "'",
        "\u2033": '"',
        "\u2013": "-",
        "\u2014": " - ",
        "\u00a0": " ",
    }
)
FRACTIONS = {"\u00bd": " and a half", "\u00bc": " and a quarter", "\u00be": " and three quarters"}


def normalize_text(text: str) -> str:
    """Map smart punctuation (iOS default), primes and fraction glyphs; collapse spaces."""
    text = text.translate(QUOTES)
    text = text.replace("''", '"')  # 5'4'' typed with two apostrophes
    for glyph, words in FRACTIONS.items():
        text = text.replace(glyph, words)
    return " ".join(text.split())


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
_WORD = "|".join([*UNITS_WORDS, *TENS_WORDS, "hundred", "point"])
NUMBER_RUN = re.compile(
    rf"\b(?:a\s+(?=hundred\b))?(?:{_WORD})\b(?:\s+(?:and\s+(?=(?:{_WORD})\b))?(?:{_WORD})\b)*"
)
# "a twenty-minute walk": a singular unit after the run means the number is adjectival,
# so "one twenty-minute walk" stays "1 20 minute" instead of becoming 120.
ADJECTIVAL = re.compile(r"\s*(?:minute|hour|mile|block|lap|pound|year|day)\b(?!s)")


def _compound(words: list[str], i: int) -> tuple[int | None, int]:
    word = words[i] if i < len(words) else None
    if word in TENS_WORDS:
        value, i = TENS_WORDS[word], i + 1
        if i < len(words) and 0 < UNITS_WORDS.get(words[i], 0) < 10:
            value, i = value + UNITS_WORDS[words[i]], i + 1
        return value, i
    if word in UNITS_WORDS:
        return UNITS_WORDS[word], i + 1
    return None, i


def _read_run(words: list[str], adjectival: bool) -> str:
    """One run of spoken number words -> digits ("one fifty two" -> "152")."""
    out: list[str] = []
    i, n = 0, len(words)
    while i < n:
        word = words[i]
        lead = 1 if word == "a" else UNITS_WORDS.get(word, 0)
        if 1 <= lead <= 9 and i + 1 < n and words[i + 1] == "hundred":
            total, i = lead * 100, i + 2
            if i + 1 < n and words[i] == "and":
                i += 1
            rest, i = _compound(words, i)
            value: int | None = total + (rest or 0)
            j = i
        else:
            value, j = _compound(words, i)
            if value is None:
                out.append("100" if word == "hundred" else word)
                i += 1
                continue
            single = j == i + 1 and word in UNITS_WORDS
            following, k = _compound(words, j)
            # Colloquial hundreds: "one twenty" (120), "two ten" (210). Heights
            # ("five ten") never start with one or two, so they stay feet/inches.
            if single and value in (1, 2) and following is not None and following >= 10:
                if not (adjectival and k == n):
                    value, j = value * 100 + following, k
            # Spoken years: "nineteen fifty" (1950).
            elif word == "nineteen" and j < n and words[j] in TENS_WORDS:
                value, j = 1900 + following, k
        if j + 1 < n and words[j] == "point" and UNITS_WORDS.get(words[j + 1], 10) < 10:
            digits, j = [], j + 1
            while j < n and UNITS_WORDS.get(words[j], 10) < 10:
                digits.append(str(UNITS_WORDS[words[j]]))
                j += 1
            out.append(f"{value}." + "".join(digits))
        else:
            out.append(str(value))
        i = j
    return " ".join(out)


def _half(match: re.Match, extra: float) -> str:
    return f"{float(match.group(1)) + extra:g}"


UNIT_SPELLINGS = [
    (r"\b(?:pounds?|lbs?)\b", "lb"),
    (r"\b(?:kilogram(?:me)?s?|kilos?|kgs?)\b", "kg"),
    (r"\bstones?\b", "stone"),
    (r"\b(?:centimet(?:er|re)s?|cms?)\b", "cm"),
    (r"\b(?:met(?:er|re)s?|mtrs?)\b", "m"),
    (r"\b(?:feet|foot|ft)\b", "ft"),
    (r"\b(?:inches|inch|ins)\b", "inch"),
    # A bare "in" is an inch only right after a number and before nothing else:
    # "5 ft 7 in." but never "77 in March".
    (r"(?<=\d) in\b(?=\s*(?:$|[,;.!?)]|tall\b|and\b))", " inch"),
    (r"\b(?:hours?|hrs?)\b", "hour"),
    (r"\b(?:minutes?|mins?)\b", "minute"),
    (r"\b(?:years?|yrs?)\b", "year"),
    (r"\b(?:mm ?hg|millimet(?:er|re)s? of mercury)\b", "mmhg"),
    (r"\bbp\b", "blood pressure"),
]


def _canonical(text: str) -> str:
    s = normalize_text(text).lower().replace("&", " and ")
    s = re.sub(r"(?<=\d),(?=\d{3}\b)", "", s)  # 10,000
    s = re.sub(r"(?<=[a-z])-(?=[a-z0-9])|(?<=\d)-(?=[a-z])", " ", s)  # seventy-six, 20-minute
    s = re.sub(r"\bmidnight\b", "12 am", s)
    s = re.sub(r"\bnoon\b", "12 pm", s)
    s = re.sub(r"\b([ap])\.m\.", r"\1m", s)
    s = re.sub(r"\b(lbs?|ft|in|yrs?|hrs?|mins?|kgs?|cms?|approx|st)\.", r"\1", s)
    # Decades are ranges, not ages: "in my 70s", "seventies".
    s = re.sub(r"\b\d0 ?'?s\b", " decades ", s)
    s = NUMBER_RUN.sub(
        lambda m: _read_run(m.group(0).split(), bool(ADJECTIVAL.match(s, m.end()))), s
    )
    s = re.sub(r"(\d)\s*'\s*(?=\d)", r"\1 ft ", s)  # 5'4
    s = re.sub(r"(\d)\s*'(?!s\b)", r"\1 ft", s)
    s = re.sub(r'(\d)\s*"', r"\1 inch", s)
    s = re.sub(r"(\d)(?!(?:st|nd|rd|th)\b)(?=[a-z])", r"\1 ", s)  # 160cm, 10pm
    s = re.sub(r"\b(?:half an|a half|half a|half) hour\b", "30 minute", s)
    s = re.sub(r"\b(?:a )?quarter (?:of an )?hour\b", "15 minute", s)
    s = re.sub(r"\b3 quarters of an hour\b", "45 minute", s)
    s = re.sub(r"\ban hour\b", "1 hour", s)
    s = re.sub(r"(\d+(?:\.\d+)?) (hours?|hrs?) and a half\b", lambda m: _half(m, 0.5) + " hour", s)
    s = re.sub(r"(\d+) and (?:a )?half\b", lambda m: _half(m, 0.5), s)
    s = re.sub(r"(\d+) and a quarter\b", lambda m: _half(m, 0.25), s)
    s = re.sub(r"(\d+) and 3 quarters\b", lambda m: _half(m, 0.75), s)
    s = re.sub(r"(?<![\d.])\.(\d)", r"0.\1", s)
    for pattern, unit in UNIT_SPELLINGS:
        s = re.sub(pattern, unit, s)
    return " ".join(s.split())


# ---------------------------------------------------------------------------
# Context markers (applied to canonical text)
# ---------------------------------------------------------------------------

# Everyday hedges carry no doubt about the value; they are removed before checks.
HEDGES = re.compile(
    r"\b(?:i'd say|i would say|i think|i guess|i believe|i reckon|i suppose|"
    r"if i remember (?:right|rightly|correctly)|if memory serves(?: me)?|if you ask me|"
    r"if i'm honest|to be honest|more or less|give or take|or so|roughly|about|around|"
    r"approximately|approx|close to|nearly|almost|just about|somewhere around|"
    r"last time i checked|at my last check ?up|these days|nowadays|right now|"
    r"at the moment|currently|usually|normally|typically|generally|on average)\b"
)
QUESTION = re.compile(r"\?")
UNCERTAIN = re.compile(
    r"\b(?:maybe|may be|might|perhaps|possibly|probably|unsure|either|dunno|guessing|"
    r"not (?:really |quite |too |entirely |exactly )?(?:sure|certain)|"
    r"(?:don't|do not|dont|didn't|did not|can't|cannot|couldn't) (?:really |even )?"
    r"(?:know|remember|recall|tell|say)|no idea|no clue|not a clue|i forget|i forgot|"
    r"who knows|hard to (?:say|tell)|could be|(?:don't|do not) (?:think|believe) so|not really)\b"
)
HYPOTHETICAL = re.compile(
    r"\b(?:if|unless|would|wouldn't|could|couldn't|should|wish|hope|hoping|hopefully|"
    r"want to|wanna|like to|goal|aim|aiming|target|suppose|supposed|imagine|pretend|"
    r"ideally|planning|plan to|trying to|i'd)\b"
)
VAGUE = re.compile(
    r"\b(?:between|anywhere from|depends|depending|varies|vary|varying|sometimes|"
    r"some (?:days|nights|weeks)|most (?:days|nights|weeks|evenings)|on and off|"
    r"now and then|occasionally|here and there|once in a while|not much|not a lot|"
    r"a lot|lots|a little|a bit|a few|a couple|couple of|several|socially|on occasion|"
    r"or more|or less|at least|at most|up to|more than|less than|fewer than|over|under|"
    r"above|below|plus|ish|odd|range|decades|twenties|thirties|forties|fifties|sixties|"
    r"seventies|eighties|nineties|on a (?:good|bad) night|(?:good|bad) nights?|every other|"
    r"alternate|every few|fortnight\w*|rarely|seldom|hardly|when|whenever)\b"
)
OTHER_PERSON = re.compile(
    r"\b(?:my|our|his|her|their)\s+(?:wife|husband|hubby|partner|spouse|son|daughter|"
    r"mother|mom|mum|father|dad|brother|sister|friend|neighbou?r|kids?|child|children|"
    r"grandson|granddaughter|grandkids?|grandchild(?:ren)?|boyfriend|girlfriend|cousin|"
    r"aunt|uncle|niece|nephew|dog|cat|family|parents?)(?:'s)?\b|\b(?:he|she|he's|she's|hers)\b"
)
NEGATION = re.compile(r"\b(?:not|no|never|none|nothing|without|nor|neither)\b|n't\b")
PAST_OLD = re.compile(
    r"\b(?:ago|used to|use to|back then|back in|in my prime|when i was|in my youth|"
    r"younger|years back|at one time|formerly|previously|anymore|in the past|decade|before)\b"
)
PAST_VERB = re.compile(r"\b(?:was|were|had been|weighed|slept|measured|walked|exercised|drank)\b")
RECENT = re.compile(
    r"\b(?:last (?:check ?up|time|visit|appointment|reading|physical|week|month|night)|"
    r"this (?:morning|week|month)|today|yesterday|recently|lately|the other day|just now)\b"
)
CHANGE = re.compile(
    r"\b(?:lost|gained|losing|gaining|dropped|put on|down to|down by|up by|went up|went down)\b"
)
# "3 hours a week, but not lately": the stated habit is not the current one.
NOT_CURRENT = re.compile(
    r"\b(?:not|no longer)\s+(?:lately|recently|anymore|any more|now|these days|nowadays|"
    r"at the moment|right now)\b|\b(?:haven't|hasn't|have not|didn't)\s+(?:lately|recently)\b"
)
FUTURE = re.compile(r"\b(?:will|won't|going to|gonna|turning|soon)\b|'ll\b")

# Topic words per field. A value whose clause names another topic ("I weigh 70"
# for the age question) is never read as the asked field.
TOPICS: dict[str, str] = {
    "age": r"\b(?:age|year old|birthday|born)\b",
    "height_cm": r"\b(?:height|tall|short)\b",
    "weight_kg": r"\b(?:weigh\w*|weight|heavy|scale)\b",
    "sleep_hours": r"\b(?:sleep\w*|slept|asleep|bed|bedtime|naps?|napping)\b",
    "exercise_minutes_weekly": (
        r"\b(?:exercis\w*|work(?:ing)? out|workouts?|walk\w*|gym|swim\w*|bik\w*|cycl\w*|"
        r"jog\w*|run|running|yoga|aerobics|tai chi|garden\w*|danc\w*|tennis|golf|pilates|"
        r"steps|miles?|hik\w*|treadmill|class(?:es)?)\b"
    ),
    "alcohol_drinks_weekly": (
        r"\b(?:drinks?|drinking|drank|alcohol|beers?|wine|whiske?y|vodka|gin|rum|"
        r"martinis?|cocktails?|pints?|booze|liquor|spirits)\b"
    ),
    "smoking_status": r"\b(?:smok\w*|cigar\w*|cigs?|pipe|tobacco|vap\w*|packs?)\b",
    "diabetes": r"\b(?:diabet\w*|sugar|insulin|metformin|a1c|glucose|type [12])\b",
    "blood_pressure": (
        r"\b(?:blood pressure|pressure|systolic|diastolic|mmhg|top number|bottom number|"
        r"upper number|lower number)\b"
    ),
}
# Units also attribute a number to a topic (used for clauses a provider did not quote).
TOPIC_UNITS: dict[str, str] = {
    "age": r"\byear\b",
    "height_cm": r"\d\s?(?:cm|m|ft|inch)\b",
    "weight_kg": r"\d\s?(?:kg|lb|stone)\b",
    "sleep_hours": r"\d\s?(?:hour|minute)\b",
    "exercise_minutes_weekly": r"\d\s?(?:hour|minute)\b",
    "alcohol_drinks_weekly": r"\d\s?(?:drinks?|beers?|glass(?:es)?)\b",
    "blood_pressure": r"\d\s?(?:/|over)\s?\d|mmhg",
}


def _topic(field: str) -> str:
    return "blood_pressure" if field in BP_FIELDS else field


def _other_topic(field: str, text: str) -> bool:
    own = _topic(field)
    return any(re.search(cue, text) for topic, cue in TOPICS.items() if topic != own)


def _unhedged(text: str) -> str:
    return HEDGES.sub(" ", text)


def _doubtful(text: str) -> bool:
    """Markers that make a whole reply unsafe, wherever they appear."""
    text = _unhedged(text)
    return bool(QUESTION.search(text) or UNCERTAIN.search(text) or HYPOTHETICAL.search(text))


CLAUSE_BREAK = re.compile(
    r"[,;:!?()]|\.(?!\d)|\s-\s|\b(?:but|and|then|though|although|except|whereas)\b"
)


def _clauses(text: str) -> list[tuple[int, int, str]]:
    """(start, end, word that introduced the clause) for each clause."""
    clauses, start, before = [], 0, ""
    for match in CLAUSE_BREAK.finditer(text):
        clauses.append((start, match.start(), before))
        start, before = match.end(), match.group(0).strip()
    clauses.append((start, len(text), before))
    return [clause for clause in clauses if text[clause[0] : clause[1]].strip()]


def _blank(text: str, spans: list[tuple[int, int]]) -> str:
    chars = list(text)
    for start, end in spans:
        chars[start:end] = " " * (end - start)
    return "".join(chars)


def _context(text: str, spans: list[tuple[int, int]]) -> str:
    """The clauses that carry the value, with the value itself blanked out."""
    lo, hi = min(start for start, _ in spans), max(end for _, end in spans)
    for start, end, _ in _clauses(text):
        if start <= lo <= end:
            lo = start
        if start <= hi <= end:
            hi = end
    return _blank(text, spans)[lo:hi]


def _clean_measurement(field: str, text: str, spans: list[tuple[int, int]]) -> bool:
    """Whether the value found at ``spans`` is the reply's only, current, own answer."""
    rest = _blank(text, spans)
    if re.search(r"\d", rest) or NOT_CURRENT.search(rest):
        return False
    whole = _unhedged(rest)
    if _doubtful(rest) or VAGUE.search(whole) or OTHER_PERSON.search(whole):
        return False
    local_raw = _context(text, spans)
    local = _unhedged(local_raw)
    if NEGATION.search(local) or PAST_OLD.search(local) or CHANGE.search(local):
        return False
    # A blood pressure is always a past reading; only an old one ("years ago") is refused.
    stale = PAST_VERB.search(local) and not RECENT.search(local_raw) and field not in BP_FIELDS
    if FUTURE.search(local) or stale:
        return False
    return not _other_topic(field, local)


# ---------------------------------------------------------------------------
# Numeric grammars (canonical text in, (value, spans) out)
# ---------------------------------------------------------------------------

# Bound numeric tokens before conversion, as well as validating profile ranges, so
# enormous spoken-number tokens cannot overflow or create non-finite intermediates.
NUM = r"(\d{1,6}(?:\.\d{1,6})?)"
N = rf"(?<![\d.])(?<!-){NUM}(?!\d)"
# A bare number (no unit) must be followed by the end or by plain connecting words,
# never by a noun: "I have 3 kids" is not an age.
FOLLOW = (
    r"(?=\s*(?:$|[,;:.!?)\-]|(?:and|but|now|last|as|going|this|in|on|since|today|already|"
    r"so|thank|thanks|yes|yeah|actually|exactly|i|or|give|more|these|nowadays|right|at|"
    r"then|myself|still|tops)\b))"
)
# After the inches of "5 ft 10" or the pounds of "11 stone 4", no other unit may follow.
NOT_UNIT = r"(?!\s?(?:ft|cm|m|kg|stone|hour|minute|year|mmhg|over|on \d|/)\b)"
Found = tuple[list[float], list[tuple[int, int]]] | None


def _collect(pattern: str, text: str, read) -> tuple[list[float], list[tuple[int, int]]] | None:
    values, spans = [], []
    for match in re.finditer(pattern, text):
        value = read(match)
        if value is None:
            return None
        values.append(value)
        spans.append(match.span())
    return values, spans


def _combine(*found: Found) -> Found:
    values, spans = [], []
    for part in found:
        if part is None:
            return None
        values += part[0]
        spans += part[1]
    return values, spans


MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}
MONTH = (
    r"(january|february|march|april|may|june|july|august|september|october|november|december"
    r"|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)"
)
BIRTH = (
    rf"(?:i was |i'm |i am )?born (?:on )?(?:{MONTH} (\d{{1,2}})(?:st|nd|rd|th)?,? (?:in )?(\d{{4}})"
    rf"|(?:the )?(\d{{1,2}})(?:st|nd|rd|th)? (?:of )?{MONTH},? (?:in )?(\d{{4}}))"
)
FUTURE_AGE = (
    r"(?:\b(?:i'll|i will|i'm going to|i am going to|i'm gonna|going to|gonna)\s+(?:be|turn)\s+"
    r"(\d{1,3})(?![\d.])|\b(?:i'm\s+|i am\s+)?turning\s+(\d{1,3})(?![\d.]))"
    r"(?:\s+in\s+(?:\d{1,2}|a)\s+(?:days?|weeks?|months?))?"
)
# "I just had my 70th birthday"
BIRTHDAY = r"\b(?:had|celebrated|turned)\s+my\s+(\d{2,3})(?:st|nd|rd|th)\s+birthday\b"
AGE = (
    rf"(?<![\d.])(?<!-)(?<!going on )(\d{{1,3}})(?![\d.]\d)"
    rf"(?:\s?year(?:\s(?:old|young|of age))?|{FOLLOW})(?:,?\s?going on\s(\d{{1,3}}))?"
)


def _age(text: str, today: date) -> Found:
    def birth(match: re.Match):
        month_name, day, year = match.group(1), match.group(2), match.group(3)
        if month_name is None:
            day, month_name, year = match.group(4), match.group(5), match.group(6)
        try:
            born = date(int(year), MONTHS[month_name[:3]], int(day))
        except ValueError:
            return None
        if born > today:
            return None
        return today.year - born.year - ((today.month, today.day) < (born.month, born.day))

    def current(match: re.Match):
        # "I retired at 65", "since 60": the age at some event, not now.
        if re.search(
            r"\b(?:at|since|until|till|by|after|before|from|when)\s+(?:the\s+)?"
            r"(?:age\s+(?:of\s+)?)?$",
            text[: match.start()],
        ):
            return None
        # "76 next month", "73 this year": a birthday still to come, so unclear.
        if re.match(
            r"\s*(?:this|next|in)\s+(?:year|month|week|spring|summer|fall|autumn|winter|"
            r"january|february|march|april|may|june|july|august|september|october|november|"
            r"december)\b",
            text[match.end() :],
        ):
            return None
        value = int(match.group(1))
        # "I'm 79, going on 80" describes the same age; any other pair is ambiguous.
        if match.group(2) and int(match.group(2)) != value + 1:
            return None
        return value

    def turning(match: re.Match):
        # "I'll be 77 in March": still 76 today.
        return int(match.group(1) or match.group(2)) - 1

    found = _combine(
        _collect(BIRTH, text, birth), _collect(BIRTHDAY, text, lambda m: int(m.group(1)))
    )
    if found is None:
        return None
    found = _combine(found, _collect(FUTURE_AGE, _blank(text, found[1]), turning))
    if found is None:
        return None
    return _combine(found, _collect(AGE, _blank(text, found[1]), current))


FEET = (
    rf"(?<![\d.])(?<!-)(\d)\s?ft(?:,?\s?(?:and\s)?(\d{{1,2}}(?:\.\d{{1,6}})?)(?!\d){NOT_UNIT}"
    r"(?:\s?inch\b)?)?(?:\s(?:even|flat|exactly))?"
)
HEIGHT_PAIR = (
    r"(?<![\d.])(?<!-)([4-7])(?:\s|\s?-\s?)(\d{1,2}(?:\.5)?)(?![\d.])"
    r"(?!\s?(?:ft|inch|cm|m|kg|lb|stone|hour|minute|year|over|/|on|to|or|and)\b)"
)


def _height(text: str, today: date) -> Found:
    def feet(match: re.Match):
        inches = float(match.group(2) or 0)
        return None if inches >= 12 else int(match.group(1)) * 30.48 + inches * 2.54

    found = _combine(
        _collect(FEET, text, feet),
        # "1 m 68", "one metre sixty-eight"
        _collect(
            r"(?<![\d.])(?<!-)1\s?m\s?(\d{2})(?![\d.])", text, lambda m: 100 + int(m.group(1))
        ),
    )
    if found is None:
        return None
    rest = _blank(text, found[1])
    found = _combine(
        found,
        _collect(rf"{N}(?:,?\s+in)?\s?cm\b", rest, lambda m: float(m.group(1))),
        _collect(rf"{N}\s?m\b", rest, lambda m: float(m.group(1)) * 100),
        _collect(rf"{N}\s?inch\b", rest, lambda m: float(m.group(1)) * 2.54),
    )
    if found is None or found[0]:
        return found
    # "six two", "five-eight": two bare numbers answering the height question.
    return _collect(HEIGHT_PAIR, text, feet)


STONE = rf"{N}\s?stone\b(?:,?\s?(?:and\s)?(\d{{1,2}}(?:\.\d{{1,6}})?)(?!\d){NOT_UNIT}(?:\s?lb\b)?)?"
LB_PER_KG = 0.45359237


def _weight(text: str, today: date) -> Found:
    def stone(match: re.Match):
        pounds = float(match.group(2) or 0)
        return None if pounds >= 14 else (float(match.group(1)) * 14 + pounds) * LB_PER_KG

    found = _collect(STONE, text, stone)
    if found is None:
        return None
    rest = _blank(text, found[1])
    return _combine(
        found,
        _collect(rf"{N}(?:,?\s+in)?\s?kg\b", rest, lambda m: float(m.group(1))),
        _collect(rf"{N}(?:,?\s+in)?\s?lb\b", rest, lambda m: float(m.group(1)) * LB_PER_KG),
    )


TIME = r"(\d{1,2})(?::(\d{2}))?(?:\s?(am|pm|o'clock))?(?![\d.:])(?!\s?(?:hour|minute)\b)"
BEDTIME = (
    rf"\b(?:bed|asleep|sleep(?:ing)?|lights out|turn in)\b(?:\s+[a-z']+){{0,3}}?\s+"
    rf"(?:(?:by|at|around|about|from)\s+)?{TIME}[^\d]{{0,30}}?\b(?:up|awake|wake(?:\s+up)?|"
    rf"get\s+up|rise|until|till|to)\b(?:\s+[a-z']+){{0,2}}?\s+(?:(?:by|at|around|about)\s+)?{TIME}"
)
NIGHT = r"(?=\s*(?:a|per|each|every|at)\s+night\b)"


def _bed_minutes(hour: int, minute: int, suffix: str | None, waking: bool) -> int | None:
    if not 1 <= hour <= 12 or minute >= 60:
        return None
    if waking:
        if suffix == "pm":
            return None
        hour = hour % 12
    elif suffix == "pm" or (suffix != "am" and 6 <= hour <= 11):
        hour += 12
    elif hour == 12:
        hour = 0
    return hour * 60 + minute


def _sleep(text: str, today: date) -> Found:
    # Naps are not a night's sleep, and "7 hours on weekends" is not a usual night.
    if re.search(
        r"\bnap\w*|\bsiesta\b|\bdoz(?:e|es|ing)\b|\bweek(?:ends?|days?|nights?)\b|"
        r"\bduring the week\b|\b(?:mon|tues|wednes|thurs|fri|satur|sun)days?\b",
        text,
    ):
        return None

    def bedtime(match: re.Match):
        bed = _bed_minutes(int(match.group(1)), int(match.group(2) or 0), match.group(3), False)
        wake = _bed_minutes(int(match.group(4)), int(match.group(5) or 0), match.group(6), True)
        if bed is None or wake is None:
            return None
        hours = ((wake - bed) % 1440) / 60
        return hours if 3 <= hours <= 14 else None

    def spread(match: re.Match):
        low, high = float(match.group(1) or match.group(2)), float(match.group(3))
        # Adjacent values ("7 to 8 hours") read as their midpoint; wider is a range.
        return (low + high) / 2 if 0 < high - low <= 1 else None

    def hours(match: re.Match):
        return float(match.group(1)) + float(match.group(2) or 0) / 60

    found = _collect(BEDTIME, text, bedtime)
    for pattern, read in (
        (
            rf"(?:\bbetween\s+{N}(?:\s?hour)?\s?and|{N}(?:\s?hour)?\s?(?:to|or|-))\s?{NUM}(?!\d)"
            r"(?!\s?(?:minute|am|pm|o'clock)\b)(?:\s?hour\b)?",
            spread,
        ),
        (rf"{N}\s?hour\b(?:,?\s?(?:and\s)?(\d{{1,2}})\s?minute\b)?", hours),
    ):
        if found is None:
            return None
        found = _combine(found, _collect(pattern, _blank(text, found[1]), read))
    if found is None or found[0]:
        return found

    def bare(match: re.Match):
        # "to 7", "at 6": a clock time, not a number of hours.
        if re.search(
            r"\b(?:to|at|by|until|till|from|after|before|past)\s+$", text[: match.start()]
        ):
            return None
        return float(match.group(1))

    return _collect(rf"{N}(?:{FOLLOW}|{NIGHT})", text, bare)


DURATION = rf"{N}\s?(minute|hour)\b(?:,?\s?(?:and\s)?(\d{{1,2}})\s?minute\b)?"
FREQUENCY = (
    r"\b(?:days?|daily|weeks?|weekly|months?|monthly|years?|yearly|mornings?|evenings?|nights?|"
    r"nightly|weekends?|weekdays?|times?|once|twice|other|sessions?|class(?:es)?|each|every|per)\b"
)
ACTIVITY = r"(?:\s+of\s+[a-z]+(?:\s+[a-z]+)?)?"
WEEKLY = rf"{ACTIVITY}\s*(?:a|per|each|every|/|in a|in the)\s*week\b"
DAILY_RATE = rf"{ACTIVITY}\s*(?:a|per)\s+day\b"
DAY_NAMES = r"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b"
EVERY_DAY = (
    r"\b(?:every\s+(?:single\s+)?day|daily|each\s+day|every\s+(?:morning|evening|afternoon|night)"
    r"|each\s+(?:morning|evening|afternoon|night)|all\s+week|nightly)\b"
)


def _times_per_week(text: str) -> tuple[list[int], list[tuple[int, int]]]:
    """How many days a week a routine happens: "twice a week", "every day", "Saturday"."""
    counts, spans = [], []
    times = {"once": 1, "twice": 2, "thrice": 3}
    for match in re.finditer(
        r"\b(?:(once|twice|thrice)|(\d) ?(?:times?|x))\s+(?:a|per|each|every|in a)\s+week\b", text
    ):
        counts.append(times.get(match.group(1)) or int(match.group(2)))
        spans.append(match.span())
    for match in re.finditer(
        r"(?<![\d.])(\d) (?:days?|nights?|evenings?)\s+(?:a|per|each|every|in a|of the)\s+week\b",
        text,
    ):
        counts.append(int(match.group(1)))
        spans.append(match.span())
    for match in re.finditer(EVERY_DAY, text):
        counts.append(7)
        spans.append(match.span())
    for pattern, days in (
        (r"\b(?:on\s+|at\s+|every\s+|each\s+)?(?:the\s+)?weekends?\b", 2),
        (r"\b(?:on\s+|every\s+)?weekdays?\b|\bmonday (?:to|through|thru) friday\b", 5),
    ):
        for match in re.finditer(pattern, text):
            counts.append(days)
            spans.append(match.span())
    text = _blank(text, spans)
    names = set(re.findall(DAY_NAMES, text))
    if names:
        counts.append(len(names))
        spans += [match.span() for match in re.finditer(DAY_NAMES, text)]
    return counts, spans


def _twice_daily(text: str) -> bool:
    """ "Every morning and evening": two times of day, so a single daily rate is unsafe."""
    return len(set(re.findall(r"\b(morning|afternoon|evening|night)s?\b", text))) > 1


def _zero(field: str, text: str) -> Found:
    """ "None", "I don't drink", "I quit drinking years ago": the whole reply is the answer,
    so only doubt, a hypothetical, someone else or another topic can make it unsafe."""
    if _doubtful(text) or OTHER_PERSON.search(text) or _other_topic(field, text):
        return None
    return [0], [(0, len(text))]


def _exercise(text: str, today: date) -> Found:
    if _twice_daily(text):
        return None
    durations = list(re.finditer(DURATION, text))
    if not durations:
        if re.search(r"\d", text):
            # A bare count: weekly minutes, the question's own unit ("150"). Small
            # numbers are more likely days or hours, so they are asked about.
            found = _collect(rf"{N}(?=\s*(?:$|[,;.!]))", text, lambda m: float(m.group(1)))
            if found and found[0] and not 0 < found[0][0] < 15:
                return found
            return None
        zero = re.search(
            r"\b(?:none|nothing|zero|not a thing|not any|no exercise|nada|zilch)\b|"
            r"\b(?:don't|do not|never)\s+(?:do\s+any(?:thing)?|exercise|work\s+out)\b",
            text,
        )
        vague = re.search(r"\b(?:much|a lot|often|enough|regularly|as much|very)\b", text)
        return _zero("exercise_minutes_weekly", text) if zero and not vague else None
    if len(durations) != 1:
        return None
    duration = durations[0]
    minutes = float(duration.group(1)) * (60 if duration.group(2) == "hour" else 1)
    if duration.group(3):
        if duration.group(2) != "hour":
            return None
        minutes += int(duration.group(3))  # "an hour and fifteen minutes"
    spans = [duration.span()]
    tail = re.match(WEEKLY, text[duration.end() :]) or re.match(DAILY_RATE, text[duration.end() :])
    if tail:
        spans.append((duration.end(), duration.end() + tail.end()))
    # "twice a day for 20 minutes": a per-day amount, which still needs days a week.
    per_day = re.search(
        r"\b(?:(once|twice|thrice)|(\d) times?)\s+(?:a|per|each)\s+day\b", _blank(text, spans)
    )
    if per_day:
        if tail:
            return None
        minutes *= {"once": 1, "twice": 2, "thrice": 3}.get(per_day.group(1)) or int(
            per_day.group(2)
        )
        spans.append(per_day.span())
    counts, count_spans = _times_per_week(_blank(text, spans))
    if len(set(counts)) > 1:
        return None
    spans += count_spans
    if tail and "week" in tail.group(0):
        return ([minutes], spans) if not counts else None
    if counts:
        return [minutes * counts[0]], spans
    # Hours without how often ("an hour"), per day without days, or any other
    # frequency ("every other day", "a 45 minute class") are asked about.
    if tail or per_day or duration.group(2) == "hour" or re.search(FREQUENCY, _blank(text, spans)):
        return None
    return [minutes], spans


BEVERAGE = (
    r"(?:(?:red|white|rose|house)\s+)?(?:wine|beer|whiske?y|scotch|bourbon|champagne|prosecco|"
    r"sherry|port|cider|vodka|gin|rum|brandy|ale|lager|stout)"
)
DRINK = (
    rf"(?:drinks?|beers?|glass(?:es)?(?:\s+of\s+{BEVERAGE})?|wines?|pints?(?:\s+of\s+{BEVERAGE})?|"
    rf"cans?(?:\s+of\s+{BEVERAGE})?|bottles?\s+of\s+(?:beer|cider)|shots?(?:\s+of\s+{BEVERAGE})?|"
    r"martinis?|cocktails?|whiske?ys?|scotch(?:es)?|bourbons?|ciders?|ales?|lagers?|nightcaps?|"
    r"highballs?|margaritas?|gin\s+and\s+tonics?|brand(?:y|ies)|sherr(?:y|ies)|vodkas?)"
)
SIZE = r"(?:(?:small|large|big|little|single|double|nice|cold|stiff|tall)\s+)?"
# A count without a drink word must not be followed by another noun: "14 units" is not drinks.
COUNT_END = r"(?=\s*(?:$|[,;.!/]|(?:a|an|per|each|every|on|in|or|with|at|tops|max|i)\b))"
ZERO_DRINKS = (
    r"\bteetotal\w*|\b(?:don't|do not|never)\s+(?:drink|touch)\b|\bnone\b|\bzero\b|\bnothing\b|"
    r"\bnot a drop\b|\bno alcohol\b|\bnon ?drinker\b|\bnot a drinker\b|\babstain\w*|\bsober\b|"
    r"\b(?:quit|stopped|gave up|given up)\s+(?:drinking|alcohol|booze|the booze)\b|^never$"
)


def _alcohol(text: str, today: date) -> Found:
    # "I quit drinking 20 years ago": the years describe the quitting, not a count.
    quit_time = r"\b\d+\s+year\s+ago\b|\b(?:in|since|back in)\s+'?\d{2,4}\b"
    if _twice_daily(text):
        return None
    zero = re.search(ZERO_DRINKS, text)
    if zero and not re.search(r"\d", re.sub(quit_time, " ", text)):
        vague = re.search(r"\b(?:much|a lot|often|very|heavily|as much|only|except|but)\b", text)
        return None if vague else _zero("alcohol_drinks_weekly", text)
    counts, spans, article = [], [], False
    for pattern, read in (
        (
            rf"(?:\bbetween\s+{N}(?:\s+{SIZE}{DRINK})?\s+and|{N}(?:\s+{SIZE}{DRINK})?\s*(?:or|to|-))"
            rf"\s*{NUM}(?!\d)(?:\s+{SIZE}{DRINK}|{COUNT_END})",
            0,
        ),
        (rf"\b(?:a|an)\s+{SIZE}{DRINK}\s+or\s+{NUM}(?!\d)", 1),
        (rf"{N}(?:\s+{SIZE}{DRINK}|{COUNT_END})", 2),
        (rf"\b(?:a|an)\s+{SIZE}{DRINK}", 3),
    ):
        for match in re.finditer(pattern, _blank(text, spans)):
            if read == 0:
                low, high = float(match.group(1) or match.group(2)), float(match.group(3))
            elif read == 1:
                low, high = 1.0, float(match.group(1))
            else:
                low = high = 1.0 if read == 3 else float(match.group(1))
                article = article or read == 3
            if read < 2 and not 0 < high - low <= 1:
                return None
            counts.append((low + high) / 2)
            spans.append(match.span())
    if len(counts) != 1:
        return None
    rest = _blank(text, spans)
    if re.search(r"\b(?:a|per|each|every)\s+(?:month|year)\b|\bmonthly\b|\bweekends?\b", rest):
        return None
    # "3 days a week" first, so its "a week" is not read as a second rate.
    rates, rate_spans = _times_per_week(rest)
    rest = _blank(rest, rate_spans)
    for pattern, rate in (
        (r"\b(?:a|per|each|every|/|in a)\s+week\b|\bweekly\b", 1),
        (r"\b(?:a|per)\s+(?:day|night|evening)\b", 7),
    ):
        for match in re.finditer(pattern, rest):
            rates.append(rate)
            rate_spans.append(match.span())
    rest = _blank(rest, rate_spans)
    if len(set(rates)) > 1:
        return None
    if not rates and (article or re.search(FREQUENCY, rest)):
        return None  # "a glass of wine": how often is not stated; or unrecognized frequency
    return [counts[0] * (rates[0] if rates else 1)], spans + rate_spans


NUMERIC = {
    "age": _age,
    "height_cm": _height,
    "weight_kg": _weight,
    "sleep_hours": _sleep,
    "exercise_minutes_weekly": _exercise,
    "alcohol_drinks_weekly": _alcohol,
}

# ---------------------------------------------------------------------------
# Blood pressure
# ---------------------------------------------------------------------------

BP_PAIR = r"(?<![\d.])(?<!-)(\d{2,3})\s?(?:/|over|on)\s?(\d{2,3})(?![\d.]\d)(?:\s?mmhg)?"
BP_SINGLE = rf"(?<![\d.])(?<!-)(\d{{2,3}})(?![\d.]\d)(?:\s?mmhg\b|{FOLLOW})"
# "The top number is 130 and the bottom is 85", "systolic 130, diastolic 85"
BP_LABELED = (
    r"\b(?:top|upper|systolic)(?: number| one| reading)?(?: is| was|:)?\s+(\d{2,3})(?![\d.])"
    r"[^\d]{0,20}?\b(?:bottom|lower|diastolic)(?: number| one| reading)?(?: is| was|:)?\s+"
    r"(\d{2,3})(?![\d.])"
)


def _blood_pressure(field: ProfileField, text: str) -> dict:
    pairs = [
        (m.group(1, 2), m.span())
        for pattern in (BP_LABELED, BP_PAIR)
        for m in re.finditer(pattern, text)
    ]
    if pairs:
        readings = {pair for pair, _ in pairs}
        if len(readings) != 1 or not _clean_measurement(field, text, [s for _, s in pairs]):
            return {}
        systolic, diastolic = (int(value) for value in readings.pop())
        if systolic <= diastolic:
            return {}
        return _validated({"systolic_bp": systolic, "diastolic_bp": diastolic})
    singles = [(int(m.group(1)), m.span()) for m in re.finditer(BP_SINGLE, text)]
    if len({value for value, _ in singles}) != 1:
        return {}
    # One number labeled as the other half of the reading does not answer this question.
    other = (
        r"\b(?:bottom|lower|second|diastolic)\b"
        if field == "systolic_bp"
        else (r"\b(?:top|upper|first|systolic)\b")
    )
    if re.search(other, text) or not _clean_measurement(field, text, [s for _, s in singles]):
        return {}
    return _validated({field: singles[0][0]})


# ---------------------------------------------------------------------------
# Categorical answers
# ---------------------------------------------------------------------------


def _plain(text: str) -> str:
    return " ".join(re.sub(r"[,.!?;:]", " ", normalize_text(text).lower()).split())


def _own_text(text: str) -> str:
    """The reply with clauses about someone else blanked out."""
    return _blank(
        text,
        [(start, end) for start, end, _ in _clauses(text) if OTHER_PERSON.search(text[start:end])],
    )


def _own_clauses(text: str) -> list[tuple[str, str]]:
    """(clause, introducing word) for clauses about the person, not someone else."""
    return [
        (text[start:end], before)
        for start, end, before in _clauses(text)
        if not OTHER_PERSON.search(text[start:end])
    ]


PREFER_NOT = re.compile(r"\b(?:prefer not to|rather not)(?:\s+(?:say|answer|tell))?\b")
SEX_FAMILIES = {
    "female": r"\b(?:female|woman|lady|gal|girl|(?:grand)?mother|grandma|granny|widow|wife)\b",
    "male": (
        r"\b(?:male|man|guy|gentleman|gent|fella|fellow|chap|bloke|boy|(?:grand)?father|grandpa|"
        r"widower|husband)\b"
    ),
    "intersex": r"\bintersex\b",
}


def _sex(text: str) -> str | None:
    phrase = _plain(text)
    if phrase in SEX_PREFER_NOT or phrase == "prefer_not_to_say":
        return "prefer_not_to_say"
    if phrase in {"f", "m"}:
        return {"f": "female", "m": "male"}[phrase]
    if _doubtful(text):
        return None
    families: set[str] = set()
    for clause, _ in _own_clauses(text):
        found = {family for family, pattern in SEX_FAMILIES.items() if re.search(pattern, clause)}
        if found and (NEGATION.search(clause) or re.search(r"\b(?:used to|called)\b", clause)):
            return None
        families |= found
    if PREFER_NOT.search(text) and not families:
        return "prefer_not_to_say"
    return families.pop() if len(families) == 1 else None


# "I'm trying to quit", "I never quit": wanting or failing to quit is not having quit.
QUIT_ATTEMPT = (
    r"\b(?:trying to|try to|tried to|want to|wanting to|wanna|going to|gonna|plan(?:ning)? to|"
    r"need to|should|thinking (?:about|of)|hope to|hoping to|can't|cannot|couldn't|never|"
    r"didn't|did not|haven't|have not|won't)\s+(?:quit(?:ting)?|stop(?:ping)?|give up|giving up)\b"
)
FORMER = (
    r"\b(?:quit|quitted|stopped|gave up|given up|used to|use to|former|formerly|ex smoker|"
    r"gave (?:it|them|those|cigarettes|smoking) up|kicked the habit|was a smoker|"
    r"in the past|not since|haven't smoked (?:since|in))\b|\bsmoked\b[^,.;]*\buntil\b"
)
CURRENT = (
    r"\b(?:i smoke|i'm smoking|i am smoking|still smoke|currently|current|"
    r"smoke (?:now|daily|every|a|about|around|\d+)|yes i smoke|again|relapsed)\b|"
    r"(?<!not a )(?<!non )(?<!ex )(?<!former )(?<!been a )(?<!was a )\bsmoker\b"
)
PRODUCT = r"\b(?:cigarettes?|cigs?|ciggies?|cigars?|cigarillos?|pipe|packs?|tobacco)\b"
SMOKING_RATE = (
    r"\b(?:a|per|every|each)\s+(?:day|week|night|evening|morning)\b(?! in my life)"
    r"|\bin the (?:evening|morning)s?\b"
    r"|\bdaily\b|(?<![\d.])\d{1,3}\s+(?:a|per)\s+(?:day|week)\b"
)
OCCASIONAL = (
    r"\b(?:still|now and then|occasionally|occasional|sometimes|once in a while|socially|"
    r"at parties|here and there|on occasion|the odd)\b"
)
NEVER_WORDS = {
    "i",
    "i've",
    "i'm",
    "have",
    "has",
    "did",
    "do",
    "ever",
    "once",
    "smoked",
    "smoke",
    "smoking",
    "a",
    "cigarette",
    "cigarettes",
    "1",
    "in",
    "my",
    "whole",
    "life",
    "day",
    "at",
    "all",
    "been",
    "smoker",
    "no",
    "never",
    "touched",
    "tobacco",
    "them",
    "it",
    "oh",
    "well",
}


def _smoking(text: str) -> str | None:
    phrase = _plain(text)
    if phrase in SEX_PREFER_NOT or phrase == "unknown":
        return "unknown"
    text = re.sub(QUIT_ATTEMPT, " ", text)
    # Vaping and cannabis are not tobacco smoking; those answers get a follow-up.
    not_tobacco = (
        r"\bvap\w*|\be ?cig\w*|\bjuul\b|\bmarijuana\b|\bweed\b|\bpot\b|\bcannabis\b|\bjoints?\b"
    )
    if _doubtful(text) or re.search(not_tobacco, text):
        return None
    clauses = [clause for clause, _ in _own_clauses(text)]
    own = _own_text(text)
    if _other_topic("smoking_status", own):
        return None
    # "I used to smoke a pack a day": habits told inside a quitting clause are the past.
    present = _blank(own, [(a, b) for a, b, _ in _clauses(own) if re.search(FORMER, own[a:b])])
    current = (
        re.search(CURRENT, present)
        or re.search(SMOKING_RATE, present)
        or re.search(OCCASIONAL, present)
    )
    never = [clause for clause in clauses if re.search(r"\bnever\b", clause)]
    if re.search(FORMER, own):
        return None if current or never else "former"
    if never:
        # "Never." / "never have" / "no, never in my life" -- but "I never smoke
        # at home" says nothing about the rest of the time.
        words = set(re.findall(r"[a-z0-9']+", " ".join(never)))
        return "never" if words <= NEVER_WORDS and not current else None
    if current and not NEGATION.search(present):
        return "current"
    return None


DIABETES_UNCLEAR = (
    r"\bpre ?diabet\w*|\bborderline\b|\bgestational\b|\bpregnan\w*|\bat risk\b|\brisk of\b|"
    r"\bfamily history\b|\bruns in\b|\bremission\b|\breversed\b|\bcured\b|\bwent away\b|"
    r"\bused to\b|(?<!'ve )(?<!have )\bhad (?:it|diabetes)\b|\bwas diabetic\b|\bno longer\b|"
    r"\banymore\b|"
    r"\btest(?:ing|ed)? (?:me|for)\b|\bwaiting\b|\bresults?\b|\binsulin resist\w*|"
    r"\bhigh (?:blood )?sugar\b|\bsugar(?:'s| is) (?:a little |a bit |slightly )?high\b"
)
YES_WORDS = (
    r"\b(?:yes|yeah|yep|yup|yea|ya|aye|affirmative|correct|uh huh|mm hm+|mhm+|mm hmm|indeed|"
    r"definitely|certainly|sure do)\b"
)
NO_WORDS = r"\b(?:no|nope|nah|naw|negative|uh uh|nay|not|never)\b|n't\b"
# Explicit statements of the diagnosis itself; casual descriptions never count.
DIAGNOSIS = (
    r"\bdiabet\w*|\btype (?:1|2|i|ii)\b|\b(?:i do|i have it|i've got it|i got it|i have that)\b"
)
DIABETES_MEDICINE = (
    r"\b(?:metformin|insulin|glipizide|ozempic|jardiance|januvia|diabetes (?:pills?|medic\w*))\b"
)


def _diabetes(text: str) -> bool | None:
    # "No thanks" declines the question rather than answering it.
    if _doubtful(text) or re.search(DIABETES_UNCLEAR, text) or re.search(r"\bno thank", text):
        return None
    answers: set[bool] = set()
    contrast = False
    clauses = _own_clauses(text)
    if _other_topic("diabetes", _own_text(text)):
        return None
    for clause, before in clauses:
        contrast = contrast or before == "but"
        if re.search(NO_WORDS, clause):
            if re.search(YES_WORDS, clause):
                return None
            answers.add(False)
        elif re.search(YES_WORDS, clause) or re.search(DIAGNOSIS, clause):
            answers.add(True)
    if len(answers) != 1:
        return None
    answer = answers.pop()
    # "No, but I take metformin": a contrast after a no needs a follow-up.
    if not answer and (contrast or re.search(DIABETES_MEDICINE, text)):
        return None
    return answer


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def is_skip(text: str, field: ProfileField) -> bool:
    phrase = _plain(text)
    if field == "smoking_status" and (phrase == "unknown" or phrase in SEX_PREFER_NOT):
        return False
    if field == "sex" and phrase in SEX_PREFER_NOT:
        return False
    if field in BP_FIELDS and phrase in BP_NO:
        return True
    return phrase in SKIP_WORDS


def parse_value(field: ProfileField, text: str, *, today: date | None = None) -> dict:
    """Accept explicit, current, single answers; do not guess units or diagnoses."""
    today = today or date.today()
    canonical = _canonical(text)
    if field in BP_FIELDS:
        return _blood_pressure(field, canonical)
    if field == "sex":
        sex = _sex(canonical)
        return _validated({field: sex}) if sex else {}
    if field == "smoking_status":
        status = _smoking(canonical)
        return _validated({field: status}) if status else {}
    if field == "diabetes":
        answer = _diabetes(canonical)
        return {} if answer is None else _validated({field: answer})
    found = NUMERIC[field](canonical, today)
    if not found or not found[0]:
        return {}
    values, spans = found
    if any(abs(value - values[0]) > 1e-6 for value in values):
        return {}
    if not _clean_measurement(field, canonical, spans):
        return {}
    result: float | int = values[0]
    if field in {"age", "exercise_minutes_weekly"}:
        if abs(result - round(result)) > 1e-6:
            return {}
        result = int(round(result))
    else:
        result = round(result, 4)
    return _validated({field: result})


def clarify(text: str, field: ProfileField) -> str | None:
    """Field-specific follow-up for an answer that is close but not safe to read."""
    canonical = _canonical(text)
    if _doubtful(canonical) or OTHER_PERSON.search(canonical):
        return None
    numbers = re.findall(rf"(?<![\d.]){NUM}(?!\d)", canonical)
    bare = None
    if len(numbers) == 1 and re.search(
        rf"(?<![\d.]){NUM}(?!\d)(?!\s?(?:ft|inch|cm|m|kg|lb|stone|hour|minute|year|over|/|drinks?)\b)",
        canonical,
    ):
        bare = numbers[0]
    if field == "weight_kg" and bare:
        return (
            f"Is that {bare} pounds or {bare} kilograms? Please say the number "
            f'with the unit, like "{bare} pounds".'
        )
    if field == "height_cm" and bare:
        return (
            "Is that inches or centimeters? Please say it with the unit, "
            'like "70 inches". You can also say "5 feet 10 inches".'
        )
    if field in BP_FIELDS:
        pair = re.search(BP_PAIR, canonical)
        if pair and int(pair.group(1)) <= int(pair.group(2)):
            return BP_ORDER_MESSAGE
    if field == "exercise_minutes_weekly":
        if re.search(r"\b(?:a|per)\s+day\b", canonical) and not _times_per_week(canonical)[0]:
            return (
                "How many days a week do you do that? You can say, for example, "
                '"30 minutes a day, 5 days a week".'
            )
        if re.fullmatch(rf"(?:\D*\s)?{NUM}\s?hour\b\D*", canonical) and not re.search(
            r"\bweek\b", canonical
        ):
            return 'How often do you do that? You can say, for example, "an hour, 3 times a week".'
        if bare and 0 < float(bare) < 15:
            return (
                f"Is that {bare} minutes or {bare} hours in the whole week? Please say it "
                f'with minutes or hours, like "{bare} hours a week".'
            )
    if (
        field == "alcohol_drinks_weekly"
        and not numbers
        and re.search(rf"\b(?:a|an)\s+{SIZE}{DRINK}", canonical)
    ):
        return (
            "How many days a week do you have that? You can say, for example, "
            '"one glass of wine, 3 days a week".'
        )
    if field == "smoking_status" and re.search(
        r"^(?:no|nope|nah)$|\bnot a smoker\b|\bnon ?smoker\b|\b(?:don't|do not) smoke\b|"
        r"\bnot anymore\b",
        canonical,
    ):
        return 'Did you ever smoke in the past? Please say "I used to smoke" or "I never smoked".'
    if field == "diabetes" and re.search(r"\bpre ?diabet\w*|\bborderline\b|\bsugar\b", canonical):
        return (
            "Has a doctor told you that you have diabetes itself? Prediabetes or borderline "
            "doesn't count. Please say yes or no."
        )
    return None


def _validated(values: dict) -> dict:
    try:
        return HealthProfile.model_validate(values).model_dump(exclude_none=True)
    except ValidationError:
        return {}


def parse_reply(text: str, field: ProfileField, *, today: date | None = None) -> dict:
    """Handle a short answer or several explicitly labeled clauses."""
    text = normalize_text(text)
    # One measurement may contain commas or "and" ("5 feet, 10 inches").
    whole = parse_value(field, text, today=today)
    if whole:
        return whole
    parts = re.split(r"[;,]|\s+and\s+", text, flags=re.I)
    values: dict = {}
    for part in parts:
        if not part.strip():
            continue
        label = re.fullmatch(r"\s*([a-z_ ]+?)\s*[:=]\s*(.+)\s*", part, re.I)
        if label:
            target = LABELS.get(label.group(1).lower())
            if target is None:
                return {}
            parsed = parse_value(target, label.group(2), today=today)
        elif len(parts) == 1:
            parsed = parse_value(field, part, today=today)
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


RAW_BREAK = re.compile(
    r"[,;:!?()\n]|(?<!\d)\.|\.(?!\d)|\s-\s|\b(?:but|and|then|though|although|except|whereas)\b",
    re.I,
)
UNIT_NEXT = re.compile(
    r"^\s*(?:ft|inch|cm|m|kg|lb|stone|hour|minute|year|mmhg|over|on \d|/|drinks?|times?|"
    r"(?:a|per|each|every) (?:day|week|night))\b|^\s*[/%]"
)


def _raw_clause(text: str, start: int, end: int) -> tuple[int, int]:
    lo, hi = 0, len(text)
    for match in RAW_BREAK.finditer(text):
        if match.end() <= start:
            lo = match.end()
        elif match.start() >= end:
            hi = match.start()
            break
    return lo, hi


def grounded_candidates(
    text: str, extraction: ExtractionResult, asked: ProfileField, *, today: date | None = None
) -> dict:
    """Accept a provider's quote only where the reply itself supports it.

    Each quote must be an exact substring of the reply and parse, with the same
    flexible parser, to its field and value. Its clause may hold no negation,
    past or old reading, change, future, other person, vague amount or second
    number; the whole reply may hold no question, uncertainty or hypothetical.
    Another clause that gives a different value for the same field, or an
    unexplained number, also refuses the turn. A field other than the asked one
    needs a clause that names it, so a bare "160" given for weight can never
    become a blood pressure.
    """
    text = normalize_text(text)
    if _doubtful(_canonical(text)):
        return {}
    values: dict = {}
    covered: list[tuple[int, int]] = []
    for candidate in extraction.candidates:
        quote = normalize_text(candidate.quote)
        quote_values = parse_value(candidate.field, quote, today=today)
        if candidate.field not in quote_values:
            return {}
        # Word boundaries stop "male" inside "female" and "70 kg" inside "170 kg".
        occurrences = [
            match.span() for match in re.finditer(r"(?<!\w)" + re.escape(quote) + r"(?!\w)", text)
        ]
        if not occurrences:
            return {}
        for start, end in occurrences:
            lo, hi = _raw_clause(text, start, end)
            if candidate.field != asked and not re.search(
                FIELD_CUES[candidate.field], text[lo:hi], flags=re.I
            ):
                return {}
            after = _canonical(text[end:hi])
            context_raw = _canonical(text[lo:start]) + " , " + after
            context = _unhedged(context_raw)
            if re.search(r"\d", context) or UNIT_NEXT.search(after):
                return {}
            if any(
                pattern.search(context)
                for pattern in (NEGATION, PAST_OLD, CHANGE, FUTURE, OTHER_PERSON, VAGUE)
            ):
                return {}
            if PAST_VERB.search(context) and not RECENT.search(context_raw):
                return {}
            if _other_topic(candidate.field, context):
                return {}
            # A categorical quote must be the whole statement: "never" taken from
            # "I never smoke at home" leaves smoking words behind in its clause.
            if candidate.field in CATEGORICAL and re.search(
                TOPICS.get(candidate.field, NOTHING), context
            ):
                return {}
        if any(key in values and values[key] != value for key, value in quote_values.items()):
            return {}
        covered += occurrences
        values.update(quote_values)
    # Clauses the provider did not quote may not hold a competing answer.
    topics = {_topic(field) for field in values}
    breaks = [0, *(m.end() for m in RAW_BREAK.finditer(text))]
    ends = [m.start() for m in RAW_BREAK.finditer(text)] + [len(text)]
    for lo, hi in zip(breaks, ends, strict=True):
        if not text[lo:hi].strip() or any(s < hi and lo < e for s, e in covered):
            continue
        clause = _canonical(text[lo:hi])
        if re.search(r"\d", clause):
            named = {
                topic
                for topic in TOPICS
                if re.search(TOPICS[topic], clause)
                or re.search(TOPIC_UNITS.get(topic, NOTHING), clause)
            }
            if not named or named & topics:
                return {}
        for field in list(values):
            other = parse_value(field, text[lo:hi], today=today)
            if field in other and other[field] != values[field]:
                return {}
    return values
