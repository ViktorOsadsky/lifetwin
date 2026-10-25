"""Mochi's daily and weekly check-in scripts. Every line Mochi says lives here.

Daily (about 1-2 minutes): last night's sleep, today's movement, and how the
person feels. On Tuesdays and Saturdays one habit question is added: yesterday's
alcoholic drinks (a weekday and a Friday night, since drinking often differs
between the two). Smoking is left to the weekly check-in: it rarely changes from
one day to the next, and asking a smoker every day would feel like nagging.

Weekly (about 3-5 minutes): every model input that can change from week to week,
in the profile's own fields and units (sleep; activity split into the kind that gets
you out of breath and easy activity, in the on-device model's names; sitting on a
usual day; drinks, smoking, weight, blood pressure), then how the week went.

Quick (30-60 seconds, the frequent check-in): one to three of last night's sleep,
the day's activity (out of breath versus easy), the day's sitting and how the person
feels, chosen by the app so the model's daily_logs fill in over time, plus at most
one optional catch-up for a day that was missed. The app says which day the
activity and sitting questions are about ("today" in the evening, "yesterday"
before then).

Each question has a plain form ("ask") and forms that mention the last answer
("again", "again_none" when it was none, and one per smoking answer), so the
person can say "same as last week".
"""

from typing import Literal

CheckinKind = Literal["daily", "weekly", "quick"]
CheckinField = Literal[
    "sleep_hours_last_night",
    "exercise_minutes_today",
    "alcohol_drinks_yesterday",
    "wellbeing",
    "sleep_hours",
    "exercise_minutes_weekly",
    "alcohol_drinks_weekly",
    "smoking_status",
    "weight_kg",
    "systolic_bp",
    "diastolic_bp",
    "sleep_hours_night_before",
    "vigorous_recreation_min",
    "moderate_recreation_min",
    "sedentary_min_day",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
]

DAILY: tuple[CheckinField, ...] = (
    "sleep_hours_last_night",
    "exercise_minutes_today",
    "wellbeing",
)
DAILY_WITH_HABIT: tuple[CheckinField, ...] = (
    "sleep_hours_last_night",
    "exercise_minutes_today",
    "alcohol_drinks_yesterday",
    "wellbeing",
)
# One blood pressure question covers both numbers, as in onboarding; one activity
# question covers both paces, with a follow-up for the part not mentioned.
WEEKLY: tuple[CheckinField, ...] = (
    "sleep_hours",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
    "sedentary_min_day",
    "alcohol_drinks_weekly",
    "smoking_status",
    "weight_kg",
    "systolic_bp",
    "wellbeing",
)
QuickTopic = Literal["sleep", "activity", "sitting", "feeling"]
# The quick check-in's topics in the order Mochi asks them, and their fields.
QUICK_TOPICS: dict[QuickTopic, tuple[CheckinField, ...]] = {
    "sleep": ("sleep_hours_last_night",),
    "activity": ("vigorous_recreation_min", "moderate_recreation_min"),
    "sitting": ("sedentary_min_day",),
    "feeling": ("wellbeing",),
}
CATCH_UP: tuple[CheckinField, ...] = ("sleep_hours_night_before",)
QUICK_MAX_TOPICS = 3


def quick_script(topics: list[str], catch_up: bool) -> tuple[CheckinField, ...]:
    """The quick check-in's questions: the topics in Mochi's order, then the catch-up."""
    order = [topic for topic in QUICK_TOPICS if topic in topics]
    fields = [name for topic in order for name in QUICK_TOPICS[topic]]
    return tuple(fields) + (CATCH_UP if catch_up else ())


def _quick_scripts() -> tuple[tuple[CheckinField, ...], ...]:
    from itertools import combinations

    scripts = []
    for size in range(1, QUICK_MAX_TOPICS + 1):
        for topics in combinations(QUICK_TOPICS, size):
            scripts += [quick_script(list(topics), False), quick_script(list(topics), True)]
    return (*scripts, CATCH_UP)


