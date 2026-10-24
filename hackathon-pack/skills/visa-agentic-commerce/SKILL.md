---
name: visa-agentic-commerce
description: Build generative AI shopping experiences for Visa's Reimagining Shopping challenge, or integrate Visa Intelligent Commerce and MCP with verified schemas, consent, and accurate evidence. Covers discovery through post-purchase; a Visa payment API is optional for the event.
---

Start from the shopper's problem and the user's chosen product. Choose the shopping stage that solves it: discovery, decision-making, personalization, checkout, payments, loyalty/rewards, or post-purchase. Show what generative AI changes beyond adding a chat interface. A comparison, discovery, or returns assistant can be a complete event project without payment execution.

For Cal Hacks 13.0 planning or judging, read [the verified starter pack and source conflict](references/cal-hacks-13.md). The linked Visa starter pack says proprietary Visa APIs will not be provided, and external APIs/datasets are optional. Its rubric is innovation 25%, technical execution 20%, UX 20%, commerce impact 20%, trust 15%; the Hive prize card has different UX/commerce weights. Preserve that unresolved discrepancy when advising on scoring. Do not make Visa integration, payments, or a particular framework an invented entry requirement. The separate Hyphenate document is not Visa guidance.

For discovery and decision projects, keep source URLs, retrieval times, exact variants and uncertainty with product claims. Separate hard constraints from preferences; a missing attribute is unknown rather than a match. Compute prices/fees and eligibility deterministically after AI extraction. Recheck volatile facts before a handoff or action, and state unknown shipping, tax or availability. Show the recommendation's reason and one useful recovery when constraints cannot be met. Avoid collecting card or address data for a read-only shopping flow.

Read [integration boundaries](references/integration.md) only when the user chooses a Visa integration. Visa Developer MCP (`https://developer.visa.com/mcp`) reads developer knowledge; it cannot invoke payment APIs. Product-specific VIC runtime MCP is a separate connection with onboarding, credentials and product-specific schemas. Discover tools in the actual environment; do not invent a generic `pay` tool or copy a documentation MCP config as a checkout backend. Runtime onboarding is an optional integration path, not a dependency for the event project.

Read [the commerce state and demo guide](references/commerce-state.md) when implementing approval, checkout, cancellation, recovery or judging evidence. Specify what the agent may research or propose and what exact external action needs the user's authorization. For a purchase, show the final merchant/cart/amount and authenticate approval. For returns, cancellations or subscriptions, use the chosen provider's action semantics and the authorized scope; do not pretend the purchase helper implements those workflows. Use the local helper as an application policy seam, not a Visa payload:

```sh
python3 scripts/commerce_policy.py --demo
python3 scripts/commerce_policy.py --manifest /absolute/path/cart.json
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

The demo uses signed fixture consent and a fake receipt. It invokes no Visa API and cannot authorize real payments. The manifest validator checks the supplied cart; a valid cart is not user consent. See `assets/cart.example.json` for the exact application fields.

Bind approval to merchant ID, currency, total, currency exponent, items, cart version, fulfillment/variant/destination context digest, environment, request ID and short expiry. A changed material term invalidates that approval. Signing runs on a trusted backend only, after the actual user approves the displayed immutable cart. Store opaque destination/token references; keep PAN, CVV, payment credentials and keys outside model context and logs.

Use unique request reservations and reconcile unknown outcomes before retrying. The helper's lock protects one process/instance; a real multi-worker integration needs a transactional durable ledger. A purchase instruction, credential retrieval, or agent assertion is not itself proof of merchant payment.

Demonstrate the visible shopping improvement, meaningful AI, commerce value and trust behavior. Show an integration only when it is actually used. Label documentation-only, simulated, cached, and real sandbox segments. Report measured fixture results as fixture results; conversion, money saved, adoption and payment completion need their own evidence. The starter pack asks teams to explain the problem, beneficiary, AI contribution, working mechanism, importance and future direction by Sunday morning; it does not specify an exact submission deadline here.

This package inspected official Visa reference source at a pinned commit and tested the local policy with doubles. It did not authenticate to VIC, discover its live tools, enroll a card, or make a sandbox payment. Treat those as explicit integration gaps, not completed capabilities.
