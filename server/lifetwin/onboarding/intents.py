"""What people say around answers: fillers, conversation control and read-back replies.

Everything here runs before value parsing, so "say that again", "go back" or
"is 72 old?" is never read as an answer, and a read-back is confirmed only by
an unmistakable yes.
"""

import re
from dataclasses import dataclass
from typing import Literal

from lifetwin.onboarding.models import ProfileField
from lifetwin.onboarding.parsing import (
    ADVICE,
    FIELD_CUES,
    HYPOTHETICAL,
    NO_WORDS,
    NOT_CURRENT,
    NOTHING,
    PAST_SPOIL,
    REPORTED,
    SEASONAL,
    SELF_CORRECTION_WORDS,
    SENTENCE_END,
    SEX_FAMILIES,
    TENS_WORDS,
    TOPICS,
    UNCERTAIN,
    UNITS_WORDS,
    VAGUE,
    YES_WORDS,
    _base,
    _canonical,
    _others,
    _topic,
    _unhedged,
    is_skip,
    normalize_text,
)

# ---------------------------------------------------------------------------
# Fillers and transcript noise
# ---------------------------------------------------------------------------

# "uh huh" (yes) and "uh uh" (no) are answers, never filler. "Oh" and "ah" stay:
# "oh man" is an exclamation, and without the "oh" it would read as an answer.
FILLER_WORD = re.compile(
    r"(?<!\buh )(?<!\bmm )(?<!\bm )\b(?:u+m+|u+h+|e+r+m*|h+m+)\b(?! (?:huh|uh)\b)", re.I
)
FILLER_PHRASE = re.compile(
    r"\b(?:let me (?:think|see)|lemme (?:think|see)|let's see|hold on|hang on|"
    r"give me a (?:second|sec|minute|moment)|just a (?:second|sec|minute|moment))\b",
    re.I,
)
# Only at the start: "I sleep well" and "not so much" keep their words.
LEAD_IN = re.compile(
    r"^(?:(?:well|so|okay so|ok so|alright so|all right so|okay well|ok well|oh well)\b"
    r"|(?:okay|ok|alright|all right)\b(?=[\s,.;:!-]+\S))[\s,.;:!-]*",
    re.I,
)
TRAILING_POLITE = re.compile(
    r"(?:[\s,]+(?:dear|dearie|honey|sweetie|sweetheart|darling|please|thanks|thank you)"
    r"|,\s*(?:love|hon|mate))+$",
    re.I,
)
# Number words are never stutters: "five five" is a height.
KEEP_DOUBLED = {*UNITS_WORDS, *TENS_WORDS, "hundred", "uh", "mm", "hm"}
DOUBLED = re.compile(r"\b([a-z']+(?: [a-z']+)?)(?:[\s,]+\1)+(?![\w'])", re.I)
# "I I'm 72", "it it's": a word cut off and said again.
STUTTER = re.compile(r"\b([a-z]+)[\s,]+(?=\1'[a-z]+\b)", re.I)


def _undouble(match: re.Match) -> str:
    words = match.group(1).lower().split()
    return match.group(0) if any(word in KEEP_DOUBLED for word in words) else match.group(1)


def clean_reply(text: str) -> str:
    """Remove fillers, stutters and transcript punctuation without changing meaning.

    A question mark is kept: it marks a question back, never an answer.
    """
    original = " ".join(text.split())
    s = re.sub(r"\b(uh|mm|um)-(huh|hmm|hm|uh)\b", r"\1 \2", original, flags=re.I)
    s = re.sub(r"…|\.{2,}", " ", s)
    s = FILLER_PHRASE.sub(" ", s)
    s = FILLER_WORD.sub(" ", s)
    s = re.sub(r"^[\s,.;:!-]+", "", s)
    for _ in range(4):
        s = LEAD_IN.sub("", s)
    s = STUTTER.sub("", s)
    s = DOUBLED.sub(_undouble, s)
    s = re.sub(r"\s+([,.;!?])", r"\1", s)
    s = re.sub(r"([,;])(?:\s*[,;])+", r"\1", s)
    s = re.sub(r"[\s,.;:!-]+$", "", s)
    s = TRAILING_POLITE.sub("", s)
    s = " ".join(re.sub(r"[\s,.;:!-]+$", "", s).split())
    return s or original


def phrase(text: str) -> str:
    """Lower-case words only, without politeness around them, for whole-phrase matching."""
    s = " ".join(re.sub(r"[^\w'\s]", " ", text.lower()).split())
    s = re.sub(r"\blets\b", "let's", s)  # transcripts drop this apostrophe too
    for _ in range(3):
        s = re.sub(
            r"^(?:please|sorry|can you please|could you please|would you please|"
            r"can you|could you|would you|will you|would you mind|do you mind)\s+(?=\S)",
            "",
            s,
        )
        s = re.sub(
            r"\s+(?:please|dear|dearie|honey|sweetie|sweetheart|darling|love|thanks|thank you|"
            r"sorry|for me)$",
            "",
            s,
        )
    return s


def _units(*parts: str) -> str:
    # Longest first, so "that's right" wins over "that's".
    return "|".join(sorted(parts, key=len, reverse=True))


# ---------------------------------------------------------------------------
# Conversation control
# ---------------------------------------------------------------------------