SCRIPTS: dict[CheckinKind, tuple[tuple[CheckinField, ...], ...]] = {
    "daily": (DAILY, DAILY_WITH_HABIT),
    "weekly": (WEEKLY,),
    "quick": _quick_scripts(),
}
# Fields asked as one question: the second is answered with the first, or followed up.
PAIRS: dict[str, str] = {
    "systolic_bp": "diastolic_bp",
    "vigorous_recreation_min": "moderate_recreation_min",
    "vigorous_recreation_min_week": "moderate_recreation_min_week",
}
PACES = {
    "vigorous_recreation_min": "vigorous",
    "moderate_recreation_min": "moderate",
    "vigorous_recreation_min_week": "vigorous",
    "moderate_recreation_min_week": "moderate",
}
# Monday is 0: Tuesday asks about Monday, Saturday about Friday night.
HABIT_DAYS = {1, 5}

GREETINGS: dict[CheckinKind, str] = {
    "daily": (
        "Hi, it's Mochi! Time for our little daily check-in. "
        "It's just a few quick questions, and you can skip any of them."
    ),
    "weekly": (
        "Hi, it's Mochi! It's time for our weekly check-in. "
        "It takes a few minutes, and you can skip any question."
    ),
    "quick": "Hi, it's Mochi! Just a quick check-in, under a minute. You can skip anything.",
}
# Sitting is hard to judge, so the question names everyday sitting (the proxies). Its
# wording rotates by date so the same question doesn't come every morning.
SITTING_PROXIES = (
    "About how many hours did you spend sitting {day}? Count reading, TV, meals and "
    "time in the car.",
    "Thinking of {day}, about how many hours were you sitting down, like watching TV, "
    "reading or at the table?",
    "Roughly how many hours did you sit {day}, all together? Things like TV, puzzles, "
    "meals or driving all count.",
)

