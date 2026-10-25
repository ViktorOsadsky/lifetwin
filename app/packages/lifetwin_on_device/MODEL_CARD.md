# Packaged Cox model card

**Version:** `personal-cox-bmi35-v3-20261024` in `assets/model.json`.

**Task:** all-cause cumulative survival at years 1–5 for complete, supported profiles with assessment ages 35–79. Eleven inputs are used. The frozen JSON and support reference reproduce the evaluated lifelines Cox model in Dart, without Python on the device. The dense neural hazard model is separate and unchanged.

**Training and evaluation:** 9,109 NHANES 2007–2012 participants for fitting, 2,570 for validation, and 3,826 from 2013–2014 for a later-cycle test. The later-cycle C-index is **0.7914**, five-year IPCW Brier is **0.04686**, and mean predicted versus observed five-year survival is **94.28% versus 94.67%**. For ages 65–79 it is **87.48% versus 88.82%**. See the [full evaluation](../../../web/survival_lab/evaluation.json) and [refit report](../../../web/survival_lab/MODEL_CARD.md). Differences from Cox v2 are small and do not prove an overall accuracy gain. This is later-cycle evaluation within NHANES, not external-cohort validation.

**BMI encoding:** BMI below 23 uses `max(23 − BMI, 0)/5`. BMI from 23 through 35 is flat by feature design. Above 35, `max(BMI − 35, 0)/5` has a fitted coefficient **+0.0348066**. Cox v2 instead had a slightly negative coefficient above 27 and produced the inverse high-BMI direction. The refit has 1,566 fitting participants at BMI ≥35 and no fitting BMI above 84.87. Neither feature direction is a causal estimate of weight change.

**Release limits:** The current 1–5-year estimates are withheld for unsupported inputs. The age-stepping curves in the package repeatedly reuse a short-horizon model and have no long-range validation. Their 50% crossing is not a validated lifespan or individual death age. The model uses [NHANES public-use linked mortality](https://www.cdc.gov/nchs/linked-data/mortality-files/index.html), is not survey-weighted to the U.S. population, and has not been tested in another cohort. The neural model still has its documented inverse associations for some profiles. These artifacts are for a labeled hackathon research prototype, not clinical decisions.
