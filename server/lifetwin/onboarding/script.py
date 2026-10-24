"""Everything Mochi says during onboarding, in one place.

``SCRIPT`` holds each question: its wordings (the first is the canonical one), help,
example, quick replies, the simpler question asked after "I don't know" (``proxy``),
and the wording used when Apple Health already supplied a related number.
``ORDER`` is the default path; the conversation may steer away from it (service.py),
but it never asks anything that is not here. Phrase banks at the end give the
acknowledgements and transitions their variety; a per-session seed picks among them.
"""

import random
from dataclasses import dataclass, field

from lifetwin.onboarding.models import ProfileField


@dataclass(frozen=True)
class Question:
    field: ProfileField
    label: str  # plain name for messages: "sleep", "sitting time"
    ask: tuple[str, ...]  # wordings; ask[0] is canonical
    help: str
    example: str  # quoted example answer for "what is the right answer?"
    quick_replies: tuple[str, ...] = ()
    # Asked once after "I don't know": a simpler question that may give an estimate.
    proxy: str | None = None
    proxy_replies: tuple[str, ...] = ()
    # Used instead of ``ask`` when Apple Health supplied the weekly exercise total.
    with_health: str | None = None
    # The example value "yes, that's right" said straight after the question stands for.
    example_value: str | None = None
    onboarding: bool = True  # False: kept for corrections and check-ins, not asked


NOT_SURE = "Not sure"

