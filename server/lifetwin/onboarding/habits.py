"""Habit notes from the person's own words, read deterministically.

Every value is a short word list entry that appeared in the reply (normalised only
in spelling: "buddies" is "friends", "knees don't like it" is "knee trouble"). Nothing
is inferred that was not said. A note is context for suggestions, never a health value.
"""

import re

from lifetwin.onboarding.models import HabitNote, HabitTopic
from lifetwin.onboarding.parsing import normalize_text

# (pattern, normalised words), checked in order; the first match per span wins.
EXERCISE_KINDS: tuple[tuple[str, str], ...] = (
    (r"\b(?:exercise|stationary) bike\b", "exercise bike"),
    (r"\bwater aerobics\b|\baqua\w*", "water aerobics"),
    (r"\bwalk\w*|\bstroll\w*", "walking"),
    (r"\bswim\w*", "swimming"),
    (r"\bgarden\w*|\byard ?work\b", "gardening"),
    (r"\bgolf\w*", "golf"),
    (r"\bdanc\w*", "dancing"),
    (r"\byoga\b", "yoga"),
    (r"\btai chi\b", "tai chi"),
    (r"\bpilates\b", "pilates"),
    (r"\bpickleball\b", "pickleball"),
    (r"\btennis\b", "tennis"),
    (r"\bbowl(?:ing|s)\b", "bowling"),
    (r"\bhik(?:e|es|ing)\b", "hiking"),
    (r"\bjog\w*|\brunning\b|\bi run\b", "jogging"),
    (r"\bbik(?:e|es|ing)\b|\bcycl\w*", "cycling"),
    (r"\btreadmill\b", "treadmill"),
    (r"\baerobics\b", "aerobics"),
    (r"\bgym\b", "gym"),
    (r"\bweights\b|\bweight training\b|\blifting\b", "weights"),
    (r"\bstretch\w*", "stretching"),
    (r"\bhousework\b|\bchores\b|\bcleaning\b", "housework"),
    (r"\bfishing\b", "fishing"),
)
SITTING_KINDS: tuple[tuple[str, str], ...] = (
    (
        r"\btv\b|\btelly\b|\btelevision\b|\bwatch\w* (?:the news|shows|movies|films|programs)\b",
        "tv",
    ),
    (r"\bread\w*\b", "reading"),
    (r"\bdriv\w*|\bin the car\b", "driving"),
    (r"\bcomputer\b|\blaptop\b|\bemails?\b|\binternet\b|\bipad\b|\btablet\b", "computer"),
    (r"\bpuzzles?\b|\bcrosswords?\b|\bsudoku\b", "puzzles"),
    (r"\bknit\w*|\bsew\w*|\bcrochet\w*", "knitting"),
    (r"\bcards\b|\bbridge\b|\bboard games\b", "cards"),
    (r"\bdesk\b|\boffice\b", "desk work"),
    (r"\bon the phone\b|\bphone calls?\b", "phone calls"),
)
COMPANIONS: tuple[tuple[str, str], ...] = (
    (r"\b(?:my|our|the) dogs?\b|\bwith (?:a|the) dogs?\b", "dog"),
    (
        r"\bwith (?:my |our )?(?:friends|buddies|pals|mates|girlfriends|the girls|the guys)\b",
        "friends",
    ),
    (r"\bwith (?:a|my) friend\b", "a friend"),
    (r"\bwith (?:my |the |our )?neighbou?rs?\b", "neighbor"),
    (r"\bwith (?:my )?wife\b", "wife"),
    (r"\bwith (?:my )?(?:husband|hubby)\b", "husband"),
    (r"\bwith (?:my )?partner\b", "partner"),
    (r"\bwith (?:my )?(?:grandkids|grandchildren|grandson|granddaughter)\b", "grandchildren"),
    (r"\bwith (?:my )?(?:daughter|son|kids|children)\b", "family"),
    (r"\bclass(?:es)?\b", "a class"),
    (r"\bwith (?:a |my |the )?(?:group|club|team)\b|\bwalking group\b|\bclub\b", "a group"),
    (r"\b(?:alone|by myself|on my own)\b", "alone"),
)
TIMES: tuple[tuple[str, str], ...] = (
    (r"\b(?:after|before) (?:breakfast|lunch|dinner|supper|tea)\b", ""),  # kept as said
    (r"\bmornings?\b", "morning"),
    (r"\bafternoons?\b", "afternoon"),
    (r"\bevenings?\b|\bat night\b", "evening"),
)
FREQUENCIES: tuple[tuple[str, str], ...] = (
    (r"\bevery (?:single )?(?:day|morning|evening|afternoon)\b|\bdaily\b|\beach day\b", "daily"),
    (r"\bmost (?:days|mornings|evenings)\b", "most days"),
    (r"\bevery other day\b", "every other day"),
    (r"\btwice a week\b|\btwo times a week\b", "twice a week"),
    (r"\bonce a week\b", "once a week"),
    (r"\b(\d|three|four|five|six) times a week\b", "{0} times a week"),
    (r"\b(?:on |at )?(?:the )?weekends?\b", "weekends"),
)
BODY = r"(knee|hip|back|shoulder|ankle|foot|feet|leg|neck|joint)s?"
PAIN = r"\b(?:pain|painful|hurts?|hurting|aches?|aching|sore|bad|stiff|arthritis|playing up|gives? me trouble)\b"
EXERCISE_BARRIERS: tuple[tuple[str, str], ...] = (
    (
        r"\b(?:scared|afraid|frightened|worried|nervous) (?:of|about) (?:falling|a fall)\b|\bfear of falling\b",
        "fear of falling",
    ),
    (r"\bbalance\b", "balance"),
    (r"\barthritis\b", "arthritis"),
    (r"\btoo cold\b|\bthe cold\b|\bcold weather\b|\bfreezing\b", "cold weather"),
    (r"\btoo hot\b|\bthe heat\b|\bhot weather\b", "hot weather"),
    (r"\brain\w*\b|\bsnow\w*\b|\bice\b|\bicy\b", "weather"),
    (r"\bno time\b|\btoo busy\b|\b(?:don't|do not) have (?:the )?time\b", "no time"),
    (r"\blook(?:ing)? after\b|\bcar(?:e|ing) for\b|\btake care of\b", "caregiving"),
    (r"\b(?:short of|out of) breath\b|\bbreathless\w*\b", "breathlessness"),
    (r"\btired\b|\bno energy\b|\blow energy\b|\bexhausted\b", "low energy"),
    (r"\bno one to\b|\bnobody to\b|\bon my own now\b", "no company"),
    (r"\bmotivat\w*\b|\blazy\b|\bcan't be bothered\b", "motivation"),
)
WAKES_FOR: tuple[tuple[str, str], ...] = (
    (r"\bbathroom\b|\btoilet\b|\bloo\b|\bpee\b|\burinate\b|\brestroom\b", "bathroom"),
    (rf"\b{BODY}\s+(?:pain|aches?|hurts?)\b", "{0} pain"),
    (r"\bpain\b", "pain"),
    (r"\bworr\w*|\banxi\w*|\bmind races\b|\bracing thoughts\b|\bthinking too much\b", "worry"),
    (r"\bsnor\w*", "snoring"),
    (r"\bnois\w*", "noise"),
    (r"\bhot flash\w*|\bnight sweats\b|\btoo hot\b", "feeling hot"),
    (r"\bcramps?\b", "cramps"),
    (r"\bthe (?:dog|cat)\b", "pets"),
    (r"\bbreath\w*", "breathing"),
)
QUIT_AIDS: tuple[tuple[str, str], ...] = (
    (r"\bpatch\w*", "patch"),
    (r"\bnicotine gum\b|\bthe gum\b|\bgum\b", "nicotine gum"),
    (r"\blozenges?\b", "lozenges"),
    (r"\bvap\w*|\be ?cig\w*", "vaping"),
    (r"\bcold turkey\b", "cold turkey"),
    (r"\bhypno\w*", "hypnosis"),
    (
        r"\bchantix\b|\bchampix\b|\bvarenicline\b|\bzyban\b|\bbupropion\b|\bpills?\b|\bmedication\b",
        "medication",
    ),
    (r"\bquit ?line\b|\b1 800\b|\bhelpline\b", "quitline"),
    (r"\bsupport group\b|\bcounsel\w*", "support group"),
)
FEELINGS: tuple[tuple[str, str], ...] = (
    (r"\bnot (?:so |too |very )?(?:great|good|well)\b|\bcould be better\b", "not great"),
    (r"\bworr\w*|\bconcerned\b|\banxious\b|\bscared\b|\bnervous\b", "worried"),
    (r"\bfrustrat\w*|\bfed up\b|\bannoyed\b", "frustrated"),
    (r"\blucky\b|\bblessed\b", "lucky"),
    (r"\bgrateful\b|\bthankful\b", "grateful"),
    (r"\bhopeful\b|\boptimistic\b", "hopeful"),
    (r"\bdown\b|\blow\b|\bsad\b|\bdepressed\b|\blonely\b", "down"),
    (r"\bgreat\b|\bexcellent\b|\bwonderful\b|\bfantastic\b", "great"),
    (r"\bpretty good\b|\bquite good\b|\bgood\b|\bwell\b", "good"),
    (r"\bokay\b|\bok\b|\bfine\b|\balright\b|\ball right\b|\bnot bad\b", "okay"),
    (r"\btired\b|\bexhausted\b|\bworn out\b", "tired"),
)
CONCERNS: tuple[tuple[str, str], ...] = (
    (r"\bbalance\b|\bfall(?:s|ing)?\b", "balance"),
    (r"\bmemory\b|\bforget\w*", "memory"),
    (r"\btired\w*|\bno energy\b|\bexhausted\b|\bworn out\b|\bfatigue\b", "tiredness"),
    (rf"\b(?:my )?{BODY}\b(?=[^.,;]*{PAIN})", "{0} pain"),
    (r"\bheart\b", "heart"),
    (r"\bweight\b", "weight"),
    (r"\b(?:blood )?sugar\b|\bdiabet\w*", "blood sugar"),
    (r"\bsleep\w*", "sleep"),
    (r"\bbreath\w*", "breathing"),
    (r"\beyes(?:ight)?\b|\bvision\b", "eyesight"),
    (r"\bhearing\b", "hearing"),
    (r"\blonel\w*", "loneliness"),
)
CLOCK = r"(\d{1,2}(?::\d{2})?(?:\s?(?:am|pm))?|midnight|noon)"
WORD_NUMBERS = {
    "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
    "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "fifteen": "15",
    "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60",
}  # fmt: skip


