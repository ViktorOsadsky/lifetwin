# Verified context — checked 2026-10-23

## The supplied starter pack resolves the build scope

The Hyphenate card on [Hive resources](https://hive.hackberkeley.org/resources) links to [CalHacks_Hyphenate_Track](https://docs.google.com/document/d/1u4iN8R97ILY3kfHTPKC82zdutHrGx4ze5eCAP-J92w4/edit?usp=sharing), the same document supplied by the user. Its full text and embedded links were read through Google Docs' public export. The root agent independently inspected the rendered Hive card; plain web extraction initially returned only a loading placeholder. Hive's other-resources tab said resources would be posted soon.

This is a finance autonomy challenge brief. It tells teams to invent a company and a few collaborating finance seats, build the software and people around those seats, and plant realistic mistakes. It allows sandboxes, borrowed schemas and datasets, with unrestricted model/framework choice. The brief does **not state a requirement to use Hyphenate's platform API**. This is a reading of this specific brief, not a promise about unannounced event rules.

Its hard cases are conflicting sources, decisions spanning months, incomplete handoffs and busy/rejecting approvers, limited access, segregation of duties, and a traceable explanation for every decision. A requester cannot approve their own payment. A model may portray an approver, colleague or auditor; disclose that simulation rather than representing it as real human sign-off.

The [Hive prizes page](https://hive.hackberkeley.org/prizes) and brief agree on $8,000 / $5,000 / $3,000. Hive also lists expedited interviews for the top five teams. The four judging questions cover realistic messy work with proof; seats earned through limited access, records and escalation; originality; and a memorable catch, recovery or defended decision. Submit code, a video opening with that moment, a live demo that tolerates a new judge scenario, a one-line seat description, and evidence distinguishing real from simulated behavior.

## Execution contracts: known and unknown

| Surface | What is established | What remains unverified |
| --- | --- | --- |
| Hyphenate platform | [Official product](https://hyphenate.ai/) and [Treasury](https://hyphenate.ai/treasury) describe autonomous finance, bank/ERP reconciliation and evidence-backed suggestions requiring approval before posting. | API base URL, auth header/security scheme, SDK, OpenAPI, MCP endpoint/tools/schema, rate limits, test tenant and integration permissions. None appears in the supplied brief. This does not prove no private/public API exists. |
| Third-party sandboxes/ledgers below | Exact links are embedded in the sponsor brief; Stripe sandbox docs and Formance repository were opened. | No credentials or tenant were supplied for these. No authenticated API call or write was made; any selected provider needs its own current API/SDK/schema inspection. |
| Bundled finance/workflow helpers | Runnable local simulations with explicit schema and scenario checks. | No external ledger, bank, remote retry, accounting-policy certification or Hyphenate integration. |

Marketing claims establish product context, not executable contracts. If an actual sponsor spec arrives, record its source/version/hash; resolve declared server/security schemes; inspect required schemas; and probe a documented non-mutating operation with authorized access. Use `catalog_tools.py` for an inert OpenAPI/MCP catalog. Keep live sandbox, documented-only, local simulation and unavailable capabilities separate.

## Exact resource links from the brief

Choose one system that supplies the needed world; this list is a source index, not a request to install every product.

- Sandboxes: [Stripe](https://docs.stripe.com/sandboxes), [Increase](https://increase.com/documentation/sandbox), [Lago](https://getlago.com/docs/guide/lago-self-hosted/docker), [Odoo](https://hub.docker.com/_/odoo), [ERPNext/Frappe Docker](https://github.com/frappe/frappe_docker).
- Ledgers: [Formance](https://github.com/formancehq/ledger), [Blnk](https://docs.blnkfinance.com/home/install), [TigerBeetle](https://docs.tigerbeetle.com/start/), [Beancount/Fava](https://github.com/beancount/fava).
- Mocks: [Mockoon CLI](https://github.com/mockoon/mockoon/blob/main/packages/cli/README.md), [Prism](https://github.com/stoplightio/prism), [stripe-mock](https://github.com/stripe/stripe-mock).
- Data: [SEC EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces) and public repositories. Filings can ground a company story but are not transaction-level bank/ledger evidence.
- Benchmarks: [AccountingBench announcement](https://x.com/yunyu_l/status/1946261507723173935), [APEX-Accounting](https://huggingface.co/datasets/mercor/apex-accounting), [Finance Agent Benchmark](https://huggingface.co/datasets/vals-ai/finance_agent_benchmark), [DABstep](https://huggingface.co/datasets/adyen/DABstep), [BenchRec](https://www.kaggle.com/datasets/benchmarkteam/benchrec-real-world-cash-reconciliation-dataset), [Invoice Sandbox Benchmark](https://github.com/ciru-ai/invoice-sandbox-benchmark).

These benchmark links were extracted, not independently reproduced or license-audited. Inspect task fit, license, splits and leakage before using a benchmark score. Stripe's current docs describe isolated sandbox payments without real payment processing; no sandbox was provisioned here. Formance's current default branch describes Ledger v3 and exposes `openapi.yml`; pin the chosen version and inspect that version's API rather than copying an older endpoint from memory. No Formance runtime was started here.

## Local fixture format

`finance_checks.py` expects `proposal_id`, `tenant_id`, distinct nonempty `source_ids`, `source_version`, `policy_version`, and `lines` containing `account`, `entity`, `currency`, `debit_minor`, `credit_minor`; optional `previous_proposal_ids` detects replay by proposal ID. This is **our local fixture format, not Hyphenate's API**. Balances are per entity and currency. See [workflow-example.md](workflow-example.md) for the additional local execution gate.
