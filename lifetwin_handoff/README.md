# LifeTwin model handoff

**For the iOS Flutter app, use [flutter/lifetwin_on_device](flutter/lifetwin_on_device/README.md).** It bundles the trained model into the application and runs predictions in Dart on the user's device with no network request or Python runtime. This folder is a handoff only: it does not change the existing app or server. Teammates can reference the Flutter package directly from `app/pubspec.yaml` using the relative path in [REPO_INTEGRATION.md](REPO_INTEGRATION.md).

The rest of this folder is a Python reference implementation and optional local API for testing. It contains the selected survival artifact, daily/weekly input aggregation, guideline-based wellness cards, examples, and tests. It does **not** need TensorFlow, lifelines, the original training scripts, or the NHANES CSV.

## What the avatar can say

- **Survival:** “Among people with a similar profile, modeled survival through year 1/2/3/4/5 is X%.” These are cumulative survival estimates from the latest profile snapshot. Supported ages are **35–79** with all eleven inputs present and adequate training support.
- **Habits:** “Your logged recreation meets the adult activity minimum,” “Your usual workday sleep is below the recommended duration,” or “You report not currently smoking.” These cards come from [public guidance](SOURCES.md), **not** from survival-model coefficients.
- **Scenarios:** “This alternative profile has a modeled five-year survival estimate Y percentage points different.” The difference is observational. It is not the benefit that would result from changing a habit.

The package does not calculate a date or age of death. A five-year survival probability cannot be converted into a reliable death date or an expected number of years gained. This model is a snapshot model: it was trained on one NHANES examination per person, not on continuous wearable histories. Recomputing it after new logs gives a new profile estimate, not a learned treatment effect or a continuous physiological digital twin.

## Start the API

Use Python 3.12 or newer. From the **parent directory** of this folder, in PowerShell:

```powershell
python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r lifetwin_handoff\requirements.txt
& .\.venv\Scripts\python.exe -m uvicorn lifetwin_handoff.service:app --host 127.0.0.1 --port 8001
```

If the backend uses another Python environment, replace `.\.venv\Scripts\python.exe` with that interpreter. Open `http://127.0.0.1:8001/docs` for live OpenAPI. The artifact manifest is checked when the service starts; missing or changed model files fail startup.

For a fully local command line run **without starting a server**, use the same environment and run:

```powershell
& .\.venv\Scripts\python.exe -m lifetwin_handoff.local lifetwin_handoff\examples\snapshot_request.json
& .\.venv\Scripts\python.exe -m lifetwin_handoff.local lifetwin_handoff\examples\compare_request.json --compare
```

You can also import `LifeTwinModel` from `lifetwin_handoff.model` in a Python app and call `predict(profile)` directly. That inference path needs only NumPy and the included `artifact/` files. Both the command line and local API process run on your machine; the package makes no external calls.

In a second PowerShell window:

```powershell
$body = Get-Content lifetwin_handoff\examples\snapshot_request.json -Raw
Invoke-RestMethod -Uri http://127.0.0.1:8001/v1/twin/assess -Method Post -ContentType application/json -Body $body
```

Try `daily_request.json`, `weekly_request.json`, and `compare_request.json` in the same folder. The compare example goes to `/v1/twin/compare`. `GET /health` reports the model version and supported age range.

## App wiring

1. At onboarding, collect age, recorded sex category compatible with NHANES, smoking history, doctor-diagnosed diabetes and hypertension, and self-rated general health. Compute BMI from a recent height/weight pair or supply BMI directly. Do not infer diagnoses, lifetime smoking, or general health from a wearable.
2. Send a complete profile to `POST /v1/twin/assess`. You may include `daily_logs` **or** `weekly_summaries`; their behavior averages replace the four behavioral fields in the profile. See [INPUT_MAPPING.md](INPUT_MAPPING.md).
3. If `survival.status` is `available`, plot `survival.survival_percent_by_year` for years 1–5 and label it **“Modeled survival of similar people.”** If the status is `missing_inputs`, `unsupported_age`, or `unsupported_profile`, hide the percentages and show its message. Do not fill missing values with healthy defaults.
4. Map `avatar.strengths` and `avatar.opportunities` to your avatar's visual states. Render the detailed `wellness_cards` beside it, with their sources. These states are based on observed habits and public guidance; the survival percentage does not control an “about to die” animation.
5. For “what if” exploration, send two complete profiles to `/v1/twin/compare`. Label the result **“Modeled difference between profiles.”** Never label it “years gained,” “benefit,” or “what will happen if you change.”

The service does not persist submitted profiles or logs. Route requests through your app backend if the frontend and inference service are on different origins; use the app's normal consent, authentication, and health-data handling. Keep `artifact/` server-side.

## Files

| File | Purpose |
|---|---|
| `artifact/model.json` | Feature coefficients, baseline survival at years 1–5, bounds, model version |
| `artifact/support_reference.npz` | 2,000 encoded reference vectors from the public training cohort for input-support checks; keep server-side |
| `artifact/manifest.json` | SHA-256 checksums for the packaged artifact |
| `model.py` | Standalone prediction and scenario comparison |
| `aggregation.py` | Daily/weekly log-to-model mapping |
| `guidance.py` | Source-backed strengths and opportunities |
| `service.py` | FastAPI endpoints |
| `local.py` | Direct local JSON command line entry point |
| `flutter/lifetwin_on_device/` | iOS Flutter on-device package with bundled model and Dart runtime |
| `examples/` | Runnable request and response examples |
| `MODEL_CARD.md` | Validation and limitations |

No new mortality model was trained for this handoff. The existing calibrated, scoped Cox model is the selected survival model; the original neural network benchmark has a small, uncertain ranking advantage but worse older-adult calibration and an inverse BMI response. A genuinely longitudinal model or a causal “habit change benefit” model would require different data and validation. See [MODEL_CARD.md](MODEL_CARD.md).

The trained assets are already included. Regenerating them requires the separate training workspace and its `build_lifetwin_handoff.py`; that script and raw training data are intentionally outside this repository handoff. To test this Python reference package from the repository root, install `lifetwin_handoff/requirements-dev.txt` into the chosen environment and run that environment's `python -m pytest lifetwin_handoff/test_handoff.py -q`.
