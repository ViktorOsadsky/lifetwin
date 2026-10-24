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

Regenerate schemas with `uv run python contracts/export.py` when approved types change; `--check` also fails on schema files that are no longer in `schema_registry.py`. Request schemas are exported in validation mode (defaulted fields are optional). Response schemas are exported in serialization mode, so every field the server always emits, including defaulted safety markers such as `status`, `prediction: null`, `voice_status` and `local_scoring`, is required. Offline mode checks the 14 schemas, 16 request fixtures and three static responses; it explicitly skips cases that require API replay. It does **not** claim to validate absent response fixtures. The 20 cases cover the success/deferred routes, a single quiz question, invalid transitions, invalid inputs (feet typed as cm, unknown unit fields, out-of-range age), unsupported client fields, an ambiguous intake answer, a skipped field, unconfigured web research, invalid quiz limits and missing question versions.

Each request fixture states its schema result: `request_schema_valid: false` asserts the shared schema rejects it, and `request_schema_valid: true` on a 422 case pins a server-only rule (duplicate topics, reply without text, blank text) that the schema cannot yet express. In `response_subset`, `{"$each": {...}}` requires a nonempty list whose every element matches, for example every advisor action staying `unmodeled`.

Use `--in-process` to replay all 20 cases against a keyless app without opening a network socket; it explicitly clears provider configuration. Use `--base-url` for the same HTTP status/schema/semantic checks against a running keyless server. The two targets are mutually exclusive. Assertions check meaningful mode/error/game-state fields without copying the entire content bank. Neither mode establishes medical/model correctness or live provider access.

The model-dependent endpoints intentionally return HTTP **501**, `status: not_implemented`, and null `prediction`/`model_version`. There are no synthetic survival estimates or trained-model assumptions in these contracts. Input validation ranges describe accepted raw data only, not a validated prediction population. Model training, model artifact loading, comparison math, input gradients and fortune calculations are left for later.

Conversation uses a stateless caller-held state, separate pending versus confirmed fields and explicit actions. Typed text and final speech transcripts share the path; voice capture/synthesis are deferred. Quiz delivery includes answer/scoring metadata for local offline play and never updates medical inputs. Advisor plans are educational and cited, with unmodeled effects. Blank provider keys must work without network calls.

HTTP conventions for the implementation: 200 for usable non-predictive responses, 422 for invalid input, 404 for missing resources, 413 for oversized bodies, 429 for limits, 503/504 for unavailable/timed-out dependencies, and 501 for intentionally deferred model features. Error bodies use `error.schema.json` and exclude raw inputs/provider details. `server/CONTRACTS.md` defines module ownership.
