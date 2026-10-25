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
