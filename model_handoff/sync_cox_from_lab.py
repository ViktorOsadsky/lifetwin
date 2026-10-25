#!/usr/bin/env python3
"""Copy the evaluated Survival Lab Cox release into both local Dart packages.

Run from the repository root after regenerating and checking the Survival Lab
artifacts. This does not retrain the model.
"""

import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "web/survival_lab"
PACKAGES = (
    ROOT / "model_handoff/lifetwin_on_device",
    ROOT / "app/packages/lifetwin_on_device",
)


def yearly_projection(model: dict, profile: dict) -> dict:
    """Independent Python calculation for the app's frozen yearly Dart fixture."""
    start_age = int(profile["age"])
    cumulative = 1.0
    crossing = None
    points = [[start_age, 100.0, False]]
    knot = int(model["encoded_features"][2].removeprefix("bmi_above"))
    for age in range(start_age, 110):
        p = dict(profile, age=age)
        encoded = [
            (age - 55) / 10,
            max(23 - p["bmi"], 0) / 5,
            max(p["bmi"] - knot, 0) / 5,
            max(7 - p["sleep_hours"], 0),
            max(p["sleep_hours"] - 8, 0),
            math.log1p(p["vigorous_recreation_min_week"]) / math.log(76),
            math.log1p(p["moderate_recreation_min_week"]) / math.log(151),
            (p["sedentary_min_day"] - 360) / 120,
            int(p["sex_nhanes"] == 2),
            int(p["smoking_status"] == 1),
            int(p["smoking_status"] == 2),
            p["diabetes_diagnosed"], p["hypertension_diagnosed"],
            *(int(p["general_health"] == level) for level in (2, 3, 4, 5)),
        ]
        score = sum(
            (value - center) * coefficient
            for value, center, coefficient in zip(
                encoded, model["feature_center"], model["coefficients"], strict=True
            )
        )
        next_survival = cumulative * model["baseline_survival"][0] ** math.exp(score)
        if crossing is None and cumulative > .5 >= next_survival:
            crossing = age + (cumulative - .5) / (cumulative - next_survival)
        cumulative = next_survival
        points.append([age + 1, 100 * cumulative, age > 79])
    return {
        "median_crossing_age": crossing,
        "median_crossing_extrapolated": crossing is not None and crossing > 80,
        "points": points,
    }


def main() -> None:
    model = json.loads((SITE / "assets/cox.json").read_text(encoding="utf-8"))
    if model["encoded_features"][2] != "bmi_above35" or model["coefficients"][2] <= 0:
        raise ValueError("Expected the evaluated positive-slope BMI35 Cox release")
    vectors = json.loads((SITE / "test/cox_vectors.json").read_text(encoding="utf-8"))
    supported = [v for v in vectors if 35 <= v["profile"]["age"] <= 79]
    if len(supported) != 3:
        raise ValueError("Expected exactly three supported Cox golden profiles")
    for package in PACKAGES:
        shutil.copyfile(SITE / "assets/cox.json", package / "assets/model.json")
        reference = (SITE / "assets/support_reference.f64").read_bytes()
        if (package / "assets/support_reference.f64.gz").exists():
            import gzip
            (package / "assets/support_reference.f64.gz").write_bytes(
                gzip.compress(reference, mtime=0)
            )
        else:
            (package / "assets/support_reference.f64").write_bytes(reference)
        (package / "test/golden_vectors.json").write_text(
            json.dumps(supported, indent=2) + "\n", encoding="utf-8"
        )
    snapshot_path = PACKAGES[1] / "test/fixtures/snapshot_response.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    first = supported[0]
    profile = snapshot["profile_used"]
    if not (23 <= profile["bmi"] <= 35) or any(
        profile[key] != value for key, value in first["profile"].items() if key != "bmi"
    ):
        raise ValueError("Snapshot is no longer the supported flat-BMI golden profile")
    survival = snapshot["survival"]
    survival["model_version"] = model["model_version"]
    survival["log_relative_hazard_score"] = first["log_relative_hazard_score"]
    survival["survival_probabilities"] = first["survival_probabilities"]
    survival["survival_percent_by_year"] = {
        year: 100 * probability
        for year, probability in first["survival_probabilities"].items()
    }
    snapshot_path.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    projection_path = ROOT / "app/test/twin/rosa_projection_golden.json"
    projection = json.loads(projection_path.read_text(encoding="utf-8"))
    projection["source"] = f"independent Python calculation from {model['model_version']}"
    projection.update(yearly_projection(model, projection["profile"]))
    projection_path.write_text(json.dumps(projection, indent=1) + "\n", encoding="utf-8")
    reference_tool = ROOT / "server/tools/lifespan_reference.py"
    subprocess.run([sys.executable, str(reference_tool), "build"], cwd=ROOT, check=True)
    report = subprocess.check_output(
        [sys.executable, str(reference_tool), "validate"], cwd=ROOT, text=True
    )
    report = report.partition("\n\n")[2].replace("## ", "### ", 1)
    report = report.replace("\n## ", "\n### ")
    lifespan_doc = ROOT / "docs/lifespan-estimate.md"
    old_doc = lifespan_doc.read_text(encoding="utf-8")
    heading = "## CDC component calculation checks\n"
    before, separator, rest = old_doc.partition(heading)
    section, limits, after = rest.partition("## Limits\n")
    if not separator or not limits or not section:
        raise ValueError("Cannot locate lifespan validation section")
    validation = (
        heading + "\n"
        f"Generated by `lifespan_reference.py validate` (model `{model['model_version']}`). "
        "The following tables are for the current packaged model.\n\n"
        + report.strip() + "\n\n"
    )
    lifespan_doc.write_text(before + validation + limits + after, encoding="utf-8")
    print(f"Copied {model['model_version']} to handoff and app package")


if __name__ == "__main__":
    main()
