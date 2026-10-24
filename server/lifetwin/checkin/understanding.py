"""Reading activity and sitting answers in the model's own terms.

Activity is split the way the on-device model wants it, in plain words: anything
that got the person out of breath (``vigorous``) and easy activity such as a gentle
walk or pottering in the garden (``moderate``). A duration goes into one of the two
only when the reply says which; otherwise Mochi asks about the pace. Sitting is read
in hours and kept in minutes. A vague amount ("all afternoon", "most of the day") is
asked about, never estimated: a wrong value is worse than a second question.
"""

import re
from dataclasses import dataclass, field
from datetime import date
from typing import Literal

from lifetwin.onboarding.parsing import (
    COMPARED,
    DAY_DURATION,
    FUTURE,
    HABIT_TIME,
    LONG_NUMBER,
    MAYBE,
    PAST_OLD,
    N,
    _canonical,
    _doubtful,
    _exercise,
    _exercise_day,
    _in_period,
    _mine,
    _minutes,
    _others,
    normalize_text,
)

Pace = Literal["vigorous", "moderate"]

# Out of breath, in everyday words, and activities that nearly always are.
VIGOROUS = (
    r"\b(?:out of breath|breathless\w*|puff\w*|huff\w*|winded|pant\w*|gasp\w*|"
    r"hard to (?:talk|breathe)|couldn't (?:talk|catch my breath)|sweat\w*|"
    r"heart (?:going|pounding|racing|thumping)|uphill|up (?:the|a|some) hills?|hills|hilly|"
    r"steep|jog\w*|run|ran|running|laps|hard|harder|strenuous|vigorous\w*|"
    r"intense|shovel\w* snow|spin class|fast)\b"
)
# "I didn't get out of breath", "nothing that made me breathless": none of the hard kind.
NOT_VIGOROUS = (
    r"\b(?:(?:didn't|did not|never|wasn't|was not|not|without)\s+(?:get(?:ting)?\s+|got\s+|feel\w*\s+|"
    r"being\s+|even\s+)?(?:out of breath|breathless|puffed|winded)|"
    r"(?:nothing|none|no(?:thing)? one)\s+(?:of it\s+)?(?:that|which)?\s*(?:got|made|left|"
    r"had)\s+(?:me\s+)?(?:out of breath|breathless|puff\w*|winded)|"
    r"no (?:hills|running|jogging)|nothing (?:strenuous|hard|vigorous|too hard)|"
    r"(?:not|wasn't|nothing|never) (?:too |very |that |so )?hard)\b"
)
MODERATE = (
    r"\b(?:easy|easily|gentle|gently|leisurely|stroll\w*|ambl\w*|potter\w*|garden\w*|"
    r"housework|house work|vacuum\w*|hoover\w*|cleaning|chores|yoga|tai chi|water aerobics|"
    r"golf|slow\w*|light|flat|bowling|stretch\w*|doubles|walk\w*|dog walk\w*)\b"
)
ZERO_BOTH = (
    r"^(?:no|nope|nah|none|nothing|zero|not really|not a thing|not at all)"
    r"(?:\s+(?:really|at all|today|yesterday|this week))?(?:$|[,.;!])|"
    r"\b(?:nothing(?: really| at all)?|did nothing|didn't do (?:any|a)thing|"
    r"didn't do (?:any )?exercise|no exercise(?: at all)?|didn't (?:get to )?(?:exercise|move)|"
    r"didn't (?:get|go) out|not a thing)\b"
)
# To "and anything easier?" or "did anything get you out of breath?" after the other part.
ZERO_ONE = (
    r"^(?:no|nope|nah|none|nothing|not really|not that i know of|i don't think so|"
    r"don't think so|i don't believe so)\b|\b(?:that was it|that's it|that's all|that was all|"
    r"nothing else|nothing like that|nothing more)\b"
)
YES_ONLY = r"(?:yes|yeah|yep|yup|i did|some|a little|a bit|sure)(?: i did)?"
VAGUE = (
    r"\b(?:all (?:day|morning|afternoon|evening)|most of the (?:day|morning|afternoon)|"
    r"half the day|a while|a bit|a little|for ages|ages|a long time|hours|some time|"
    r"not (?:long|much)|hardly|barely|a few|lots|a lot|plenty)\b"
)
# A little, but not none: "not much", "a bit".
FEW = r"\b(?:much|a lot|a bit|a little|hardly|barely|some)\b"
STEPS = r"\bsteps\b|\bmiles?\b|\bkm\b|\bblocks?\b"
EACH_WAY = r"\b(?:each way|both ways|there and back)\b"
DAY_WORDS = {
    "today": (
        r"\btoday\b|\bthis (?:morning|afternoon|evening)\b|\bearlier\b",
        rf"\byesterday\b|\blast night\b|{HABIT_TIME}|\b(?:this|last) week\b",
    ),
    "yesterday": (
        r"\byesterday(?: (?:morning|afternoon|evening))?\b",
        rf"\btoday\b|\bthis (?:morning|afternoon|evening)\b|\btonight\b|\blater\b|{HABIT_TIME}|"
        r"\b(?:this|last) week\b",
    ),
}
PACE_VIGOROUS = (
    r"^(?:yes|yeah|yep|yup|it did|i was|all of it|the whole time|out of breath|hard|"
    r"brisk(?:ly)? uphill|puffed)\b|\b(?:out of breath|breathless|puff\w*|huff\w*|hard going|"
    r"all of it|the whole (?:time|thing))\b"
)
PACE_MODERATE = (
    r"^(?:no|nope|nah|not really|easy|gentle|it was easy|all easy|none of it)\b|"
    r"\b(?:easy|gentle|leisurely|slow|none of it|no breath\w*)\b"
)
PACE_BOTH = r"\b(?:bit of both|some of (?:it|each)|both|part of it|half and half)\b"
SITTING_VAGUE = (
    r"\b(?:most of the (?:day|time)|all day|all (?:morning|afternoon|evening)|the whole day|"
    r"half the day|a lot|lots|not much|hardly|barely|a while|ages|too (?:long|much)$|"
    r"a fair bit|quite a bit|plenty)\b"
)
SITTING_RATE = (
    r"\b(?:a|per|each) day\b|\bon a (?:usual|normal|typical) day\b|\bmost days\b|\bdaily\b"
)