REPEAT = _units(
    "what",
    "what now",
    "huh",
    "eh",
    "pardon",
    "pardon me",
    "beg pardon",
    "beg your pardon",
    "i beg your pardon",
    "sorry",
    "excuse me",
    "you what",
    "come again",
    "again",
    "one more time",
    "once more",
    "what was that",
    "what's that",
    "what did you say",
    "what did you just say",
    "what was the question",
    "what's the question",
    "what is the question",
    "what question",
    "what was it",
    "say again",
    "say that again",
    "say it again",
    "say the question again",
    "say that one more time",
    "ask me again",
    "ask that again",
    "ask the question again",
    "ask me that again",
    "repeat",
    "repeat that",
    "repeat it",
    "repeat yourself",
    "repeat the question",
    "repeat the last part",
    "repeat that question",
    "run that by me again",
    "i didn't catch that",
    "i didn't catch it",
    "i didn't catch the question",
    "didn't catch that",
    "i didn't hear that",
    "i didn't hear you",
    "i didn't hear the question",
    "i didn't get that",
    "i didn't get the question",
    "i missed that",
    "i missed it",
    "i missed the question",
    "missed that",
    "what did you ask",
    "what did you ask me",
    "can you repeat",
)
LOUDER = _units(
    "i can't hear you",
    "i cannot hear you",
    "i can not hear you",
    "i couldn't hear you",
    "i can't hear that",
    "i can't hear it",
    "i can't hear a thing",
    "i can't hear anything",
    "i can't hear you very well",
    "i can't hear you well",
    "can't hear you",
    "cannot hear you",
    "i can barely hear you",
    "barely hear you",
    "speak up",
    "talk louder",
    "speak louder",
    "louder",
    "a bit louder",
    "a little louder",
    "little louder",
    "you're too quiet",
    "you're quiet",
    "too quiet",
    "turn it up",
    "turn the volume up",
    "turn yourself up",
    "volume up",
    "i'm hard of hearing",
    "i'm a bit deaf",
    "i'm a little deaf",
)
SLOWER = _units(
    "slow down",
    "slow it down",
    "slower",
    "a bit slower",
    "a little slower",
    "little slower",
    "slowly",
    "more slowly",
    "speak slower",
    "speak slowly",
    "speak more slowly",
    "talk slower",
    "talk slowly",
    "talk more slowly",
    "go slower",
    "go slowly",
    "say it slower",
    "say it slowly",
    "say it more slowly",
    "read it slower",
    "read it slowly",
    "too fast",
    "not so fast",
    "you're too fast",
    "you're talking too fast",
    "you're talking so fast",
    "you're speaking too fast",
    "you're going too fast",
    "you talk too fast",
    "you talk fast",
    "talking too fast",
)
HELP = _units(
    "help",
    "help me",
    "i need help",
    "i don't understand",
    "i don't understand the question",
    "i don't understand that",
    "i don't understand you",
    "i don't understand this",
    "i don't understand this question",
    "i don't understand what you mean",
    "i don't understand what you're asking",
    "i don't understand what you want",
    "i don't get it",
    "i don't get the question",
    "i don't follow",
    "i'm confused",
    "i am confused",
    "confused",
    "i'm lost",
    "what do you mean",
    "what do you mean by that",
    "what does that mean",
    "what does this mean",
    "what does it mean",
    "what's that mean",
    "what are you asking",
    "what are you asking me",
    "what do you want",
    "what do you want me to say",
    "what do you want to know",
    "what should i say",
    "explain",
    "explain that",
    "explain it",
    "explain the question",
    "how do i answer",
    "how do i answer that",
    "how do i answer this",
    "i'm not sure what you mean",
    "not sure what you mean",
    "i don't know what you mean",
    "i don't know what you're asking",
    "i'm not sure what you're asking",
    "i don't know what to say",
    "what kind of answer",
    "what kind of answer do you want",
    "how should i answer",
)
WHY = _units(
    "why",
    "why's that",
    "why do you ask",
    "why do you need this",
    "why do you need that",
    "why do you need it",
    "why do you need to know",
    "why do you need to know that",
    "why do you need to know this",
    "why do you want to know",
    "why do you want to know that",
    "why do you want this",
    "why would you need that",
    "why did you need that",
    "why did you need this",
    "why did you need all that",
    "why did you ask that",
    "why would you need to know that",
    "why are you asking",
    "why are you asking me",
    "why are you asking that",
    "why are you asking me that",
    "why does it matter",
    "why does that matter",
    "why is that important",
    "what's this for",
    "what's that for",
    "what is this for",
    "what is that for",
    "what do you need this for",
    "what do you need that for",
    "what do you need it for",
    "what are you going to do with this",
    "what are you going to do with that",
    "what will you do with this",
    "what will you do with that",
    "what will you do with my answers",
    "do i have to answer",
    "do i have to answer that",
    "do i have to answer this",
    "do i have to tell you",
    "is this necessary",
)
PRIVATE = _units(
    "is this private",
    "is that private",
    "is it private",
    "is this safe",
    "is it safe",
    "is this secure",
    "is this confidential",
    "is this secret",
    "is my information private",
    "is my information safe",
    "is my data private",
    "is my data safe",
    "is my info safe",
    "are my answers private",
    "are my answers safe",
    "is this being recorded",
    "is this recorded",
    "is this saved",
    "is this stored",
    "are you recording",
    "are you recording me",
    "are you recording this",
    "are you saving this",
    "are you listening",
    "who sees this",
    "who can see this",
    "who will see this",
    "who sees my answers",
    "who can see my answers",
    "who reads this",
    "who gets this",
    "where does this go",
    "where does it go",
    "where does my information go",
    "will you share this",
    "will you share my information",
    "will you sell my information",
    "do you share this",
    "do you share my information",
    "do you sell my information",
    "do you keep this",
    "do you store this",
    "what about my privacy",
    "privacy",
    "my privacy",
    "is this between us",
    "private",
    "confidential",
)
RESTART = (
    r"(?:(?:please|okay|ok)\s+)*"
    r"(?:let's |let us |can we |could we |i want to |i'd like to |i wanna |we should |"
    r"i need to |just )?"
    r"(?:start (?:all )?over(?: again)?|start again|start afresh|start from (?:the )?beginning|"
    r"start from scratch|start from the top|begin again|from the top|from the beginning|"
    r"restart|reset|do it (?:all )?again|start the whole thing over|"
    r"clear (?:everything|it all|all|all my answers|my answers)|erase (?:everything|it all|"
    r"my answers)|wipe (?:it|everything)(?: clean)?|go back to the (?:beginning|start)|"
    r"back to the (?:beginning|start))"
)
# Only an explicit yes said with the request itself clears anything: a bare "yes"
# on the next turn answers the question or read-back that was asked again.
_SURE = r"(?:yes|yeah|yep|yup|yes please|yes i'm sure|i'm sure)"
_CLEAR = r"(?:clear|erase|wipe) (?:everything|it all|all|all my answers|my answers)"
_AGAIN = r"(?:start (?:all )?over|start again|begin again|start from the beginning)"
RESTART_CONFIRMED = (
    rf"{_SURE} (?:{RESTART})|(?:{RESTART}) {_SURE}"
    rf"|(?:{_SURE} )?{_CLEAR} and {_AGAIN}|(?:{_SURE} )?{_AGAIN} and {_CLEAR}"
)
GO_BACK = (
    r"(?:wait |oops |hang on |sorry )?"
    r"(?:(?:can we |could we |let's |let me |i want to |i'd like to |i need to )?go back"
    r"(?: one| a step| one question| to the (?:last|previous) (?:one|question|answer))?"
    r"|back|previous question|the (?:last|previous) question"
    r"|the (?:last|previous) (?:one|answer) (?:was|is) wrong"
    r"|that last (?:one|answer) (?:was|is) wrong"
    r"|i made a mistake(?: (?:on|with|in) the (?:last|previous) (?:one|question|answer))?"
    r"|i made an error|i messed up(?: the last one)?|i got the (?:last|previous) one wrong"
    r"|i (?:said|gave) the wrong (?:answer|thing|number)(?: before)?"
    r"|(?:can i |i want to |let me )?(?:change|fix|redo|correct) (?:my |the )?"
    r"(?:last|previous) (?:one|answer|question)|undo(?: that)?)"
)
# Spoken names for each question; the blood pressure question is about both numbers.
FIELD_NAMES: dict[ProfileField, str] = {
    "age": r"age|how old i am",
    "sex": r"sex|gender",
    "height_cm": r"height|how tall i am",
    "weight_kg": r"weight",
    "sleep_hours": r"sleep|sleeping|hours of sleep",
    "exercise_minutes_weekly": r"exercise|exercising|activity|workouts?",
    "smoking_status": r"smoking|smoker|cigarettes",
    "alcohol_drinks_weekly": r"alcohol|drinking|drinks",
    "diabetes": r"diabetes|blood sugar",
    "systolic_bp": r"blood pressure|bp|top (?:blood pressure )?number",
    "diastolic_bp": r"bottom (?:blood pressure )?number",
    "general_health": r"general health|overall health|health rating|health",
    "hypertension_diagnosed": r"high blood pressure|hypertension",
    "sedentary_min_day": r"sitting|sitting time|sitting down|how much i sit",
    "moderate_recreation_min_week": r"lighter activity|light activity|light exercise|walking|walks",
    "vigorous_recreation_min_week": r"harder exercise|hard exercise|vigorous exercise|vigorous activity",
}
_NAME = "|".join(FIELD_NAMES.values())
_THE = r"(?:my |the |your )?"
_ANSWER = r"(?: answer| question| one| number| reading)?"
# One capture per form for the spoken name, mapped to a field afterwards.
CHANGE = re.compile(
    r"(?:wait |oops |sorry |actually )?(?:"
    r"(?:i want to |i'd like to |can i |could i |let me |let's |i need to |may i |we need to )?"
    r"(?:change|fix|correct|redo|update|edit|go back to|back to)(?: my answer (?:about|for|on))? "
    rf"{_THE}(?P<n1>{_NAME}){_ANSWER}(?: to (?P<r1>.+))?"
    rf"|{_THE}(?P<n2>{_NAME}){_ANSWER} (?:is|was|'s) wrong(?: (?P<r2>.+))?"
    rf"|you (?:got|have|put|wrote|heard) {_THE}(?P<n3>{_NAME}){_ANSWER} wrong(?: (?P<r3>.+))?"
    rf"|i made a mistake (?:on|with|in|about) {_THE}(?P<n4>{_NAME}){_ANSWER}(?: (?P<r4>.+))?"
    r")"
)
SKIP_REQUEST = (
    r"(?:can|could|may) (?:i|we) (?:skip|pass on|pass) (?:this|that|it)(?: one| question)?"
    r"|can (?:i|we) skip|i'd like to skip(?: this| that| this one)?|let's skip(?: this| that| it)?"
)
KEEP = (
    r"keep it|keep that|keep it as it is|keep it the same|leave it|leave it as it is|"
    r"leave it alone|it was right|that was right|it's fine|it was fine|never mind|nevermind|"
    r"no change|don't change it|it's right"
)
# A question back to the mascot ("is 72 old?"): never an answer, even with a number in it.
# Transcripts often drop the question mark, so a question's opening words are enough.
# (?![\w']) keeps "can't remember" and "isn't" from reading as "can" or "is".
QUESTION_START = re.compile(
    r"^(?:is|isn't|are|aren't|am i|was (?:that|it|i)|were you|does|doesn't|do you|do people|"
    r"do most|did you|did i|should (?:i|it|that|my|a|people)|can (?:you|i|it|that|a|my|people)|"
    r"could (?:you|it|that|i)|would (?:you|it|that)|will (?:you|it|that|i)|what's|whats|"
    r"what is|what are|what about|how much|how many|how old|how long|how tall|how do|how does|"
    r"how is|how's|which)(?![\w'])"
)
LOOSE_QUESTION_START = re.compile(r"^(?:what|how|who|when|where)(?![\w'])")
NOT_A_QUESTION = re.compile(r"^(?:how about|what i|how i|who knows|when i|where i)(?![\w'])")
# "I'm 72 is that old": a question tagged onto a number, with or without "?".
TAGGED_QUESTION = re.compile(
    r"\b(?:is|isn't) (?:that|it|this) (?:\w+ )?(?:old|young|normal|ok|okay|good|bad|high|low|"
    r"healthy|a lot|enough|too much|too little|alright|all right)\b"
    r"|\bam i (?:\w+ )?(?:old|ok|okay|normal|healthy|overweight|underweight)\b"
)


