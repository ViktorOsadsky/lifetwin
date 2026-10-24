"""What Mochi says in a change conversation: current values, questions and read-backs.

Plain words only: no code names, no forecast numbers, no advice and never a diagnosis.
"""

import re

LB_PER_KG = 0.45359237

GREETING = "Hi, it's Mochi! What would you like to update?"
WHAT_CHANGED = "What's changed?"
CHOOSE_AGAIN = (
    "Sorry, I didn't catch that. You can update your weight, height, sleep, exercise, "
    "drinks, smoking, blood pressure, diabetes or age. What would you like to update?"
)
ONE_AT_A_TIME = "Let's do one at a time. Which would you like to update first: {}?"
ALSO = "You also mentioned your {}. Would you like to update that too?"
RESTART = "Okay, let's start again. Nothing has changed. What would you like to update?"
DELETE_NOTE = 'To remove all your answers, use "Delete my data" in Settings.'
CHANGE_THANKS = "Thanks for telling me. "
PROBE = "Thank you. Before I read it back: did something change, like a new routine?"
NOTED = "Thank you, I'll remember that. "
NOT_NOTED = "Okay. "
SAVED = "Got it. I've updated your {}."
# How the saved answer is named in SAVED ("I've updated your smoking answer").
SAVED_NAMES = {
    "smoking_status": "smoking answer",
    "alcohol_drinks_weekly": "drinks answer",
    "diabetes": "diabetes answer",
    "exercise_minutes_weekly": "exercise answer",
    "sleep_hours": "sleep answer",
}
SAME = "That's the same as what I have, so nothing needs to change."
KEPT = "Okay, I'll leave it as it is. Nothing has changed."
NOTHING_CHANGED = "Okay, nothing has changed."
DONE_AGAIN = "We're all done. If something else changes, just tap Update."
CANCELLED = "Okay, we'll leave it there. Nothing has changed."
OTHERS = "I can only change your own answers, not anyone else's."
SEX_FIXED = (
    "Sex at birth can't be changed here. Your twin's forecast is built on it, so it stays "
    'as you first told me. If it was saved by mistake, "Delete my data" in Settings lets you '
    "start fresh."
)
ANYTHING_ELSE = "Is there anything else you'd like to update?"
AGE_RULE = (
    "Your age only changes on your birthday, so I can't change it from {old} to {new}. "
    "If you've had a birthday, just tell me, and I'll make it {next}."
)
BIRTHDAY = "Happy birthday! "
DOCTOR_QUESTION = "Did a doctor tell you that you have diabetes?"
DIABETES_NO_DOCTOR = (
    "Okay. I only add diabetes when a doctor has told you, so I'll leave it as it is. "
    "If you're worried, your doctor can check. Nothing has changed."
)
DIABETES_STAYS = (
    "This answer is about whether a doctor has ever told you that you have diabetes, so it "
    "stays the same even when it's well managed. Nothing has changed."
)
BP_NO_READING = "That's okay. When you have a new reading, we can update it. Nothing has changed."
BP_TALK = "Thanks for telling me. I keep your blood pressure as its two numbers. "
BOTH_BP = 'Please tell me both blood pressure numbers, for example "135 over 85".'
WHY_NOTE = (
    "I check every change with you, so your twin uses what's true for you now. Your answers "
    "stay on your phone, and LifeTwin's server doesn't keep them. Nothing changes until you "
    "say yes."
)
PRIVATE_NOTE = (
    "Your answers stay on your phone. LifeTwin's server uses them for your forecast but "
    "doesn't keep them. Nothing changes until you say yes."
)
MEMORY_NOTE = "I'll only remember why it changed because you said that's okay."
HELP_CHOOSING = (
    'Tell me what\'s different, like "I lost some weight" or "I quit smoking". I\'ll read it '
    "back to you before anything changes."
)
HELP_PROBING = (
    "I'd like to know what's behind the change, like a new routine or a doctor's advice. "
    'If you\'d rather not say, just say "skip".'
)
HELP_CONFIRMING = (
    "I'm checking that I heard you right before I change anything. {} "
    'If that\'s right, say "yes". If not, say "no" and then the right answer.'
)
NEVER_MIND = ' If nothing has changed, just say "never mind".'