@dataclass
class ActivityRead:
    """What an activity reply said: values to read back, or a follow-up to ask."""

    values: dict = field(default_factory=dict)
    hint: str | None = None
    # The part of the activity the follow-up is about ("pottered all afternoon").
    focus: Pace | None = None
    # An activity duration whose pace is not known yet ("about 20 minutes").
    held: int | None = None
    keep_held: bool = False


# A wish, a plan or the past is not what happened.
WISH = (
    r"\b(?:want(?:s|ed)? to|wanna|wish|hope|hoping|goal|aim|plan(?:ning)? to|trying to|"
    r"should|ought to|meant to|would like|need to)\b"
)


def _plain(text: str) -> str:
    text = _canonical(normalize_text(text))
    # "maybe 25 minutes", "seven hours maybe": an estimate, read back as "about".
    text = re.sub(MAYBE.pattern + r"(?=\d)", "about ", text)
    text = re.sub(r"(?:(?<=minute)|(?<=hour))\s+(?:maybe|probably|perhaps)\b", " ", text)
    return " ".join(text.split())


def _unsafe(text: str) -> bool:
    return bool(re.search(WISH, text) or PAST_OLD.search(text))


def _other_time(text: str, day: str) -> bool:
    if FUTURE.search(text) and not re.search(r"\bi'll (?:say|guess)\b", text):
        return True
    return day in DAY_WORDS and bool(re.search(DAY_WORDS[day][1], text))


