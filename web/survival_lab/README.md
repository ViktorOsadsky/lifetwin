# LifeTwin internal survival website

This is a standalone HTML/CSS/JavaScript page for testing the two model outputs with your own inputs. It is **separate from the Flutter app handoff**. It has no Flutter runtime, build step, npm dependency, account, or inference server. The frozen neural and Cox artifacts are copied into `assets/`, so a local static server is enough.

## Open it on your computer

In PowerShell from the repository root:

```powershell
cd web/survival_lab
py -m http.server 8765 --bind 127.0.0.1
```

Open **http://127.0.0.1:8765/** in a browser. Leave the terminal running while testing; press Ctrl+C to stop it. Opening `index.html` directly as a `file://` page is unreliable because browsers block its local model-file fetches. Nothing is uploaded: form inputs stay in the tab, and all inference runs in JavaScript. The page offers the neural hazard ratio, a supported current five-year Cox number, both age-stepping curves, a per-age table, and CSV export.

The form starts with an illustrative age-65 profile. Replace every field with your own confirmed value and click **Run both models**. Toggle **Show ages beyond 79** to compare supported-age output with explicitly unvalidated age extrapolation. The neural ratio uses the fixed reference profile shown in the page’s details section. It is a *relative hazard*, not an absolute mortality rate. The 50% crossing is a median threshold of the projection algorithm, not validated life expectancy.

## Check the arithmetic

Node.js is used only for tests:

```powershell
node --test test/model.test.mjs
```

The tests compare browser-side Cox and neural calculations with frozen Python/Keras vectors, compare both projected 50% crossings with the independent Dart implementation, and check unsupported inputs. Source models are the existing `personal-cox-v2-20261024T182404Z` and `temporal-deepsurv-35-79-20261024T184421Z`; this site does not train either model. The copied assets make the website independent from the Flutter package at runtime. If a model is replaced, update the three assets and both vector files together and rerun the tests.

Both long-range curves repeatedly reuse a short-horizon model while keeping all non-age inputs fixed. The trained input ages end at 79. The [R survival documentation](https://web.mit.edu/r/current/lib/R/library/survival/html/survfit.coxph.html) explains why a time-varying covariate path needs careful definition. Do not use an extrapolated crossing as a clinical or personal lifespan forecast.
