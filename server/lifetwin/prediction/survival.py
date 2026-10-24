"""Victor's DeepSurv survival model, served without TensorFlow.

The Keras weights are read from ``model.keras`` (a zip holding ``model.weights.h5``) and the
three Dense layers run as a numpy forward pass; Dropout is inactive at inference. Survival is
``S(t) = exp(-H0(t) * exp(risk))`` with ``H0`` the last baseline row at or before ``t``.
"""

import csv
import hashlib
import io
import json
import math
import zipfile
from dataclasses import dataclass
from pathlib import Path

import h5py
import joblib
import numpy as np
import pandas as pd

from lifetwin.core.models import HealthProfile
from lifetwin.prediction.models import (
    CurvePoint,
    FilledInput,
    HorizonSurvival,
    PredictionResponse,
)

# server/lifetwin/prediction/survival.py -> repository root.
DEFAULT_MODEL_DIR = Path(__file__).resolve().parents[3]
ARTIFACTS = ("model.keras", "preprocessor.joblib", "baseline_hazard.csv", "metrics.json")
DENSE_LAYERS = ("dense", "dense_1", "dense_2")
MIN_AGE = 18
MAX_AGE = 80

# Plain words for each model input, used when the missing-value policy fills one in.
FEATURE_LABELS = {
    "age": "age",
    "bmi": "height and weight",
    "sleep_hours": "hours of sleep",
    "vigorous_recreation_min_week": "hard exercise each week",
    "moderate_recreation_min_week": "exercise each week",
    "sedentary_min_day": "time spent sitting each day",
    "sex_nhanes": "sex at birth",
    "smoking_status": "smoking",
    "diabetes_diagnosed": "diabetes",
    "hypertension_diagnosed": "high blood pressure",
    "general_health": "how you rate your health",
}
SMOKING_CODES = {"never": 0.0, "former": 1.0, "current": 2.0}
# Few training rows lacked these, and the model's missing-value indicators for them swing
# the result far more than any real answer (e.g. a missing sleep answer moved a 5-year
# figure from 88% to 99%). A forecast without them would be invented, so it is unsupported.
REQUIRED_ANSWERS = {
    "bmi": "your height and weight",
    "sleep_hours": "how many hours you sleep",
    "moderate_recreation_min_week": "how many minutes you exercise each week",
}
EXTRA_LIMITATIONS = [
    "Smoking answers are assumed to be coded 0 never, 1 former, 2 current; "
    "the model author has not yet confirmed this coding.",
    "Time spent sitting, high blood pressure and general health are not asked yet; "
    "the model's missing-value rule fills them in, which can change the result.",
    "The weekly exercise answer is used as moderate exercise with no extra hard exercise.",
    "Survival is shown only up to 5 years, the longest horizon the model supports.",
    "These are averages for people with similar answers in a US survey, not a promise "
    "and not a date.",
]


class ArtifactsMissing(Exception):
    """One or more model files are absent; the prediction route stays deferred (501)."""