# "Can we talk about my sleep?", "let's do the sitting question": the person picks
# the topic. Each topic maps to the question it opens (``topic_field``).
TOPIC_NAMES: dict[str, str] = {
    r"(?:my |the |how i )?(?:sleep|sleeping)(?: question)?|how (?:much|well) i sleep": "sleep_hours",
    r"(?:my |the )?(?:general |overall )?health(?: question)?|how i feel": "general_health",
    r"(?:my |the )?(?:high )?blood pressure(?: question)?|(?:my )?hypertension": "hypertension_diagnosed",
    r"(?:my |the )?(?:diabetes|blood sugar)(?: question)?": "diabetes",
    r"(?:my |the )?(?:sitting|sitting time|sitting down)(?: question| part)?|how much i sit": (
        "sedentary_min_day"
    ),
    r"(?:my |the )?(?:exercise|exercising|activity|walking|walks|workouts?|moving)(?: questions?| part)?"
    r"|how active i am|what i do to stay active": "moderate_recreation_min_week",
    r"(?:my |the )?(?:harder|hard|vigorous) (?:exercise|activity)": "vigorous_recreation_min_week",
    r"(?:my |the )?(?:smoking|cigarettes)(?: question)?": "smoking_status",
    r"(?:my |the )?weight(?: question)?|how much i weigh": "weight_kg",
    r"(?:my |the )?height(?: question)?|how tall i am": "height_cm",
    r"(?:my |the )?age(?: question)?|how old i am": "age",
    r"(?:my |the )?(?:sex|gender)(?: question)?": "sex",
}
_TOPIC = "|".join(f"(?:{names})" for names in TOPIC_NAMES)
JUMP = re.compile(
    r"(?:actually |wait |oh |and |but )?"
    r"(?:(?:can|could|shall) we (?:please )?(?:talk about|go to|go back to|do|skip (?:ahead )?to|"
    r"move (?:on )?to|switch to|get to|jump to|chat about|discuss)"
    r"|let's (?:talk about|do|go to|move on to|skip (?:ahead )?to|switch to|chat about|get to)"
    r"|let me tell you about|i (?:want|wanted|would like|'d like) to (?:talk about|tell you about|"
    r"do|go to)|i'd (?:rather|prefer to) (?:talk about|do)|(?:what|how) about"
    r"|i have something to (?:say|tell you) about|talk about)"
    rf" (?P<topic>{_TOPIC})(?: (?:first|now|instead|next|for a minute|for a bit|then))?"
)


