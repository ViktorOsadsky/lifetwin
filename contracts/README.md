# Backend contracts v1

The user requested non-prediction backend implementation with blank credentials. The Pydantic models in `server/lifetwin/` are the source for generated JSON schemas here. `schema_version` is `1.0`; breaking changes require a coordinated contract PR.

Run from the repository root after installing the project's dev dependencies:

```sh
uv sync --python 3.11
uv run python contracts/export.py --check
uv run python contracts/check.py
# Once the implementation server is running:
uv run python contracts/check.py --base-url http://127.0.0.1:8000
```

Regenerate schemas with `uv run python contracts/export.py` when approved types change. The checker validates JSON Schema and illustrative request bodies; with `--base-url` it also verifies real response status and shape. It does not prove medical/model correctness or live provider access.

The model-dependent endpoints intentionally return HTTP **501**, `status: not_implemented`, and null `prediction`/`model_version`. There are no synthetic survival estimates or trained-model assumptions in these contracts. Input validation ranges describe accepted raw data only, not a validated prediction population. Model training, model artifact loading, comparison math, input gradients and fortune calculations are left for later.

Conversation uses a stateless caller-held state, separate pending versus confirmed fields and explicit actions. Typed text and final speech transcripts share the path; voice capture/synthesis are deferred. Quiz delivery includes answer/scoring metadata for local offline play and never updates medical inputs. Advisor plans are educational and cited, with unmodeled effects. Blank provider keys must work without network calls.

HTTP conventions for the implementation: 200 for usable non-predictive responses, 422 for invalid input, 404 for missing resources, 413 for oversized bodies, 429 for limits, 503/504 for unavailable/timed-out dependencies, and 501 for intentionally deferred model features. Error bodies use `error.schema.json` and exclude raw inputs/provider details. `server/CONTRACTS.md` defines module ownership.
