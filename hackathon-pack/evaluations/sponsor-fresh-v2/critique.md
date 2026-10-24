# Fresh task outcomes and concrete limits

Evaluated packaged skills independently on 2026-10-23, before reading any author's scenario output, evaluation report or confidence claim. Read their SKILL.md and operational contracts, inspected scripts, and compared with `design-lab/sponsor-docs/{hyphenate,visa,apify}-source.txt`. No authors' evaluation documents were read. All files here are owned by this evaluator. No skills were edited.

## Resale monthly close

`run_fresh.py` executes a small local ledger rather than stopping at a proposed architecture. `company.json` defines the authoritative owner of each fact and an explicit fictional accounting policy. The actual flow has March sale/fee/settlement, an inherited April error from a partial handoff, a June adjustment without rewriting closed periods, a late-arriving bank debit retaining its April economic date, and a later inspection that reverses part of an owned-stock impairment. Nine source-document rows separate effective dates from arrival dates. The local journal includes eight entries and a chained evidence event per entry. Consigned quarantined goods remain custody records, not shop assets. Consignor payout is blocked and handed to warehouse/controller rather than inferred from inventory status.

The final debit-positive balances in `initial-results.json` reconcile: consignor payable zero; refund clearing zero; commission revenue and return contra zero together; owned inventory net $70; processor fee $6 remains. Bank movement is net negative $6 for the fully refunded consignment sale. March/April journal snapshots remain identical. A real controller must decide the appropriate fiscal presentation of late April cash; posting in June does not turn it into June operational cash. All authorizations are simulated and have distinct proposer/controller roles.

Eleven independent cases exercise a benign sale, numerically balanced but wrong 75/25 consignor split, rejected approval, self-approval, closed March/new return, confirmed replay, uncertain bank outcome, revised inspection, absent condition evidence, consigned versus owned stock, and equal-value ambiguous bank events. The fixture's deterministic application policy computes the contract split and ownership/inspection/uniqueness holds; those checks are not attributed to the generic helper. No missing source became true because a journal balanced.

The skill materially helped choose an explicit simulation, model authority per fact, keep closed periods closed, track late events, separate duties, preserve fees, and make a correction auditable. This is aligned with the actual brief's messy sources, time, half-complete collaboration, limited access and evidence requirements. No Hyphenate API requirement or fictional vendor capability was invented.

**Concrete helper gap:** the independent `rejection_history_probe` in `initial-results.json` supplies an earlier rejection for the same exact proposal/hash plus a new current `approved` decision. `workflow_checks.gate` returns `ready_for_adapter: true`; it has no documented rejection history/revision check. SKILL.md says rejected proposals remain rejected until a revised independently authorized decision. A production store would have to enforce that rule. A useful narrow fix is an explicit trusted rejection/revision contract and a heldout test, or explicitly listing this as a local helper omission. This probe is not proof of actual unauthorized posting: the helper never posts, and an arbitrary additional `prior_decisions` key is not part of its existing documented context.

**Accurately disclosed limitation, not a newly discovered bug:** the helper accepts the balanced wrong commission split when freshly approved. The skill explicitly says policy semantics and document truth require an adapter. Our task needed roughly 30 lines of company-specific checks in addition to the supplied gate; a user copying only the generic gate would not have a working consignment accountant.

This evaluation's ledger, approvals and current-context dictionaries are synthetic test fixtures. It does not prove a real independent authorization store, durable immutable audit storage, remote uncertain-outcome lookup, or policy certification. Savings/time reduction is a proposed metric, not measured.

## Visa student shopping

`shopping.json` contains seven exact product variants, a $650 strict delivered cap, the bag's internal envelope and two native app requirements. `run_fresh.py` selects B at **$637.20** with a source/variant/timestamp trail. A costs **$650.16** and fails despite a $590 sticker; ChromeOS/ARM are rejected for the explicit native x86 Windows app requirement; oversized E fails fit; unknown-tax F is held; G's unknown dimensions/architecture never count as a match.

Seven scenarios include the base decision, B's price increase causing abstention, an explicit F tax quote restoring a valid selection, stale quote, wrong-RAM variant, a one-millimeter fit failure and the inclusive exact cap boundary. Each scenario saves its selected/abstained output and every candidate's failure reason. Nothing collects payment or address data; the endpoint is a read-only merchant handoff.

The skill helped keep delivered cost separate from sticker price, hard constraints separate from preference, missing data unknown, and current facts rechecked at handoff. Its event scope agrees with the raw Visa brief: generative AI shopping can address decision-making; no proprietary Visa APIs are offered, external APIs are optional, and a chatbot alone is insufficient. We preserve starter weights 25/20/20/20/15 and the skill's recorded Hive disagreement at UX/commerce 25/15 rather than declaring a resolved rubric.

