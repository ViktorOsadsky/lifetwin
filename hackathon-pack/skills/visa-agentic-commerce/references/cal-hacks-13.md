# Visa x Cal Hacks 13.0: verified brief

Use this reference for event project scope, demo planning and judging. It records sources observed on 2026-10-23; verify changes before submission. General VIC implementation is a separate, optional path in [integration.md](integration.md).

## Identity and provenance

The [Hive resources page](https://hive.hackberkeley.org/resources), in its Sponsor Starter Packs tab, links its Visa card to the [Visa x CAL Hacks 13.0 Hacker Starter Pack](https://docs.google.com/document/d/1Lgtd0f8mHZy_nWabtz751AkSW5Oj-z1XMhzAwddtfOA/edit?tab=t.0#heading=h.bo9rj437g1tj). The retrieved document title and content match the Visa challenge. Hive lists [the document beginning `1u4iN8R97...`](https://docs.google.com/document/d/1u4iN8R97ILY3kfHTPKC82zdutHrGx4ze5eCAP-J92w4/edit?usp=sharing) under Hyphenate; do not apply its finance resources, access promises or judging rules to Visa. The inspected Other Resources tab was empty; this is not evidence of missing runtime services or a promise that resources will never be added.

## What the Visa starter pack establishes

The challenge is to use generative AI to make shopping more intuitive, personalized and effortless, while supporting secure, trusted experiences. Teams may work anywhere in the journey:

| Area | Examples from the brief, summarized |
| --- | --- |
| Discovery | Conversational/voice search, personalized discovery, social recommendations, gifts |
| Decision-making | Comparison, buying guides, sustainability, budgets, review synthesis |
| Personalization | Storefronts, recommendations, companions, bundles, lifestyle fit |
| Checkout | Cart optimization, subscriptions, checkout assistance, savings, purchase planning |
| Payments | Spending/budget assistance, financial wellness, fraud awareness, payment preferences |
| Loyalty and rewards | Rewards advice/optimization/redemption, gamification, merchant engagement |
| Post-purchase | Tracking, support, returns, engagement, product assistance |

The brief says a chatbot alone is insufficient. Explain why the task needs AI, what it enables and how it improves the experience. Consider privacy, transparency, security, responsible AI, data protection and consent.

The starter pack states: “Visa will not be providing proprietary Visa APIs for this challenge.” It welcomes public catalogs, retail/e-commerce data, geolocation, financial education, comparison, sustainability and open-source commerce tools. These are optional choices. Suggested frameworks, model providers, backend services and databases are suggestions, not eligibility requirements. The brief does not establish a requirement for a Visa product, API, MCP, Visa-card enrollment or transaction.

## Rubric conflict: preserve both sources

| Criterion | Visa starter pack | Hive prize card |
| --- | ---: | ---: |
| Innovation | 25% | 25% |
| Technical execution | 20% | 20% |
| User experience | 20% | 25% |
| Commerce impact | 20% | 15% |
| Trust and responsibility | 15% | 15% |

The [Hive prize page](https://hive.hackberkeley.org/prizes) lists a $5,000 Visa award. The starter pack does not state that amount. These public artifacts disagree on UX and commerce weights; neither captured artifact establishes precedence or a later revision. Use the starter pack provisionally when building against its detailed guidance, disclose the discrepancy in scoring advice, and ask the sponsor which weights govern before claiming a final score or submission strategy. Both favor a usable product, working AI, visible commerce value and trustworthy behavior.

For each criterion, produce something observable: a distinct shopper decision improved by AI; a working end-to-end path; a short, understandable interaction; a measured or clearly proposed commerce metric; and one demonstrated trust behavior. Fixture correctness is not measured conversion or realized savings.

## Build and demo without sponsor runtime access

Preserve the user's category and choose a narrow shopping problem. Translate the shopper's request into editable constraints; retrieve product facts with provenance; use AI to explain tradeoffs grounded in those facts; validate hard constraints and money with application code; give a useful next step. A merchant link can end a read-only prototype without asserting the merchant accepted an order. A post-purchase assistant can propose a return without claiming it submitted one.

Prioritize one successful decision and a realistic failure: stale price, unavailable variant, insufficient evidence, conflicting preference or missing delivery estimate. Show the shopper how to resolve it. Avoid forcing a checkout sequence onto discovery, personalization or support projects.

Before Sunday morning, prepare answers for the brief's six demo topics: the challenge, beneficiary, AI improvement, working mechanism, importance and next step. The supplied text does not establish exact Sunday timing, submission format, prize stacking, or extra sponsor integration conditions. Confirm those from the current event rules if needed.

If the user specifically chooses VIC, follow the integration guide and record the access gap accurately. Missing credentials do not require abandoning the shopper experience or claiming an unperformed payment.