def _text(reply: str) -> str:
    text = normalize_text(reply).lower()
    text = re.sub(r"[’']", "'", text)
    text = re.sub(r"\b(?:uh|um|er|erm|hmm)\b,?", " ", text)
    for word, digit in WORD_NUMBERS.items():
        text = re.sub(rf"\b{word}\b", digit, text)
    return " ".join(re.sub(r"o'clock", " ", text).split())


def _all(text: str, table: tuple[tuple[str, str], ...]) -> str | None:
    """Every entry the reply names, in the order said, joined with "and"."""
    hits: list[tuple[int, str]] = []
    taken: list[tuple[int, int]] = []
    for pattern, words in table:
        for match in re.finditer(pattern, text):
            if any(match.start() < end and start < match.end() for start, end in taken):
                continue
            value = (
                words.format(*(g.rstrip("s") if g else g for g in match.groups()))
                if words
                else match.group(0)
            )
            value = value.replace("feet pain", "foot pain")
            if value not in [v for _, v in hits]:
                hits.append((match.start(), value))
            taken.append(match.span())
    hits.sort()
    return " and ".join(value for _, value in hits) or None


def _first(text: str, table: tuple[tuple[str, str], ...]) -> str | None:
    hits = []
    for pattern, words in table:
        match = re.search(pattern, text)
        if match:
            value = (
                words.format(*(g.rstrip("s") if g else g for g in match.groups()))
                if words
                else match.group(0)
            )
            hits.append((match.start(), value))
    return min(hits)[1] if hits else None


