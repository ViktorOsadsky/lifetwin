# LifeSim team plan

How we split the original spec ([`projectspec.md`](../projectspec.md)) so four people can build in parallel without drifting apart. Read [MASTER_PLAN.md](../MASTER_PLAN.md) first for the current product and [the backend run guide](../server/README.md) for implemented non-prediction functionality/contracts. This document governs owners and original sync targets. Changes from the spec are listed in [prd-reconciliation.md](prd-reconciliation.md); stack defaults are in [tech-stack.md](tech-stack.md). Flutter, voice, model, numerical stub and iOS helper paths below remain future work; the user explicitly deferred prediction implementation.

## Decisions so far

| Area | Decision |
|---|---|
| App | Flutter / Dart, tested on iOS through Xcode |
| Presentation | LottieFiles motion and SVG assets; Talking Tom-style game shell, mascot-led voice/text intake, magic-ball fortune, quiz with independent game-health reactions |
| Training | Python. Victor picks the method |
| Server | FastAPI (master doc §7). Serves Victor's model and keeps the LLM key off the phone (§15) |
| Advisor input | The user's inputs plus the model's results. May change later |
| Merging | Short branch → PR → merge to `main` after applicable checks and repository protections pass. No extra review required unless repository rules require it. Bad merge → revert through a PR |

Because Victor is free to choose the model, the shared boundary is **the API, not the model file**. Everyone builds against the
JSON contracts in `contracts/`, so the model behind them can change without breaking anyone.

## Tracks

| Track | Owner | Master doc | Starts on (no waiting) | Done when |
|---|---|---|---|---|
| [**A. Data & Model**](tracks/A-data-model.md) | Victor | §6, §12 phase 1 | Immediately | Model artifact + eval report committed; validated age range and max horizon stated |
| [**B. API & Integration**](tracks/B-api.md) | _TBD_ | §7 backend, §8, §9 | The stub server | `contracts/check.py` passes against the real server; deployed URL reachable from the phone |
| [**C. Flutter App**](tracks/C-flutter-app.md) | _TBD_ | §2, §3, §4, §10, §11 | The stub server | Full demo flow runs on the iPhone against the stub, then against the real API |
| [**D. Advisor, Trust & Demo**](tracks/D-advisor-demo.md) | _TBD_ | §5, §15, §16 | Fixture predictions | Advisor passes the number check; demo rehearsed with a judge changing inputs |

**Three people instead of four:** merge B and D. The advisor is one more FastAPI route.

**Critical path:** A. NHANES harmonization eats time, so a small first slice (2–4 cycles, the §6.3 core features) gets real
numbers flowing early. Everyone else works on the stub, so a late model delays only the switch to real numbers.

## How we avoid drifting apart

1. **Contract Zero first (about the first 2 hours, together).** `contracts/` lands on `main` before anyone branches:
   - `profile.schema.json`: what the user enters (§2.2, metric units; the app converts)
   - `prediction.schema.json`: `/api/predict` response (§9 fields plus `status` / `limitation`)
   - `compare.schema.json`: `/api/compare`, deltas in percentage points computed by the server
   - `advisor.schema.json`: `/api/advisor` request and response
   - `sensitivity.schema.json`, `conversation.schema.json`, `quiz.schema.json`: bounded scans, confirmed conversational intake, and independent game-health scoring from the master guide
   - `fixtures/`: sample requests and expected responses (typical, smoker + diabetic, minor, age out of range, the §4.1 demo futures, an advisor question)
   - `stub_server.py`: returns contract-shaped responses from **fake** coefficients (`model_version: "stub-0"`)
   - `check.py`: replays every fixture against any server
2. **One checker, used by everyone.** `check.py` validates every response against the schemas. With the same `model_version`
   the numbers must match exactly. Advisor answers must not contain a percentage that isn't in the model output (§5.3); it
   can't yet catch a real number quoted for the wrong year.
   ```sh
   python3 contracts/stub_server.py                                   # stub on :8000
   uv run --with jsonschema python contracts/check.py                 # or: pip install jsonschema
   uv run --with jsonschema python contracts/check.py --base-url https://<deployed-api>
   ```
3. **Changing a contract** = edit the schema, update `stub_server.py`, run `python3 contracts/stub_server.py --write-fixtures`,
   check passes, and tell the team in chat **before** merging. A contract change merged without telling people is the main
   way we'd drift.
4. **Branches are short.** Default to `codex/<track>-<task>`; the earlier `a/…` through `d/…` names are legacy conventions. Pull `main` into your branch often and merge through PRs at every sync point.
5. **Sync points** (hours after kickoff; master doc §12 phases in brackets):
   **T+2** Contract Zero · **T+8** every track merged, stub flow runs on the phone [phase 2] · **T+16** real model behind the
   API [phase 1 done] · **T+20** compare screen working end to end [phase 3] · **T+24** advisor in the app [phase 4] ·
   **T+32** polish and deploy [phase 5] · **T+40** feature freeze (fixes and rehearsal only)
6. **When Victor's real model lands:** B swaps it in behind the same routes in one merge, regenerates fixtures from the real
   server and bumps `model_version`. The app shouldn't need any change.

## Checkpoints and rollback

A checkpoint is a tag on a `main` commit where the demo flow works and `check.py` passes:

```sh
git tag cp-03 && git push origin cp-03
```

To undo one bad merge (keeps everyone else's later work):

```sh
git revert -m 1 <merge-commit>   # or: git revert <commit> for a non-merge commit
```

To recover checkpoint behavior, branch from current `main`, then revert the bad changes or restore reviewed paths from the checkpoint and open a recovery PR:

```sh
git switch -c codex/recover-checkpoint main
# Revert bad changes or restore reviewed paths from cp-03; open a PR.
```

Branching from an ancestor checkpoint and merging it back does not undo later commits. Don't `git reset --hard` and force-push `main`. That throws away every teammate's commits made after the checkpoint. Deliver individual reverts through PRs too.

## Rules every track follows (master doc §3.1, §5.3, §15)

- Every personal survival prediction comes from the model API. Never hardcode one or let the LLM invent one. Quiz/game-health scores are separate deterministic game values and never change medical predictions.
- Out-of-population profiles (minors, ages outside the validated range) get a limitation message, not a curve.
- Curves stop at the model's `max_horizon_years`.
- Always label results as modeled associations from observational data, not causal effects.
- Don't store or log raw health profiles. The stub server logs only method, path and status.
- API keys live on the server only.