def topic_field(topic: str) -> ProfileField:
    return next(field for names, field in TOPIC_NAMES.items() if re.fullmatch(names, topic))


IntentKind = Literal[
    "repeat",
    "slower",
    "louder",
    "help",
    "why",
    "private",
    "restart",
    "restart_confirmed",
    "back",
    "skip",
    "ask",
    "jump",
]


@dataclass(frozen=True)
class Intent:
    kind: IntentKind
    field: ProfileField | None = None
    rest: str | None = None


def _full(pattern: str, words: str) -> bool:
    return re.fullmatch(f"(?:{pattern})", words) is not None


def _speech(text: str) -> IntentKind | None:
    """ "Slow down and speak up", "what? louder please": every piece asks for a repeat.

    The first request about how to speak wins; otherwise it is a plain repeat.
    """
    pieces = [phrase(piece) for piece in re.split(r"[,?!.;]|\band\b|\bthen\b", text.lower())]
    kinds = []
    for piece in filter(None, pieces):
        if _full(LOUDER, piece):
            kinds.append("louder")
        elif _full(SLOWER, piece):
            kinds.append("slower")
        elif _full(f"(?:{REPEAT})(?: (?:{REPEAT}))*", piece):
            kinds.append("repeat")
        else:
            return None
    return next((kind for kind in kinds if kind != "repeat"), "repeat" if kinds else None)


def control_intent(text: str) -> Intent | None:
    """A request about the conversation itself, recognized before any value is read."""
    words = phrase(text)
    if not words:
        return None
    speech = _speech(text)
    if speech:
        return Intent(speech)
    if _full(HELP, words):
        return Intent("help")
    if _full(PRIVATE, words):
        return Intent("private")
    if _full(WHY, words):
        return Intent("why")
    if _full(RESTART_CONFIRMED, words):
        return Intent("restart_confirmed")
    if _full(RESTART, words):
        return Intent("restart")
    if _full(GO_BACK, words):
        return Intent("back")
    change = CHANGE.fullmatch(words)
    if change:
        name = next(change.group(f"n{i}") for i in range(1, 5) if change.group(f"n{i}"))
        field = next(f for f, names in FIELD_NAMES.items() if re.fullmatch(names, name))
        said = any(change.group(f"r{i}") for i in range(1, 5))
        return Intent("back", field, _original_rest(text, field) if said else None)
    jump = JUMP.fullmatch(words)
    if jump:
        return Intent("jump", topic_field(jump.group("topic")))
    if _full(SKIP_REQUEST, words):
        return Intent("skip")
    if is_question_back(text):
        return Intent("ask")
    return None


