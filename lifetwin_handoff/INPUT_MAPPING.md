# Mapping LifeTwin inputs to the trained model

The training variables are mostly one-time measurements or answers about **usual** habits. Daily logs are condensed into a recent snapshot; they are not interpreted by a time-series model. Keep the raw measurement, window, and source in the LifeTwin app so a person can inspect or correct what was used.

| Model input | LifeTwin source | Exact rule |
|---|---|---|
| `age` | Onboarding | Years at the latest assessment. Annual model horizons start **now**, not at birth. |
| `sex_nhanes` | Onboarding | NHANES recorded category: `1` male, `2` female. Do not guess for users outside this encoding; show survival unavailable. |
| `bmi` | Latest height and weight | `weight_kg / (height_m ** 2)`, or supplied BMI. The source study measured BMI; user-entered values may differ. |
| `sleep_hours` | Usual workday sleep | Average sleep from logged workdays in the complete recent window, or a direct answer about usual workday sleep. Do not substitute one exceptional night. |
| `smoking_status` | Smoking-history questions | `0` never smoked 100 cigarettes, `1` smoked 100+ but not now, `2` smoked 100+ and currently smokes. A smoke-free day does **not** turn a current smoker into a former smoker. |
| `diabetes_diagnosed` | Onboarding/medical history | `1` only if the user reports a doctor diagnosis; otherwise `0` only after an explicit “no.” Do not infer from glucose readings. |
| `hypertension_diagnosed` | Onboarding/medical history | `1` only if the user reports a doctor diagnosis; otherwise `0` only after an explicit “no.” Do not infer from one blood-pressure reading. |
| `general_health` | User answer | `1` excellent, `2` very good, `3` good, `4` fair, `5` poor. Do not compute this from activity or avatar appearance. |
| `vigorous_recreation_min_week` | Recreation logs | Weekly mean of vigorous **recreational** minutes. Exclude work and transport minutes unless the data mapping is revalidated. |
| `moderate_recreation_min_week` | Recreation logs | Weekly mean of moderate **recreational** minutes. Do not double-count a minute in both categories. |
| `sedentary_min_day` | Awake sitting logs | Mean minutes sitting/reclining **while awake** per day. Screen time alone is not equivalent. |

`daily_logs` accepts 7, 14, 21, or 28 **consecutive complete days ending yesterday** relative to `as_of_date`. Every row needs `date`, `workday`, `sleep_hours`, `vigorous_recreation_min`, `moderate_recreation_min`, and `sedentary_min_day`. The service averages workday sleep (at least three workday observations per week), activity minutes per seven days, and sitting per day. Each day must fit within 24 hours.

`weekly_summaries` accepts one to four consecutive, completed Monday–Sunday weeks, ending with the latest completed week before `as_of_date`. Each row needs `week_start` and the four model behavior fields. The service averages these weeks. Do not send both log forms in one request. If no logs are available, send all eleven model fields in `profile` directly.

These are **engineering approximations** to NHANES questionnaire answers. The API returns `input_provenance` and the exact `profile_used`. If source data are absent, the model returns `missing_inputs` and no annual percentage; do not treat missing as zero recreation, no diagnosis, or healthy sleep.