SCRIPT: tuple[Question, ...] = (
    Question(
        "age",
        "age",
        ("How old are you?", "To start, how old are you?"),
        "I'm asking how many years old you are today. For example, say \"I'm 72\". "
        "You can also tell me the year you were born.",
        '"I\'m 72"',
    ),
    Question(
        "sex",
        "sex",
        ("What sex were you at birth: female or male?", "Were you born female or male?"),
        "I'm asking whether you were born female or male, because health numbers differ "
        'between the two. Just say "female" or "male".',
        '"female"',
        ("Female", "Male"),
    ),
    Question(
        "smoking_status",
        "smoking",
        (
            "Do you smoke now, did you smoke before, or have you never smoked?",
            "Do you smoke now, did you use to, or have you never smoked?",
        ),
        'I\'m asking about smoking cigarettes. Say "never" if you never smoked, '
        '"I quit" if you smoked in the past, or "I smoke" if you smoke now.',
        '"I never smoked"',
        ("Never", "I quit", "I smoke now"),
    ),
    Question(
        "height_cm",
        "height",
        ("How tall are you? For example, 5 feet 10 inches.",),
        "I'm asking how tall you are, standing without shoes. For example, "
        '"5 feet 10 inches" or "178 cm". A close guess is fine.',
        '"5 feet 10 inches"',
        (NOT_SURE,),
        example_value="5 feet 10 inches",
    ),
    Question(
        "weight_kg",
        "weight",
        (
            "How much do you weigh? For example, 160 pounds.",
            "And about how much do you weigh? For example, 160 pounds.",
        ),
        'I\'m asking how much you weigh. For example, "160 pounds" or "72 kg". '
        "A close guess is fine. I'll read it back to you.",
        '"160 pounds"',
        (NOT_SURE,),
        example_value="160 pounds",
    ),
    Question(
        "sleep_hours",
        "sleep",
        (
            "How many hours do you sleep on a usual night?",
            "On a usual night, about how many hours do you sleep?",
        ),
        "I'm asking how many hours you sleep on a usual night. For example, "
        '"7 hours", or "from 11 at night to 6 in the morning".',
        '"7 hours"',
        ("6 hours", "7 hours", "8 hours", "9 hours", NOT_SURE),
        proxy="That's okay. What time do you usually go to bed, and when do you get up?",
    ),
    Question(
        "general_health",
        "health",
        (
            "How would you rate your health: excellent, very good, good, fair or poor?",
            "Overall, is your health excellent, very good, good, fair or poor?",
        ),
        "I'm asking how you'd rate your own health in general. There's no right answer. "
        "Just pick one: excellent, very good, good, fair or poor.",
        '"good"',
        ("Excellent", "Very good", "Good", "Fair", "Poor", NOT_SURE),
        proxy="That's fine. On most days, do you feel great, pretty good, okay, not so good, or poorly?",
        proxy_replies=("Great", "Pretty good", "Okay", "Not so good", "Poorly"),
    ),
    Question(
        "hypertension",
        "high blood pressure",
        (
            "Has a doctor ever told you that you have high blood pressure?",
            "Has a doctor ever said you have high blood pressure?",
        ),
        "I'm asking whether a doctor has ever told you that you have high blood pressure, "
        "also called hypertension. A single reading doesn't count. Say yes, no, or "
        '"not sure".',
        '"yes" or "no"',
        ("Yes", "No", NOT_SURE),
    ),
    Question(
        "diabetes",
        "diabetes",
        (
            "Has a doctor ever told you that you have diabetes?",
            "And has a doctor ever told you that you have diabetes?",
        ),
        "I'm asking if a doctor has ever told you that you have diabetes, also called "
        'high blood sugar. Say "yes", "no", or "I\'m not sure".',
        '"I don\'t have diabetes"',
        ("Yes", "No", NOT_SURE),
    ),
    Question(
        "sitting_minutes_daily",
        "sitting time",
        (
            "About how many hours a day do you spend sitting? TV and driving count.",
            "On a usual day, how many hours do you sit? TV and driving count.",
        ),
        "I'm asking how long you sit on a usual day while you're awake: at the table, "
        'in a chair, in the car. A rough guess is fine, like "6 hours".',
        '"6 hours"',
        ("2 hours", "4 hours", "6 hours", "8 hours", "10 hours", NOT_SURE),
        proxy=(
            "That's okay. Do you sit most of the day, about half, or are you on your feet "
            "most of the day?"
        ),
        proxy_replies=("Mostly sitting", "About half", "On my feet most of the day"),
    ),
    Question(
        "moderate_minutes_weekly",
        "lighter activity",
        (
            "In a usual week, how many minutes of lighter activity do you do, like brisk "
            "walking or gardening?",
            "How many minutes a week of lighter activity, like brisk walking or gardening?",
        ),
        "I'm asking about activity that gets you a little out of breath, like a brisk "
        "walk, gardening or dancing. Add up a usual week. A 30-minute walk, 5 days a week, "
        'is 150 minutes. If you don\'t do any, say "none".',
        '"150 minutes a week"',
        (
            "None",
            "30 minutes a week",
            "1 hour a week",
            "2 hours a week",
            "5 hours a week",
            NOT_SURE,
        ),
        proxy="That's okay. Do you walk, garden or dance at all?",
        proxy_replies=("Yes", "No"),
        example_value="150 minutes",
    ),
    Question(
        "vigorous_minutes_weekly",
        "harder exercise",
        (
            "And harder exercise that makes you breathe hard, like jogging or tennis? "
            "How many minutes a week?",
            "Any harder exercise, like jogging or tennis? How many minutes a week?",
        ),
        "I'm asking about exercise that makes you breathe hard and talk only in short "
        'bursts, like jogging, fast cycling or singles tennis. "None" is a fine answer.',
        '"none"',
        ("None", "30 minutes a week", "1 hour a week", "2 hours a week", NOT_SURE),
        proxy="That's okay. Do you ever do anything that leaves you out of breath?",
        proxy_replies=("Yes", "No"),
        with_health=(
            "Apple Health shows about {total} of activity a week. How much of it makes you "
            "breathe hard, like jogging?"
        ),
    ),
    # Kept for corrections, Apple Health and check-ins; onboarding no longer asks them.
    Question(
        "exercise_minutes_weekly",
        "exercise",
        (
            "About how many minutes do you exercise in a week? "
            "A 30-minute walk, 5 days a week, is 150 minutes.",
        ),
        "I'm asking how many minutes you move on purpose in a whole week, like walking, "
        'swimming or gardening. For example, a 30-minute walk 5 days a week is "150 minutes". '
        'If you don\'t exercise, say "none".',
        '"150 minutes a week"',
        example_value="150 minutes",
        onboarding=False,
    ),
    Question(
        "alcohol_drinks_weekly",
        "alcohol",
        ("How many alcoholic drinks do you have in a week? Say none if you don't drink.",),
        "I'm asking how many drinks of beer, wine or liquor you have in a usual week. One beer "
        'or one glass of wine is one drink. For example, "3 drinks", or "none".',
        '"3 drinks a week"',
        onboarding=False,
    ),
    Question(
        "systolic_bp",
        "top blood pressure number",
        ("What is your blood pressure? For example, 120 over 80.",),
        "I'm asking for your blood pressure: the two numbers a blood pressure cuff shows, the "
        'bigger one first. For example, "120 over 80". If you don\'t know it, say '
        '"I don\'t know".',
        '"120 over 80"',
        onboarding=False,
    ),
    Question(
        "diastolic_bp",
        "bottom blood pressure number",
        ("What is the bottom number of your blood pressure? For example, the 80 in 120 over 80.",),
        'I\'m asking for the bottom, smaller number of your blood pressure. For example, the 80 in "120 over 80". If you don\'t know it, say "I don\'t know".',
        '"80"',
        onboarding=False,
    ),
)
BY_FIELD: dict[str, Question] = {question.field: question for question in SCRIPT}

