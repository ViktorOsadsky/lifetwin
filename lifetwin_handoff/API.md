# HTTP contract for LifeTwin

The API expects JSON. It returns fractions and percentages separately so the UI does not have to guess units. Routes are local to the inference backend; proxy them through the app server in production.

## `GET /health`

Returns readiness, model version, supported ages `[35,79]`, horizons `[1,2,3,4,5]`, and explicit `false` flags for death-date and causal-effect predictions. Use this at startup to fail closed if the artifact is missing or changed.

## `POST /v1/twin/assess`

Body: `{ "profile": {...}, "as_of_date": "YYYY-MM-DD", "daily_logs": [...] }`, or replace `daily_logs` with `weekly_summaries`, or omit logs and send all eleven model fields in `profile`. `height_cm` plus `weight_kg` may replace `bmi`. The log formats are in [INPUT_MAPPING.md](INPUT_MAPPING.md) and [examples/](examples/). `as_of_date` defaults to the backend's current date.

Key response fields:

```json
{
  "profile_used": {"age": 45, "bmi": 25.0},
  "input_provenance": {"source": "daily_logs", "complete_weeks": 1},
  "survival": {
    "status": "available",
    "horizons_years": [1, 2, 3, 4, 5],
    "survival_probabilities": {"1": 0.9988, "5": 0.9932},
    "survival_percent_by_year": {"1": 99.88, "5": 99.32},
    "death_date": null,
    "estimated_age_at_death": null,
    "causal_interpretation": false
  },
  "wellness_cards": [{"id": "activity", "level": "strength", "source_url": "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"}],
  "avatar": {"survival_display": "annual_curve", "wellness_state": "steady", "strengths": ["activity"], "opportunities": []}
}
```

The example is abbreviated; use [snapshot_response.json](examples/snapshot_response.json) for a full response. `survival.status` is one of:

| Status | UI action |
|---|---|
| `available` | Display years 1–5 as **cumulative** modeled survival. |
| `missing_inputs` | Ask for the named fields; do not impute or show a number. |
| `unsupported_age` | Hide survival curve; show general adult wellness cards if appropriate. |
| `unsupported_profile` | Hide survival curve; show the support issues, without extrapolating. |

Malformed category, implausible values, contradictory BMI, incomplete logs, or both log forms yield HTTP 422 with `detail` explaining the issue. No request writes a user record.

## `POST /v1/twin/compare`

Body: `{ "current_profile": {...}, "alternative_profile": {...} }`, with complete eleven-input snapshots. See [compare_request.json](examples/compare_request.json). The response contains `current`, `alternative`, `changed_features`, and `modeled_difference_percentage_points`. A difference is returned only when **both** profiles pass the support checks; otherwise it is `null`. `causal_interpretation` is always `false`.

If your UI creates an alternative from a habit edit, copy the current profile and change only the chosen field. Do not use this endpoint to rank or prescribe “best” interventions. BMI, sleep and sitting comparisons carry an extra warning because their observational associations are especially easy to misread.

## Minimal frontend adapter

The included [frontend.ts](examples/frontend.ts) shows the fetch call, status handling, year-by-year chart points, and separate wellness card mapping. It assumes your app backend proxies `/api/lifetwin/*` to this service. Its labels intentionally avoid “date of death” and “years gained.”
