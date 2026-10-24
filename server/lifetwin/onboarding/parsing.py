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

import calendar
import re
import unicodedata
from datetime import date

from pydantic import ValidationError

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import ExtractionResult, ProfileField

QUESTIONS: dict[ProfileField, str] = {
    "age": "How old are you?",
    "sex": "What sex were you at birth: female or male?",
    "height_cm": "How tall are you? For example, 5 feet 10 inches.",
    "weight_kg": "How much do you weigh? For example, 160 pounds.",
    "sleep_hours": "How many hours do you sleep on a usual night?",
    "exercise_minutes_weekly": (
        "About how many minutes do you exercise in a week? "
        "A 30-minute walk, 5 days a week, is 150 minutes."
    ),
    "smoking_status": "Do you smoke now, did you smoke before, or have you never smoked?",
    "alcohol_drinks_weekly": (
        "How many alcoholic drinks do you have in a week? Say none if you don't drink."
    ),
    "diabetes": "Has a doctor ever told you that you have diabetes?",
    "systolic_bp": "What is your blood pressure? For example, 120 over 80.",
    "diastolic_bp": (
        "What is the bottom number of your blood pressure? For example, the 80 in 120 over 80."
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
# The value each question's own example stands for, so "yes, that's right" said
# right after it can be offered back for confirmation.
QUESTION_EXAMPLE_VALUES: dict[ProfileField, str] = {
    "height_cm": "5 feet 10 inches",
    "weight_kg": "160 pounds",
    "exercise_minutes_weekly": "150 minutes",
}
EXAMPLES: dict[ProfileField, str] = {
    "age": '"I\'m 72"',
    "sex": '"female"',
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
    "sex": r"\b(?:sex|female|male|woman|man)\b",
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


# Contractions typed or transcribed without the apostrophe ("i dont drink").
# "ill" is "I'll" only before a verb, since "I'm ill" is a word of its own.
APOSTROPHES = [
    (r"\b(do|does|did|have|has|is|was|were|are|could|would|should|had|must|need)nt\b", r"\1n't"),
    (r"\bcant\b", "can't"),
    (r"\bwont\b", "won't"),
    (r"\bim\b", "i'm"),
    (r"\bive\b", "i've"),
    (r"\bid\b", "i'd"),
    (r"\bill(?= (?:be|turn|have|say|go|need|try)\b)", "i'll"),
    (r"\b(that|it|what|there|he|she)s\b", r"\1's"),
    (r"\b(they|you)re\b", r"\1're"),
]


def normalize_text(text: str) -> str:
    """Map smart punctuation (iOS default), primes, fraction glyphs and missing
    apostrophes; collapse spaces."""
    text = text.translate(QUOTES)
    text = text.replace("''", '"')  # 5'4'' typed with two apostrophes
    for glyph, words in FRACTIONS.items():
        text = text.replace(glyph, words)
    for pattern, spelled in APOSTROPHES:
        text = re.sub(pattern, spelled, text, flags=re.I)
    # Other scripts' digits ("١٢") become ASCII, so every rule reads them alike.
    text = re.sub(
        r"[^\x00-\x7f]", lambda m: str(unicodedata.decimal(m.group(), "")) or m.group(), text
    )
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


MONTH = (
    r"(january|february|march|april|may|june|july|august|september|october|november|december"
    r"|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)"
)
ORDINALS = {
    word: n
    for n, word in enumerate(
        "first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth "
        "thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth".split(),
        1,
    )
} | {"twentieth": 20, "thirtieth": 30}
_ORD = rf"(?:(twenty|thirty) )?({'|'.join(ORDINALS)})"


def _ordinal(tens: str | None, word: str) -> str:
    return str({"twenty": 20, "thirty": 30}.get(tens or "", 0) + ORDINALS[word])


# Containers become drink counts: a 750 ml bottle of wine is 5 glasses. Once a
# weekend, they are that many a week ("a six-pack on weekends" -> 6). A leading
# "a" is kept, so "a bottle of wine" still asks how often, like "a glass of wine".
WINE = r"(?:(?:red|white|rose|house) )?wine"
CONTAINERS = [
    # "half a bottle of wine" with no how-often is asked about, like "a glass of wine".
    (rf"\b(?P<a>)half (?:a )?bottle of {WINE}", lambda m: 2.5, "glasses of wine"),
    (
        rf"\b(?:(?P<a>a )|(\d) )bottles? of {WINE}",
        lambda m: 5 * int(m.group(2) or 1),
        "glasses of wine",
    ),
    (
        r"\b(?:(?P<a>a )|(\d) )?(6|12|18|24|30) packs?(?: of (?:beers?|cans))?",
        lambda m: int(m.group(3)) * int(m.group(2) or 1),
        "beers",
    ),
]
WEEKEND_ONCE = r"(?P<weekend> (?:on|at|over) (?:the )?weekends?\b)?"


def _containers(s: str) -> str:
    def rewrite(m: re.Match, count, noun: str) -> str:
        if m.group("weekend"):
            return f"{count(m):g} {noun} a week"
        article = "a " if m.group("a") is not None else ""
        return f"{article}{count(m):g} {noun}"

    for pattern, count, noun in CONTAINERS:
        s = re.sub(pattern + WEEKEND_ONCE, lambda m, c=count, n=noun: rewrite(m, c, n), s)
    return s


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
    # A two-digit year is a year, never an age: "born in '80" -> 1980.
    s = re.sub(r"(?<!\d )(?<![\w'])'(\d{2})\b(?!')", r"19\1", s)  # not "5 '10"
    # Speech-to-text drops the apostrophe: "born in 52" -> 1952 ("born 52 years ago" stays).
    s = re.sub(
        r"\bborn (?:in |on )?(?:the year )?(\d{2})\b(?![\d:/']|\.\d|\s?(?:years?|yrs?)\b)",
        lambda m: f"born in {'20' if int(m.group(1)) <= 8 else '19'}{m.group(1)}",
        s,
    )
    s = re.sub(rf"\b{_ORD}(?= of {MONTH}\b)", lambda m: _ordinal(m.group(1), m.group(2)), s)
    s = re.sub(
        rf"\b{MONTH} (?:the )?{_ORD}\b",
        lambda m: f"{m.group(1)} {_ordinal(m.group(2), m.group(3))}",
        s,
    )
    s = re.sub(r"\ba buck(?: and)? (\d{2})\b", r"1\1", s)  # "a buck sixty", "a buck 60"
    s = re.sub(
        r"\b(a|one|two) hundred(?: and)? (\d{2})\b",
        lambda m: str({"a": 1, "one": 1, "two": 2}[m.group(1)] * 100 + int(m.group(2))),
        s,
    )  # "a hundred 30"
    # Speech to text writes "one hundred and sixty" as "100 and 60" ("between 100 and 110"
    # is a range).
    s = re.sub(
        r"(?<!between )(?<![\d.,])\b([12])00 and (\d{1,2})\b(?![\d.,]\d)",
        lambda m: str(int(m.group(1)) * 100 + int(m.group(2))),
        s,
    )
    s = re.sub(r"\ba couple(?: of)? (?=[a-z0-9])", "2 ", s)
    s = re.sub(r"\ba buck(?: and)? (?=[a-z])", "one hundred ", s)
    s = NUMBER_RUN.sub(
        lambda m: _read_run(m.group(0).split(), bool(ADJECTIVAL.match(s, m.end()))), s
    )
    # "two years shy of 70" -> 68
    s = re.sub(
        r"\b(a|\d{1,2}) years? (?:shy|short|away) (?:of|from) (\d{2,3})\b",
        lambda m: str(int(m.group(2)) - (1 if m.group(1) == "a" else int(m.group(1)))),
        s,
    )
    # Spoken clock times: "half past nine", "ten thirty to six thirty".
    s = re.sub(r"\bhalf past (\d{1,2})\b", r"\1:30", s)
    s = re.sub(r"\b(?:a )?quarter past (\d{1,2})\b", r"\1:15", s)
    s = re.sub(r"\b(\d{1,2}) (15|30|45)(?= (?:to|till|until)\b)", r"\1:\2", s)
    s = re.sub(
        r"\b(to|till|until) (\d{1,2}) (15|30|45)\b(?! ?(?:minute|hour|min)s?\b)", r"\1 \2:\3", s
    )
    s = re.sub(r"(?<=\d) slash (?=\d)", "/", s)
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
    return " ".join(_containers(s).split())


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
# "I feel like it depends on the day, maybe like 130 over 85": one typical value,
# read back as "about"; "it depends" with no value after it stays vague.
DEPENDS = re.compile(
    r"\b(?:i feel like )?it (?:all )?depends(?: on (?:the|what|how|my) \w+)?,? (?:but )?"
    r"(?=(?:maybe|probably|usually|mostly|about|around|like|roughly)\b)"
)
QUESTION = re.compile(r"\?")
MAYBE = re.compile(r"\b(?:maybe|probably|perhaps|possibly)\s+(?:(?:about|around|like)\s+)?")
UNCERTAIN = re.compile(
    r"\b(?:maybe|may be|might|perhaps|possibly|probably|unsure|either|dunno|guessing|"
    r"not (?:really |quite |too |entirely |exactly )?(?:sure|certain)|"
    r"(?:don't|do not|dont|didn't|did not|can't|cannot|couldn't) (?:really |even )?"
    r"(?:know|remember|recall|tell|say)|no idea|no clue|not a clue|i forget|i forgot|"
    r"who knows|hard to (?:say|tell)|could be|(?:don't|do not) (?:think|believe) so|not really)\b"
)
HYPOTHETICAL = re.compile(
    r"\b(?:if|unless|would|wouldn't|could|couldn't|should|wish|hope|hoping|hopefully|"
    r"want|wants|wanted|want to|wanna|like to|goal|aim|aiming|target|suppose|supposed|"
    r"imagine|pretend|ought to|meant to|"
    r"ideally|planning|plan to|trying to|i'd)\b"
)
VAGUE = re.compile(
    r"\b(?:between|anywhere from|depends|depending|varies|vary|varying|sometimes|"
    r"some (?:days|nights|weeks)|most (?:days|nights|weeks|evenings)|on and off|"
    r"now and then|occasionally|here and there|once in a while|not much|not a lot|"
    r"a lot|lots|a little|a bit|a few|a couple|couple of|several|socially|on occasion|"
    r"or more|or less|at least|at most|up to|more than|less than|fewer than|over|under|"
    # "7 hours, no, less": a bare comparison says the number is not the answer.
    r"less|more|fewer|"
    r"above|below|plus|ish|odd|range|decades|twenties|thirties|forties|fifties|sixties|"
    r"seventies|eighties|nineties|on a (?:good|bad) night|(?:good|bad) nights?|"
    r"every other(?! days?\b)|shy of|short of|north of|south of|side of|"
    r"alternate|every few|fortnight\w*|rarely|seldom|hardly|when|whenever|"
    r"except|apart from|other than|excluding)\b"
)
PEOPLE = (
    r"(?:wife|husband|hubby|partner|spouse|son|daughter|better half|other half|missus|missis|"
    r"mrs|wifey|old man|old lady|mother|mom|mum|mommy|father|dad|daddy|papa|brother|sister|"
    r"twin|friend|neighbou?r|kids?|child|children|grandson|granddaughter|grandkids?|"
    r"grandchild(?:ren)?|grandma|grandpa|granny|grandmother|grandfather|boyfriend|girlfriend|"
    r"cousin|aunt|uncle|niece|nephew|dog|cat|family|parents?)"
)
# A relative as the subject even without "my": "Dad is 90", "hubby has diabetes".
KIN = (
    r"(?:wife|husband|hubby|missus|missis|wifey|spouse|partner|son|daughter|mother|mom|mum|"
    r"father|dad|brother|sister|twin|grandma|grandpa|granny|grandmother|grandfather|"
    r"boyfriend|girlfriend)"
)
OTHER_PERSON = re.compile(
    rf"\b(?:my|our|his|her|their|your)\s+{PEOPLE}(?:'s)?\b"
    r"|\bthe (?:wife|husband|missus|missis|mrs|old man|old lady|other half|better half|kids)\b"
    rf"|\b{KIN}(?:'s\b|\s+(?:is|was|has|had|does|did|weighs|sleeps|drinks|smokes|walks|says|"
    r"said|turned|turns|gets)\b)|\b(?:he|she|he's|she's|hers|him)\b"
)
# "Bob is 75": a name as the subject (only visible while the reply keeps its capitals).
NAME_SUBJECT = re.compile(
    r"\b(?!(?:Who|What|When|Where|Why|How|Which|Can|Could|Would|Will|Is|Are|Do|Does|Did|"
    r"Hey|Wait|Dude|Bro|Like|Okay|Ok|And|But|Or|If|Then|Now|Ah|See|Look|Listen|"
    r"I|It|Its|That|This|There|Here|My|Mine|Yes|Yeah|Yep|No|Nope|Nah|Well|Oh|So|Um|"
    r"Uh|Hmm|The|We|They|You|Doctor|Dr|Female|Male|Woman|Man|Never|Not|Just|About|Around|"
    r"Maybe|Probably|Mostly|Usually|Normal|Everything|Nothing|None|Today|Weight|Height|Age|"
    r"Sleep|Exercise|Alcohol|Smoking|Diabetes|Blood|Pressure|Monday|Tuesday|Wednesday|"
    r"Thursday|Friday|Saturday|Sunday)\b)[A-Z][a-z]+(?:'s)?\s+(?:is|was|has|weighs|sleeps|"
    r"drinks|smokes|walks|does|turned|turns)\b"
)
FIRST_PERSON = re.compile(r"\b(?:i|i'm|i've|i'd|i'll|me|my|mine|myself)\b")
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
    r"\bbut\s+(?:now|these days|nowadays|today|lately)\b|\bnow\s+(?:it's|it is|i'm|i am|they)\b|"
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


# Anywhere in a reply, these make a number someone's past, goal or advice instead of
# the person's usual value now: "160 pounds, before my surgery", "I need 8 hours".
PAST_SPOIL = re.compile(
    r"\b(?:ago|back then|back in|a while back|years back|originally|shrunk|shrank|"
    r"used to(?: be)?(?=\s*(?:$|[,.;!]))|before (?:my|the|i|we|that|it)|at (?:my|our) wedding|"
    r"in (?:high )?school|in college|in the (?:army|navy|service|military|marines|war)|"
    r"in my (?:youth|prime|decades)|when i was|back when|in (?:19|20)\d\d|not since|"
    r"(?:until|till) (?:my|the|i|we)|(?:and|then|but) (?:then )?i (?:quit|stopped|gave up)"
    r"(?! smoking))\b"
)
ADVICE = re.compile(
    r"\b(?:need|needs|needed|recommend\w*|advised?|allowed|ideal|ideally|normal is|normal's|"
    r"normal for|ought|feels?(?! like it\b)|(?:i|you) look|looks? (?:like )?\d+|in my dreams|"
    r"dream)\b"
)
# Sleep, exercise and drinks are the person's own habit, so a doctor's word is advice.
REPORTED = re.compile(r"\b(?:says|said|tells me|told me)\b")  # not "I'd say 6"
HABITS = {"sleep_hours", "exercise_minutes_weekly", "alcohol_drinks_weekly"}
SEASONAL = re.compile(
    r"\b(?:in|during) (?:the )?(?:summer|winter|spring|fall|autumn)(?:time)?\b|\bin season\b"
)


def _spoiled(field: str, rest: str) -> bool:
    """Words outside the value that make it not the person's usual value now."""
    if field != "age" and PAST_SPOIL.search(rest):
        return True
    if ADVICE.search(rest) or (
        field in HABITS and (REPORTED.search(rest) or SEASONAL.search(rest))
    ):
        return True
    return field == "alcohol_drinks_weekly" and bool(re.search(NON_ALCOHOL, rest))


def _clean_measurement(field: str, text: str, spans: list[tuple[int, int]]) -> bool:
    """Whether the value found at ``spans`` is the reply's only, current, own answer."""
    # "maybe 60": right before the one number, maybe is a hedge (it is read back);
    # "maybe I weigh 70" doubts the whole statement.
    starts = {start for start, _ in spans}
    hedged = [m.span() for m in MAYBE.finditer(text) if m.end() in starts]
    hedged += [m.span() for m in DEPENDS.finditer(text) if any(s >= m.end() for s in starts)]
    rest = _blank(text, spans + hedged)
    if re.search(r"\d", rest) or NOT_CURRENT.search(rest):
        return False
    whole = _unhedged(rest)
    if _doubtful(rest) or VAGUE.search(whole) or OTHER_PERSON.search(whole):
        return False
    if _spoiled(field, rest):
        return False
    local_raw = _context(text, spans)
    local = _unhedged(local_raw)
    if NEGATION.search(local) or PAST_OLD.search(local) or CHANGE.search(local):
        return False
    # A blood pressure is always a past reading; only an old one ("years ago") is refused.
    # "were you just getting 5'4": a past verb said to someone else is not the person's past.
    own_past = PAST_VERB.search(re.sub(r"\b(?:were|was|did) you\b", " ", local))
    stale = own_past and not RECENT.search(local_raw) and field not in BP_FIELDS
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
    r"then|myself|still|tops|next|come)\b))"
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
MONTH_TITLES = (
    "January February March April May June July August September October November December"
).split()
MONTH_WORD = MONTH.replace("(", "(?:", 1)
# A date is a birth date after "born" or "my birthday is", or as the whole reply:
# "1980 was a good year" and "class of '98" are not.
BORN = r"(?:(?:i was |i'm |i am )?born|(?:my )?(?:birthday|date of birth|birth date|dob)(?: is)?)"
NAMED_DATE = (
    rf"(?P<m1>{MONTH_WORD}) (?P<d1>\d{{1,2}})(?:st|nd|rd|th)?,? (?:in )?(?P<y1>\d{{4}})"
    rf"|(?:the )?(?P<d2>\d{{1,2}})(?:st|nd|rd|th)? (?:of )?(?P<m2>{MONTH_WORD}),? (?:in )?(?P<y2>\d{{4}})"
)
NUMERIC_DATE = (
    r"(?<![\d/.])(?:(?P<a>\d{1,2})(?P<sep>[/.-])(?P<b>\d{1,2})(?P=sep)(?P<y>\d{4}|\d{2})"
    r"|(?P<iy>\d{4})-(?P<im>\d{1,2})-(?P<id>\d{1,2}))(?![\d/]|\.\d)"
)
MONTH_YEAR = rf"(?P<m>{MONTH_WORD}),? (?:of |in )?(?P<y>\d{{4}})"
YEAR_ONLY = r"(?:the year )?(?P<y>1[89]\d\d|20[0-2]\d)(?!\d|\.\d)"
# "I'm 46 this year": the birthday may or may not have passed yet.
THIS_YEAR = (
    r"(?:\bi turn |(?<!be )(?<!turning )(?<![\d.]))(?P<n>\d{1,3})(?:\s?year(?: old)?)?"
    r" this (?P<unit>year|month|week)\b"
)
FUTURE_AGE = (
    r"(?:\b(?:i'll|i will|i'm going to|i am going to|i'm gonna|going to|gonna)\s+(?:be|turn)\s+"
    r"(\d{1,3})(?![\d.])|\b(?:i'm\s+|i am\s+)?turning\s+(\d{1,3})(?![\d.])|\bi turn\s+(\d{1,3})(?![\d.]))"
    r"(?:\s+in\s+(?:\d{1,2}|a)\s+(?:days?|weeks?|months?))?"
)
# "I just had my 70th birthday"
BIRTHDAY = r"\b(?:had|celebrated|turned)\s+my\s+(\d{2,3})(?:st|nd|rd|th)\s+birthday\b"
# "70 next week", "76 in March": a birthday still to come.
WHEN = (
    rf"(?:(?:\d{{1,2}}|a|an)\s(?:days?|weeks?|months?|year)|year|month|week|birthday|"
    rf"(?:my\s)?(?:next\s)?birthday|christmas|(?:next\s)?(?:monday|tuesday|wednesday|thursday|"
    rf"friday|saturday|sunday)|(?:the\s)?(?:spring|summer|fall|autumn|winter)|{MONTH_WORD})\b"
)
AGE = (
    rf"(?<![\d.])(?<!-)(?<!going on )(\d{{1,3}})(?![\d.]\d)"
    rf"(?:\s?year(?:\s(?:old|young|of age))?|{FOLLOW})(?:,?\s?going on\s(\d{{1,3}}))?"
    rf"(?:\s(next|in|this|on|come|come next|by)\s{WHEN})?"
)


def _dated(pattern: str) -> str:
    return (
        rf"(?:\b{BORN}\s(?:on\s|in\s)?|(?P<alone>^)(?:on\s|in\s)?)(?:{pattern})(?(alone)[\s.!]*$)"
    )


def _born(year: int, month: int, day: int, today: date) -> int | None:
    try:
        born = date(year, month, day)
    except ValueError:
        return None
    if born > today:
        return None
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _span_ages(year: int, month: int | None, today: date) -> set[int]:
    """Ages for a birth known only to the month or year: the earliest and latest day."""
    first, last = (month or 1, 1), (month or 12, calendar.monthrange(year, month or 12)[1])
    return {
        age for age in (_born(year, *first, today), _born(year, *last, today)) if age is not None
    }


def _age_readings(text: str, today: date) -> list[tuple[set[int], tuple[int, int], str]] | None:
    """(possible ages, span, how to say it) for each birth date or "46 this year".

    A full date gives one age; a month in the current month, a year alone or a
    turning-this-year gives the two ages either side of the birthday. None when
    a date is impossible.
    """
    readings: list[tuple[set[int], tuple[int, int], str]] = []

    def year(digits: str) -> int:
        return int(digits) if len(digits) == 4 else 1900 + int(digits)

    for pattern in (NAMED_DATE, NUMERIC_DATE, MONTH_YEAR, YEAR_ONLY, THIS_YEAR):
        rest = _blank(text, [span for _, span, _ in readings])
        regex = pattern if pattern is THIS_YEAR else _dated(pattern)
        for m in re.finditer(regex, rest):
            groups = m.groupdict()
            if pattern is NAMED_DATE:
                name = groups["m1"] or groups["m2"]
                ages = {
                    _born(
                        int(groups["y1"] or groups["y2"]),
                        MONTHS[name[:3]],
                        int(groups["d1"] or groups["d2"]),
                        today,
                    )
                }
                lead = ""
            elif pattern is NUMERIC_DATE:
                if groups["iy"]:
                    ages = {_born(int(groups["iy"]), int(groups["im"]), int(groups["id"]), today)}
                else:
                    a, b, born_year = int(groups["a"]), int(groups["b"]), year(groups["y"])
                    # Month first (US), unless only day first is a real date.
                    ages = {_born(born_year, a, b, today), _born(born_year, b, a, today)}
                    ages = ages - {None} or ages
                lead = "Born on " + "{a}{sep}{b}{sep}{y}".format(**groups)
            elif pattern is MONTH_YEAR:
                month = MONTHS[groups["m"][:3]]
                ages = _span_ages(int(groups["y"]), month, today)
                lead = f"Born in {MONTH_TITLES[month - 1]} {groups['y']}"
            elif pattern is YEAR_ONLY:
                ages = _span_ages(int(groups["y"]), None, today)
                lead = f"Born in {groups['y']}"
            else:
                n = int(groups["n"])
                ages = {n - 1, n}
                lead = f"Turning {n} this {groups['unit']}"
            if not ages or None in ages:
                return None
            readings.append((ages, m.span(), lead))
    return readings


def _age(text: str, today: date) -> Found:
    def current(match: re.Match):
        # "I retired at 65", "since 60": the age at some event, not now.
        before = text[: match.start()]
        # "the year I turned 65", "when I turned 65": an event, not today's age.
        if re.search(r"\b(?:when|the year|after|before|since|once)\s+i\s+turned\s+$", before):
            return None
        if re.search(
            r"\b(?:at|since|until|till|by|after|before|from|when|for)\s+"
            r"(?:(?:the|about|around|almost|nearly|over)\s+)?"
            r"(?:age\s+(?:of\s+)?)?$",
            before,
        ):
            return None
        value = int(match.group(1))
        # "on the wrong side of 70", "shy of 70": a comparison, not an age.
        if re.search(r"\b(?:side|shy|short|north|south) of\s+$", before):
            return None
        # "almost 80", "pushing 80": still 79.
        if re.search(r"\b(?:almost|nearly|pushing|close to|coming up on|approaching)\s+$", before):
            return value - 1 if not match.group(3) else None
        # "I'm 79, going on 80" describes the same age; any other pair is ambiguous.
        if match.group(2) and int(match.group(2)) != value + 1:
            return None
        if match.group(3) == "this":
            return None  # asked as two ages by clarify
        # "70 next week": still 69 today; "turned 70 in March" is 70.
        if match.group(3) and not re.search(r"\bturned\s+$", before):
            return value - 1
        return value

    def turning(match: re.Match):
        # "I'll be 77 in March": still 76 today.
        return int(match.group(1) or match.group(2) or match.group(3)) - 1

    readings = _age_readings(text, today)
    if readings is None:
        return None
    dated = [span for _, span, _ in readings]
    sure = [(min(ages), span) for ages, span, _ in readings if len(ages) == 1]
    found = _combine(
        ([value for value, _ in sure], [span for _, span in sure]),
        _collect(BIRTHDAY, _blank(text, dated), lambda m: int(m.group(1))),
    )
    for pattern, read in ((FUTURE_AGE, turning), (AGE, current)):
        if found is None:
            return None
        found = _combine(found, _collect(pattern, _blank(text, dated + found[1]), read))
    if found is None:
        return None
    unsure = [(ages, span) for ages, span, _ in readings if len(ages) > 1]
    if unsure:
        # "I'm 72, born in 1954": a stated age settles which side of the birthday.
        if not found[0] or any(value not in ages for ages, _ in unsure for value in found[0]):
            return None
        found = (found[0], found[1] + [span for _, span in unsure])
    return found


FEET = (
    rf"(?<![\d.])(?<!-)(\d)\s?ft(?:,?\s?(?:and\s)?(\d{{1,2}}(?:\.\d{{1,6}})?)(?!\d){NOT_UNIT}"
    r"(?:\s?inch\b)?)?(?:\s(?:even|flat|exactly))?"
)
_FT_IN = r"([4-7])(?:\s?ft\s?|\s)(\d{1,2})(?:\s?inch)?"
HEIGHT_EITHER = rf"(?<![\d.])(?<!-){_FT_IN}\s(?:or|to|-)\s{_FT_IN}(?![\d.])"
# "5 and a half feet" (canonical "5.5 ft")
FEET_DECIMAL = r"(?<![\d.])(?<!-)(\d\.(?:25|5|75))\s?ft\b(?!\s?\d)"
# Speech to text writes "five ten" as "510"; nothing else that size is a height.
SPOKEN_HEIGHT = rf"(?<![\d.])(?<!-)([4-7])(0[1-9]|1[01])(?![\d.]){FOLLOW}"
# A bare 120-219 can only be centimeters.
BARE_CM = rf"(?<![\d.])(?<!-)(1[2-9]\d|2[01]\d)(?![\d.]){FOLLOW}"
HEIGHT_PAIR = (
    r"(?<![\d.])(?<!-)([4-7])(?:\s|\s?-\s?|,\s?)(\d{1,2}(?:\.5)?)(?![\d.])"
    r"(?!\s?(?:ft|inch|cm|m|kg|lb|stone|hour|minute|year|over|/|on|to|or|and)\b)"
)


def _height(text: str, today: date) -> Found:
    def feet(match: re.Match):
        inches = float(match.group(2) or 0)
        return None if inches >= 12 else int(match.group(1)) * 30.48 + inches * 2.54

    def either(match: re.Match):
        low, high = (int(match.group(i)) * 12 + int(match.group(i + 1)) for i in (1, 3))
        ok = 0 < high - low <= 1 and int(match.group(2)) < 12 and int(match.group(4)) < 12
        return (low + high) / 2 * 2.54 if ok else None

    # "5 7 or 5 8": an inch apart reads as the middle, like "7 or 8 hours".
    found = _collect(HEIGHT_EITHER, text, either)
    if found is None:
        return None
    text = _blank(text, found[1])
    found = _combine(
        found,
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
        _collect(FEET_DECIMAL, rest, lambda m: float(m.group(1)) * 30.48),
        _collect(rf"{N}(?:,?\s+in)?\s?cm\b", rest, lambda m: float(m.group(1))),
        _collect(rf"{N}\s?m\b", rest, lambda m: float(m.group(1)) * 100),
        _collect(rf"{N}\s?inch\b", rest, lambda m: float(m.group(1)) * 2.54),
    )
    # "six two", "five-eight": two bare numbers answering the height question.
    for pattern, read in (
        (HEIGHT_PAIR, feet),
        (SPOKEN_HEIGHT, feet),
        (BARE_CM, lambda m: float(m.group(1))),
    ):
        if found is None or found[0]:
            return found
        found = _collect(pattern, text, read)
    return found


# Speech to text writes "one eighty" as "1 80": as a weight that is 180 pounds.
SPLIT_POUNDS = rf"(?<![\d.:/])(?<!-)\b([12]) ([1-9]\d)\b(?![\d.:/])(?=\s?lb\b|{FOLLOW})"
STONE = rf"{N}\s?stone\b(?:,?\s?(?:and\s)?(\d{{1,2}}(?:\.\d{{1,6}})?)(?!\d){NOT_UNIT}(?:\s?lb\b)?)?"
LB_PER_KG = 0.45359237


def _weight(text: str, today: date) -> Found:
    def stone(match: re.Match):
        pounds = float(match.group(2) or 0)
        return None if pounds >= 14 else (float(match.group(1)) * 14 + pounds) * LB_PER_KG

    def bare(match: re.Match):
        # US default: a bare adult weight is pounds (read back before saving).
        # Under 90 could be either unit, so it is asked about.
        pounds = float(match.group(1))
        return pounds * LB_PER_KG if 90 <= pounds <= 450 else None

    def spread(match: re.Match):
        # "between 150 and 160": a close range reads as its middle.
        low, high, unit = (
            float(match.group(1) or match.group(2)),
            float(match.group(3)),
            match.group(4),
        )
        if unit is None and high < 90:
            return None
        width = 5 if unit == "kg" else 10
        middle = (low + high) / 2
        return None if not 0 < high - low <= width else middle * (1 if unit == "kg" else LB_PER_KG)

    found = _combine(
        _collect(
            rf"(?:\bbetween\s+{N}(?:\s?(?:lb|kg))?\s+and|{N}(?:\s?(?:lb|kg))?\s?(?:to|-))\s?{NUM}"
            rf"(?!\d)(?:\s?(lb|kg)\b|{FOLLOW})",
            text,
            spread,
        ),
    )
    found = _combine(found, _collect(STONE, _blank(text, found[1] if found else []), stone))
    if found is None:
        return None
    rest = _blank(text, found[1])
    found = _combine(
        found,
        _collect(rf"{N}(?:,?\s+in)?\s?kg\b", rest, lambda m: float(m.group(1))),
        _collect(rf"{N}(?:,?\s+in)?\s?lb\b", rest, lambda m: float(m.group(1)) * LB_PER_KG),
    )
    if found is None or found[0]:
        return found
    return _collect(rf"{N}{FOLLOW}", text, bare)


TIME = r"(\d{1,2})(?::(\d{2}))?(?:\s?(am|pm|o'clock))?(?![\d.:])(?!\s?(?:hour|minute)\b)"
BEDTIME = (
    rf"\b(?:bed|asleep|sleep(?:ing)?|lights out|turn in)\b(?:\s+[a-z']+){{0,3}}?\s+"
    rf"(?:(?:by|at|around|about|from)\s+)?{TIME}[^\d]{{0,30}}?\b(?:up|awake|wake(?:\s+up)?|"
    rf"get\s+up|rise|until|till|to)\b(?:\s+[a-z']+){{0,2}}?\s+(?:(?:by|at|around|about)\s+)?{TIME}"
)
# "midnight to 7", "11 till 5:30", "10 to 6": bedtime to waking without saying bed.
# "7 to 8" counts up, so it stays a range of hours.
CLOCK_RANGE = rf"(?<![\d.:])(?:\bfrom\s+)?{TIME}\s?(?:to|till|until|-)\s?{TIME}"
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
    if found is not None:
        for m in re.finditer(CLOCK_RANGE, _blank(text, found[1])):
            if not any(m.group(i) for i in (2, 3, 5, 6)) and int(m.group(1)) <= int(m.group(4)):
                continue
            hours = bedtime(m)
            if hours is None:
                return None
            found[0].append(hours)
            found[1].append(m.span())
    for pattern, read in (
        (
            # "7 or 8 hours", and "6, 7 hours" as transcripts write "six, seven hours".
            rf"(?:\bbetween\s+{N}(?:\s?hour)?\s?and|{N}(?:\s?hour)?(?:\s?(?:to|or|-)|,))\s?{NUM}(?!\d)"
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


# "30 to 40 minutes" (a close range, read as its middle), "an hour and fifteen minutes"
DURATION = (
    rf"(?:{N}\s?(?:to|-|or)\s?)?{N}\s?(minute|hour)\b(?:,?\s?(?:and\s)?(\d{{1,2}})\s?minute\b)?"
)
FREQUENCY = (
    r"\b(?:days?|daily|weeks?|weekly|months?|monthly|years?|yearly|mornings?|evenings?|nights?|"
    r"nightly|weekends?|weekdays?|times?|once|twice|other|sessions?|class(?:es)?|each|every|per)\b"
)
ACTIVITY = r"(?:\s+of\s+[a-z]+(?:\s+[a-z]+)?)?"
WEEKLY = (
    rf"{ACTIVITY}\s*(?:(?:a|per|each|every|/|in a|in the)\s*week\b|"
    r"(?:in\s+)?(?:total|all together|altogether|all told|in all)\b)"
)
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
    # "every other day", "every 3 days": 7 / n days a week.
    for match in re.finditer(r"\bevery (?:(other|second)|([2-7])) days?\b", text):
        counts.append(7 / (2 if match.group(1) else int(match.group(2))))
        spans.append(match.span())
    text = _blank(text, spans)
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
    # The question is per week, so "3 times" and "4 days" are a week's count.
    for match in re.finditer(
        r"\b(?:(once|twice|thrice)|(\d) ?(?:times?|x|days?))\b"
        r"(?!\s+(?:a|per|each|every|in a|of the)\s+(?:day|month|year)\b)(?!\s+ago\b)",
        _blank(text, spans),
    ):
        counts.append(times.get(match.group(1)) or int(match.group(2)))
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


def _sessions(text: str) -> Found:
    """ "A 30 minute walk 4 days and 1 hour of tai chi on Saturday": each part with
    its own duration and how often, added up."""
    total, spans, offset = 0.0, [], 0
    segments = re.split(r"(\band\b|\bplus\b|[,;])", text)
    if len(segments) < 3:
        return None  # "45 minutes or an hour", "30 minutes then 20": asked about
    for segment in segments:
        if segment.strip() and not re.fullmatch(r"and|plus|[,;]", segment.strip()):
            found = _exercise(segment, date.min, nested=True)
            # Every part needs its own how-often, or the sum is a guess.
            if not found or not (re.search(FREQUENCY, segment) or re.search(DAY_NAMES, segment)):
                return None
            total += found[0][0]
            spans += [(start + offset, end + offset) for start, end in found[1]]
        offset += len(segment)
    return [total], spans


def _exercise(text: str, today: date, nested: bool = False) -> Found:
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
            r"\b(?:don't|do not|never)\s+(?:do\s+any(?:thing)?|exercise|work\s+out)\b|"
            r"^(?:no )?i (?:don't|do not)$",
            text,
        )
        vague = re.search(r"\b(?:much|a lot|often|enough|regularly|as much|very)\b", text)
        return _zero("exercise_minutes_weekly", text) if zero and not vague else None
    if len(durations) != 1:
        return None if nested else _sessions(text)
    duration = durations[0]
    hours = duration.group(3) == "hour"
    value = float(duration.group(2))
    if duration.group(1):
        low = float(duration.group(1))
        if not 0 < value - low <= (0.5 if hours else 15):
            return None
        value = (low + value) / 2
    minutes = value * (60 if hours else 1)
    if duration.group(4):
        if not hours:
            return None
        minutes += int(duration.group(4))  # "an hour and fifteen minutes"
    spans = [duration.span()]
    after = text[duration.end() :]
    weekly, daily = re.match(WEEKLY, after), re.match(DAILY_RATE, after)
    tail = weekly or daily
    if tail:
        spans.append((duration.end(), duration.end() + tail.end()))
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
    if weekly:
        return ([minutes], spans) if not counts else None
    if counts:
        return [minutes * counts[0]], spans
    # "an hour a day", "twice a day for 20 minutes": every day, read back to confirm.
    if (daily or per_day) and not re.search(FREQUENCY, _blank(text, spans)):
        return [minutes * 7], spans
    # Hours without how often ("an hour") or any other frequency ("every other
    # day", "a 45 minute class") are asked about.
    if daily or per_day or hours or re.search(FREQUENCY, _blank(text, spans)):
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


# Not alcohol: "8 glasses of water a day" is never 56 drinks.
NON_ALCOHOL = (
    r"\b(?:water|sodas?|pop|soft drinks?|coffees?|espressos?|lattes?|cappuccinos?|decaf|milk|"
    r"teas?|juices?|lemonade|seltzer|colas?|cokes?|pepsi|ginger ale|smoothies?|shakes?|cocoa|"
    r"hot chocolate|non ?alcoholic|alcohol free|mocktails?|kombucha)\b"
)
# "I don't drink beer, just wine", "none on weekdays", "never drink alone": not none.
ZERO_QUALIFIED = (
    r"\b(?:beer|wine|spirits|liquor|whiske?y|vodka|weekdays?|weekends?|during|alone|drive|"
    r"driving|just|only|except|but|unless|until|week|home|out|much|a lot|often|very|heavily|"
    r"as much)\b|\bnot\s+(?:sober|teetotal\w*|a non ?drinker)\b"
)


def _alcohol(text: str, today: date) -> Found:
    # "I quit drinking 20 years ago": the years describe the quitting, not a count.
    quit_time = (
        r"\b\d+\s+year\s+ago\b|\b(?:in|since|back in)\s+'?\d{2,4}\b|"
        r"\b(?:sober|dry|quit|stopped)\s+(?:for\s+)?\d+\s+year(?:\s+now)?\b"
    )
    if _twice_daily(text) or re.search(NON_ALCOHOL, text):
        return None
    zero = re.search(ZERO_DRINKS, text)
    if zero and not re.search(r"\d", re.sub(quit_time, " ", text)):
        qualified = re.search(ZERO_QUALIFIED, re.sub(quit_time, " ", text))
        return None if qualified else _zero("alcohol_drinks_weekly", text)
    counts, spans, article = [], [], False
    for pattern, read in (
        (
            rf"(?:\bbetween\s+{N}(?:\s+{SIZE}{DRINK})?\s+and|{N}(?:\s+{SIZE}{DRINK})?(?:\s*(?:or|to|-)|,))"
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
    article = article or bool(re.search(r"\ba \d", text))  # "a bottle of wine", rewritten
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

# "120 over 80", "120/80", spoken without a joiner: "130 80"
BP_PAIR = r"(?<![\d.])(?<!-)(\d{2,3})(?:\s?(?:/|over|on)\s?|\s)(\d{2,3})(?![\d.]\d)(?:\s?mmhg)?"
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


AT_BIRTH = re.compile(r"\b(?:born|at birth|assigned)\b")
PREFER_NOT = re.compile(r"\b(?:prefer not to|rather not)(?:\s+(?:say|answer|tell))?\b")
SEX_FAMILIES = {
    # "wife" and "husband" describe a partner ("I have a wife"), never the person.
    "female": r"\b(?:female|woman|lady|gal|girl|(?:grand)?mother|grandma|granny|widow)\b",
    "male": (
        r"\b(?:male|man|guy|gentleman|gent|fella|fellow|chap|bloke|boy|(?:grand)?father|grandpa|"
        r"widower)\b"
    ),
}
# The forecast can only use female or male at birth; say so instead of guessing.
OTHER_SEX = re.compile(r"\b(?:intersex|non ?binary|both|neither|other)\b")


# "oh man", "man, that's personal", "7, man": exclamations, not answers.
INTERJECTION = (
    r"\b(?:oh|aw|ah|ooh|man oh|boy oh) (?:man|boy)\b|^(?:man|boy)\b(?=\s*,)|,\s*(?:man|boy)\s*$"
)
PARTNER = r"\b(?:married|wedded)\b|\b(?:have|got|with) an? (?:wife|husband|man|woman|boyfriend|girlfriend)\b"


def _sex(text: str) -> str | None:
    phrase = _plain(text)
    if phrase in {"f", "m"}:
        return {"f": "female", "m": "male"}[phrase]
    text = re.sub(INTERJECTION, " ", text)
    if _doubtful(text) or re.search(PARTNER, text):
        return None
    families: set[str] = set()
    for clause, _ in _own_clauses(text):
        found = {family for family, pattern in SEX_FAMILIES.items() if re.search(pattern, clause)}
        if found and (NEGATION.search(clause) or re.search(r"\b(?:used to|called)\b", clause)):
            return None
        # The question asks for sex at birth, so "born male" outweighs anything said after it.
        if len(found) == 1 and AT_BIRTH.search(clause):
            return found.pop()
        families |= found
    return families.pop() if len(families) == 1 else None


# "I'm trying to quit", "I never quit": wanting or failing to quit is not having quit.
QUIT_ATTEMPT = (
    r"\b(?:trying to|try to|tried to|want to|wanting to|wanna|going to|gonna|plan(?:ning)? to|"
    r"need to|should|thinking (?:about|of)|hope to|hoping to|can't|cannot|couldn't|never|"
    r"didn't|did not|haven't|have not|won't)\s+(?:quit(?:ting)?|stop(?:ping)?|give up|giving up)\b"
)
# "I quit my job", "stopped drinking": quitting something else is no smoking answer.
NOT_SMOKING_OBJECT = (
    r"(?!\s+(?:my|his|her|our|their|work\w*|job|drink\w*|alcohol|booze|eating|coffee|sugar|"
    r"the (?!cig|smok|habit|tobacco|pipe)))"
)
FORMER = (
    r"\b(?:(?:quit|quitted|stopped|gave up|given up)" + NOT_SMOKING_OBJECT + r"|used to|use to|"
    r"former|formerly|ex smoker|"
    r"gave (?:it|them|those|cigarettes|smoking) up|kicked the habit|was a smoker|"
    r"in the past|not since|haven't smoked (?:since|in)|(?:don't|do not|no longer) smoke "
    r"(?:anymore|any more))\b|\bsmoked\b[^,.;]*\buntil\b|"
    # "I haven't had one since 1988", "I smoked in the army"
    r"\bhaven't (?:had|touched|smoked)\b[^,.;]*\b(?:since|in)\b|"
    r"\bsmoked\b[^,.;]*\b(?:in the (?:army|navy|service|military|war)|in (?:college|school)|"
    r"as a (?:kid|teen\w*|young\w*)|in my (?:youth|decades)|years ago|back then|during)\b"
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
    "nope",
    "nah",
    "oh",
    "well",
}


# "I quit when my daughter was born": someone else only dates the person's own habit.
_IN_CLAUSE = r"(?:(?!\b(?:but|and|though|although|except)\b)[^,;.!?])"
LIFE_EVENT = (
    rf"\b(when|after|before|since|until|till)\b{_IN_CLAUSE}*?\b(?:my|our)\s+(?:\w+\s+)?"
    rf"{PEOPLE}\b{_IN_CLAUSE}*"
)


QUIT_INTENT = (
    r"\b(?:trying to|try to|want to|wanting to|wanna|going to|gonna|plan(?:ning)? to|need to|"
    r"thinking (?:about|of)|hope to|hoping to)\s+(?:quit(?:ting)?|stop(?:ping)?|give up)\b"
    r"(?!\s+(?:drinking|alcohol|booze|eating|sugar))"
)
# Cigars and pipes are smoking too: "never smoked cigarettes, only cigars".
CIGARS_NOW = (
    r"\b(?:only|now|just|still)\b[^,.;]*\b(?:cigars?|cigarillos?|pipes?)\b|"
    r"\b(?:cigars?|cigarillos?|pipes?)\b(?:[^,.;]*|,\s*)\b(?:only|now|yes|still)\b"
)
RESUMED = (
    r"\b(?:started|starting|smoking|smoke) (?:up )?again\b|\bback (?:to|on) (?:smoking|cigarettes|"
    r"the cigarettes)\b|\brelapsed\b|\bpicked (?:it|them) back up\b"
)


def _smoking(text: str) -> str | None:
    phrase = _plain(text)
    if phrase in SEX_PREFER_NOT or phrase == "unknown":
        return "unknown"
    # "trying to quit", "I want to quit": still smoking.
    attempt = re.search(QUIT_INTENT, text)
    text = re.sub(QUIT_ATTEMPT, " ", text)
    text = re.sub(LIFE_EVENT, r"\1 then ", text)
    text = re.sub(r"\bnot (?:once|even once|1 time|a single time)\b", "never", text)
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
    # "I smoked a pack a day" may be long past; "I've smoked" is still going.
    past = re.search(r"(?<!'ve )(?<!have )(?<!has )\bsmoked\b", present)
    current = (
        re.search(CURRENT, present)
        or (re.search(SMOKING_RATE, present) and not past)
        or re.search(OCCASIONAL, present)
    )
    current = current or attempt
    if re.search(CIGARS_NOW, own):
        return "current"
    never = [clause for clause in clauses if re.search(r"\bnever\b", clause)]
    # "I used to smoke but started again": the last change counts.
    resumed = [m.start() for m in re.finditer(RESUMED, own)]
    if resumed and not never:
        stopped = [m.start() for m in re.finditer(FORMER, own)]
        return "current" if max(resumed) > max(stopped, default=-1) else None
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
    r"\banymore\b|\bruled (?:it |that )?out\b|\binsipidus\b|\bpcos\b|\bpolycystic\b|"
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
    if field == "sex" and (phrase in SEX_PREFER_NOT or PREFER_NOT.search(phrase)):
        return True  # there is no "prefer not to say" answer; it is a skip
    if field in BP_FIELDS and phrase in BP_NO:
        return True
    return phrase in SKIP_WORDS


MEASURE_UNIT = r"(?:year old|year|ft|inch|cm|m|kg|lb|stone|hour|minute|drinks?)"
# "I'm 71, not 72", "not 72, 71": the number after "not" is the one being replaced.
# ("5 10 no 6 foot" names the new value instead; two values are asked about.)
CORRECTED = (
    rf"(?:,\s*)?\bnot\s+{NUM}(?:\s?{MEASURE_UNIT})?(?:\s{NUM}(?:\s?{MEASURE_UNIT})?)?"
    r"(?=\s*(?:$|[,;.!]|but\b))"
)


def _drop_correction(text: str) -> str:
    dropped = re.sub(CORRECTED, " ", text)
    return dropped if re.search(r"\d", dropped) else text


# "70, no, 71", "6 hours, sorry, 7 hours", "150, I mean 155 pounds", "I'm 74, 75 actually":
# a value said and corrected straight away; the later one is the answer.
_VALUE = rf"\d+(?:\.\d+)?(?:\s?(?P<unit>{MEASURE_UNIT}))?(?:\s\d{{1,2}}(?:\.\d+)?(?:\s?inch)?)?"
_CORRECTION_NO = r"(?:no|nope|oh no)"
_CORRECTION_CUE = (
    r"(?:wait|sorry|i'm sorry|i mean|i meant|actually|or rather|rather|correction|"
    r"scratch that|make that|make it)"
)
SELF_CORRECTION_WORDS = rf"(?:{_CORRECTION_NO}|{_CORRECTION_CUE})"
# A bare "no" counts only set off by punctuation, as transcripts write it: "5 10 no 6 foot"
# typed without any is asked about.
_CORRECTION = (
    rf"(?:[,.;]\s*)?(?:{_CORRECTION_NO}\s+)?{_CORRECTION_CUE}\b[,.;]?"
    rf"|[,.;]\s*{_CORRECTION_NO}\b[,.;]?|{_CORRECTION_NO}[,.;]"
)
SELF_CORRECTED = (
    rf"(?<![\d.:/])(?:{_VALUE})\s*(?:(?:{_CORRECTION})\s*)+"
    rf"(?=(?:(?:i'm|i am|it's|it is) )?(?P<next>{_VALUE.replace('unit', 'unit2')}))"
    rf"|(?<![\d.:/])(?:{_VALUE.replace('unit', 'unit3')})\s*[,.;]\s*"
    rf"(?=(?P<last>{_VALUE.replace('unit', 'unit4')})\s+actually[.!]?\s*$)"
)


def _drop_self_correction(text: str) -> str:
    """Keep only the corrected value, when both are the same kind of measurement."""

    def drop(match: re.Match) -> str:
        first = match.group("unit") or match.group("unit3")
        second = match.group("unit2") or match.group("unit4")
        if first and second and first.rstrip("s") != second.rstrip("s"):
            return match.group(0)
        return " "

    for _ in range(3):  # "70, no, 71, no, 72"
        dropped = re.sub(SELF_CORRECTED, drop, text)
        if dropped == text:
            break
        text = dropped
    return " ".join(text.split())


# "Not much, maybe 4", "not a lot. 90 minutes a week": a modest word before the number
# itself. Only at the start, so "more than 7" and "not much exercise" still count.
MODEST_LEAD = r"^(?:oh,? )?not (?:(?:that |very |too )?much|(?:a )?(?:whole )?lot|many)\b[\s,.;:-]*(?=[^\d]*\d)"
# "I used to be 5'9", I'm 5'8" now", "I was 200 pounds, now I'm 185": an old value set
# against one marked as now. Only the now value is read; nothing else may hold a number.
PAST_CLAUSE = re.compile(
    r"\b(?:used to|use to|was|were|weighed|slept|walked|drank|exercised|ago|back then)\b"
)
NOW_CLAUSE = re.compile(r"\b(?:now|these days|nowadays|currently|at the moment|right now)\b")
NOW_AFTER_PAST = {"height_cm", "weight_kg", "sleep_hours", "exercise_minutes_weekly"}


def _now_after_past(text: str) -> str:
    clauses = [(start, end) for start, end, _ in _clauses(text)]
    past = [
        (a, b)
        for a, b in clauses
        if PAST_CLAUSE.search(text[a:b]) and not NOW_CLAUSE.search(text[a:b])
    ]
    now = [
        (a, b)
        for a, b in clauses
        if NOW_CLAUSE.search(text[a:b]) and not PAST_CLAUSE.search(text[a:b])
    ]
    numbered = {(a, b) for a, b in clauses if re.search(r"\d", text[a:b])}
    if not past or len(now) != 1 or not numbered <= set(past) | set(now) or not numbered & set(now):
        return text
    a, b = now[0]
    text = _blank(text, past)
    return text[:a] + NOW_CLAUSE.sub(" ", text[a:b]) + text[b:]


def parse_value(field: ProfileField, text: str, *, today: date | None = None) -> dict:
    """Accept explicit, current, single answers; do not guess units or diagnoses."""
    today = today or date.today()
    canonical = _drop_correction(_canonical(text))
    if field in BP_FIELDS:
        # A corrected half of a reading ("130 over 80, no, 85") is asked about.
        return _blood_pressure(field, canonical)
    if field not in CATEGORICAL:
        canonical = re.sub(MODEST_LEAD, "", _drop_self_correction(canonical))
    if field in NOW_AFTER_PAST:
        canonical = _now_after_past(canonical)
    if field == "sex":
        sex = _sex(canonical)
        return _validated({field: sex}) if sex else {}
    if field == "smoking_status":
        status = _smoking(canonical)
        return _validated({field: status}) if status else {}
    if field == "diabetes":
        answer = _diabetes(canonical)
        return {} if answer is None else _validated({field: answer})
    if field == "weight_kg":
        canonical = re.sub(
            SPLIT_POUNDS, lambda m: str(int(m.group(1)) * 100 + int(m.group(2))), canonical
        )
    found = NUMERIC[field](canonical, today)
    if not found or not found[0]:
        return {}
    values, spans = found
    if any(abs(value - values[0]) > 1e-6 for value in values):
        return {}
    if not _clean_measurement(field, canonical, spans):
        return {}
    result: float | int = values[0]
    if field == "exercise_minutes_weekly":
        result = int(round(result))  # "25 minutes every 3 days": an estimate, read back
    elif field == "age":
        if abs(result - round(result)) > 1e-6:
            return {}
        result = int(round(result))
    else:
        result = round(result, 4)
    return _validated({field: result})


def _feet(inches: int) -> str:
    feet, rest = divmod(inches, 12)
    return f"{feet} feet" + (f" {rest} inch{'' if rest == 1 else 'es'}" if rest else "")


def birth_year_ages(text: str, *, today: date | None = None) -> tuple[int, int, str] | None:
    """(likelier age, other age, how to say it) for a birth year alone ("born in 1980").

    The year gives two possible ages. After midsummer most birthdays have passed,
    so the older one is offered first; the read-back lets the person correct it.
    """
    today = today or date.today()
    canonical = _canonical(text)
    if _doubtful(canonical) or OTHER_PERSON.search(canonical):
        return None
    readings = _age_readings(canonical, today) or []
    if len(readings) != 1 or len(readings[0][0]) != 2:
        return None
    ages, span, lead = readings[0]
    if re.search(r"\d", _blank(canonical, [span])):
        return None
    low, high = sorted(ages)
    if not _validated({"age": low}):
        return None
    late = today.timetuple().tm_yday > 182
    return (high, low, lead) if late else (low, high, lead)


def clarify(text: str, field: ProfileField, *, today: date | None = None) -> str | None:
    """Field-specific follow-up for an answer that is close but not safe to read.

    An answer with exactly two readings gets a question that names both.
    """
    if LONG_NUMBER.search(normalize_text(text)):
        return None
    if competing(normalize_text(text), field):
        return f"I heard more than one number. What is your own {FRIENDLY_LABELS[field]}?"
    canonical = _canonical(text)
    if _doubtful(canonical) or OTHER_PERSON.search(canonical):
        return None
    if field == "alcohol_drinks_weekly" and re.search(NON_ALCOHOL, canonical):
        return (
            "I only count alcoholic drinks, like beer, wine or spirits. "
            "How many of those do you have in a week? Say none if you have none."
        )
    if field in HABITS and SEASONAL.search(canonical):
        return "How much is that in a usual week, all year round?"
    # A past value, goal or advice gets no unit or how-often question.
    if _spoiled(field, canonical) or NOT_CURRENT.search(canonical):
        return None
    if field == "sex" and OTHER_SEX.search(canonical):
        return (
            "For the forecast I can only use female or male at birth. "
            "Which fits best? You can also skip this question."
        )
    if field == "age":
        readings = _age_readings(canonical, today or date.today()) or []
        if len(readings) == 1 and len(readings[0][0]) == 2:
            ages, span, lead = readings[0]
            low, high = sorted(ages)
            if not re.search(r"\d", _blank(canonical, [span])) and _validated({"age": low}):
                return f"{lead} means you're {low} or {high}. Which one?"
    numbers = re.findall(rf"(?<![\d.]){NUM}(?!\d)", canonical)
    bare = None
    if len(numbers) == 1 and re.search(
        rf"(?<![\d.]){NUM}(?!\d)"
        r"(?!\s?(?:ft|inch|cm|m|kg|lb|stone|hour|minute|year|over|/|drinks?|times?|x|days?)\b)",
        canonical,
    ):
        bare = numbers[0]
    if field == "weight_kg" and bare:
        return (
            f"Is that {bare} pounds or {bare} kilograms? Please say the number "
            f'with the unit, like "{bare} pounds".'
        )
    if field == "height_cm" and bare and re.fullmatch(r"4[89]|[56]\d", bare):
        # "62": 6 feet 2 inches, or 62 inches.
        return (
            f"Do you mean {_feet(int(bare[0]) * 12 + int(bare[1]))}, or {bare} inches "
            f"({_feet(int(bare))})?"
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
        and len(numbers) == 1
        and re.search(r"\bweekends?\b", canonical)
    ):
        n = float(numbers[0])
        return (
            f"Is that {n:g} drinks over the whole weekend, or {n:g} on each day ({2 * n:g} in all)?"
        )
    if field == "alcohol_drinks_weekly" and (
        (not numbers and re.search(rf"\b(?:a|an)\s+{SIZE}{DRINK}", canonical))
        or re.fullmatch(rf"(?:\D*\s)?a \d+(?:\.\d+)? {DRINK}\D*", canonical)  # "a bottle of wine"
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


LABELED = r"\s*([a-z_ ]+?)\s*[:=]\s*(.+)\s*"
CORRECTION_CUE = r"\b(?:actually|i meant|sorry)\b|\bnot\s+\d"
SELF_AGE = r"\b(?:i'm|i am)\s+\d{2,3}(?![\d.])(?!\s?(?:ft|inch|cm|m|kg|lb|stone|hour|minute)\b)"
SEX_CUE = r"\b(?:female|male|woman|man)\b"
# Beside another answer, "man" is often an exclamation ("7 hours, oh man").
SEX_CUE_OTHER = r"\b(?:female|male)\b|\b(?:i'm|i am) an? (?:wo)?man\b|^an? (?:wo)?man$"
# "74 male", "female 68": a sex word and a bare number are two answers.
SEX_AND_NUMBER = (
    r"\b(\d{2,3}) (?=(?:female|male|woman|man)\b)|\b(female|male|woman|man) (?=\d{2,3}\b)"
)


def _part_fields(part: str, asked: ProfileField, several: bool) -> set[str]:
    """The fields one part of a reply names, by topic words, else by units."""
    text = _canonical(part)
    named = {topic for topic, cue in TOPICS.items() if re.search(cue, text)}
    named |= {"sex"} if re.search(SEX_CUE if asked == "sex" else SEX_CUE_OTHER, text) else set()
    if not named:
        # "for ten years" is how long, never an age.
        named = {t for t, cue in TOPIC_UNITS.items() if t != "age" and re.search(cue, text)}
    # "I'm 70" is an age beside another answer, as a correction ("actually I'm 71,
    # not 72"), or where the question has no number for an answer ("female and 68").
    bare_age = (
        re.fullmatch(r"(?:i'm |i am )?\d{2,3}(?: year(?: old)?)?", text) and asked in CATEGORICAL
    )
    if not named and asked != "age" and (bare_age or re.search(SELF_AGE, text)):
        if bare_age or several or re.search(CORRECTION_CUE, text) or asked in CATEGORICAL:
            return {"age"}
    # A number for a question nobody asked needs its unit: "class of 1998" is no exercise.
    named = {
        topic
        for topic in named
        if topic in CATEGORICAL | {_topic(asked), "alcohol_drinks_weekly"}
        or re.search(TOPIC_UNITS[topic], text)
    }
    bp = asked if asked in BP_FIELDS else "systolic_bp"
    return {bp if topic == "blood_pressure" else topic for topic in named}


# No answer has seven digits in a row; refusing them early keeps huge inputs cheap.
LONG_NUMBER = re.compile(r"\d{7,}")
# Sentence ends, but not the dot of "5 ft. 7 in."
SENTENCE_END = (
    r"(?<!\bft)(?<!\bin)(?<!\blb)(?<!\blbs)(?<!\bst)(?<!\bdr)(?<!\bmr)(?<!\bmrs)[.!?]+(?=\s|$)"
)


def _others(text: str) -> bool:
    # "quit when my daughter was born": someone else only dates the person's own answer.
    plain = re.sub(LIFE_EVENT, r"\1 then ", _canonical(text))
    return bool(OTHER_PERSON.search(plain) or NAME_SUBJECT.search(text))


def _mine(text: str) -> bool:
    """Whether the words say "I" or "my" outside any mention of someone else
    (a hedge such as "I mean" or "I think" does not count)."""
    own = OTHER_PERSON.sub(" ", _canonical(text))
    own = _unhedged(re.sub(r"\bi mean\b|\bnot (?:me|mine|my\w*)\b", " ", own))
    return bool(FIRST_PERSON.search(own))


def corrects(text: str, field: ProfileField) -> bool:
    """An explicit correction that names the field: "actually I'm 71, not 72"."""
    canonical = _canonical(normalize_text(text))
    if not re.search(CORRECTION_CUE, canonical):
        return False
    if field == "age" and re.search(SELF_AGE, canonical):
        return True
    cues = [TOPICS.get(_topic(field), NOTHING), TOPIC_UNITS.get(_topic(field), NOTHING)]
    if field == "sex":
        cues.append(r"\b(?:female|male)\b")
    return any(re.search(cue, canonical) for cue in cues)


# Two numbers joined as alternatives or a range: the value is their middle.
RANGE = re.compile(
    r"\b(?:about|around|roughly|approximately|approx|give or take|or so|maybe|probably|"
    r"depends)\b|"
    r"\bbetween\b|(?<![:\d])\d+(?:\.\d+)?(?: [a-z]+){0,2} (?:or|to|-) (?:an? |\d)|\ban? \w+ or \d|"
    r"(?<![:\d.])\d+, \d+(?: [a-z]+)? (?:hour|drinks?|beers?|glass(?:es)?)\b"
)


def approximate(text: str) -> bool:
    return bool(RANGE.search(_canonical(normalize_text(text))))


def competing(text: str, field: ProfileField) -> bool:
    """Someone else's number beside a number for this question ("My brother is 6 foot.
    I'm 5'4"). In a room full of voices it may not be the person's own answer."""
    if field in CATEGORICAL:
        return False
    pieces = [p for p in re.split(rf"{SENTENCE_END}|[;,]|\s+and\s+", text, flags=re.I) if p]
    theirs = [p for p in pieces if p.strip() and _others(p)]
    numbered = [p for p in pieces if re.search(r"\d", _canonical(p))]
    return any(re.search(r"\d", _canonical(p)) for p in theirs) and len(numbered) > 1


def parse_reply(
    text: str, field: ProfileField, *, today: date | None = None, strict: bool = False
) -> dict:
    """Handle a short answer, or clauses that each say what they answer.

    A clause names another field by its topic or unit ("I weigh 160 pounds" to
    the age question); clauses only about someone else are left out. ``strict``
    (a voice transcript) also refuses when someone else's number competes.
    """
    text = normalize_text(text)
    if LONG_NUMBER.search(text) or (strict and competing(text, field)):
        return {}
    # "I'm 70. My wife, 72": sentences about someone else are left out, and what is
    # left must be said about oneself ("No. My mother, yes." answers nothing).
    sentences = [part for part in re.split(SENTENCE_END, text) if part.strip()]
    if any(_others(part) for part in sentences):
        mine = (
            [part for part in sentences if not _others(part)] if len(sentences) > 1 else sentences
        )
        # "no, but my husband does": a no set against someone else is the person's own.
        contrast = re.match(r"\W*(?:no|nope|never|not me)\b[^.]*\bbut\b", _canonical(text))
        if not mine or not (_mine(" ".join(mine)) or (len(sentences) == 1 and contrast)):
            return {}
        text = ". ".join(part.strip() for part in mine)
    # One measurement may contain commas or "and" ("5 feet, 10 inches").
    whole = parse_value(field, text, today=today)
    split = re.sub(SEX_AND_NUMBER, lambda m: (m.group(1) or m.group(2)) + ", ", text, flags=re.I)
    parts = [part for part in re.split(r"[;,]|\s+and\s+", split, flags=re.I) if part.strip()]
    labeled = any(re.fullmatch(LABELED, part, re.I) for part in parts)
    own = [part for part in parts if not _others(part)]
    dropped = bool(own) and len(own) < len(parts) and not labeled
    parts = own if dropped else parts
    several = len(parts) > 1
    values: dict = {}
    for part in parts:
        label = re.fullmatch(LABELED, part, re.I)
        if label:
            target = LABELS.get(label.group(1).lower())
            if target is None:
                return {}
            part = label.group(2)
        else:
            named = _part_fields(part, field, several)
            if not several and not dropped and (not named or field in named):
                return whole
            # Unlabeled leftovers may contradict a labeled measurement. Never
            # discard "80" from "weight: 70 kg and 80", for example.
            target = (
                field
                if field in named or (not named and not labeled)
                else next(iter(named))
                if len(named) == 1
                else None
            )
        parsed = parse_value(target, part, today=today) if target else {}
        if not parsed:
            return whole
        # Contradictory repeated values require clarification of the whole turn,
        # unless the reply read as one answer ("30 minutes 4 days and an hour on Saturday").
        if any(key in values and values[key] != val for key, val in parsed.items()):
            return whole
        values.update(parsed)
    return values if whole.items() <= values.items() else {}


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


def _raw_spans(text: str) -> list[tuple[int, int]]:
    breaks = [0, *(m.end() for m in RAW_BREAK.finditer(text))]
    ends = [m.start() for m in RAW_BREAK.finditer(text)] + [len(text)]
    return list(zip(breaks, ends, strict=True))


def _categorical_blocked(field: str, text: str) -> bool:
    """Words anywhere in the reply that make a quoted yes/no or category unsafe."""
    if field == "diabetes":
        return bool(re.search(DIABETES_UNCLEAR, text))
    if field == "sex":
        return bool(re.search(PARTNER, text) or OTHER_SEX.search(text))
    return bool(re.search(CIGARS_NOW, text) or re.search(RESUMED, text))


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
    if (
        LONG_NUMBER.search(text)
        or _doubtful(_canonical(text))
        or NOT_CURRENT.search(_canonical(text))
    ):
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
            # The quote's whole clause must read the same: "80 come next Friday" is 79.
            said = parse_value(candidate.field, text[lo:hi], today=today).get(candidate.field)
            if said is not None and said != quote_values[candidate.field]:
                return {}
        if any(key in values and values[key] != value for key, value in quote_values.items()):
            return {}
        covered += occurrences
        values.update(quote_values)
    # The rest of the reply may not make the values someone else's, past, a goal or
    # advice: "160 pounds. That's what my wife weighs.", "7 hours. Sometimes less."
    clauses = [text[lo:hi] for lo, hi in _raw_spans(text)]
    if any(_others(clause) for clause in clauses):
        if not _mine(" ".join(clause for clause in clauses if not _others(clause))):
            return {}
    rest = _canonical(_blank(text, covered))
    for field, value in values.items():
        if field in CATEGORICAL:
            if _categorical_blocked(field, rest):
                return {}
            settled = parse_reply(text, field, today=today).get(field)
            if settled is not None and settled != value:
                return {}
        elif _spoiled(field, rest) or VAGUE.search(_unhedged(rest)):
            return {}
    # Clauses the provider did not quote may not hold a competing answer.
    topics = {_topic(field) for field in values}
    for lo, hi in _raw_spans(text):
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
