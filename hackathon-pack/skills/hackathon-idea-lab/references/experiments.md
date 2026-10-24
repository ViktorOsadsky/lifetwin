# Experiments that change the build decision

## Public research is not customer validation

A regulator's warning establishes a problem or obligation. A competitor's price establishes an offer. A company case study establishes a vendor-reported outcome with a named customer, subject to selection bias. None proves that the proposed user will adopt the proposed product. Do not manufacture interview counts, quotes, conversion, savings, or willingness to pay.

When interaction with users is authorized, prefer artifacts and choices: ask the actual operator to show the last occurrence, recreate their workflow, then choose between the existing workaround and the prototype. A useful test asks them to perform a task or commit to a pilot, rather than “would you use this?” Record time, errors, refusal reasons, and whether they already own a substitute. Without authorization, write the protocol and mark it unrun.

## Novelty audit

Create a matrix of the proposed workflow steps against the closest products. Read current feature documentation before claiming a gap. Include at least one exact-action search and one adjacent substitute. An incumbent need not advertise the same positioning to disqualify a supposed feature novelty. A novel visualization is an execution distinction, not proof of a new market.

Record search terms, date, products examined, facts found, and exclusions. Use “the reviewed pages did not establish X” when documentation is incomplete. Do not turn absence of documentation into evidence of absence.

## Weekend feasibility

Get one representative raw input into the system before committing to the idea. An API documentation page is not a successful data fetch. A cached result proves parsing against that cache, not live reliability. A simulated bank or ERP proves state transitions, not production integration. Check that a sponsor integration changes a useful result, not just a logo or README.

Timebox the riskiest dependency first. Define a fallback that retains the core claim; if the fallback removes the point of the product, kill or re-scope it. A public demo using synthetic customer documents should say so. A rubric forbidding mocked data may make such a fallback ineligible for that particular prize even when the overall prototype is valid.

## Reliability and adversarial scenarios

Separate deterministic policy invariants from model extraction quality. Test missing fields, conflicting sources, corrected source documents, duplicates, partial execution, stale caches, denied credentials, and adversarial text embedded in external documents. Use held-out inputs rather than replaying only the opening demo.

For money-like workflows, represent amounts as integer minor units or exact decimals; distinguish proposed, approved, submitted, and settled states. A repeated event should not create another payment or recovery. Uncertain supplier reimbursement should not be counted as cash received. If these are not the product's domain, choose equivalently concrete invariants.

Report the denominator and actual result: “12/12 fixture cases passed” is useful; “100% safe” is unsupported. A local policy script does not measure LLM accuracy, demand, legal compliance, profitability, or production readiness.

## Useful stop rules

- Kill a novelty claim if a current product already performs the proposed core action; either articulate a material new workflow or choose a stronger candidate.
- Kill a weekend scope if the key data cannot be obtained legitimately within the build window.
- Reduce confidence when only vendors describe the problem or when competitors offer the same thing free.
- Prefer a smaller complete flow if another sponsor integration consumes the failure-recovery and presentation time.