def _original_rest(text: str, field: ProfileField) -> str | None:
    """The new answer after the field's name, with its own punctuation ("5.5 hours")."""
    named = re.search(rf"\b(?:{FIELD_NAMES[field]})\b", text, re.I)
    if not named:
        return None
    tail = re.sub(
        r"^\s*(?:answer|question|one|number|reading)?\s*"
        r"(?:(?:is|was|'s)\s+wrong|wrong|to)?[\s,:;.!-]*",
        "",
        text[named.end() :],
        flags=re.I,
    )
    return tail.strip() or None


def is_question_back(text: str) -> bool:
    # Politeness is kept: "can you tell me if 72 is old" is still a question.
    words = " ".join(re.sub(r"[^\w'\s]", " ", text.lower()).split())
    if TAGGED_QUESTION.search(words):
        return True
    if NOT_A_QUESTION.match(words):
        return False
    return bool(QUESTION_START.match(words)) or (
        text.rstrip().endswith("?") and bool(LOOSE_QUESTION_START.match(words))
    )


def keeps_answer(text: str) -> bool:
    """ "Never mind, keep it" to a question reopened by "go back"."""
    return _full(f"(?:{KEEP})(?: (?:{KEEP}))*", phrase(text))


# ---------------------------------------------------------------------------
# Replies to a read-back ("Age: 46. Is that right?")
# ---------------------------------------------------------------------------

YES = _units(
    "yes",
    "yeah",
    "yea",
    "yep",
    "yup",
    "ya",
    "yah",
    "aye",
    "uh huh",
    "mhm",
    "mhmm",
    "mm hmm",
    "mm hm",
    "m hm",
    "correct",
    "right",
    "exactly",
    "absolutely",
    "definitely",
    "certainly",
    "of course",
    "sure",
    "sure is",
    "sure thing",
    "spot on",
    "bang on",
    "perfect",
    "indeed",
    "true",
    "bingo",
    "affirmative",
    "right on",
    "you bet",
    "precisely",
    "for sure",
    "quite right",
    "right you are",
    "that's it",
    "that is it",
    "that's right",
    "that is right",
    "that's correct",
    "that is correct",
    "that's true",
    "that's me",
    "that's exactly right",
    "that's spot on",
    "that's what i said",
    "that's what i told you",
    "that sounds right",
    "sounds right",
    "looks right",
    "it's right",
    "it's correct",
    "yes it is",
    "yes i am",
    "i'm sure",
    "you got it",
    "you've got it",
    "you got it right",
    "you're right",
    "all correct",
    "yes sir",
    "yes ma'am",
    "yes indeed",
    "yes please",
    "that'll do",
)
NO = _units(
    "no",
    "noo",
    "nooo",
    "nope",
    "nah",
    "naw",
    "nay",
    "uh uh",
    "negative",
    "not quite",
    "not exactly",
    "not really",
    "not right",
    "not correct",
    "incorrect",
    "wrong",
    "that's wrong",
    "that is wrong",
    "that's not right",
    "that is not right",
    "that isn't right",
    "that's not correct",
    "that isn't correct",
    "that's incorrect",
    "that's not it",
    "that isn't it",
    "that's not me",
    "it's not",
    "it isn't",
    "it is not",
    "it's wrong",
    "that's not what i said",
    "i didn't say that",
    "you got it wrong",
    "you've got it wrong",
    "you heard wrong",
    "you heard me wrong",
    "you misheard",
    "you misheard me",
    "no way",
    "not at all",
    "not even close",
    "that's off",
    "that's way off",
    "definitely not",
    "absolutely not",
    "of course not",
    "no sir",
    "no ma'am",
    "i made a mistake",
    "that was wrong",
    "that's a mistake",
    "oops",
)
UNSURE = _units(
    "i guess",
    "i guess so",
    "yeah i guess",
    "yes i guess",
    "i suppose",
    "i suppose so",
    "maybe",
    "maybe so",
    "perhaps",
    "probably",
    "possibly",
    "i think",
    "i think so",
    "yes i think so",
    "yeah i think so",
    "i think that's right",
    "i believe so",
    "i hope so",
    "i'd say so",
    "kind of",
    "kinda",
    "sort of",
    "sorta",
    "more or less",
    "could be",
    "might be",
    "it might be",
    "that might be right",
    "ok",
    "okay",
    "alright",
    "all right",
    "fine",
    "good",
    "very good",
    "hmm",
    "sounds about right",
    "about right",
    "close enough",
    "something like that",
    "roughly",
    "got it",
    "if you say so",
    "whatever you think",
    "so so",
    "yes and no",
    "yeah no",
    "yes no",
)
# Words that may come before a corrected value: "no, 47", "close, it's 47".
LEADS = _units(
    "close",
    "close but",
    "almost",
    "actually",
    "wait",
    "sorry",
    "i said",
    "i meant",
    "i mean",
    "it should be",
    "should be",
    "make it",
    "change it to",
    "it's actually",
    "it's",
    "it is",
    "i'm actually",
)
CORRECTION_LEAD = re.compile(rf"^(?:(?:{NO}|{LEADS})(?![\w'])[\s,.;:!-]*)+", re.I)
YES_LEAD = re.compile(rf"^(?:(?:{YES})(?![\w'])[\s,.;:!-]*)+", re.I)
CONTRAST = re.compile(r"\b(?:but|no|not|nope|actually|except|wrong)\b|n't\b")

ReadBack = Literal["yes", "yes_value", "no", "unsure", "correction", "other"]


