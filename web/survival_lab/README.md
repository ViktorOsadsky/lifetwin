# LifeTwin internal survival website

This is a standalone HTML/CSS/JavaScript page for testing two model outputs with your own inputs. It is **separate from the Flutter app handoff**. It has no Flutter runtime, build step, npm dependency, account, or inference server. The frozen neural model and the website-specific refitted Cox model are bundled in `assets/`, so a local static server is enough.

## Open it on your computer

In PowerShell from the repository root:

```powershell
cd web/survival_lab
python -m http.server 8765 --bind 127.0.0.1
```

Open **http://127.0.0.1:8765/** in a browser. Leave the terminal running while testing; press Ctrl+C to stop it. Opening `index.html` directly as a `file://` page is unreliable because browsers block its local model-file fetches. Nothing is uploaded: form inputs stay in the tab, and all inference runs in JavaScript. The page offers the neural hazard ratio, a current five-year Cox number, both age-stepping curves, a per-age table, and CSV export.

The form starts with an illustrative age-65 profile. Replace every field with your own values and click **Run both models**. Adults ages 18–109 can be entered. The models were fitted on ages 35–79; an 18-year-old result is a zero-shot extrapolation, not an age-18-validated forecast. Toggle **Show ages beyond 79** to extend the curve through older hypothetical assessments. The neural ratio uses the fixed reference profile shown in the page’s details section. It is a *relative hazard*, not an absolute mortality rate. The 50% crossing is a median threshold of the projection algorithm, not validated life expectancy.

The site's 1st–99th percentile and nearby-profile checks now display **warnings instead of blocking calculations**. They describe how far the input is from the NHANES training sample, not whether the input is realistic. Missing/nonfinite values, unsupported survey categories, nonadult/over-109 ages, nonpositive BMI, negative or impossible time amounts, daily time totals above 24 hours, and numerical overflow still stop a calculation. This permissive policy is for internal zero-shot testing only; it does not modify the separate Flutter model package or establish accuracy in another cohort. Test cross-cohort accuracy against observed outcomes before using these numbers as personal forecasts. See [TRIPOD+AI](https://www.bmj.com/content/385/bmj-2023-078378) for model applicability and validation reporting.

## Check the arithmetic

Node.js is used only for tests:

```powershell
node --test test/model.test.mjs
```

The tests compare browser-side Cox and neural calculations with frozen lifelines/Keras vectors, compare both projected 50% crossings with independent lifelines calculations, and check the BMI direction, permissive out-of-distribution inputs, and impossible values. The Cox artifact is `personal-cox-bmi35-v3-20261024`; the unchanged neural artifact is `temporal-deepsurv-35-79-20261024T184421Z`. The [website Cox model card](MODEL_CARD.md) records the refit, validation, and limits. The website is independent from the Flutter package at runtime; **the Flutter package still uses its original Cox v2 artifact**.

To reproduce the Cox refit, use the prepared `lifestyle_long_followup.csv` from the original training workspace and an environment with the pinned packages in [training requirements](tools/requirements.txt):

```powershell
python web/survival_lab/tools/train_bmi35_cox.py --data ../output/lifestyle_v2/lifestyle_long_followup.csv
```

Run that command from the `lifetwin` repository root. It rewrites `assets/cox.json`, `assets/support_reference.f64`, `evaluation.json`, and the Cox/projection test vectors. The dataset is not bundled in this repository. The script's output is checked against the committed vectors and metrics, and the browser inference is checked with `node --test test/model.test.mjs`.

Both long-range curves repeatedly reuse a short-horizon model while keeping all non-age inputs fixed. The trained input ages are 35–79. The [R survival documentation](https://web.mit.edu/r/current/lib/R/library/survival/html/survfit.coxph.html) explains why a time-varying covariate path needs careful definition. Do not use an extrapolated crossing as a clinical or personal lifespan forecast.