@dataclass(frozen=True)
class SurvivalModel:
    preprocessor: object
    layers: tuple[tuple[np.ndarray, np.ndarray], ...]
    baseline_times: np.ndarray
    baseline_hazard: np.ndarray
    horizons: tuple[int, ...]
    max_horizon_years: int
    limitations: tuple[str, ...]
    version: str

    @classmethod
    def load(cls, directory: str | Path) -> "SurvivalModel":
        directory = Path(directory)
        paths = [directory / name for name in ARTIFACTS]
        if not all(path.is_file() for path in paths):
            raise ArtifactsMissing(str(directory))
        digest = hashlib.sha256()
        for path in paths:
            digest.update(path.read_bytes())

        with zipfile.ZipFile(paths[0]) as archive:
            weights = io.BytesIO(archive.read("model.weights.h5"))
        with h5py.File(weights, "r") as h5:
            layers = tuple(
                (
                    np.asarray(h5[f"layers/{name}/vars/0"], dtype=np.float64),
                    np.asarray(h5[f"layers/{name}/vars/1"], dtype=np.float64),
                )
                for name in DENSE_LAYERS
            )
        preprocessor = joblib.load(paths[1])
        with paths[2].open(newline="") as handle:
            rows = [
                (float(row["time_years"]), float(row["cum_baseline_hazard"]))
                for row in csv.DictReader(handle)
            ]
        times = np.array([time for time, _ in rows])
        hazard = np.array([value for _, value in rows])
        if np.any(np.diff(times) <= 0) or np.any(np.diff(hazard) < 0) or np.any(hazard < 0):
            raise ValueError("baseline_hazard.csv must be sorted with a nondecreasing hazard")
        metrics = json.loads(paths[3].read_text())
        horizons = tuple(int(h) for h in metrics["supported_horizons_years"])
        expected_inputs = layers[0][0].shape[0]
        if len(preprocessor.get_feature_names_out()) != expected_inputs:
            raise ValueError("Preprocessor output does not match the model input size")
        return cls(
            preprocessor=preprocessor,
            layers=layers,
            baseline_times=times,
            baseline_hazard=hazard,
            horizons=horizons,
            max_horizon_years=max(horizons),
            limitations=tuple(metrics["limitations"]) + tuple(EXTRA_LIMITATIONS),
            version="deepsurv-nhanes-" + digest.hexdigest()[:12],
        )

    @property
    def feature_names(self) -> list[str]:
        return list(self.preprocessor.feature_names_in_)

    def risks(self, rows: list[dict[str, float | None]]) -> np.ndarray:
        """Log relative risk for each row of raw model inputs (None means missing)."""
        frame = pd.DataFrame(rows, columns=self.feature_names).astype(float)
        values = np.asarray(self.preprocessor.transform(frame), dtype=np.float64)
        for index, (kernel, bias) in enumerate(self.layers):
            values = values @ kernel + bias
            if index < len(self.layers) - 1:
                values = np.maximum(values, 0.0)
        return values.reshape(-1)

    def survival_at(self, risk: float, years: float) -> float:
        index = np.searchsorted(self.baseline_times, years, side="right") - 1
        hazard = self.baseline_hazard[index] if index >= 0 else 0.0
        return math.exp(-float(hazard) * math.exp(risk))

    def predict(self, profile: HealthProfile) -> PredictionResponse:
        row = model_inputs(profile)
        reason = unsupported_reason(profile, row)
        if reason:
            return PredictionResponse(
                status="unsupported",
                model_version=self.version,
                max_horizon_years=self.max_horizon_years,
                survival=[],
                curve=[],
                filled_in=[],
                reason=reason,
                limitations=list(self.limitations),
            )
        risk = float(self.risks([row])[0])
        survival = [
            HorizonSurvival(years=years, survival=round(self.survival_at(risk, years), 4))
            for years in self.horizons
        ]
        curve = [CurvePoint(years=0.0, survival=1.0)] + [
            CurvePoint(years=round(float(time), 4), survival=round(self.survival_at(risk, time), 4))
            for time in self.baseline_times
            if time <= self.max_horizon_years
        ]
        return PredictionResponse(
            status="supported",
            model_version=self.version,
            max_horizon_years=self.max_horizon_years,
            survival=survival,
            curve=curve,
            filled_in=[
                FilledInput(feature=name, label=FEATURE_LABELS.get(name, name))
                for name in self.feature_names
                if row.get(name) is None
            ],
            limitations=list(self.limitations),
        )


def unsupported_reason(profile: HealthProfile, row: dict[str, float | None]) -> str | None:
    if profile.age is None or profile.sex is None:
        return "We need your age and your sex at birth to make a forecast."
    if profile.age > MAX_AGE:
        return (
            "The survey this forecast learns from does not record exact ages above 80, "
            "so we cannot make a forecast for you yet."
        )
    if profile.age < MIN_AGE:
        return "This forecast is made for adults aged 18 and over."
    missing = [words for name, words in REQUIRED_ANSWERS.items() if row[name] is None]
    if missing:
        listed = (
            missing[0] if len(missing) == 1 else ", ".join(missing[:-1]) + " and " + missing[-1]
        )
        pronoun = "it" if len(missing) == 1 else "them"
        return f"To make a forecast, we need to know {listed}. You can go back and add {pronoun}."
    return None


def model_inputs(profile: HealthProfile) -> dict[str, float | None]:
    """Map confirmed intake answers to model inputs; unasked or skipped answers stay None."""
    bmi = None
    if profile.height_cm is not None and profile.weight_kg is not None:
        bmi = profile.weight_kg / (profile.height_cm / 100) ** 2
    exercise = profile.exercise_minutes_weekly
    return {
        "age": float(profile.age) if profile.age is not None else None,
        "bmi": bmi,
        "sleep_hours": profile.sleep_hours,
        # The intake asks one exercise question; it counts as moderate activity, so there
        # are no extra hard-exercise minutes. Leaving this missing would trip a missing-value
        # indicator the model learned from about a dozen people (5-year 93% -> 99.6%).
        "vigorous_recreation_min_week": 0.0 if exercise is not None else None,
        "moderate_recreation_min_week": float(exercise) if exercise is not None else None,
        "sedentary_min_day": None,
        "sex_nhanes": {"male": 1.0, "female": 2.0}.get(profile.sex or ""),
        "smoking_status": SMOKING_CODES.get(profile.smoking_status or ""),
        "diabetes_diagnosed": None if profile.diabetes is None else float(profile.diabetes),
        "hypertension_diagnosed": None,
        "general_health": None,
    }


def load_model(directory: str) -> SurvivalModel | None:
    """Load from ``directory`` (blank means the repository root); None if files are missing."""
    try:
        return SurvivalModel.load(directory.strip() or DEFAULT_MODEL_DIR)
    except ArtifactsMissing:
        return None