def _own(text: str) -> str | None:
    """The reply without clauses only about someone else; None when nothing is left."""
    clauses = [c for c in re.split(r"[;,.!?]|\bbut\b|\bwhile\b", text) if c.strip()]
    # "my husband and I walked": the person's own too.
    mine = [c for c in clauses if not _others(c) or _mine(c)]
    if not mine:
        return None
    return ", ".join(c.strip() for c in mine)


ACTIVITY = (
    r"\b(?:walk\w*|stroll\w*|garden\w*|potter\w*|housework|vacuum\w*|hoover\w*|clean\w*|"
    r"chores|yoga|tai chi|golf|swim\w*|swam|laps|jog\w*|run|ran|running|bik\w*|cycl\w*|"
    r"rode|ride|danc\w*|hik\w*|tennis|bowl\w*|aerobics|exercis\w*|class|stairs|treadmill|"
    r"shovel\w*|dog|stretch\w*|gym|workout|mow\w*|digging|dug)\b"
)
PIECES = r"[;,]|\b(?:and then|then|and|but|after that|plus)\b"


def _pace(piece: str) -> set[str]:
    """The paces one part of a reply names. "Walking up the hill" is the hard kind."""
    rest = re.sub(NOT_VIGOROUS, " ", piece)
    paces = set()
    if re.search(VIGOROUS, rest):
        paces.add("vigorous")
        rest = re.sub(r"\bwalk\w*\b", " ", rest)
    if re.search(MODERATE, rest):
        paces.add("moderate")
    return paces


def _amount(text: str, week: bool, today: date) -> float | None:
    """Minutes in one part of a reply: the day's or the week's total."""
    doubled = bool(re.search(EACH_WAY, text))
    text = re.sub(EACH_WAY, " ", text)
    if week:
        timed = _in_period(text, "exercise_minutes_weekly", "week")
        if timed is None:
            return None
        found = _exercise(timed, today, past=True)
    else:
        found = _exercise_day(text, today)
    if not found or not found[0] or len(found[0]) != 1:
        return None
    minutes = found[0][0]
    return minutes * 2 if doubled else minutes


def _durations(text: str) -> int:
    return len(re.findall(DAY_DURATION, text))


def _segments(text: str) -> list[tuple[set[str], str]]:
    """(paces, words) for each activity in a reply. A part that only says how it felt
    ("and was quite puffed") or only how long ("30 minutes each time") belongs to the
    activity before it."""
    parts: list[str] = []
    for piece in re.split(PIECES, text):
        piece = piece.strip()
        if not piece:
            continue
        timed = bool(re.search(r"\d", piece))
        if parts and not re.search(ACTIVITY, piece) and (not timed or not _pace(piece)):
            parts[-1] += ", " + piece
        else:
            parts.append(piece)
    # "walked for 30" after "jogged for 15 minutes": the same unit.
    if re.search(r"\bminute\b", text):
        parts = [
            part
            if re.search(r"\b(?:minute|hour)\b", part)
            else re.sub(rf"{N}(?!\s*(?:time|day|week))", r"\1 minute", part, count=1)
            for part in parts
        ]
    return [(_pace(part), part) for part in parts]


def _paces(text: str) -> set[str]:
    return set().union(*(paces for paces, _ in _segments(text)))


