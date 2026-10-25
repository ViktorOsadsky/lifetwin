"""Lever ranking from docs/model-sensitivity.json (branch codex/d-model-sensitivity, 65acf39).

That scan ranks the recommendable levers by their median modeled 5-year difference
for each age band and sex; the order is identical in every group, so only the order
is kept here. No percentage points are copied: Mochi never quotes them, and the app
computes a person's own difference with the on-device ``compare()``.
``test_recommendations.py`` checks this order against the JSON when it is present.
"""

MODEL_VERSION = "personal-cox-v2-20261024T182404Z"
SOURCE = "docs/model-sensitivity.json"
LEVER_ORDER: tuple[str, ...] = (
    "quit_smoking",
    "vigorous_plus_60",
    "moderate_plus_90",
    "short_sleep_plus_1h",
    "sitting_minus_60_realistic",
)

# Model input field behind each lever, in ranking order (used for missing_inputs).
LEVER_FIELD: dict[str, str] = {
    "quit_smoking": "smoking_status",
    "vigorous_plus_60": "vigorous_recreation_min_week",
    "moderate_plus_90": "moderate_recreation_min_week",
    "short_sleep_plus_1h": "sleep_hours",
    "sitting_minus_60_realistic": "sedentary_min_day",
}
MIN_ADULT_AGE = 18
UNDER_AGE = (
    "I'm only able to share ideas with adults for now. "
    "A parent, guardian or your doctor is the best person to ask about healthy habits."
)


# Effect-size cue. Category cut-offs on the modeled 5-year survival difference, in
# percentage points (docs/model-sensitivity.json). The numbers stay on the server:
# only the category is returned, never a figure.
EFFECT_THRESHOLDS_PP: tuple[tuple[str, float], ...] = (
    ("big", 2.0),
    ("some", 0.75),
    ("small", 0.25),
)  # anything lower is "tiny"
EFFECT_AGE_RANGE = (18, 85)
EFFECT_NOTE = "Modeled difference for people like you, not a promise."

# Median modeled difference (pp) per lever, copied from the JSON's "groups" (age band,
# age band|sex, or "all"). The JSON only has bands 35-49, 50-64 and 65-79; other ages
# fall back to "all". ``test_recommendation_effect.py`` checks this table against the JSON.
MEDIAN_PP: dict[str, dict[str, float]] = {
    "all": {
        "quit_smoking": 1.053,
        "vigorous_plus_60": 0.6364,
        "moderate_plus_90": 0.4085,
        "short_sleep_plus_1h": 0.156,
        "sitting_minus_60_realistic": 0.1544,
    },
    "35-49": {
        "quit_smoking": 0.5728,
        "vigorous_plus_60": 0.2196,
        "moderate_plus_90": 0.1919,
        "short_sleep_plus_1h": 0.0637,
        "sitting_minus_60_realistic": 0.0557,
    },
    "50-64": {
        "quit_smoking": 1.6675,
        "vigorous_plus_60": 0.7895,
        "moderate_plus_90": 0.6978,
        "short_sleep_plus_1h": 0.2043,
        "sitting_minus_60_realistic": 0.1764,
    },
    "65-79": {
        "quit_smoking": 4.8122,
        "vigorous_plus_60": 2.0683,
        "moderate_plus_90": 2.0103,
        "short_sleep_plus_1h": 0.5049,
        "sitting_minus_60_realistic": 0.4638,
    },
    "35-49|male": {
        "quit_smoking": 0.6212,
        "vigorous_plus_60": 0.2784,
        "moderate_plus_90": 0.2528,
        "short_sleep_plus_1h": 0.0782,
        "sitting_minus_60_realistic": 0.068,
    },
    "35-49|female": {
        "quit_smoking": 0.5019,
        "vigorous_plus_60": 0.1859,
        "moderate_plus_90": 0.1482,
        "short_sleep_plus_1h": 0.0521,
        "sitting_minus_60_realistic": 0.0452,
    },
    "50-64|male": {
        "quit_smoking": 1.9506,
        "vigorous_plus_60": 0.9422,
        "moderate_plus_90": 0.8665,
        "short_sleep_plus_1h": 0.2342,
        "sitting_minus_60_realistic": 0.215,
    },
    "50-64|female": {
        "quit_smoking": 1.3535,
        "vigorous_plus_60": 0.6811,
        "moderate_plus_90": 0.6084,
        "short_sleep_plus_1h": 0.1667,
        "sitting_minus_60_realistic": 0.1513,
    },
    "65-79|male": {
        "quit_smoking": 5.2514,
        "vigorous_plus_60": 2.4429,
        "moderate_plus_90": 2.235,
        "short_sleep_plus_1h": 0.6306,
        "sitting_minus_60_realistic": 0.5351,
    },
    "65-79|female": {
        "quit_smoking": 4.6009,
        "vigorous_plus_60": 1.7306,
        "moderate_plus_90": 1.5893,
        "short_sleep_plus_1h": 0.4053,
        "sitting_minus_60_realistic": 0.3884,
    },
}


def _band(age: int) -> str | None:
    for low, high in ((35, 49), (50, 64), (65, 79)):
        if low <= age <= high:
            return f"{low}-{high}"
    return None


def effect_category(lever: str, age: int | None, sex: str | None) -> str | None:
    """Big/some/small/tiny for a lever and person, or None when there is nothing modeled."""
    if age is not None and not EFFECT_AGE_RANGE[0] <= age <= EFFECT_AGE_RANGE[1]:
        return None
    band = _band(age) if age is not None else None
    for key in (f"{band}|{sex}", band, "all"):
        pp = MEDIAN_PP.get(key, {}).get(lever) if key else None
        if pp is not None:
            break
    else:
        return None
    return category_for_pp(pp)


def category_for_pp(pp: float) -> str:
    return next((name for name, low in EFFECT_THRESHOLDS_PP if pp >= low), "tiny")