LABELS: dict[str, str] = {
    "age": "age",
    "sex": "sex at birth",
    "height_cm": "height",
    "weight_kg": "weight",
    "sleep_hours": "sleep",
    "exercise_minutes_weekly": "exercise",
    "smoking_status": "smoking",
    "alcohol_drinks_weekly": "drinks",
    "diabetes": "diabetes",
    "systolic_bp": "blood pressure",
}
# Asked when the person said what changed but not the new value.
NEW_VALUE: dict[str, str] = {
    "age": "How old are you now?",
    "sex": "What sex were you at birth: female or male?",
    "height_cm": "How tall are you now? For example, 5 feet 6 inches.",
    "weight_kg": "What do you weigh now?",
    "sleep_hours": "About how many hours do you sleep on a usual night now?",
    "exercise_minutes_weekly": (
        "About how many minutes do you exercise in a usual week now? "
        "A 30-minute walk, 5 days a week, is 150 minutes."
    ),
    "smoking_status": "Do you smoke now, did you smoke before, or have you never smoked?",
    "alcohol_drinks_weekly": (
        "How many alcoholic drinks do you have in a usual week now? Say none if you don't drink."
    ),
    "diabetes": "Has a doctor told you that you have diabetes?",
    "systolic_bp": "What was your latest blood pressure reading? For example, 135 over 85.",
}
HELP: dict[str, str] = {
    "age": "Your age goes up by one on your birthday. If you've had one, just tell me.",
    "sex": 'I\'m asking whether you were born female or male. Just say "female" or "male".',
    "height_cm": 'Tell me how tall you are now, standing without shoes, like "5 feet 6 inches".',
    "weight_kg": 'Tell me what you weigh now, like "155 pounds". A close guess is fine.',
    "sleep_hours": 'Tell me how many hours you sleep on a usual night now, like "7 hours".',
    "exercise_minutes_weekly": (
        "Tell me how many minutes you move on purpose in a usual week now, like walking or "
        'gardening. For example, "30 minutes, 5 days a week".'
    ),
    "smoking_status": 'Tell me if you smoke now, like "I quit" or "I started again".',
    "alcohol_drinks_weekly": (
        'Tell me how many beers, glasses of wine or other drinks you have in a usual week, like "2 drinks a week", or "none".'
    ),
    "diabetes": "I'm asking if a doctor has told you that you have diabetes. Say yes or no.",
    "systolic_bp": (
        'Tell me both numbers from your latest blood pressure reading, like "135 over 85".'
    ),
}
SMOKING_NOW = {
    "current": "you smoke now",
    "former": "you don't smoke now, but you used to",
    "never": "you have never smoked",
    "unknown": "you're not sure about smoking",
}
SMOKING_HAD = {
    "current": "that you smoke",
    "former": "that you used to smoke but don't now",
    "never": "that you've never smoked",
    "unknown": "that you're not sure about smoking",
}
SMOKING_TOLD = {
    "current": "you smoke",
    "former": "you used to smoke",
    "never": "you had never smoked",
    "unknown": "you weren't sure about smoking",
}
SMOKING_SO = {
    "current": "you smoke now",
    "former": "you used to smoke, but you don't now",
    "never": "you have never smoked at all",
    "unknown": "you're not sure about smoking",
}
METRIC = re.compile(r"\b(?:kg|kgs|kilo\w*|cm|cms|centimet\w*|met(?:er|re)s?)\b", re.I)


def plain(value: float, digits: int = 1) -> str:
    text = f"{value:.{digits}f}"
    return text.rstrip("0").rstrip(".") if "." in text else text


def count(value: float, unit: str) -> str:
    return f"{plain(value)} {unit}{'' if value == 1 else 's'}"


def weight_number(kg: float, metric: bool = False) -> str:
    return plain(kg) if metric else plain(kg / LB_PER_KG)


def weight_words(kg: float, metric: bool = False) -> str:
    return f"{weight_number(kg, metric)} {'kg' if metric else 'pounds'}"


