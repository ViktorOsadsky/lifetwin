# Backend contracts v1

The user requested non-prediction backend implementation with blank credentials. The Pydantic models in `server/lifetwin/` are the source for generated JSON schemas here. `schema_version` is `1.0`; breaking changes require a coordinated contract PR.

Run from the repository root after installing the project's dev dependencies:

```sh
uv sync --python 3.11
uv run python contracts/export.py --check
uv run python contracts/check.py
uv run python contracts/check.py --in-process
# Once the implementation server is running:
uv run python contracts/check.py --base-url http://127.0.0.1:8000
```

Regenerate schemas with `uv run python contracts/export.py` when approved types change; `--check` also fails on schema files that are no longer in `schema_registry.py`. Request schemas are exported in validation mode (defaulted fields are optional). Response schemas are exported in serialization mode, so every field the server always emits, including defaulted safety markers such as `status`, `prediction: null`, `voice_status` and `local_scoring`, is required. Offline mode checks the 16 schemas, 21 request fixtures and two static responses; it explicitly skips cases that require API replay. It does **not** claim to validate absent response fixtures. The 25 cases cover the success/deferred routes, a supported and an unsupported (age above 80) forecast, a single quiz question, invalid transitions, invalid inputs (feet typed as cm, unknown unit fields, out-of-range age), unsupported client fields, an ambiguous intake answer, a skipped field, unconfigured web research, invalid quiz limits, missing question versions, a missing voice consent and an unconfigured voice token route, and a confirmed Apple Health import with and without values.

Each request fixture states its schema result: `request_schema_valid: false` asserts the shared schema rejects it, and `request_schema_valid: true` on a 422 case pins a server-only rule (duplicate topics, reply without text, blank text) that the schema cannot yet express. In `response_subset`, `{"$each": {...}}` requires a nonempty list whose every element matches, for example every advisor action staying `unmodeled`.

Use `--in-process` to replay all 25 cases against a keyless app without opening a network socket; it explicitly clears provider configuration. Use `--base-url` for the same HTTP status/schema/semantic checks against a running keyless server. The two targets are mutually exclusive. Assertions check meaningful mode/error/game-state fields without copying the entire content bank. Neither mode establishes medical/model correctness or live provider access.

`POST /api/predict` returns `prediction.schema.json`: `status` `supported`/`unsupported`, survival at 1/3/5 years, a curve to `max_horizon_years` (5), `model_version`, the model inputs `filled_in` by the missing-value policy, a plain `reason` when unsupported, and `limitations`. Its fixtures pin the current trained model's numbers, so retraining updates them. It returns 501 `not_implemented` only when the model files are missing (see `server/README.md`). Compare and sensitivity intentionally return HTTP **501**, `status: not_implemented`, and null `prediction`/`model_version`. Input validation ranges describe accepted raw data only, not a validated prediction population. Comparison math, input gradients and fortune narration are left for later.

Conversation uses a stateless caller-held state, separate pending versus confirmed fields and explicit actions. Typed text and final speech transcripts share the path; voice capture/synthesis are deferred. Quiz delivery includes answer/scoring metadata for local offline play and never updates medical inputs. Advisor plans are educational and cited, with unmodeled effects. Blank provider keys must work without network calls.

HTTP conventions for the implementation: 200 for usable non-predictive responses, 422 for invalid input, 404 for missing resources, 413 for oversized bodies, 429 for limits, 503/504 for unavailable/timed-out dependencies, and 501 for intentionally deferred model features. Error bodies use `error.schema.json` and exclude raw inputs/provider details. `server/CONTRACTS.md` defines module ownership.
