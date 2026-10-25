# Provider copy guard — #124

Original base: `27c973654f4ca44475dbc4dddbcdbf5d0198bdf6`; branch `codex/b-provider-copy-guard`. Reconciled by normal merge with `origin/main` at `b906b1ac87593706a6a640f0f11600d778ff227e`, preserving owner PRs #157 (Claude provider) and #158 (document provider consent). [PR #162](https://github.com/ViktorOsadsky/lifetwin/pull/162) is open; this integration update is local for parent publication. No rebase, force-push or main-branch push is used. [Issue #124](https://github.com/ViktorOsadsky/lifetwin/issues/124) remains open until publication/merge is reviewed.

The [previous endpoint evidence](../qa/model-acceptance-2026-10-24/server-checks.json) and [reproduction](../qa/model-acceptance-2026-10-24/server_check.py) showed recommendation messages publishing unsupported weight-gain claims appended to otherwise valid drafts. A word/number denylist did not establish that the meaning matched the chosen action. This fix replaces that boundary for recommendation/question copy with complete server-authored choices. It does not claim a regex can certify arbitrary prose.

## Behavior and contracts

- The server offers the whole deterministic recommendation, either unchanged or followed by “We can go at your pace.” / “There's no rush.” Questions retain their whole plain server question, optionally preceded by “Take your time.” / “When you're ready:”. No action, caution, number or evidence is removed or rewritten.
- A provider can select one complete choice. The server performs full-string equality and publishes its private canonical string, rather than the provider string. Only outer ASCII spaces may differ. New prose, appended/mixed claims, reordered sentences, omitted cautions, Unicode/confusable/control changes and malformed lines fall back. Even harmless unrecognized paraphrases intentionally fall back.
- Choices are kept separately from the provider payload, so a fake/buggy adapter cannot mutate the transmitted list to introduce an approved claim. Request facts, quoted notes and provider replies never add choices.
- Recommendation builders mark note-derived messages with `based_on: note:<topic>`. Their free-text slots include smoking quit aids, exercise kind/company/barriers and sleep bedtime/waking reasons. These messages have **no provider choices** and keep their existing deterministic wording. When every recommendation is ineligible, no provider call is made. New builders must preserve this provenance boundary. This change does not validate or rewrite the existing note-slot renderer.
- Plain next questions come from `_question(..., plain=True)`, excluding the free-text steering lead; the optional duration is formatted from a validated numeric profile field. The provider cannot introduce a different question or echo an untrusted claim into it. Read-backs and value extraction stay unchanged.
- Relative to the merged owner changes, external API schemas, provider-specific consent, capabilities, per-item fallback and `phrased_by` semantics remain unchanged. Claude/Muse provider selection, the Claude SDK and document consent changes are preserved. Provider JSON still uses `lines` / `line`; prompts now supply `approved_wordings` and request a selection (an unchanged draft string for an ineligible item, which is ignored in favor of the existing template). Ranking, deterministic plans, effects, model inputs, profile state, citations and experiment targets are untouched.
- Check-in care replies also select whole server-authored choices: unchanged, or with a neutral “I'm here with you.” prefix. Their final safety sentence remains unchanged, including the caller's existing safety check. The reflected mood comes from fixed `_REFLECT` phrases, not raw user text. Both providers retain their own consent identity.
- Coach plans retain their existing, separate draft/keep-word guard. The original attack reproduction still falls back there. This patch does not certify arbitrary Coach prose or replace its planner.

Implementation: [copy boundary](../../server/lifetwin/personalize/safety.py), [integration](../../server/lifetwin/personalize/service.py), [focused regressions](../../server/tests/test_provider_copy_guard.py). The underlying product restrictions remain in [the master guide](../../MASTER_PLAN.md) and [spec §15](../../projectspec.md#15-safety-privacy-and-responsible-ai).

## Validation

All inputs were synthetic; all providers were doubles. No real profile, external provider key, live Muse/Cartesia call, app/model change or simulator/device action was used.

- Full Python 3.11 backend suite: **4119 passed, 5 skipped, 12 expected failures**. This includes all **190 focused provider-copy regression cases** and the recommendation, conversation, critical safety and Coach suites.
- Ruff lint and format check passed across `server` and `contracts` (117 files checked for formatting).
- OpenAPI export: **28 schemas checked**, with no schema changes. Offline contract fixtures passed; in-process replay checked **85 responses across 85 cases**. A temporary keyless Uvicorn service on localhost:8124 passed the same **85 HTTP response cases** and was stopped afterward.
- The original endpoint reproduction was rerun against these working changes, using a temporary script copy whose only alteration was its output filename. All **six** appended-claim attempts returned `disallowed_line_published: false`, with one fake-provider call per attempt; baseline versus BMI-plus-one content stayed identical on both endpoints. Historical committed evidence was preserved. Temporary result: `/private/tmp/lifetwin-124-server-results.json`.
- Existing positive tests that permitted unrelated supplement insertion now require fallback. Other positive tests select an actual approved choice, retain the whole action and confirm that evidence, effects, profile/model inputs and state are unchanged. New tests exercise diverse weight/health paraphrases, mixed claims, same-vocabulary action reversal, Unicode/zero-width/bidi/fullwidth variants, numbers, malformed values, note provenance, private-allowlist mutation, bounded questions, outages and log privacy.

Reproduce with the locked development environment:

```sh
PYTHONPATH=server python -m pytest -q server/tests/test_provider_copy_guard.py server/tests/test_critical_recommendations.py server/tests/test_conversation_v2.py server/tests/test_critical_safety_paths.py server/tests/test_critical_coach_plan.py
PYTHONPATH=server python -m pytest -q
ruff check server contracts
ruff format --check server contracts
PYTHONPATH=server python contracts/export.py --check
PYTHONPATH=server python contracts/check.py
PYTHONPATH=server python contracts/check.py --in-process
```

Integration checks use a separate temporary Python 3.11 environment synchronized from the merged `uv.lock` with CI-pinned uv 0.13.5; the shared repository environment is untouched. This worktree's `server` is on `PYTHONPATH`, and all provider keys are explicitly blank for full-suite and contract runs. Docker CLI is unavailable, so no runtime container build/replay was run locally. Python 3.12/3.13 and container checks remain for CI; live provider behavior remains untested. There is no claim that the bounded wording is clinically validated, that arbitrary prose is safe, or that a configured provider will always select a valid choice.

Next dependency: parent review, normal PR checks and merge. The merge additionally checks selected/malicious care replies through both consent identities and fake Claude structured outputs. The combined focused suite passed **646 tests**. The owner quick-check-in positive fixture was updated from unrecognized “Gentler.” prose to the approved neutral prefix; its focused test passed before the full rerun. Ineligible recommendation slots return strings, matching the owner's existing Claude `PHRASE_SCHEMA`; a returned string does not make an ineligible slot trusted.

Future expansion beyond these small neutral variants needs reviewed server-authored choices or a separately reviewed semantic boundary; adding more denylist phrases is insufficient. Preserve deterministic fallback while testing any future provider configuration.
