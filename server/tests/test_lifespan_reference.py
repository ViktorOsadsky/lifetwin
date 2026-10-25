"""Tests for the lifespan research prototype (server/tools/lifespan_reference.py)."""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

import lifespan_reference as lr  # noqa: E402
import lifespan_validation as lv  # noqa: E402


@pytest.fixture(scope="module")
def inputs() -> lr.Inputs:
    return lr.Inputs()


def test_hr_one_reproduces_the_life_table(inputs: lr.Inputs) -> None:
    for sex in ("male", "female"):
        t = inputs.life_table[sex]
        recomputed = lv.recompute_ex(t["qx"], t["e100"])
        for age in range(1, 100):
            le = lr.estimate(t["qx"], t["e100"], float(age), 0.0, None)["life_expectancy_years"]
            assert le == pytest.approx(recomputed[age], abs=1e-9)
            assert le == pytest.approx(t["ex"][age], abs=2e-5)  # spreadsheet is float32
    # NVSR 75-5 Table A.
    for sex, e65 in lv.PUBLISHED_E65.items():
        t = inputs.life_table[sex]
        assert lr.estimate(t["qx"], t["e100"], 65.0, 0.0)["life_expectancy_years"] == pytest.approx(
            e65, abs=0.05
        )


def test_higher_hr_lowers_life_expectancy(inputs: lr.Inputs) -> None:
    for sex in ("male", "female"):
        t = inputs.life_table[sex]
        for age in (30.0, 47.5, 65.0, 85.0):
            for hl in (None, 20.0, 10.0):
                les = [
                    lr.estimate(t["qx"], t["e100"], age, lhr, hl)["life_expectancy_years"]
                    for lhr in (-1.5, -0.5, 0.0, 0.5, 1.5)
                ]
                assert les == sorted(les, reverse=True)
                assert len(set(les)) == len(les)


def test_percentiles_ordered_and_not_below_age(inputs: lr.Inputs) -> None:
    for sex in ("male", "female"):
        t = inputs.life_table[sex]
        for age in (30.0, 34.5, 60.0, 79.9, 85.0):
            for lhr in (-2.0, 0.0, 2.5):
                r = lr.estimate(t["qx"], t["e100"], age, lhr)
                assert age <= r["age_25th_percentile"] < r["median_age"] < r["age_75th_percentile"]
                assert r["range_low_age"] <= r["headline_age"] <= r["range_high_age"]
                assert r["sd_years"] > 0
                survival = [s for _, s in r["survival_curve"]]
                assert survival == sorted(survival, reverse=True)
                assert r["survival_curve"][-1][0] == 110


def test_median_matches_survival_curve(inputs: lr.Inputs) -> None:
    t = inputs.life_table["female"]
    r = lr.estimate(t["qx"], t["e100"], 60.0, 0.4, None)
    median = r["median_age"]
    lower = max(s for a, s in r["survival_curve"] if a <= median)
    upper = min(s for a, s in r["survival_curve"] if a >= median)
    assert lower >= 0.5 >= upper


def test_reference_makes_mean_hr_about_one(inputs: lr.Inputs) -> None:
    rows = lv.decoded_rows(inputs)
    for sex in ("male", "female"):
        sel = [r for r in rows if r["sex"] == sex]
        hrs = [
            math.exp(r["risk"] - lr.reference_score(inputs.reference[sex], r["age"])) for r in sel
        ]
        assert sum(hrs) / len(hrs) == pytest.approx(1.0, abs=0.03)


def test_band_adjustment_matches_cox_five_year_survival(inputs: lr.Inputs) -> None:
    """After the per-band hazard factor, mean life-table S5 == mean Cox S5 within 0.5 pp."""
    s0_5 = inputs.model["baseline_survival"][4]
    for sex in ("male", "female"):
        qx = inputs.life_table[sex]["qx"]
        for band, (lo, hi) in enumerate(lr.CALIBRATION_BANDS):
            sel = [r for r in inputs.rows if r["sex"] == sex and lo <= r["age"] <= hi]
            cox = sum(s0_5 ** math.exp(r["full"]) for r in sel) / len(sel)
            c = inputs.band_log_adjustment[sex][band]
            lt = sum(
                lr.five_year_survival(
                    qx,
                    int(r["age"]),
                    r["risk"] - lr.reference_score(inputs.reference[sex], r["age"]) + c,
                )
                for r in sel
            ) / len(sel)
            assert abs(100 * (lt - cox)) < 0.5


def test_extrapolated_ages_use_the_nearest_band(inputs: lr.Inputs) -> None:
    assert [lr.band_index(a) for a in (18, 34, 35, 44, 45, 79, 80, 85)] == [0, 0, 0, 0, 1, 4, 4, 4]
    p = lr.EXAMPLE_PROFILES["female_20_typical"]
    assert lr.log_hazard_ratio(inputs, p) - lr.log_hazard_ratio(inputs, p, adjusted=False) == (
        pytest.approx(inputs.band_log_adjustment["female"][0])
    )


def test_headline_wording_and_calendar_year(inputs: lr.Inputs) -> None:
    g = lr.build_golden(inputs)["calendar_example"]
    assert g["headline"].startswith("You're likely to live to about ")
    assert "die" not in g["headline"]
    assert g["expected_calendar_year"] == 2065


def test_profile_checks() -> None:
    p = lr.EXAMPLE_PROFILES["male_45_readme"]
    for bad in (
        {"age": 17},
        {"age": 86},
        {"bmi": None},
        {"smoking_status": 3},
        {"bmi": float("nan")},
    ):
        with pytest.raises(ValueError):
            lr.check_profile(p | bad)


_NUMBER = re.compile(r"-?\d+\.\d+(?:[eE][-+]?\d+)?")


def _close(a: object, b: object) -> bool:
    # Floats may differ in the last bits between platforms' maths libraries.
    if isinstance(a, float) or isinstance(b, float):
        return (
            isinstance(a, (int, float))
            and isinstance(b, (int, float))
            and math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-12)
        )
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_close(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_close(x, y) for x, y in zip(a, b, strict=True))
    return a == b


def test_golden_and_dart_data_are_current(inputs: lr.Inputs) -> None:
    """Regenerate with: python server/tools/lifespan_reference.py build"""
    assert _close(
        json.loads(lr.GOLDEN.read_text()), json.loads(json.dumps(lr.build_golden(inputs)))
    )
    saved, fresh = lr.DART_DATA.read_text(), lr.render_dart_data(inputs)
    assert _NUMBER.sub("#", saved) == _NUMBER.sub("#", fresh)
    assert _close(
        [float(n) for n in _NUMBER.findall(saved)], [float(n) for n in _NUMBER.findall(fresh)]
    )