def read_activity(
    text: str,
    *,
    open_paces: list[Pace],
    week: bool,
    day: str,
    held: int | None = None,
    today: date | None = None,
) -> ActivityRead:
    """An answer to the activity question, or to its follow-up about one pace.

    ``open_paces`` are the parts still to answer, in question order: both for the
    first question, one for a follow-up. ``held`` is a duration whose pace was asked
    about (from the last reply, or Apple Health's exercise minutes).
    """
    today = today or date.today()
    plain = _plain(text)
    vig, mod = (
        ("vigorous_recreation_min_week", "moderate_recreation_min_week")
        if week
        else ("vigorous_recreation_min", "moderate_recreation_min")
    )
    names = {"vigorous": vig, "moderate": mod}
    if LONG_NUMBER.search(plain):
        return ActivityRead()
    if week and re.search(r"(?<!this )(?<!the )\blast week\b|\busually\b|\bnormally\b", plain):
        return ActivityRead()  # the weekly follow-up asks about this past week
    if not week and _other_time(plain, day):
        return ActivityRead(hint=f"And {day}? ")
    if week and FUTURE.search(plain):
        return ActivityRead()
    own = _own(plain)
    if own is None:
        return ActivityRead()
    plain = own
    if not week and day in DAY_WORDS:
        plain = " ".join(re.sub(DAY_WORDS[day][0], " ", plain).split())
    if _unsafe(plain):
        return ActivityRead()

    if held is not None:
        paced = _paced(plain, held, names)
        if paced is not None:
            return paced

    timed = _durations(plain) > 0 or bool(re.search(r"\d", plain))
    if not timed and re.search(COMPARED, plain) and not week:
        return ActivityRead(hint="More or less is fine, but I need a number. ")
    if not timed:
        named = _paces(plain)
        if not named and not re.search(FEW, plain):
            if len(open_paces) == 2 and re.search(ZERO_BOTH, plain):
                return ActivityRead(values={vig: 0, mod: 0})
            if len(open_paces) == 1 and re.search(ZERO_ONE, plain):
                return ActivityRead(values={names[open_paces[0]]: 0})
        if re.search(STEPS, plain):
            return ActivityRead(hint="Thank you. About how many minutes was that, all together?")
        if len(open_paces) == 1 and re.fullmatch(YES_ONLY, plain.strip(" .!,")):
            return ActivityRead(hint="Good for you! About how many minutes was that?")
        if len(named) == 1:
            pace = next(iter(named))
            if pace in open_paces:
                kind = (
                    "That counts as easy activity."
                    if pace == "moderate"
                    else "That's the kind that gets you out of breath."
                )
                return ActivityRead(
                    hint=f"{kind} About how long was it, in minutes or hours?", focus=pace
                )
        return ActivityRead()

    if _doubtful(plain):
        return ActivityRead()
    values: dict = {}
    if re.search(NOT_VIGOROUS, plain) and "vigorous" in open_paces:
        values[vig] = 0
    paces = _paces(plain)
    if len(paces) <= 1:
        minutes = _amount(plain, week, today)
        if minutes is None:
            if paces and next(iter(paces)) in open_paces and re.search(VAGUE, plain):
                pace = next(iter(paces))
                return ActivityRead(hint="About how long was it, in minutes or hours?", focus=pace)
            return ActivityRead()
        if paces:
            pace = next(iter(paces))
        elif len(open_paces) == 1:
            pace = open_paces[0]
        elif vig in values:
            pace = "moderate"
        else:
            return ActivityRead(
                hint=(
                    "Did that get you out of breath, like brisk walking uphill, "
                    "or was it at an easy pace?"
                ),
                held=int(round(minutes)),
            )
        if pace not in open_paces or names[pace] in values:
            return ActivityRead()
        values[names[pace]] = int(round(minutes))
        return ActivityRead(values=values)
    # Both paces named: each part's time goes to its own pace.
    totals: dict[str, float] = {}
    for named, words in _segments(plain):
        if len(named) != 1:
            if re.search(r"\d", words) or named:
                return ActivityRead()
            continue
        pace = next(iter(named))
        minutes = _amount(words, week, today)
        if minutes is None:
            if re.search(r"\d", words) or re.search(VAGUE, words) or totals.get(pace) is not None:
                return ActivityRead()
            totals.setdefault(pace, None)  # named, but not how long
            continue
        if pace in totals:
            return ActivityRead()  # two times for one pace: asked about, not added up
        totals[pace] = minutes
    for pace, minutes in totals.items():
        if minutes is None:
            continue
        if pace not in open_paces:
            return ActivityRead()
        values[names[pace]] = int(round(minutes))
    return ActivityRead(values=values)


