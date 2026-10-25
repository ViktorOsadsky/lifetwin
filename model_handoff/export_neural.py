"""Export the existing temporal DeepSurv network to portable inference JSON.

Run with the scientific Python environment from the repository root:
python lifetwin/model_handoff/export_neural.py
"""

import io
import json
import zipfile
from pathlib import Path

import h5py
import joblib
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "output/models/temporal_deepsurv_35_79"
TARGET = Path(__file__).resolve().parent / "lifetwin_on_device"
NUMERIC = [
    "age", "bmi", "sleep_hours", "vigorous_recreation_min_week",
    "moderate_recreation_min_week", "sedentary_min_day",
]
CATEGORICAL = [
    "sex_nhanes", "smoking_status", "diabetes_diagnosed",
    "hypertension_diagnosed", "general_health",
]
NUMERIC_BOUNDS = {
    "bmi": [10, 85], "sleep_hours": [2, 12],
    "vigorous_recreation_min_week": [0, 10073],
    "moderate_recreation_min_week": [0, 10073],
    "sedentary_min_day": [0, 1439],
}
REFERENCE = {
    "age": 55, "bmi": 27, "sleep_hours": 7,
    "vigorous_recreation_min_week": 0, "moderate_recreation_min_week": 150,
    "sedentary_min_day": 360, "sex_nhanes": 1, "smoking_status": 0,
    "diabetes_diagnosed": 0, "hypertension_diagnosed": 0,
    "general_health": 3,
}


def main():
    prep = joblib.load(SOURCE / "preprocessor.joblib")
    numeric = prep.named_transformers_["numeric"]
    categories = prep.named_transformers_["categorical"]["onehot"].categories_
    with zipfile.ZipFile(SOURCE / "model.keras") as archive:
        with h5py.File(io.BytesIO(archive.read("model.weights.h5"))) as weights:
            layers = [
                {
                    "kernel": np.asarray(weights[f"layers/{name}/vars/0"]).tolist(),
                    "bias": np.asarray(weights[f"layers/{name}/vars/1"]).tolist(),
                }
                for name in ("dense", "dense_1", "dense_2")
            ]
    x = prep.transform(pd.DataFrame([REFERENCE], columns=NUMERIC + CATEGORICAL))
    z = x.astype(np.float64)
    for i, layer in enumerate(layers):
        z = z @ np.asarray(layer["kernel"]) + np.asarray(layer["bias"])
        if i < len(layers) - 1:
            z = np.maximum(z, 0)
    metrics = json.loads((SOURCE / "metrics.json").read_text())
    spec = {
        "schema_version": 1,
        "model_version": metrics["model_version"],
        "source_dataset_sha256": metrics["dataset_sha256"],
        "age_range": [metrics["age_min"], metrics["age_max"]],
        "numeric_features": NUMERIC,
        "numeric_bounds": NUMERIC_BOUNDS,
        "categorical_features": CATEGORICAL,
        "numeric_means": numeric["scale"].mean_.tolist(),
        "numeric_scales": numeric["scale"].scale_.tolist(),
        "categorical_levels": [array.tolist() for array in categories],
        "layers": layers,
        "reference_profile": REFERENCE,
        "reference_log_hazard": float(z[0, 0]),
        "interpretation": "Neural Cox log relative hazard; ratio is versus a fixed reference profile, not a mortality rate.",
    }
    out = TARGET / "assets/neural_model.json"
    out.write_text(json.dumps(spec, separators=(",", ":")))
    profiles = [
        REFERENCE,
        {**REFERENCE, "age": 45, "bmi": 26, "sleep_hours": 8,
         "vigorous_recreation_min_week": 60, "moderate_recreation_min_week": 120,
         "sedentary_min_day": 300, "general_health": 2},
        {**REFERENCE, "age": 70, "bmi": 30, "smoking_status": 2,
         "diabetes_diagnosed": 1, "hypertension_diagnosed": 1,
         "general_health": 4, "moderate_recreation_min_week": 0,
         "sedentary_min_day": 600},
    ]
    vectors = prep.transform(pd.DataFrame(profiles, columns=NUMERIC + CATEGORICAL)).astype(np.float64)
    for i, layer in enumerate(layers):
        vectors = vectors @ np.asarray(layer["kernel"]) + np.asarray(layer["bias"])
        if i < len(layers) - 1:
            vectors = np.maximum(vectors, 0)
    import tensorflow as tf
    keras = tf.keras.models.load_model(SOURCE / "model.keras", compile=False)
    keras_scores = keras.predict(
        prep.transform(pd.DataFrame(profiles, columns=NUMERIC + CATEGORICAL)).astype("float32"),
        verbose=0,
    ).reshape(-1)
    if not np.allclose(vectors.reshape(-1), keras_scores, atol=1e-5, rtol=1e-5):
        raise ValueError("Portable weights disagree with the original Keras model")
    golden = [
        {"profile": profile, "log_relative_hazard": float(value[0])}
        for profile, value in zip(profiles, vectors)
    ]
    (TARGET / "test/neural_golden.json").write_text(json.dumps(golden, indent=2))
    print(f"Exported {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
