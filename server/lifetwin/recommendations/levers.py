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
        "quit_smoking": 1.0228,
        "vigorous_plus_60": 0.6442,
        "moderate_plus_90": 0.4177,
        "short_sleep_plus_1h": 0.1608,
        "sitting_minus_60_realistic": 0.1594,
    },
    "35-49": {
        "quit_smoking": 0.5491,
        "vigorous_plus_60": 0.2237,
        "moderate_plus_90": 0.1947,
        "short_sleep_plus_1h": 0.0656,
        "sitting_minus_60_realistic": 0.0577,
    },
    "50-64": {
        "quit_smoking": 1.655,
        "vigorous_plus_60": 0.7998,
        "moderate_plus_90": 0.7121,
        "short_sleep_plus_1h": 0.2118,
        "sitting_minus_60_realistic": 0.182,
    },
    "65-79": {
        "quit_smoking": 4.7378,
        "vigorous_plus_60": 2.1091,
        "moderate_plus_90": 2.0187,
        "short_sleep_plus_1h": 0.5152,
        "sitting_minus_60_realistic": 0.4805,
    },
    "35-49|male": {
        "quit_smoking": 0.6118,
        "vigorous_plus_60": 0.2786,
        "moderate_plus_90": 0.2591,
        "short_sleep_plus_1h": 0.0788,
        "sitting_minus_60_realistic": 0.0702,
    },
    "35-49|female": {
        "quit_smoking": 0.4977,
        "vigorous_plus_60": 0.1897,
        "moderate_plus_90": 0.1527,
        "short_sleep_plus_1h": 0.0548,
        "sitting_minus_60_realistic": 0.0476,
    },
    "50-64|male": {
        "quit_smoking": 1.9048,
        "vigorous_plus_60": 0.9718,
        "moderate_plus_90": 0.8737,
        "short_sleep_plus_1h": 0.2439,
        "sitting_minus_60_realistic": 0.2222,
    },
    "50-64|female": {
        "quit_smoking": 1.3362,
        "vigorous_plus_60": 0.7024,
        "moderate_plus_90": 0.6131,
        "short_sleep_plus_1h": 0.1712,
        "sitting_minus_60_realistic": 0.1563,
    },
    "65-79|male": {
        "quit_smoking": 5.0548,
        "vigorous_plus_60": 2.4935,
        "moderate_plus_90": 2.2762,
        "short_sleep_plus_1h": 0.6518,
        "sitting_minus_60_realistic": 0.5586,
    },
    "65-79|female": {
        "quit_smoking": 4.3865,
        "vigorous_plus_60": 1.7642,
        "moderate_plus_90": 1.6705,
        "short_sleep_plus_1h": 0.4179,
        "sitting_minus_60_realistic": 0.3944,
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
