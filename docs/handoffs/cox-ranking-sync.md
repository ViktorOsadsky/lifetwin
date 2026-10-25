# Cox recommendation cache sync

Local review branch: `codex/d-sync-cox-ranking`, based on merged main
`1a86d9a71943a869ee34348526652208bb2096f9`. No push, PR or merge is claimed.
Root coordinated this focused advisor integration with the model/app owners on PR #151.

The approved [sensitivity JSON](../model-sensitivity.json) now identifies
`personal-cox-bmi35-v3-20261024`, while the server recommendation cache previously used v2.
This updates its 50 median values across the existing ten cached groups and its
`MODEL_VERSION`; the docstring now describes the actual server-side categorical use.
The existing integration test checks model-version provenance as well as median equality.
Source SHA256: `0061175e134b053c7e2967a3ba5a98f91d9ec439ed384e4afc2b1fe31e189aec`.

Lever order, applicability, thresholds, fallback age bands, recommendation wording,
schemas, app/engine code and personal comparison math are unchanged. All 50 cached
entries retain their existing effect categories at the unchanged 2.0/0.75/0.25 pp
cutoffs. The ranking response's existing `lever_ranking.model_version` string now
truthfully names v3. The medians are observational five-year profile contrasts;
they are not personal benefits or years gained. No numeric prediction is added.

Validation used the existing Python 3.11 environment with this worktree's `server/`
first on `PYTHONPATH`, no installs or live providers:

- Before: `test_table_matches_the_sensitivity_json` failed against the stale cache.
- After: recommendation effect/fields, critical recommendation and onboarding files:
  **302 passed**.
- Ruff check over `server contracts`: pass. Ruff format check: **112 files pass**.
- Boundary check: every source group's lever order matches the preserved order;
  no cached median crosses an existing effect-category threshold.
- Initial seam supplement found one stale generated fixture. After root authorized
  the exact seven-label refresh, the existing `make_seam_fixture.py` generator
  reproduced only those seven changes; the full backend suite then passed:
  **3,868 passed, 5 skipped, 12 xfailed** in 29.91 seconds.
- Contract export check: **28 schemas pass**. Static fixture check and in-process
  replay pass: **81 request fixtures, 85 responses across 85 cases**.
- `git diff --check`: pass.

The only app fixture changes are the following `model_version` leaves, each from
`personal-cox-v2-20261024T182404Z` to `personal-cox-bmi35-v3-20261024`:

- `/recommendations/from_onboarding/lever_ranking/model_version`
- `/recommendations/smoker/lever_ranking/model_version`
- `/recommendations/very_old_smoker/lever_ranking/model_version`
- `/recommendations/guideline_only/lever_ranking/model_version`
- `/recommendations/not_enough_information/lever_ranking/model_version`
- `/recommendations/under_age/lever_ranking/model_version`
- `/recommendations_after_weekly/lever_ranking/model_version`

No other fixture leaf, assertion, app code or contract schema changed.

Known limits: local checks used Python 3.11; the remote Python matrix remains the
publication/merge gate. These are deterministic in-process and fixture integrations,
not device or live-provider validation. The model owner retains authority over approved
artifacts/support; this integration only synchronizes their current output. Root reviews,
publishes the focused PR, waits for CI, and coordinates dependent report branches.