QUESTIONS: dict[CheckinKind, dict[CheckinField, dict[str, str]]] = {
    "daily": {
        "sleep_hours_last_night": {
            "ask": "How many hours did you sleep last night?",
            "again": "Last time you slept {value}. How many hours did you sleep last night?",
            "again_none": (
                "Last time you hardly slept at all. How many hours did you sleep last night?"
            ),
        },
        "exercise_minutes_today": {
            "ask": (
                "Did you move or exercise today, like a walk or some gardening? "
                "About how many minutes?"
            ),
            "again": (
                "Last time you moved for {value}. How about today? "
                "About how many minutes did you move or exercise?"
            ),
            "again_none": (
                "Last time you didn't get to exercise. How about today? "
                "Did you move or exercise, and for about how many minutes?"
            ),
        },
        "alcohol_drinks_yesterday": {
            "ask": ("How many alcoholic drinks did you have yesterday? Say none if you had none."),
            "again": (
                "Last time you had {value}. How many alcoholic drinks did you have yesterday?"
            ),
            "again_none": (
                "Last time you had no alcoholic drinks. How many did you have yesterday? "
                "Say none if you had none."
            ),
        },
        "wellbeing": {
            "ask": "And how are you feeling today: good, okay, or not great?",
            "again": (
                "Last time you were feeling {value}. "
                "How are you feeling today: good, okay, or not great?"
            ),
        },
    },
    "weekly": {
        "sleep_hours": {
            "ask": "Let's start with sleep. On a usual night this week, how many hours did you sleep?",
            "again": (
                "Last week you said about {value} of sleep a night. How has sleep been this "
                "week? About how many hours on a usual night?"
            ),
            "again_none": (
                "Last week you said you hardly slept at all. How has sleep been this week? "
                "About how many hours on a usual night?"
            ),
        },
        "vigorous_recreation_min_week": {
            "ask": (
                "Now activity this week. Did anything get you out of breath, like brisk walking "
                "uphill? And easier things, like gentle walks? About how many minutes of each?"
            ),
            "again": (
                "Last week you did {value}. How about this week? About how many minutes of each?"
            ),
            "follow": (
                "And did anything this week get you out of breath, like brisk walking uphill? "
                "About how many minutes, all together?"
            ),
        },
        "moderate_recreation_min_week": {
            "ask": (
                "And easier activity this week, like gentle walks, gardening or housework? "
                "About how many minutes, all together?"
            ),
            "follow": (
                "And easier activity this week, like gentle walks, gardening or housework? "
                "About how many minutes, all together?"
            ),
        },
        "sedentary_min_day": {
            "ask": (
                "On a usual day this week, about how many hours did you spend sitting? "
                "Count reading, TV, meals and time in the car."
            ),
            "again": (
                "Last week you sat for about {value} on a usual day. How about this week? "
                "About how many hours a day?"
            ),
        },
        "alcohol_drinks_weekly": {
            "ask": "How many alcoholic drinks did you have this week? Say none if you had none.",
            "again": (
                "Last week you had about {value}. How many alcoholic drinks did you have this week?"
            ),
            "again_none": (
                "Last week you had no alcoholic drinks. How about this week? "
                "Say none if you had none."
            ),
        },
        "smoking_status": {
            "ask": "Do you smoke at all these days?",
            "again_current": "Last week you told me you smoke. Do you still smoke these days?",
            "again_former": (
                "Last week you told me you used to smoke. Do you smoke at all these days?"
            ),
        },
        "weight_kg": {
            "ask": "What do you weigh these days? For example, 160 pounds.",
            "again": "Last week you weighed about {value}. What do you weigh now?",
        },
        "systolic_bp": {
            "ask": (
                "Have you had your blood pressure checked lately? If you know the numbers, "
                "tell me, like 120 over 80. If not, just say no."
            ),
            "again": (
                "Last time your blood pressure was {value}. Do you have a newer reading? "
                "If not, just say no."
            ),
        },
        "wellbeing": {
            "ask": "Last one: how did this week go for you: good, okay, or not great?",
            "again": (
                "Last one. Last week you said your week was {value}. "
                "How did this week go: good, okay, or not great?"
            ),
        },
    },
    "quick": {
        "sleep_hours_last_night": {
            "ask": "How did you sleep last night? About how many hours?",
            "again": "Last time you slept {value}. How about last night? About how many hours?",
            "again_none": (
                "Last time you hardly slept at all. How about last night? About how many hours?"
            ),
            "health": "Apple Health says you slept about {value} last night. Looks right?",
        },
        "vigorous_recreation_min": {
            "ask": (
                "Did you get out and about {day}? Tell me if anything got you out of breath, "
                "like brisk walking uphill, or if it was easy, like a gentle walk, and for "
                "about how long."
            ),
            "again": (
                "Last time you did {value}. How about {day}? Did anything get you out of "
                "breath, like brisk walking uphill, or was it easy, like a gentle walk? "
                "And for about how long?"
            ),
            "follow": (
                "And did anything {day} get you out of breath, like brisk walking uphill? "
                "If so, for about how long?"
            ),
            "health": (
                "Apple Health shows about {value} of exercise {day}. Did any of it get you "
                "out of breath, or was it all at an easy pace?"
            ),
        },
        "moderate_recreation_min": {
            "ask": "And anything easier {day}, like an easy walk or pottering about? About how long?",
            "follow": (
                "And anything easier {day}, like an easy walk or pottering about? About how long?"
            ),
        },
        "sedentary_min_day": {
            "ask": SITTING_PROXIES[0],
            "again": (
                "Last time you sat for about {value}. How about {day}? About how many hours, "
                "all together?"
            ),
        },
        "wellbeing": {
            "ask": "And how are you feeling today: good, okay, or not great?",
            "again": (
                "Last time you were feeling {value}. "
                "How are you feeling today: good, okay, or not great?"
            ),
        },
        "sleep_hours_night_before": {
            "ask": (
                "One more, only if you like. Yesterday was a bit of a blank. How did you sleep "
                "the night before? If you can't remember, just say skip."
            ),
            "health": (
                "One more, only if you like. Yesterday was a bit of a blank, but Apple Health "
                "says you slept about {value} the night before. Looks right?"
            ),
        },
    },
}