def read_back_reply(text: str) -> tuple[ReadBack, str]:
    """Classify a reply to a read-back; ``rest`` is the value said alongside it, if any.

    Nothing with a no, a doubt or a question in it is ever a yes.
    """
    words = phrase(text)
    asked = text.rstrip().endswith("?")
    if _full(f"(?:{NO})(?: (?:{NO}))*", words):
        return "no", ""
    if _full(f"(?:{YES})(?: (?:{YES}))*", words):
        return ("unsure" if asked else "yes"), ""
    if _full(UNSURE, words):
        return "unsure", ""
    yes = YES_LEAD.match(text.lower())
    if yes:
        rest = text[yes.end() :].strip()
        if CONTRAST.search(rest.lower()) or not re.search(r"\d", rest) or asked:
            return "unsure", rest
        return "yes_value", rest
    lead = CORRECTION_LEAD.match(text.lower())
    if lead:
        rest = text[lead.end() :].strip(" ,.;:!-")
        if not rest:
            return "no", ""
        # "no, that's right" contradicts itself: ask, never confirm or correct.
        rest_words = phrase(rest)
        if _full(f"(?:{YES})(?: (?:{YES}))*", rest_words) or _full(UNSURE, rest_words):
            return "unsure", rest
        return "correction", rest
    return "other", text


# ---------------------------------------------------------------------------
# Room chatter in transcripts
# ---------------------------------------------------------------------------

# Words that answer a question without naming it ("Female.", "No.", "Never.").
_ANSWER_WORDS: dict[str, str] = {
    "sex": rf"{SEX_FAMILIES['female']}|{SEX_FAMILIES['male']}|^[fm]$",
    "smoking_status": r"\b(?:never|quit|used to|former|stopped|gave up|no|nope|yes|yeah)\b",
    "diabetes": rf"{YES_WORDS}|{NO_WORDS}",
    # Not DRINK itself: its "cans" would make "can you hear me" a drinks answer.
    "alcohol_drinks_weekly": (
        r"\b(?:drinks?|beers?|wines?|pints?|glass(?:es)? of|shots? of|whiske?y|scotch|bourbon|"
        r"vodka|gin|rum|cider|champagne|cocktails?|martinis?|booze|liquor|spirits|six pack|"
        r"none|zero|never|nothing|teetotal\w*|sober|don't|do not)\b"
    ),
    "exercise_minutes_weekly": r"\b(?:none|nothing|zero|never|don't|do not)\b",
    # Check-in questions about one day: a plain yes or no answers them.
    "exercise_minutes_today": (
        r"\b(?:no|nope|nah|yes|yeah|yep|didn't|did not|haven't|none|nothing|not today)\b"
    ),
    "alcohol_drinks_yesterday": (
        r"\b(?:drinks?|beers?|wines?|glass(?:es)? of|whiske?y|none|zero|nothing|no|nope|"
        r"didn't|did not)\b"
    ),
}
_READ_BACK_WORDS = r"\b(?:yes|yeah|yep|yup|no|nope|nah|right|correct|wrong)\b"
# "per day 2 glasses of wine a week": a rate cut off from speech before the number.
_DANGLING_RATE = r"^(?:per|a|each|every) (?:day|week|night|month)\s+(?=\S*\d)"
_RATE = r"\b(?:a|per|each|every) (?:day|week|night|month)\b"


def _on_topic(piece: str, field: ProfileField, confirming: bool, checkin: bool = False) -> bool:
    """A number, the question's topic, or a word that answers it."""
    canonical = _canonical(piece)
    if re.search(r"\d", canonical) or is_skip(piece, field):
        return True
    if checkin and same_as_before(piece):
        return True
    cues = (
        TOPICS.get(_topic(field), NOTHING),
        FIELD_CUES.get(field, NOTHING),
        _ANSWER_WORDS.get(field) or _ANSWER_WORDS.get(_base(field), NOTHING),
    )
    if any(re.search(cue, canonical) for cue in cues):
        return True
    return confirming and bool(re.search(_READ_BACK_WORDS, canonical))


def _changes_meaning(piece: str) -> bool:
    """Doubt, someone else, the past, a goal, advice or a vague amount: never chatter."""
    canonical = _canonical(piece)
    plain = _unhedged(canonical)
    return bool(
        # "No, but I did": a contrast is part of the answer before it.
        re.match(r"(?:but|except|though|although)\b", plain)
        or UNCERTAIN.search(plain)
        or HYPOTHETICAL.search(plain)
        or VAGUE.search(plain)
        or ADVICE.search(plain)
        or PAST_SPOIL.search(canonical)
        or REPORTED.search(canonical)
        or NOT_CURRENT.search(canonical)
        or SEASONAL.search(canonical)
        or TAGGED_QUESTION.search(words_of(piece))
        or _others(piece)
    )


def _corrects_between(pieces: list[str], i: int) -> bool:
    """A correction word between two numbers ("70, no, 71") stays for the parser."""
    if not re.fullmatch(rf"(?:{SELF_CORRECTION_WORDS}\s*)+", words_of(pieces[i])):
        return False

    def numbered(side: list[str]) -> bool:
        return any(re.search(r"\d", _canonical(piece)) for piece in side)

    return numbered(pieces[:i]) and numbered(pieces[i + 1 :])


def words_of(text: str) -> str:
    return " ".join(re.sub(r"[^\w'\s]", " ", text.lower()).split())


def focus(
    text: str,
    field: ProfileField,
    *,
    transcript: bool = False,
    confirming: bool = False,
    checkin: bool = False,
    also: tuple[str, ...] = (),
) -> str:
    """Leave out room chatter around an answer.

    A sentence (and, in a voice transcript, a comma-separated piece) goes only when
    it holds nothing for the asked question (or the ``also`` questions) and nothing
    that could change an answer's meaning: "Are we gonna include this, bro? Female." is "Female". A
    reply with nothing on topic stays whole, so "say that again" still works.
    """

    def keep(piece: str) -> bool:
        # ``also``: other questions a piece may answer ("I'm 72, female"), kept for them.
        return (
            _on_topic(piece, field, confirming, checkin)
            or _changes_meaning(piece)
            or any(_on_topic(piece, other, False) for other in also)
        )

    # Each sentence keeps its own end, so "yes?" stays a question.
    parts = re.split(f"({SENTENCE_END})", text)
    sentences = [
        (parts[i].strip(), parts[i + 1] if i + 1 < len(parts) else "")
        for i in range(0, len(parts), 2)
        if parts[i].strip()
    ]
    kept = []
    for sentence, end in sentences:
        if not keep(sentence):
            continue
        if transcript:
            pieces = [piece.strip() for piece in sentence.split(",") if piece.strip()]
            sentence = (
                ", ".join(
                    piece
                    for i, piece in enumerate(pieces)
                    if keep(piece) or _corrects_between(pieces, i)
                )
                or sentence
            )
            trimmed = re.sub(_DANGLING_RATE, "", sentence, flags=re.I)
            if trimmed != sentence and re.search(_RATE, trimmed, re.I):
                sentence = trimmed
        kept.append(sentence + end)
    if not kept:
        return text
    return " ".join(kept)


