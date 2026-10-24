"""Mochi's daily and weekly check-in scripts. Every line Mochi says lives here.

Daily (about 1-2 minutes): last night's sleep, today's movement, and how the
person feels. On Tuesdays and Saturdays one habit question is added: yesterday's
alcoholic drinks (a weekday and a Friday night, since drinking often differs
between the two). Smoking is left to the weekly check-in: it rarely changes from
one day to the next, and asking a smoker every day would feel like nagging.

Weekly (about 3-5 minutes): every model input that can change from week to week,
in the profile's own fields and units (sleep, exercise, drinks, smoking, weight,
blood pressure), then how the week went.

Each question has a plain form ("ask") and forms that mention the last answer
("again", "again_none" when it was none, and one per smoking answer), so the
person can say "same as last week".
"""

from typing import Literal

CheckinKind = Literal["daily", "weekly"]
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
# One blood pressure question covers both numbers, as in onboarding.
WEEKLY: tuple[CheckinField, ...] = (
    "sleep_hours",
    "exercise_minutes_weekly",
    "alcohol_drinks_weekly",
    "smoking_status",
    "weight_kg",
    "systolic_bp",
    "wellbeing",
)
SCRIPTS: dict[CheckinKind, tuple[tuple[CheckinField, ...], ...]] = {
    "daily": (DAILY, DAILY_WITH_HABIT),
    "weekly": (WEEKLY,),
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
}

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
        "exercise_minutes_weekly": {
            "ask": (
                "About how many minutes did you exercise this week, all together? "
                "A 30-minute walk on 5 days is 150 minutes."
            ),
            "again": (
                "Last week you exercised about {value}. How about this week? "
                "About how many minutes all together?"
            ),
            "again_none": (
                "Last week you didn't get to exercise. How about this week? "
                "About how many minutes all together?"
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
        "exercise_minutes_weekly": (
            "I'm asking how many minutes you moved on purpose this week, all together, like "
            "walking, swimming or gardening. For example, two 30-minute walks is 60 minutes. "
            "If you didn't, say none."
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

# Closing lines: short and kind. Never advice, a prediction, a date or a score.
CLOSINGS: dict[CheckinKind, dict[str, str]] = {
    "daily": {
        "default": "That's all for today. Thank you for checking in with me! See you tomorrow.",
        "not_great": (
            "Thank you for telling me. I hope tomorrow feels a little better. See you then."
        ),
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
WHY_NOTE = (
    "I ask so your twin can keep up with how you're doing. Nothing is saved until you say yes."
)
PRIVATE_NOTE = "This check-in isn't kept on LifeTwin's server. Nothing is saved until you say yes."
HOW_ARE_YOU = "I'm a happy bear, thank you for asking! "
# Said once, then the check-in goes on, when a reply mentions an emergency.
URGENT_NOTE = "I'm sorry you're going through that. If you need help right now, please call 911. "