def height_words(cm: float, metric: bool = False) -> str:
    if metric:
        return f"{plain(cm, 0)} cm"
    inches = round(cm / 2.54 * 2) / 2
    feet, rest = int(inches // 12), inches % 12
    if not rest:
        return f"{feet} feet"
    return f"{feet} feet {plain(rest)} inch{'' if rest == 1 else 'es'}"


def bp_words(values: dict) -> str:
    return f"{values['systolic_bp']} over {values['diastolic_bp']}"


def current_line(field: str, profile: dict) -> str:
    """What Mochi has now ("Right now I have you at 160 pounds."), or that it has nothing."""
    value = profile.get(field)
    if field == "systolic_bp" and value is not None and profile.get("diastolic_bp") is None:
        return f"Right now I have your top blood pressure number at {value}."
    if value is None:
        return f"I don't have your {LABELS[field]} yet."
    if field == "age":
        return f"Right now I have your age as {value}."
    if field == "sex":
        return f"Right now I have you as {value} at birth."
    if field == "height_cm":
        return f"Right now I have you at {height_words(value)} tall."
    if field == "weight_kg":
        return f"Right now I have you at {weight_words(value)}."
    if field == "sleep_hours":
        return f"Right now I have you sleeping {count(value, 'hour')} a night."
    if field == "exercise_minutes_weekly":
        if value == 0:
            return "Right now I have that you don't exercise."
        return f"Right now I have you exercising {count(value, 'minute')} a week."
    if field == "alcohol_drinks_weekly":
        if value == 0:
            return "Right now I have that you don't drink alcohol."
        return f"Right now I have you at {count(value, 'drink')} a week."
    if field == "smoking_status":
        return f"Right now I have {SMOKING_HAD[value]}."
    if field == "diabetes":
        told = "has told" if value else "hasn't told"
        return f"Right now I have that a doctor {told} you that you have diabetes."
    return f"Right now I have your blood pressure at {bp_words(profile)}."


def _direction(field: str, old, new, metric: bool) -> str:
    if (
        old is None
        or old == new
        or (field in {"exercise_minutes_weekly", "alcohol_drinks_weekly"} and new == 0)
    ):
        return ""
    way = "down" if new < old else "up"
    if field == "weight_kg":
        return f", {way} from {weight_number(old, metric)}"
    if field == "height_cm":
        return f", {way} from {height_words(old, metric)}"
    return f", {way} from {plain(old)}"


def heard(
    field: str, values: dict, profile: dict, metric: bool = False, about: bool = False
) -> str:
    """The new value read back with the old one beside it ("..., down from 160")."""
    approx = "about " if about else ""
    old = profile.get(field)
    new = values[field]
    if field == "systolic_bp":
        before = (
            f", instead of {bp_words(profile)}"
            if profile.get("systolic_bp") is not None and profile.get("diastolic_bp") is not None
            else ""
        )
        return f"I heard your latest blood pressure is {approx}{bp_words(values)}{before}."
    if field == "smoking_status":
        return f"I heard {SMOKING_NOW[new]}."
    if field == "sex":
        return f"I heard you were {new} at birth."
    if field == "age":
        return f"I heard you're {new} now."
    if field == "diabetes":
        told = "has told" if new else "has not told"
        return f"I heard a doctor {told} you that you have diabetes."
    side = _direction(field, old, new, metric)
    if field == "weight_kg":
        return f"I heard you weigh {approx}{weight_words(new, metric)} now{side}."
    if field == "height_cm":
        return f"I heard you're {approx}{height_words(new, metric)} tall now{side}."
    if field == "sleep_hours":
        return f"I heard you sleep {approx}{count(new, 'hour')} a night now{side}."
    if field == "exercise_minutes_weekly":
        if new == 0:
            return "I heard you don't exercise now."
        return f"I heard you exercise {approx}{count(new, 'minute')} a week now{side}."
    if new == 0:
        return "I heard you don't drink alcohol now."
    return f"I heard you have {approx}{count(new, 'drink')} a week now{side}."


def big_change(field: str, values: dict, profile: dict, metric: bool = False) -> str | None:
    """A gentle double-check for a big jump ("That's quite a change from 160 to 120
    pounds. Is 120 right?"); None for an ordinary change."""
    old, new = profile.get(field), values[field]
    if old is None:
        return None
    if field == "weight_kg" and abs(new - old) >= max(0.15 * old, 15):
        unit = "kg" if metric else "pounds"
        before, after = weight_number(old, metric), weight_number(new, metric)
        return f"That's quite a change from {before} to {after} {unit}. Is {after} right?"
    if field == "height_cm" and abs(new - old) >= 5:
        before, after = height_words(old, metric), height_words(new, metric)
        return f"That's quite a change from {before} to {after}. Is {after} right?"
    if field == "sleep_hours" and abs(new - old) >= 3:
        return (
            f"That's quite a change from {plain(old)} to {plain(new)} hours a night. "
            f"Is {count(new, 'hour')} right?"
        )
    if field == "exercise_minutes_weekly" and abs(new - old) >= 300:
        return (
            f"That's quite a change from {plain(old)} to {plain(new)} minutes a week. "
            f"Is {count(new, 'minute')} right?"
        )
    if field == "alcohol_drinks_weekly" and abs(new - old) >= 14:
        return (
            f"That's quite a change from {plain(old)} to {plain(new)} drinks a week. "
            f"Is {count(new, 'drink')} right?"
        )
    if field == "systolic_bp" and profile.get("diastolic_bp") is not None:
        if abs(new - old) >= 30 or abs(values["diastolic_bp"] - profile["diastolic_bp"]) >= 20:
            before, after = bp_words(profile), bp_words(values)
            return f"That's quite a change from {before} to {after}. Is {after} right?"
    if field == "smoking_status" and (old == "never" or (old == "former" and new == "never")):
        if new != old and new != "unknown":
            return f"Before, you told me {SMOKING_TOLD[old]}. So {SMOKING_SO[new]}. Is that right?"
    return None