def _barrier(text: str) -> str | None:
    found = []
    for match in re.finditer(rf"\b(?:my |the )?{BODY}\b", text):
        part = {"feet": "foot"}.get(match.group(1), match.group(1))
        if part == "back" and not re.search(
            r"\bmy back\b|\bback (?:pain|ache|hurts|trouble)", text
        ):
            continue
        clause = re.split(r"[,.;!?]|\bbut\b", text[match.start() :])[0]
        found.append(
            (match.start(), f"{part} pain" if re.search(PAIN, clause) else f"{part} trouble")
        )
    other = _all(text, EXERCISE_BARRIERS)
    if other:
        for value in other.split(" and "):
            if not (value == "arthritis" and found):
                found.append(
                    (text.find(value.split()[0]) if value.split()[0] in text else len(text), value)
                )
    seen: list[str] = []
    for _, value in sorted(found):
        if value not in seen:
            seen.append(value)
    return " and ".join(seen) or None


def _frequency(text: str) -> str | None:
    for pattern, words in FREQUENCIES:
        match = re.search(pattern, text)
        if match:
            return words.format(*match.groups()) if match.groups() else words
    return None


def _time_of_day(text: str) -> str | None:
    return _first(text, TIMES)


def exercise_note(text: str) -> HabitNote | None:
    kind = _all(text, EXERCISE_KINDS)
    companion = _all(text, COMPANIONS)
    if companion == "a group and a class" or companion == "a class and a group":
        companion = "a class"
    values = {
        "kind": kind,
        "with": companion if kind or companion else None,
        "time_of_day": _time_of_day(text) if kind else None,
        "frequency": _frequency(text) if kind else None,
        "barrier": _barrier(text),
    }
    return _note("exercise", values)