def asks_back(text: str, field: ProfileField, *, transcript: bool = False) -> bool:
    """A voice transcript's question counts only when it is marked with "?" or is
    about the asked question: "were you just getting 5'4." is chatter and an answer."""
    if not transcript:
        return True
    words = words_of(text)
    return (
        "?" in text
        or bool(TAGGED_QUESTION.search(words))
        or bool(re.search(TOPICS.get(_topic(field), NOTHING), _canonical(text)))
        or bool(re.search(rf"\b(?:{FIELD_NAMES.get(_base(field), NOTHING)})\b", words))
    )


# ---------------------------------------------------------------------------
# Check-ins: "same as last week"
# ---------------------------------------------------------------------------

SAME = re.compile(
    r"same old(?: same old)?|"
    r"(?:(?:about|much|pretty much|just about|roughly|more or less|basically|exactly|still|"
    r"very much|pretty|all)\s+)*(?:the )?same(?:(?: as| like) (?:usual|always|ever|before|normal|"
    r"last (?:time|week|night|check ?in|one)|the last (?:time|week|one)|yesterday|i said|"
    r"i told you|then))?(?: as (?:usual|always|ever))?"
    r"|(?:as|like) (?:usual|always|before|normal|last (?:week|time))"
    r"|the usual|no changes?|nothing(?:'s| has)? changed"
    r"|(?:hasn't|has not|didn't|did not|haven't|have not) changed?|unchanged|no different"
)
# Words that may stand around "the same": who or what is the same, and plain fillers.
SAME_AROUND = set(
    """oh yes yeah yep yup well i'd i would say think it's its it is was has been were are my the
    this that that's week night time really honestly pretty much so just about mochi dear thanks
    thank you here too as again sleep sleeping slept weight weigh weighed exercise exercising
    exercised walking walked walks drinks drinking drank drink smoking smoke blood pressure
    reading numbers feel feeling felt i'm am did do had have got all around roughly basically
    still stayed staying stays for me everything things amount one usual always before last
    hon honey love""".split()
)


# Number words other than "one" ("same as last one") mean a value was said.
SAME_NUMBERS = "|".join(word for word in (*UNITS_WORDS, *TENS_WORDS) if word != "one")


def same_as_before(text: str) -> bool:
    """ "Same as last week", "about the same", "no change": the last answer still holds.

    Only the words around it may be fillers or the topic: "not the same", "the same
    but a bit less" or any number is not a plain "same".
    """
    words = phrase(text)
    if re.search(rf"\d|\b(?:{SAME_NUMBERS})\b", words):
        return False
    match = SAME.search(words)
    if not match:
        return False
    rest = (words[: match.start()] + " " + words[match.end() :]).split()
    return all(word in SAME_AROUND for word in rest)


# ---------------------------------------------------------------------------
# Emergencies (onboarding and check-ins share this)
# ---------------------------------------------------------------------------

EMERGENCY_NOTE = "If you need help right now, please call 911."
# Calm and short: no cheerful filler and no next question while it is on screen.
EMERGENCY_MESSAGE = (
    "I'm sorry you're going through that. "
    + EMERGENCY_NOTE
    + " We can carry on whenever you're ready."
)
RESUME_LEAD = "Okay, let's carry on. "
# Only obvious phrasings, typed or transcribed. "My heart attack was in 2015", "I'm
# dying to see my grandkids" and "this pain in my knee" are not among them.
EMERGENCY = re.compile(
    r"\bchest pains?\b|\bpains? in (?:my|the) chest\b|\btightness in my chest\b|"
    r"\bmy chest (?:hurts|is hurting|is (?:really |so |very )?tight|feels (?:tight|heavy))\b|"
    r"\b(?:can't|cannot|can not|couldn't|could not) (?:breathe|catch my breath|get my breath)\b|"
    r"\b(?:struggling|trouble|hard|difficulty) (?:to )?breath(?:e|ing)\b|"
    r"\bhaving a (?:heart attack|stroke)\b|"
    r"\b(?:think|feel like) (?:i'm|i am|it's|it is) (?:a |having a )?(?:heart attack|stroke)\b|"
    r"\b(?:fell|fallen|had a fall)(?: down)?,? and (?:i )?(?:can't|cannot|can not) get up\b|"
    r"\b(?:want|wanna|wants) to die\b|\bwant to be dead\b|\bkill(?:ing)? myself\b(?! laughing)|"
    r"\bend (?:my life|it all)\b|\bsuicid\w*|\bbetter off dead\b|\bno reason to live\b|"
    r"\b(?:don't|do not) want to (?:live|be alive)(?: anymore| any more)?\b|"
    r"\b(?:i think|i feel like) (?:i'm|i am) dying\b|"
    r"\b(?:won't|will not|can't|cannot) stop (?:the )?bleeding\b|"
    r"\b(?:call|need|get me|send) (?:an ambulance|911|nine one one)\b"
)
# "I had chest pain years ago": history, unless it is said to be happening now.
HISTORY = re.compile(
    r"(?<!'ve )(?<!have )(?<!has )\bhad\b|\b(?:was|were|ago|used to|back in|history of|"
    r"after my|since my|when i was|survived|recovered|years|last (?:year|month|week))\b|"
    r"\bin (?:19|20)\d\d\b"
)
HAPPENING_NOW = re.compile(
    r"\b(?:now|right now|today|tonight|this (?:morning|afternoon|evening)|all (?:day|morning|night)|"
    r"just now|still|again)\b"
)
RESUME = _units(
    "continue",
    "let's continue",
    "please continue",
    "ok continue",
    "okay continue",
    "okay let's continue",
    "carry on",
    "let's carry on",
    "keep going",
    "let's keep going",
    "go on",
    "go ahead",
    "i'm ready",
    "i'm ready now",
)