# The Apple Health offer: a step in the order, not a question with a value.
HEALTH_STEP = "apple_health"
HEALTH_FIELDS: tuple[ProfileField, ...] = (
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
)
HEALTH_OFFER = "Shall I fill in your height, weight, sleep and activity from Apple Health?"
HEALTH_OFFER_REPLIES = ("Yes, use Apple Health", "No thanks")
HEALTH_OPEN = "Lovely. Check each reading in Apple Health, then come back to me."
HEALTH_DECLINED = ("No problem, I'll just ask you.", "That's fine, we'll do it together.")

# The default path: a few spoken questions, then Apple Health, then what is missing.
ORDER: tuple[str, ...] = (
    "age",
    "sex",
    "smoking_status",
    HEALTH_STEP,
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "general_health",
    "hypertension",
    "diabetes",
    "sitting_minutes_daily",
    "moderate_minutes_weekly",
    "vigorous_minutes_weekly",
)
ASKED: tuple[ProfileField, ...] = tuple(step for step in ORDER if step != HEALTH_STEP)

GREETING = "Hi, I'm Mochi! You can talk or type, skip anything, or say \"I don't know\". "
MEMORY_ASK = (
    "Can I remember the little things you tell me, like your walks? It helps me make better "
    "suggestions. You can change this any time."
)
MEMORY_REPLIES = ("Yes, remember", "No thanks")
MEMORY_YES = "Thank you!"
MEMORY_NO = "That's fine, just your answers then."
MEMORY_WHY = (
    "If you tell me you walk your dog in the mornings, I can suggest something that fits "
    "your day. It stays on your phone, and you can change your mind any time. "
)
# Asked about supplements: one fixed reply. Mochi never suggests one.
SUPPLEMENT_REPLY = (
    "That's a good one to ask your pharmacist or doctor. Bring your bottles to your next "
    "visit so they can check them with your other medicines."
)

# -- Phrase banks -----------------------------------------------------------------

ACKS = ("Got it.", "Thank you.", "Lovely.", "Okay.", "Thanks.")
UNKNOWN_ACKS = (
    "That's okay, we'll leave it out.",
    "No problem, I'll leave that blank.",
    "That's fine, we'll skip it.",
)
# Said with the first "I don't know" only.
UNKNOWN_FIRST = " Your twin will say it's still learning."
SMALL_TALK = ("That sounds nice.", "How lovely.", "I'm glad you told me.")
STEER_BACK = ("Now, ", "So, ", "Back to you: ")
HOW_ARE_YOU = "I'm doing well, thank you for asking!"
PROBE_SKIPPED = ("Of course.", "That's fine.")
PROBE_THANKS = ("Thank you, that helps.", "Thanks for telling me.")
# The first probe tells the person it is optional.
PROBE_OPTIONAL = " Or we can move on."
ESTIMATE_NOTE = " That's a rough estimate from what you said."
BP_READING = "Thanks, {reading}. A single reading isn't the same as a diagnosis, so I'll just ask: "