def sleep_note(text: str, probe: bool = False) -> HabitNote | None:
    bedtime = re.search(
        rf"\b(?:go|get|went|going|head) (?:to bed|to sleep)(?: (?:at|around|about|by))? (?:about |around )?{CLOCK}"
        rf"|\bbed (?:at|around|by) (?:about |around )?{CLOCK}|\bbedtime is (?:about |around )?{CLOCK}",
        text,
    )
    wake = re.search(
        rf"\b(?:up|wake up|wake|get up|awake|i'm up|rise)(?: (?:at|around|about|by))? (?:about |around )?{CLOCK}\b",
        text,
    )
    bed = next((g for g in bedtime.groups() if g), None) if bedtime else None
    if probe and bed is None:
        # Answering "what time do you go to bed?" with just a time: "usually 10".
        lead = re.match(rf"^(?:usually |about |around |normally |oh )*{CLOCK}\b", text)
        bed = lead.group(1) if lead else None
    naps = None
    if re.search(r"\b(?:no naps?|never nap|don't nap|do not nap)\b", text):
        naps = "no"
    elif re.search(r"\bnap\w*|\bdoz(?:e|es|ing)\b|\bsnooz\w*|\bsiesta\b", text):
        when = re.search(
            r"\b(?:after (?:lunch|dinner|breakfast)|in the (?:afternoon|evening)|in front of the tv)\b",
            text,
        )
        naps = when.group(0) if when else "yes"
    wakes_for = None
    if re.search(
        r"\bwake\w*|\bget up\b|\bup (?:at night|in the night)\b|\bkeeps? me up\b|\bcan't (?:fall )?(?:get to )?sleep\b|\bfall asleep\b|\bat night\b|\btimes\b",
        text,
    ):
        wakes_for = _all(text, WAKES_FOR)
        if wakes_for and "pain" in wakes_for and re.search(r"\b\w+ pain\b", wakes_for):
            wakes_for = " and ".join(v for v in wakes_for.split(" and ") if v != "pain")
    values = {
        "bedtime": bed,
        "wake_time": wake.group(1) if wake else None,
        "wakes_for": wakes_for,
        "naps": naps,
    }
    return _note("sleep", values)


def smoking_note(text: str) -> HabitNote | None:
    years = re.search(
        r"\b(?:for |about |around |over |nearly |almost )*(\d{1,2}) years?\b(?! ago)", text
    )
    ago = re.search(r"\b(\d{1,2}) (years?|months?) ago\b", text)
    tried = None
    if re.search(
        r"\bnever (?:tried|attempted)\b|\bhaven't (?:tried|attempted)\b|\bnever quit\b", text
    ):
        tried = "no"
    elif re.search(
        r"\btried\b|\bquit for\b|\bstopped for\b|\bgave (?:it )?up for\b|\b(?:quit|stopped) "
        r"(?:a few|several|many|\d) times\b|\bwith (?:the )?(?:patch|gum|nicotine)",
        text,
    ):
        tried = "yes"
    values = {
        "smoked_years": years.group(1) if years and not ago else None,
        "tried_quitting": tried,
        "quit_aid": _all(text, QUIT_AIDS),
        "quit_ago": f"{ago.group(1)} {ago.group(2)}" if ago else None,
    }
    if values["quit_ago"]:
        values["tried_quitting"] = None  # they did quit; "tried" is about current smokers
    return _note("smoking", values)