def emergency(text: str) -> bool:
    """A reply that says something urgent is happening now ("I've got chest pain")."""
    words = " ".join(re.sub(r"[^\w'\s.,;!?]", " ", normalize_text(text).lower()).split())
    for clause in re.split(r"[.,;!?]|\bbut\b", words):
        if EMERGENCY.search(clause) and (
            not HISTORY.search(clause) or HAPPENING_NOW.search(clause)
        ):
            return True
    return False


def resumes(text: str) -> bool:
    """ "Continue", "let's carry on": go on with the question that was paused."""
    return _full(RESUME, phrase(text))


# ---------------------------------------------------------------------------
# "I don't know"
# ---------------------------------------------------------------------------

_DK = (
    r"(?:i )?(?:really |honestly |just |truly |simply )?(?:don't|do not) (?:really |even |honestly )?"
    r"(?:know|remember|recall)"
    r"|(?:i )?dunno|(?:i )?(?:have |got )?(?:no|not a|no earthly|not the (?:slightest|faintest|foggiest)) "
    r"(?:idea|clue)|(?:i )?haven't (?:a|the (?:faintest|foggiest|slightest)) (?:clue|idea)"
    r"|(?:i'm |i am )?(?:really |honestly |just )?not (?:really |quite |too |entirely |exactly |totally |"
    r"a hundred percent |100 percent )?(?:sure|certain)|unsure|uncertain"
    r"|beats me|search me|who knows|(?:i )?(?:couldn't|could not|can't|cannot) (?:really )?(?:tell you|say)"
    r"|hard to (?:say|tell)|(?:i )?(?:can't|cannot|couldn't) (?:really )?(?:remember|recall)"
    r"|(?:i )?forg[eo]t|i've forgotten|i have forgotten|pass|i'll pass|unknown"
    r"|(?:i'd|i would|i'll|i will|i|let me|i'll need to|i'd need to|i need to|i have to|i'd have to|"
    r"i would have to|i'll have to|i will have to) (?:have to |need to )?(?:check|look(?: it| that)? up|find out|"
    r"ask (?:my|the|a) \w+)"
    r"|(?:you'd|you would|you'll|you will) (?:have to|need to) ask (?:my|the) \w+"
    r"|(?:my|the) (?:doctor|doc|nurse|gp|daughter|son|wife|husband) (?:would|will|might|could) know"
    r"|ask my (?:doctor|doc|nurse|gp)"
    r"|(?:i've |i have |i )?never (?:thought about|measured|counted|checked|tracked|timed|weighed|"
    r"had it (?:checked|tested|measured|taken)|been (?:tested|checked|measured|weighed|told))"
    r"|(?:i )?(?:don't|do not) (?:keep track|track|count|measure|own a scale|have a scale|"
    r"weigh myself|know my numbers|pay attention)"
    r"|(?:i )?haven't (?:weighed myself|been weighed|measured|checked|had it checked)"
    r"|it varies(?: so much| a lot| too much)?"
)
_DK_LEAD = re.compile(
    r"^(?:(?:oh|uh|um|hmm|gosh|well|sorry|honestly|to be honest|oh dear|goodness|golly),? )*"
    rf"(?:{_DK})\b"
)
_DK_TAIL = (
    r"(?:\s+(?:to be honest|honestly|really|offhand|off hand|off the top of my head|exactly|"
    r"for sure|i'm afraid|sorry|right now|at the moment|dear|anymore|any more))*"
)
# "I don't know if I'd call it exercise, but I walk an hour a day", "not sure exactly,
# but 7 hours": the doubt is about something else (or only the exact figure), and the
# rest is the answer. A bare "I'm not sure. About 7 hours." is still asked about.
HEDGED_ANSWER = re.compile(
    rf"^(?:(?:oh|uh|um|hmm|gosh|well|honestly),? )*(?:{_DK})\b"
    r" (?:if|whether|why|what to call it|exactly|for sure|offhand|to the minute)\b[^,;.]*"
    r"\s*(?:[,;.]|\s(?=but\b)|\s-\s)\s*(?:but\s+|though\s+)?(?P<rest>\S.*)$"
)


def dont_know(text: str) -> bool:
    """ "No idea", "I'd have to check", "my doctor would know", "pass": the person doesn't
    know the answer. Every clause is either such a phrase or plain context, and no
    clause holds a number."""
    words = " ".join(re.sub(r"[^\w'\s,.;]", " ", normalize_text(text).lower()).split())
    if re.search(r"\d", _canonical(words)):
        return False
    clauses = [c.strip() for c in re.split(r"[,.;]|\bbut\b|\bso\b", words) if c.strip()]
    if not clauses:
        return False
    return any(_DK_LEAD.match(clause) for clause in clauses)


def hedged_answer(text: str) -> str | None:
    """The answer after a doubt about something else, kept with its own words."""
    match = HEDGED_ANSWER.match(" ".join(normalize_text(text).split()).lower())
    if not match:
        return None
    start = len(text) - len(match.group("rest"))
    return text[start:].strip() if start > 0 and text[start:].strip() else match.group("rest")
