"""Confirmed answers as the on-device model's inputs, plus coarse hints for the twin.

Codes and units are the package's (model_handoff/lifetwin_on_device, assets/model.json):

| Model input | From the profile | Code |
|---|---|---|
| age | age | years, whole number (estimates for 35-79 only) |
| sex_nhanes | sex | male 1, female 2 |
| bmi | height_cm + weight_kg | the package derives it; both or neither are sent |
| smoking_status | smoking_status | never 0, former 1, current 2 ("unknown" is unknown) |
| diabetes_diagnosed | diabetes | no 0, yes 1 |
| hypertension_diagnosed | hypertension | no 0, yes 1 |
| general_health | general_health | excellent 1, very good 2, good 3, fair 4, poor 5 |
| sleep_hours | sleep_hours | hours, 2-12 |
| vigorous_recreation_min_week | vigorous_recreation_min_week | minutes a week |
| moderate_recreation_min_week | moderate_recreation_min_week | minutes a week |
| sedentary_min_day | sedentary_min_day | minutes a day |

Nothing is filled in: a missing answer stays missing, and with any input missing
the model gives no number. Values outside the package's entry ranges are left out.
"""

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import (
    CharacterHints,
    HabitNote,
    ModelInput,
    ModelInputs,
    ModelProfile,
)

INPUTS: dict[ModelInput, tuple[str, ...]] = {
    "age": ("age",),
    "sex_nhanes": ("sex",),
    "bmi": ("height_cm", "weight_kg"),
    "smoking_status": ("smoking_status",),
    "diabetes_diagnosed": ("diabetes",),
    "hypertension_diagnosed": ("hypertension_diagnosed",),
    "general_health": ("general_health",),
    "sleep_hours": ("sleep_hours",),
    "vigorous_recreation_min_week": ("vigorous_recreation_min_week",),
    "moderate_recreation_min_week": ("moderate_recreation_min_week",),
    "sedentary_min_day": ("sedentary_min_day",),
}
SEX = {"male": 1, "female": 2}
SMOKING = {"never": 0, "former": 1, "current": 2}
HEALTH = {"excellent": 1, "very_good": 2, "good": 3, "fair": 4, "poor": 5}
# The package's numeric_bounds (entry ranges), and its height/weight check.
BOUNDS = {
    "sleep_hours": (2.0, 12.0),
    "vigorous_recreation_min_week": (0, 10073),
    "moderate_recreation_min_week": (0, 10073),
    "sedentary_min_day": (0, 1439),
    "height_cm": (100, 230),
    "weight_kg": (25, 350),
}
AGE_RANGE = (35, 79)


def _within(name: str, value) -> bool:
    low, high = BOUNDS.get(name, (float("-inf"), float("inf")))
    return value is not None and low <= value <= high


def model_inputs(
    profile: HealthProfile,
    unknown: list[str] = (),
    skipped: list[str] = (),
    estimated: list[str] = (),
) -> ModelInputs:
    p = profile
    values = {
        "age": p.age,
        "sex_nhanes": SEX.get(p.sex or ""),
        "smoking_status": SMOKING.get(p.smoking_status or ""),
        "diabetes_diagnosed": None if p.diabetes is None else int(p.diabetes),
        "hypertension_diagnosed": None
        if p.hypertension_diagnosed is None
        else int(p.hypertension_diagnosed),
        "general_health": HEALTH.get(p.general_health or ""),
        "sleep_hours": p.sleep_hours,
        "vigorous_recreation_min_week": p.vigorous_recreation_min_week,
        "moderate_recreation_min_week": p.moderate_recreation_min_week,
        "sedentary_min_day": p.sedentary_min_day,
    }
    values = {
        name: value if value is None or name not in BOUNDS or _within(name, value) else None
        for name, value in values.items()
    }
    body = _within("height_cm", p.height_cm) and _within("weight_kg", p.weight_kg)
    if (
        body
        and values["sleep_hours"] is not None
        and values["sedentary_min_day"] is not None
        and values["sleep_hours"] * 60 + values["sedentary_min_day"] > 1440
    ):
        values["sedentary_min_day"] = None  # more than a day: the package would refuse it
    known = {name for name, value in values.items() if value is not None}
    if body:
        known.add("bmi")

    def named(fields) -> list[ModelInput]:
        return [name for name, sources in INPUTS.items() if set(sources) & set(fields)]

    missing = [name for name in INPUTS if name not in known]
    unknown_inputs = [name for name in named(unknown) if name in missing]
    if p.smoking_status == "unknown" and "smoking_status" not in unknown_inputs:
        unknown_inputs.append("smoking_status")
    if p.age is not None and not AGE_RANGE[0] <= p.age <= AGE_RANGE[1]:
        status = "unsupported_age"
    else:
        status = "still_learning" if missing else "ready"
    return ModelInputs(
        status=status,
        profile=ModelProfile(
            **values,
            height_cm=p.height_cm if body else None,
            weight_kg=p.weight_kg if body else None,
        ),
        missing=missing,
        unknown=unknown_inputs,
        skipped=[name for name in named(skipped) if name in missing],
        estimated=[name for name in named(estimated) if name in known],
    )


GOOD_FEELINGS = {"great", "good", "lucky", "grateful", "hopeful"}
LOW_FEELINGS = {"not great", "worried", "frustrated", "down", "tired"}


def character_hints(profile: HealthProfile, notes: list[HabitNote]) -> CharacterHints:
    """mood: how the person says they feel; energy: sleep and activity. Coarse and kind.

    mood: a feeling in their own words wins ("lucky", "worried"); otherwise the
    rating: excellent/very good/good -> "good", fair -> "okay", poor -> "not_great".
    energy: activity of 150+ moderate-equivalent minutes a week (vigorous counts
    double) -> "high", 30-149 -> "medium", under 30 -> "low"; under 6 hours of sleep
    takes it one step down. With sleep only, 6+ hours -> "medium", under 6 -> "low".
    """
    mood = None
    feeling = next((note.feeling for note in reversed(notes) if note.feeling), None)
    if feeling in GOOD_FEELINGS:
        mood = "good"
    elif feeling in LOW_FEELINGS:
        mood = "not_great"
    elif feeling == "okay":
        mood = "okay"
    elif profile.general_health:
        mood = {"fair": "okay", "poor": "not_great"}.get(profile.general_health, "good")
    energy = None
    moderate, vigorous = profile.moderate_recreation_min_week, profile.vigorous_recreation_min_week
    if moderate is not None or vigorous is not None:
        minutes = (moderate or 0) + 2 * (vigorous or 0)
    else:
        minutes = profile.exercise_minutes_weekly
    levels = ["low", "medium", "high"]
    if minutes is not None:
        level = 2 if minutes >= 150 else 1 if minutes >= 30 else 0
        if profile.sleep_hours is not None and profile.sleep_hours < 6:
            level = max(level - 1, 0)
        energy = levels[level]
    elif profile.sleep_hours is not None:
        energy = "medium" if profile.sleep_hours >= 6 else "low"
    return CharacterHints(mood=mood, energy=energy)