def sitting_note(text: str) -> HabitNote | None:
    return _note("sitting", {"kind": _all(text, SITTING_KINDS)})


def health_note(text: str) -> HabitNote | None:
    concern = _all(text, CONCERNS)
    reading = re.search(r"(?<![\d.])(\d{2,3}) ?(?:/|over|on) ?(\d{2,3})(?![\d.])", text)
    return _note(
        "health",
        {
            "feeling": _first(text, FEELINGS),
            "concern": concern,
            "reading": f"{reading.group(1)} over {reading.group(2)}" if reading else None,
        },
    )


def blood_pressure_reading(reply: str) -> HabitNote | None:
    """ "Last time it was 140 over 90": context only, never a diagnosis."""
    reading = re.search(r"(?<![\d.])(\d{2,3}) ?(?:/|over|on) ?(\d{2,3})(?![\d.])", _text(reply))
    if not reading or int(reading.group(1)) <= int(reading.group(2)):
        return None
    return HabitNote(topic="health", reading=f"{reading.group(1)} over {reading.group(2)}")


def _note(topic: HabitTopic, values: dict) -> HabitNote | None:
    kept = {key: value[:80] for key, value in values.items() if value}
    return HabitNote(topic=topic, **kept) if kept else None


READERS = {
    "exercise": exercise_note,
    "sleep": sleep_note,
    "smoking": smoking_note,
    "sitting": sitting_note,
    "health": health_note,
}
# The habit topic a question belongs to, for notes said alongside its answer.
FIELD_TOPICS: dict[str, HabitTopic] = {
    "sleep_hours": "sleep",
    "smoking_status": "smoking",
    "sitting_minutes_daily": "sitting",
    "general_health": "health",
    "moderate_minutes_weekly": "exercise",
    "vigorous_minutes_weekly": "exercise",
    "exercise_minutes_weekly": "exercise",
}
EXERCISE_CUE = r"\b(?:walk\w*|swim\w*|garden\w*|golf|danc\w*|yoga|tai chi|bik\w*|cycl\w*|jog\w*|tennis|pickleball|bowling|hik\w*|gym|treadmill|aerobics|stroll\w*|pilates)\b"
SLEEP_CUE = r"\b(?:go to bed|bedtime|nap\w*|wake\w* up)\b"
SITTING_CUE = r"\b(?:tv|television|telly)\b"


def read_notes(
    reply: str, *, topic: HabitTopic | None = None, asked: str | None = None
) -> list[HabitNote]:
    """Notes from one reply: the probe's topic, the asked question's topic, and an
    activity mentioned in passing ("I'm 72 and I walk my dog")."""
    text = _text(reply)
    topics: list[HabitTopic] = []
    if topic:
        topics.append(topic)
    if asked in FIELD_TOPICS:
        topics.append(FIELD_TOPICS[asked])
    if re.search(EXERCISE_CUE, text):
        topics.append("exercise")
    if re.search(SLEEP_CUE, text):
        topics.append("sleep")
    if re.search(SITTING_CUE, text):
        topics.append("sitting")
    notes = []
    for name in dict.fromkeys(topics):
        if name == "sleep":
            note = sleep_note(text, probe=topic == "sleep")
        elif name == "health" and topic != "health":
            # Said beside a rating ("Fair. My knees are bad"): concerns only.
            note = _note("health", {"concern": _all(text, CONCERNS)})
        else:
            note = READERS[name](text)
        if note:
            notes.append(note)
    return notes


def merge(notes: list[HabitNote], new: list[HabitNote]) -> list[HabitNote]:
    """One note per topic; newer words fill or replace that topic's fields."""
    merged = {note.topic: note.model_dump(by_alias=False, exclude_none=True) for note in notes}
    for note in new:
        merged.setdefault(note.topic, {}).update(note.model_dump(by_alias=False, exclude_none=True))
    return [HabitNote.model_validate(values) for values in merged.values()][-10:]