**No concrete Visa skill defect was demonstrated.** Its general constraint guidance was enough to design these cases. The meaningful remaining gap is in this evaluation's prototype: the assistant did the generative translation of shopper/course prose into editable constraints during authoring; the saved runner then operates deterministically. A runtime model API is not integrated or benchmarked. Therefore this artifact demonstrates constraint correctness and a useful shopping decision, but is not yet a complete competition-ready generative shopping app. The skill expressly demands meaningful AI; it did not cause this limitation. Add runtime extraction with attributed spans and a grounded explanation, then measure false acceptance on new product/app facts. Do not call the 7 fixture scenarios conversion evidence or payment verification.

The bag check uses a rectangular internal envelope and permits orientation changes; it does not establish zipper clearance, fit under flexible pressure or real product tolerances. The synthetic requirements should be replaced by the actual bag and exact app/version/license support matrices before a purchase recommendation. No actual retail offers or real application compatibility were verified.

## Apify bounded evidence

Fresh unauthenticated MCP connection, `tools/list`, search and Actor-detail calls succeeded. The four raw live responses are saved under `apify-live-*.json`. They establish actual current tool names, schemas, pricing and metadata, not extraction results. The selected candidate is `apify/website-content-crawler`, modified October 21, because one input accepts both exact URLs and explicit crawl bounds. Current required keys are `startUrls` and `proxyConfiguration`. Our input uses depth zero, two pages, no sitemap/llms discovery, one worker and raw HTTP. We inspected `apify/rag-web-browser` as an alternative: its single `query` accepts a single URL or search, and its current response lists fetched-page, search and startup event prices. Choosing the website crawler on popularity alone would not have supplied those facts.

The selected crawler's **Actor fee is FREE; platform compute/proxy/storage still cost money**. The $0.05 plan is an unexecuted bound, not a quote or authorized expenditure. Current platform cost, executable build pin and account permission review remain unresolved, so the decision is provisional and no Actor ran. The plan's build ID is deliberately synthetic. MCP discovery visibility is not a completed account permission review.

`apify_fresh.py` runs ten independent offline cases with request logs: one-item pages, zero items, incomplete second-source coverage, off-scope source, changed build, unknown cost, failed partial run, never-terminal run/abort, uncertain POST start, and mutated reviewed plan. At most one start occurs; the mutated plan produces zero calls; a full two-source result requires two page reads. A separate application evidence gate withholds incomplete, out-of-scope, unreviewed-build and unknown-cost results. The helper's fetch time is not relabeled crawl time.

**Concrete robustness gap:** the helper accepts a successful run reporting a different `buildId` from the requested pinned plan and returns that envelope as usual. The original build is carried only through the plan; no request/result comparison occurs. Our evidence gate catches it. This is a controlled malformed-response probe, not a claim that the real Apify service violates pinned builds. A small adapter verification rule would make the promised reviewed-schema/build boundary explicit. Similarly, successful empty/partial output needs application coverage checks; the skill already explains this well, so it is not a new defect.

`apify-direct-observations.json` contains a genuinely obtained two-source sample from Python and Node release pages using the public web reader, **separate from Apify**. This makes the target evidence useful while respecting the no-paid-run constraint. The Python source labels 3.15 as bugfix maintenance; the Node source labels v24 LTS and v26 Current. Those are different maintenance models and cannot be collapsed into one ungrounded score. This source-backed distinction changes a developer runtime recommendation, whereas missing either site must cause a partial/abstained comparison. These observed facts are cited to their exact official pages; no Apify run IDs, cloud execution or measured collection cost are invented.

The raw Apify guide is a platform starter guide, not a detailed challenge rulebook. It offers account-owner event credits and many routes (Console, AI Chat, MCP/plugins, API/clients, build/deploy, tasks/schedules/webhooks/storage). The skill covers these routes without treating credit or credentials as spend authorization. The raw guide does not establish publication/monetization as an award condition. The skill separately records Best use and Best Actor award categories with an explicit eligibility gap; this evaluation has not independently reverified those live award pages and claims no eligible submission.

## Evidence boundaries

| Claim | Evidence actually obtained |
| --- | --- |
| Resale close/corrections and shopper constraints execute | Local synthetic fixtures and Python assertions |
| Independent real controller approval | Not obtained; separate simulated roles only |
| Visa API/MCP runtime/payment | Not attempted; unnecessary to the selected shopping stage |
| Hyphenate API or third-party finance sandbox | Not attempted; local ledger explicitly chosen |
| Apify discovery/current schemas/pricing | Actual unauthenticated MCP read-only responses |
| Apify lifecycle/pagination/recovery | Offline doubles with request logs |
| Source facts from two specified websites | Actual direct public web reads, not Apify extraction |
| Paid collection, deployed Actor, production reliability | Not obtained |

No arbitrary aesthetic scores or perfect-readiness claims are warranted. The outcomes support useful local workflows and two narrow helper-boundary improvements. A rerun of unchanged deterministic fixtures after prose edits alone would not establish improved fresh-agent behavior.
