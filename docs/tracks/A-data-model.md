# Track A: Data & Model

**Owner:** Victor · **Master doc:** §6 (all), §12 phase 1, §17 technical criteria

Victor chooses the method and tools. The master doc's default (Cox first; random survival forest only if validation justifies
it, §6.4) is a recommendation. What the rest of the team needs is the output, listed below.

## What the other tracks need from you

| Need | Why | Master doc |
|---|---|---|
| A loadable artifact plus a small Python `predict(profile) -> survival curve` function | B serves it behind `/api/predict` | §7, §12 |
| Survival probability S(t) at yearly points from 0 to the max horizon | Curve and headline numbers | §3.2, §9 |
| **Max defensible horizon** (years) | Curves must stop there | §3.2 |
| **Validated population** (age range, any other limits) | Out-of-range profiles get a limitation, not a curve | §3.1, §15 |
| **Features actually used** | Unused inputs are shown as informational | §2.2 |
| Per-profile risk-factor ranking (largest modeled contributions) | Dashboard and advisor | §3.1, §5.3 |
| Eval report: C-index, Brier at horizons, calibration, subgroups by age/sex, sample size, deaths, follow-up | Proves the model; the demo quotes it | §6.5, §17 |

The app sends `height_cm` and `weight_kg`. Whoever wraps the model (you or B) computes BMI. Input names and units are in
`contracts/profile.schema.json`.

## Master-doc requirements to keep

- NHANES 1999–2018 with the NCHS linked mortality files (follow-up through Dec 31, 2022); merge on `SEQN`; adults eligible for
  linkage only (§6.1, §6.2).
- Event = `MORTSTAT`; duration = `PERMTH_INT` where appropriate; survivors are **right-censored**, never given a final lifespan (§6.2).
- Held-out test set with no leakage (§6.5).
- Training offline; only serialized inference artifacts are deployed (§7).

## Suggested order (yours to change)

1. Smallest real slice: 2–4 cycles, core features from §6.3 (age, sex, BMI, smoking, activity, sleep, alcohol, diabetes, blood pressure).
2. Baseline model + eval report.
3. Hand B the first real artifact (target **T+16**), even if it's only the baseline.
4. Improve (more cycles, diet, a more flexible model) only where validation justifies it (§6.4).
