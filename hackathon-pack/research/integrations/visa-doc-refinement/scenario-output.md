# Actual planning output: commuter USB-C buying guide

Build a small decision assistant that catches an easy shopping mistake: a USB-C charging socket does not establish wired USB-C audio. Keep the user's headphone category and finish at an explicit merchant handoff. The Visa starter pack permits decision-making projects and will not provide proprietary APIs; this implementation requires no Visa credentials or payments.

The shopper enters a budget and arrival date, then sees editable hard requirements: digital wired USB-C audio, microphone, in stock, delivery by October 26, and $80 maximum including all charges. The application returns a short evidence-backed comparison. It explains why a tempting wireless listing fails and withholds options whose delivery is unknown. A button opens the exact merchant variant; its label says to verify current terms at checkout. No order is submitted and there is no paid state.

## Fixture decision produced for the supplied request

Every item below is fictional, from `catalog.fixture.json`. The `.example` URLs identify fixtures; they are not working retail sources. Tax/shipping are fixture quotes for a preset delivery region, not externally verified charges. These facts expire at 20:15 UTC on October 23, 2026.

| Candidate | All-in USD | Decision | Explanation |
| --- | ---: | --- | --- |
| Harbor USB-C Wired | $69.01 | Recommend in fixture mode | Digital USB-C audio, mic, stock and October 26 delivery explicitly recorded |
| Metro ANC Wireless | $79.87 | Exclude | USB-C is charging only; hard audio requirement fails |
| Studio C | $75.53 | Needs evidence | Delivery date unknown; do not imply it will arrive in time |
| Fast C | $85.29 | Exclude | $5.29 over the complete budget |
| Commute C | $65.10 | Exclude | Out of stock |

Suggested explanation: “Harbor is the only verified fixture match at $69.01 including the quoted tax and shipping. Metro charges over USB-C but does not meet wired audio. Studio may work, but its delivery is unverified. Recheck the exact variant and final charges before buying.” The $10.99 difference between Harbor's quote and the budget is remaining budget, not realized savings.

If all candidates fail, explain the blocking constraints and offer an editable relaxation, such as extending the arrival date. Do not silently increase budget or infer missing compatibility. After fixture expiry, display that the quote needs refresh and withhold a current match claim. If tax or shipping is missing, the all-in total is unknown. The accompanying checker exercises a $60 no-match budget, expiry and missing tax, in addition to the five comparison decisions.

## Implementation contract

`POST /recommendations` is an application route we would build, not a Visa endpoint. It accepts the editable constraints and product records with exact variant, source URL, retrieval time, expiry, attributed claim evidence, stock, delivery and integer money components. A model maps conversational preferences to proposed constraints and extracts cited claims; the user can correct them. Application code validates hard requirements and totals, then returns eligible options, unknowns and exclusions with reasons. The model explains those validated decisions and must not invent missing facts or trust instructions embedded in catalog descriptions. Keep API secrets server-side and exclude card/address data from the model path.

Generative AI's intended contribution is translating varied commuter needs and unstructured listing language into comparable attributes, including charging-versus-audio distinctions, then explaining evidence and tradeoffs. The deterministic fixture checker does not implement or validate that model step. Before claiming meaningful AI execution, connect a real model, retain extraction source spans, and evaluate unseen listings with ambiguous, conflicting and missing claims against manually checked labels. A keyword filter alone would not establish this contribution.

For a weekend build, implement the comparison screen, typed constraint/result contract, fixture source adapter and deterministic verifier first. Then connect one permitted public catalog or manually curated public listing source with its usage terms and provenance; use a server-side model for extraction and explanations. Recheck volatile prices, delivery and variant before handoff. If actual tax/shipping cannot be quoted for the shopper's region, mark the all-in total unknown rather than awarding a budget pass. Cache sources for the demo and label cached material. No paid data or sponsor account dependency is required for the fixture version.

Show a short demo: enter the request; inspect the editable constraints; compare the five candidates; explain the USB-C trap; reveal the missing-delivery rejection; expire the selected quote and show the refresh requirement; finish on the merchant handoff. Describe the next step as a real data/model adapter and a measured user comparison task. This is a demo script, not a timed recording or running UI.

## Evidence and judging

The starter-pack rubric is innovation 25%, technical execution 20%, UX 20%, commerce impact 20%, trust 15%. Hive's prize card differs at UX 25% and commerce 15%. Keep that discrepancy visible until the sponsor resolves it; no computed score is justified.

The product hypothesis is fewer incompatible purchases and less comparison effort. Evaluate this with shoppers completing the same buying task against a normal listing flow, measuring valid decision rate, time and comprehension of rejected options. Those outcomes have not been measured. Five deterministic fixture decisions, stale-quote rejection and a no-match branch are local correctness evidence only. No real product recommendation, conversion lift, purchase, realized savings, deployed UI, AI extraction quality or track acceptance is claimed.

## Optional VIC integration after access is supplied

Keep the decision flow working while onboarding separately. Use official source-pinned runtime examples and discover the authorized product MCP tools and schemas after authentication; never invent a `pay` tool. The Developer MCP is a read-only documentation surface, and its configuration is not a payment backend. The supplied task has no credentials, so live schema discovery and runtime actions stop here.

If a later authorized sandbox checkout is added, translate the selected verified cart into the discovered product contract, verify minor-unit conversion, obtain approval of immutable merchant/amount/variant/delivery terms, reserve a durable request before mutation and keep credential material in a backend adapter. Reconcile unknown results before a retry; confirm a purchase only with the chosen integration's authoritative outcome. The included local replay exercises a future policy seam with fake approvals and receipt, and its result explicitly states `visaApiInvoked: false`. It does not turn this decision assistant into a payment integration.
