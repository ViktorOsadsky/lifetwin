# Independent fresh behavioral evaluation

Created 2026-10-23. These cases were designed before reading any author's evaluation report or scenario output. The only targets read first were the two packaged skills, their execution contracts, their scripts, and the raw sponsor briefs.

Run from this directory: `python3 run_fresh.py`. All data, actors, approvals, quotations and local ledger writes are synthetic. No credentials, external writes, Visa calls, Hyphenate calls or live third-party sandbox calls occur. The script uses the packaged finance gate for boundary checks, and adds a small application policy derived from the fictional shop's signed contract. The Visa task ends at an informed shopping handoff; payment machinery would add no value here.

Files: `company.json`, `shopping.json` are explicit input fixtures; `initial-results.json` is the first execution result; `critique.md` records the independent conclusions. `run_fresh.py` can rerun the same cases after skill changes, but an unchanged deterministic runner cannot measure whether prose changes improve a new agent's behavior.

After the parent authorized narrow helper fixes, before copies were preserved in `before-fixes/`. See `replay-report.md` for the corrected Apify request/response build contract, exact changes and rerun results. `after-fixes-results.json` and `apify-rerun-results.json` preserve the new results without replacing the initial observations.