def pick(options: tuple[str, ...], seed: int, *keys: object) -> str:
    """One option, the same for the same seed and keys. Seed 0 is the canonical first."""
    if seed == 0 or len(options) == 1:
        return options[0]
    return random.Random(f"{seed}:{':'.join(map(str, keys))}").choice(options)


@dataclass(frozen=True)
class Proxy:
    """How the simpler question's answer maps to an estimate (owner approval pending)."""

    field: ProfileField
    # (reply pattern, what it stands for, as said back to the person)
    choices: tuple[tuple[str, str], ...] = field(default_factory=tuple)


# Sitting: a share of the waking day (24 h minus usual sleep, 16 h if unknown),
# rounded to the nearest hour.
SITTING_SHARES: tuple[tuple[str, float, str], ...] = (
    (
        r"\b(?:on my feet|up and about|on the go|moving around|up and down|not much|"
        r"hardly|rarely|very little)\b",
        0.25,
        "on your feet most of the day",
    ),
    (r"\b(?:half|in between|in the middle|bit of both|50 50|some of the day)\b", 0.5, "about half"),
    (
        r"\b(?:most|mostly|all day|nearly all|almost all|the whole day|a lot|lots|sitting)\b",
        0.625,
        "most of the day sitting",
    ),
)
# General health in plain words, one step each on the survey's five-point scale.
HEALTH_WORDS: tuple[tuple[str, str, str], ...] = (
    (
        r"\b(?:not so good|not too good|not very good|not great|not good|so so|so-so)\b",
        "fair",
        "not so good",
    ),
    (r"\b(?:poorly|poor|bad|awful|terrible|unwell|rough|lousy)\b", "poor", "poorly"),
    (
        r"\b(?:pretty good|quite good|very good|really good|good mostly)\b",
        "very_good",
        "pretty good",
    ),
    (
        r"\b(?:great|wonderful|fantastic|excellent|brilliant|marvellous|marvelous)\b",
        "excellent",
        "great",
    ),
    (r"\b(?:okay|ok|alright|all right|fine|not bad|average|good)\b", "good", "okay"),
)

# -- Steering: what the person brings up picks the next topic ----------------------

# (cue in their words, the question it leads to). Checked in order; the first cue
# whose question is still open wins.
STEERS: tuple[tuple[str, ProfileField], ...] = (
    (
        r"\b(?:walk\w*|stroll\w*|garden\w*|golf\w*|danc\w*|swim\w*|yoga|tai chi|bik\w*|"
        r"cycl\w*|hik\w*|tennis|gym|pickleball|bowling)\b",
        "moderate_minutes_weekly",
    ),
    (r"\b(?:sleep\w*|slept|tired|exhausted|insomnia|nap\w*|bedtime)\b", "sleep_hours"),
    (r"\b(?:tv|television|telly|sit|sitting|couch|recliner|computer)\b", "sitting_minutes_daily"),
    (r"\b(?:smok\w*|cigar\w*)\b", "smoking_status"),
    (r"\b(?:blood pressure|hypertension)\b", "hypertension"),
    (r"\b(?:diabet\w*|blood sugar)\b", "diabetes"),
    (r"\b(?:knees?|hips?|arthritis|aches?|pains?|my health)\b", "general_health"),
)
STEER_LEADS = ("You mentioned {said}.", "You said {said}.")
# Something for a later question, said to this one: thanked, kept for later.
LATER = ("Lovely, we'll come to that in a moment.", "I'll come back to that.")
# First person to second, for saying their words back.
FLIP = {
    "i": "you",
    "i'm": "you're",
    "im": "you're",
    "i've": "you've",
    "i'd": "you'd",
    "i'll": "you'll",
    "me": "you",
    "my": "your",
    "mine": "yours",
    "myself": "yourself",
    "am": "are",
}
