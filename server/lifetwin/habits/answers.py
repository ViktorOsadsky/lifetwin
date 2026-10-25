"""Reading the one check-in habit answer: "Yes", "sort of" or "not today".

A wrong reading is worse than a miss, so anything mixed or unclear ("no, I did
it", "maybe") is not read and Mochi asks again. "Skip", "I don't remember" and
"not sure" leave the day unknown, which is never the same as "not today".
"""

import re
from typing import Literal

from lifetwin.onboarding.parsing import normalize_text

HabitResult = Literal["done", "partly", "not_today"]
Reading = HabitResult | Literal["unknown"] | None

UNKNOWN = re.compile(
    r"^(?:(?:please |just |i'll |i will |let's |can we )?skip(?: it| this| that| this one)?|pass|"
    r"next|rather not say|i'd rather not say|i'd rather not|no comment|"
    r"(?:i )?(?:don't|do not|can't|cannot) (?:remember|recall)|(?:i'm |i am )?not sure|"
    r"i don't know|i dunno|dunno|no idea|(?:i )?forget if i did|unsure)$"
)
PARTLY = re.compile(
    r"\byes and no\b|\bsort of\b|\bsorta\b|\bkind of\b|\bkinda\b|\bpartly\b|\bpartially\b|"
    r"\bhalfway\b|\bhalf of it\b|\b(?:did|only|about) half\b|\bsome of it\b|"
    r"\bnot (?:fully|completely|all of it|"
    r"the whole (?:thing|time)|quite|as much as i (?:wanted|planned|meant))\b|\balmost\b|"
    r"\bnearly\b|\bmore or less\b|\bjust a (?:little|bit)\b|\bonly (?:a (?:little|bit|minute)|"
    r"for a minute|one minute|briefly)\b|\bbriefly\b|\bsomewhat\b|\bshorter\b|\ba shorter\b"
)
NOT_TODAY = re.compile(
    r"\bnot today\b|\bno\b|\bnope\b|\bnah\b|\bnot really\b|\bnot yet\b|"
    r"\b(?:i )?(?:didn't|did not|haven't|have not|couldn't|could not|wasn't able to)\b|"
    r"\bforgot\b|\bnot this time\b|\bno time\b|\bnot at all\b|\bmissed it\b|\bskipped it\b|"
    r"\bdidn't get (?:to it|round to it|around to it)\b|\bnext time\b|\btomorrow\b"
)
YES = re.compile(
    r"\byes\b|\byeah\b|\byep\b|\byup\b|\byes+\b|\bya\b|\byeh\b|\bsure did\b|\bi did\b|"
    r"\bdid it\b|\bdone\b|\bof course\b|\babsolutely\b|\bdefinitely\b|\buh[ -]?huh\b|\bmhm+\b|"
    r"\bi (?:got|managed|made) (?:it|to)\b|\bgot it done\b|\bi sure did\b|\btwice\b|\bi do\b|"
    r"\bevery (?:bit|time)\b|\bthat i did\b|\bwent well\b|\bsure\b|\bcorrect\b|\bthat's right\b"
)
# Hedges that make a yes or no unclear: ask again rather than guess.
UNCLEAR = re.compile(r"\bmaybe\b|\bperhaps\b|\bi think\b|\bprobably\b|\bnot sure\b|\bi guess\b")


def _words(text: str) -> str:
    lowered = normalize_text(text).lower().replace("’", "'")
    return " ".join(re.sub(r"[^\w'\s-]", " ", lowered).split())


def read_answer(text: str) -> Reading:
    """The habit result, "unknown" for a skip, or None when it is not clear."""
    words = _words(text)
    if not words:
        return None
    if UNKNOWN.fullmatch(words):
        return "unknown"
    if UNCLEAR.search(words):
        return None
    found: set[str] = set()
    rest = words
    # Longest, most qualified phrases first; each match is removed before the next
    # pattern reads, so "not completely" is partly, never "no".
    for name, pattern in (("partly", PARTLY), ("not_today", NOT_TODAY), ("done", YES)):
        if pattern.search(rest):
            found.add(name)
            rest = pattern.sub(" ", rest)
    if found == {"partly", "done"}:
        return "partly"  # "kind of did it"
    if len(found) == 1:
        return found.pop()  # type: ignore[return-value]
    return None