# A plain explanation of each question, with an example answer ("help").
HELP: dict[CheckinKind, dict[CheckinField, str]] = {
    "daily": {
        "sleep_hours_last_night": (
            'I\'m asking how many hours you slept last night. For example, "7 hours", '
            'or "from 11 to 6". A close guess is fine.'
        ),
        "exercise_minutes_today": (
            "I'm asking how many minutes you moved on purpose today, like walking, swimming "
            'or gardening. For example, "20 minutes". If you didn\'t, just say no.'
        ),
        "alcohol_drinks_yesterday": (
            "I'm asking how many drinks of beer, wine or liquor you had yesterday. One beer "
            "or one glass of wine is one drink. If you had none, say none."
        ),
        "wellbeing": "I'm asking how you feel today, in a word. Just say good, okay, or not great.",
    },
    "weekly": {
        "sleep_hours": (
            "I'm asking how many hours you slept on a usual night this week. For example, "
            '"7 hours". A close guess is fine.'
        ),
        "vigorous_recreation_min_week": (
            "I'm asking about activity that got you out of breath this week, like brisk "
            "walking uphill, and easier activity, like gentle walks or gardening. For "
            'example, "an hour of hard walking and two hours of gardening". If you didn\'t, '
            "say none."
        ),
        "moderate_recreation_min_week": (
            "I'm asking about easier activity this week, like gentle walks, gardening or "
            'housework, all together. For example, "2 hours". If you didn\'t, say none.'
        ),
        "sedentary_min_day": (
            "I'm asking how many hours you sat on a usual day this week, while awake: "
            'reading, TV, meals, driving. For example, "about 6 hours". A close guess is fine.'
        ),
        "alcohol_drinks_weekly": (
            "I'm asking how many drinks of beer, wine or liquor you had this week. One beer "
            'or one glass of wine is one drink. For example, "3 drinks", or "none".'
        ),
        "smoking_status": (
            "I'm asking whether you smoke cigarettes these days. Just say yes or no. "
            'If you quit, you can say "I quit".'
        ),
        "weight_kg": (
            'I\'m asking what you weigh now. For example, "160 pounds". A close guess is fine.'
        ),
        "systolic_bp": (
            "I'm asking for a recent blood pressure reading, if you have one: the two numbers, "
            'bigger one first, like "120 over 80". If you haven\'t had it checked, just say no.'
        ),
        "wellbeing": (
            "I'm asking how this week went for you, in a word. Just say good, okay, or not great."
        ),
    },
}

HELP["quick"] = {
    "sleep_hours_last_night": (
        'I\'m asking how many hours you slept last night. For example, "7 hours", '
        'or "from 11 to 6". A close guess is fine.'
    ),
    "vigorous_recreation_min": (
        "I'm asking what you did to move about, and whether any of it got you out of "
        'breath. For example, "20 minutes up the hill, out of breath", or "an easy '
        "walk for half an hour\". If you didn't, just say no."
    ),
    "moderate_recreation_min": (
        "I'm asking about easy activity, like a gentle walk, gardening or housework. "
        'For example, "30 minutes". If you didn\'t, just say no.'
    ),
    "sedentary_min_day": (
        "I'm asking how many hours you were sitting while awake: reading, TV, meals, "
        'driving. For example, "about 6 hours". A close guess is fine.'
    ),
    "wellbeing": "I'm asking how you feel today, in a word. Just say good, okay, or not great.",
    "sleep_hours_night_before": (
        "I missed you yesterday, so I'm asking about the night before yesterday: about how "
        'many hours did you sleep? For example, "7 hours". If you can\'t remember, say skip.'
    ),
}

# Closing lines: short and kind. Never advice, a prediction, a date or a score.
CLOSINGS: dict[CheckinKind, dict[str, str]] = {
    "daily": {
        "default": "That's all for today. Thank you for checking in with me! See you tomorrow.",
        "not_great": (
            "Thank you for telling me. I hope tomorrow feels a little better. See you then."
        ),
    },
    "quick": {
        "default": "That's all. Thank you for checking in with me!",
        "not_great": "Thank you for telling me. I hope the rest of the day is gentle with you.",
    },
    "weekly": {
        "default": (
            "That's everything for this week. Thank you, it's always nice to catch up! "
            "I'll check in again next week."
        ),
        "not_great": (
            "Thank you for sharing your week with me. I hope next week is kinder to you. "
            "I'll check in again soon."
        ),
    },
}

DONE_AGAIN = "We're all done for now. Thank you!"
SAME_LEAD = "Same as last time, then. "
NO_PREVIOUS = "I don't have your last answer to go by. "
# Check-in history lives only on the phone; weekly answers also update the forecast.
WHY_NOTES: dict[CheckinKind, str] = {
    "quick": (
        "A few words each day help your twin keep up with how you sleep, move and sit. "
        "Your check-ins stay on your phone. Nothing is saved until you say yes."
    ),
    "daily": (
        "I ask so your twin can keep up with how you're doing. Your check-ins stay on your "
        "phone. Nothing is saved until you say yes."
    ),
    "weekly": (
        "I ask so your twin can keep your forecast up to date. Your check-ins stay on your "
        "phone. Nothing is saved until you say yes."
    ),
}
PRIVATE_NOTE = (
    "Your check-ins stay on your phone. LifeTwin's server doesn't keep them. "
    "Nothing is saved until you say yes."
)
HOW_ARE_YOU = "I'm a happy bear, thank you for asking! "
