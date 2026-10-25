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
    r"^(?:(?:please |just |i'll |i will |let's |can we )?skip(?: it| this| that| this one| today)?|pass|"
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
    r"for a minute|one minute|briefly)\b|\bbriefly\b|\bsomewhat\b|\bshorter\b|\ba shorter\b|"
    r"\bmostly\b|\bpretty much\b|\ba bit\b|\bnot entirely\b|\bmost of it\b|^(?:half|a little|some)$"
)
# "I didn't skip it", "never missed it": a negated miss is a clear yes.
NEGATED_MISS = re.compile(
    r"\b(?:i )?(?:didn't|did not|never|don't|do not|wasn't going to) (?:skip|miss|forget)\w*"
    r"(?: it| today| out)?\b"
)
NOT_TODAY = re.compile(
    r"\bnot today\b|\bno\b|\bnope\b|\bnah\b|\bnot really\b|\bnot yet\b|"
    r"\b(?:i )?(?:didn't|did not|haven't|have not|couldn't|could not|wasn't able to)"
    r"(?: (?:do|done|get|got|manage|make)(?: it| to it)?)?\b|"
    r"\bforgot\b|\bnot this time\b|\bno time\b|\bnot at all\b|\bmissed it\b|\bskipped(?: it)?\b|"
    r"\bdidn't get (?:to it|round to it|around to it)\b|\bnext time\b|\btomorrow\b|"
    r"\bnothing today\b|\btoo (?:tired|busy)\b|\bi was busy\b|\bnot once\b|\bnot a chance\b|^never$"
)
YES = re.compile(
    r"\byes+\b|\byeah\b|\byea\b|\bye\b|\byep\b|\byup\b|\bya\b|\byeh\b|\bsure did\b|\bi did\b|"
    r"\bdid it\b|\bdone\b|\bof course\b|\babsolutely\b|\bdefinitely\b|\buh[ -]?huh\b|\bmhm+\b|"
    r"\bi (?:got|managed|made) (?:it|to)\b|\bgot it done\b|\bi sure did\b|\btwice\b|\bi do\b|"
    r"\bevery (?:bit|time)\b|\bthat i did\b|\bwent well\b|\bsure\b|\bcorrect\b|\bthat's right\b|"
    r"\btotally\b|\baye\b|\byh\b|\bfinished\b|\bnailed it\b|\bdid (?:my|the) \w+\b|\bnegated_miss\b"
)
# Hedges that make a yes or no unclear: ask again rather than guess.
# Another day ("yesterday", "later") is not today's answer either.
UNCLEAR = re.compile(
    r"\bmaybe\b|\bperhaps\b|\bthink\b|\bprobably\b|\bnot sure\b|\bi guess\b|\bmight\b|"
    r"\b(?:don't|do not) (?:know|remember|recall)\b|\bcan't (?:remember|recall)\b|\bpass\b|"
    r"\bskip (?:it|this)\b|\byesterday\b|\blater\b|\btonight\b|\bwill do\b|\bgoing to\b|\bgonna\b|"
    r"\bnot not\b|n't not\b|\b(?:couldn't|could not|can't) stop\b|\bwhat\b|\bwhich\b"
)
# Friendly fillers that are not a "no": "no problem, I did it".
FILLERS = re.compile(r"\bno (?:problem|worries|excuses|doubt)\b")
# A bare "no" with more said after it ("no it was great") may not answer the question.
BARE_NO = re.compile(r"^(?:no|nope|nah)\b")


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
    words = " ".join(FILLERS.sub(" ", NEGATED_MISS.sub(" negated_miss ", words)).split())
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
    if found == {"not_today"} and BARE_NO.match(words) and len(words.split()) > 3:
        if not NOT_TODAY.search(BARE_NO.sub(" ", words)):
            return None
    if found == {"partly", "done"}:
        return "partly"  # "kind of did it"
    if len(found) == 1:
        return found.pop()  # type: ignore[return-value]
    return None