def _paced(plain: str, held: int, names: dict[str, str]) -> ActivityRead | None:
    """The pace of a held duration: "easy", "out of breath", or how much of it was hard."""
    vig, mod = names["vigorous"], names["moderate"]
    durations = list(re.finditer(DAY_DURATION, plain))
    bare = re.fullmatch(rf"\D*?{N}\D*", plain)
    if durations or bare:
        if len(durations) > 1:
            return None
        if durations:
            minutes = _minutes(durations[0])
        else:
            minutes = float(bare.group(1))
        if minutes is None or not 0 <= minutes <= held:
            return None
        if minutes == held and re.search(PACE_MODERATE, plain) and not re.search(VIGOROUS, plain):
            return None  # "no, it was 35 minutes": a correction, read again as a new answer
        if durations and minutes != held and re.search(r"\b(?:walk\w*|garden\w*)\b", plain):
            return None  # a new activity, not part of the held one
        return ActivityRead(values={vig: int(round(minutes)), mod: int(round(held - minutes))})
    if re.search(PACE_BOTH, plain):
        return ActivityRead(
            hint="About how many minutes of it got you out of breath?", held=held, keep_held=True
        )
    hard = bool(re.search(PACE_VIGOROUS, re.sub(NOT_VIGOROUS, " ", plain)))
    easy = bool(re.search(PACE_MODERATE, plain) or re.search(NOT_VIGOROUS, plain))
    if hard and not easy:
        return ActivityRead(values={vig: held, mod: 0})
    if easy and not hard:
        return ActivityRead(values={vig: 0, mod: held})
    return None


def _sitting_minutes(text: str) -> float | None:
    durations = list(re.finditer(DAY_DURATION, text))
    if not durations:
        bare = re.findall(rf"{N}(?!\s*(?:minute|hour|time|day|week|o'clock|am|pm))", text)
        if len(bare) == 1 and 1 <= float(bare[0]) <= 16 and not re.search(r"[/:]", text):
            return float(bare[0]) * 60
        return None
    parts = []
    for duration in durations:
        low, value, unit, extra = duration.groups()
        if low and unit == "hour" and 0 < float(value) - float(low) <= 1:
            minutes = (float(low) + float(value)) / 2 * 60
        else:
            minutes = _minutes(duration)
        if minutes is None:
            return None
        parts.append(minutes)
    if len(parts) > 1:
        gaps = [text[a.end() : b.start()] for a, b in zip(durations, durations[1:], strict=False)]
        if not all(re.search(r"\b(?:and|plus|then)\b|[,;]", gap) for gap in gaps) or any(
            re.search(r"\bor\b", gap) for gap in gaps
        ):
            return None
    return sum(parts)


def read_sitting(text: str, *, week: bool, day: str) -> tuple[dict, str | None]:
    """Awake time sitting on the day (or a usual day this week), in minutes."""
    plain = _plain(text)
    ask = "About how many hours was that, all together? A rough guess is fine, like 6 hours."
    if LONG_NUMBER.search(plain):
        return {}, None
    if week:
        plain = re.sub(SITTING_RATE, " ", plain)
        plain = re.sub(r"\b(?:this|the) (?:past )?week\b|\busually\b|\bnormally\b", " ", plain)
    elif _other_time(plain, day):
        return {}, f"And {day}? "
    own = _own(plain)
    if own is None:
        return {}, None
    if not week and day in DAY_WORDS:
        own = re.sub(DAY_WORDS[day][0], " ", own)
    minutes = _sitting_minutes(own)
    if minutes is None:
        if re.search(SITTING_VAGUE, own) or re.search(r"\b(?:sat|sitting|sit)\b", own):
            return {}, ask
        return {}, None
    if _doubtful(own) or _unsafe(own):
        return {}, None
    if not 0 < minutes <= 1439:
        return {}, ask
    return {"sedentary_min_day": int(round(minutes))}, None
