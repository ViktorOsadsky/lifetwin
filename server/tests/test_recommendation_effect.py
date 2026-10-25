import json
from pathlib import Path

import pytest

import lifetwin.onboarding  # noqa: F401  (import first: avoids a pre-existing import cycle)
from lifetwin.core.models import HealthProfile
from lifetwin.recommendations import levers
from lifetwin.recommendations.ideas import IDEAS
from lifetwin.recommendations.levers import EFFECT_NOTE, category_for_pp, effect_category
from lifetwin.recommendations.service import suggest

# Coping tricks carry no effect cue; set them aside so each lever shows its habit change.
COPING = [idea.id for idea in IDEAS if idea.coping]

SENSITIVITY = Path(__file__).resolve().parents[2] / "docs" / "model-sensitivity.json"


def recs(**profile):
    return {r.lever: r for r in suggest(HealthProfile(**profile), [], excluded_ids=COPING)}


def test_smoker_65_to_79_gets_big_for_quitting():
    found = recs(age=70, sex="male", smoking_status="current")
    assert found["quit_smoking"].effect == "big"
    assert found["quit_smoking"].effect_note == EFFECT_NOTE
    assert found["quit_smoking"].causal_interpretation is False


def test_short_sleeper_plus_one_hour_is_small_or_tiny():
    found = recs(age=40, sex="female", sleep_hours=5.5)
    assert found["short_sleep_plus_1h"].effect in {"small", "tiny"}
    assert recs(age=70, sex="male", sleep_hours=5.5)["short_sleep_plus_1h"].effect == "small"


def test_guideline_only_items_have_no_effect():
    found = recs(
        age=50, sex="male", moderate_recreation_min_week=200, vigorous_recreation_min_week=0
    )
    assert found["keep_it_up"].effect is None


@pytest.mark.parametrize(
    ("pp", "name"),
    [
        (2.0, "big"),
        (1.99, "some"),
        (0.75, "some"),
        (0.7499, "small"),
        (0.25, "small"),
        (0.2499, "tiny"),
        (0.0, "tiny"),
    ],
)
def test_threshold_edges(pp, name):
    assert category_for_pp(pp) == name


@pytest.mark.parametrize("age", [0, 17, 86, 100])
def test_outside_18_to_85_is_null(age):
    assert effect_category("quit_smoking", age, "male") is None
    assert recs(age=age, smoking_status="current")["quit_smoking"].effect is None


def test_ages_without_a_band_use_the_overall_median():
    assert effect_category("quit_smoking", 25, "male") == "some"  # overall 1.05 pp
    assert effect_category("quit_smoking", 85, None) == "some"


def test_table_matches_the_sensitivity_json():
    sensitivity = json.loads(SENSITIVITY.read_text())
    assert levers.MODEL_VERSION == sensitivity["model_version"]
    groups = sensitivity["groups"]
    for key, medians in levers.MEDIAN_PP.items():
        group = groups[key if "|" in key or key == "all" else f"age:{key}"]
        want = {r["lever"]: r["median_pp"] for r in group["recommendable_levers_ranked"]}
        assert medians == want
