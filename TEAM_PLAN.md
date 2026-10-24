# LifeSim team plan

How we split [the PRD](projectspec.md) so four people can build in parallel without drifting apart.

## Decisions so far

| Area | Decision |
|---|---|
| App | Flutter / Dart, tested on iOS through Xcode |
| Training | Python. Victor picks the method (Cox, random survival forest, whatever validates best) |
| Server | Python. It serves Victor's model and keeps the LLM key off the phone (PRD 15). *Assumed from the two rows above; say so if you disagree* |
| Advisor input | The user's inputs plus the model's results. May change later |
| Merging | Fast: merge straight to `main`, no required review. Bad merge → roll back to a checkpoint (below) |

Because Victor is free to choose the model, the shared boundary is **the API, not the model file**. Everyone builds against the JSON in [`contracts/`](contracts/). Whatever model sits behind it can change without breaking anyone.

## Tracks

| Track | Owner | Owns | Starts on (no waiting) | Done when |
|---|---|---|---|---|
| **A. Data & Model** | Victor | NHANES + linked mortality download, `SEQN` merge, cycle harmonization, censoring (`MORTSTAT`, `PERMTH_INT`), model training, evaluation (C-index, Brier, calibration, subgroups), exported artifact + short model card | Immediately | Model artifact + eval report (sample size, deaths, follow-up) committed; validated age range and max horizon stated |
| **B. API & Integration** | _TBD_ | Python server for `/api/predict`, `/api/compare`, `/api/advisor` route; loads Victor's artifact; input validation, out-of-population refusal, horizon cap, risk-factor list, deployment | [`contracts/stub_server.py`](contracts/stub_server.py) as a reference | `contracts/check.py` passes against the real server; deployed URL works from the phone |
| **C. Flutter App** | _TBD_ | Onboarding (< 60 s), dashboard, survival-curve chart with tooltips and animation, lifestyle sliders, Compare screen (split layout, overlaid curves, deltas), persistent "modeled association, not cause" label, unsupported-profile state | The stub server (fake but contract-shaped numbers) | Full demo flow runs on the iPhone against the stub, then against the real API |
| **D. Advisor, Trust & Demo** | _TBD_ | LLM call with structured context, curated guideline sources, rule that the advisor never states a number the model didn't produce, safety/limitation copy, held-out judge scenario, demo script and rehearsal | Fixture predictions as model output | Advisor passes the number check; 2- and 3-minute demo rehearsed with a judge changing inputs |

**Three people instead of four:** merge B and D. The advisor is one more server route.

**Critical path:** A. NHANES harmonization eats time, so start with 2–4 survey cycles and a short feature list (age, sex, BMI, smoking, activity, alcohol, diabetes). Everyone else works on the stub, so a late model delays only the switch to real numbers.

## How we avoid drifting apart

1. **Contract Zero first (about the first 2 hours, together).** `contracts/` lands on `main` before anyone branches. It holds:
   - `profile.schema.json`: what the user enters (metric units; the app converts)
   - `prediction.schema.json`: `/api/predict` response, including `status: "unsupported"` + `limitation`
   - `compare.schema.json`: `/api/compare`, deltas in percentage points computed by the server
   - `advisor.schema.json`: `/api/advisor` request and response
   - `fixtures/`: sample requests with expected responses (typical, smoker + diabetic, minor, age out of range, the two demo futures, an advisor question)
2. **One checker, used by everyone.** `contracts/check.py` replays every fixture against a server and validates the responses. For the same `model_version` the numbers must match. Advisor answers must not contain a percentage that isn't in the model output (it can't yet catch a real number quoted for the wrong year).
   ```sh
   python3 contracts/stub_server.py                                  # stub on :8000
   uv run --with jsonschema python contracts/check.py                # or pip install jsonschema
   uv run --with jsonschema python contracts/check.py --base-url https://<deployed-api>
   ```
3. **Changing a contract** = edit the schema, update `stub_server.py`, run `python3 contracts/stub_server.py --write-fixtures`, check passes, and tell the team in chat **before** merging. A contract change merged without telling people is the main way we'd drift.
4. **Branches are short.** Name them `a/…`, `b/…`, `c/…`, `d/…`. Pull `main` into your branch often and merge back at least at every sync point.
5. **Sync points** (hours after kickoff): **T+2** Contract Zero, **T+8** every track merged and the stub flow runs on the phone, **T+16** real model behind the API, **T+24** advisor in the app, **T+32** polish and deploy, **T+40** feature freeze (fixes and rehearsal only).
6. **When Victor's real model lands:** B swaps it in behind the same routes in one merge, regenerates fixtures from the real server and bumps `model_version`. The app shouldn't need any change.

## Checkpoints and rollback

A checkpoint is a tag on a `main` commit where the demo flow works and `check.py` passes:

```sh
git tag cp-03 && git push origin cp-03
```

To undo one bad merge (keeps everyone else's later work):

```sh
git revert -m 1 <merge-commit>   # or: git revert <commit> for a non-merge commit
```

To get back to a known-good state when `main` is badly broken:

```sh
git switch -c recover cp-03      # inspect, then merge recover back into main
```

Don't `git reset --hard` and force-push `main`. That throws away every teammate's commits made after the checkpoint.

## iOS testing

Device testing runs on Daniel's Mac, where the iPhone is connected and signing is set up (team `A5C3J42JT3`). Other Macs can use the simulator, which needs no signing.

One-time on the phone: **Settings → Privacy & Security → Developer Mode → On**, then restart.

```sh
python3 contracts/stub_server.py &                                   # the phone reaches it over Wi-Fi
scripts/ios-device.sh --dart-define=API_BASE_URL=http://Overpriced-Hardware.local:8000
# in the app:  const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
```

- `scripts/ios-device.sh` finds the connected iPhone, stops with instructions if Developer Mode is off, then runs `flutter run` (hot reload `r`, restart `R`, quit `q`).
- `localhost` on the phone means the phone itself. Use the Mac's `.local` name (above) or the deployed API.
- `app/ios/Runner/Info.plist` allows plain HTTP on the local network (`NSAllowsLocalNetworking`) and includes the Local Network prompt text. Accept that prompt on first launch.
- Simulator: `cd app && flutter run -d "iPhone 17"`, where `localhost:8000` works directly.
- Teammates deploying to their own iPhone: in Xcode, pick your own team under Runner → Signing, and don't commit that change.

## Rules every track follows (from PRD 15)

- Every number on screen comes from the model API. Never hardcode one, and never let the LLM invent one.
- Out-of-population profiles (minors, ages outside the validated range) get a limitation message, not a curve.
- Curves stop at the model's `max_horizon_years`.
- Always label results as modeled associations from observational data, not causal effects.
- Don't store or log raw health profiles. The stub server logs only method, path and status.
- API keys live on the server only.
