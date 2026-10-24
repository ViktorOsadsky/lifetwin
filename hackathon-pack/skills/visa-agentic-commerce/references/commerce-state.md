# Keep the commerce state trustworthy

The application's shopping state and Visa's product state are separate. Track research → proposed cart → approved immutable cart → instruction/checkout processing → authoritative outcome. Render the state the backend knows. A convincing UI should not turn `submitted` into `paid` on a timer.

`commerce_policy.py` is a reusable local guard for the application boundary. It validates cart structure, HMAC-binds approved terms, and reserves a request once. Its `record_outcome` accepts `confirmed`, `failed`, `cancelled`, or `unknown` from a trusted adapter; those are application states, not asserted Visa status strings.

The example manifest uses integer minor units with an explicit currency exponent. `contextDigest` is SHA256 of the backend's canonical context snapshot: selected variant, delivery method/slot, opaque destination reference, taxes/fees policy and any other term affecting the approved purchase. Store the snapshot separately. Recompute it from actual checkout terms before submission; accepting an arbitrary client-supplied hash without checking those terms defeats the guard. Keep raw address data in the authorized fulfillment system, outside the model-facing manifest.

Sign only after an authenticated person explicitly approves the displayed final details. The helper exposes a signing method for backend integration; never expose that method or its key as an LLM tool. Consent is scoped to a request and environment and expires within 15 minutes. A cart edit, fee increase, merchant substitution, variant swap, destination change or expired quote requires fresh approval.

The included dictionary ledger and lock are for a single-process local app/test. Shared instances must share a lock. Real multi-worker use requires a database transaction with a unique request key, durable states and recovery after restarts. Reservation happens before the network call. If transport fails after sending, mark `unknown`, keep the reservation, and reconcile rather than issuing a second purchase. No exactly-once external guarantee is claimed by this helper.

An instruction can be created without a completed merchant purchase. A cancellation request can be pending rather than complete. A confirmation needs an authoritative receipt/settlement signal from the chosen integration, not merely an opaque string supplied by the model. The helper checks that a sanitized reference is present; the trusted adapter must verify what that reference means.

## Demo and technical evidence

Prepare one short shopping story: uncertainty → source-backed recommendation → approved exact cart → integration action → outcome. Put an error branch beside it: a price or variant changes and the approval is invalidated. Demonstrate a timed-out submission and that recovery avoids a duplicate.

Label each segment precisely:

| Label | What it proves |
| --- | --- |
| Documentation MCP live | Official documentation retrieval/discovery only. |
| Simulated | Local test data and test doubles; no Visa tool invoked. |
| Cached sandbox response | A previously recorded real sandbox response with timestamp and sanitized correlation reference. |
| Sandbox live | Actual sandbox tool calls in the presented run; still not a production payment. |

For Cal Hacks 13.0, read [the event brief and source conflict](cal-hacks-13.md). The Visa starter pack explicitly says proprietary Visa APIs will not be provided; public APIs are optional, and projects may address any shopping stage. Its weights are innovation 25, technical execution 20, UX 20, commerce 20 and trust 15. The Hive prize card lists a $5,000 award and different UX/commerce weights (25/15); do not silently merge them or claim the conflict is resolved. A useful shopping experience can be complete without a Visa integration or payment. Never describe documentation retrieval or a fake receipt as payment execution.

For a project that stops at product discovery or comparison, demo the request, source-grounded comparison, constraint validation, explanation and handoff. Show one case where the system withholds a recommendation because a hard constraint cannot be verified. Do not add a fake paid state to that experience. For post-purchase workflows, distinguish an explanation or drafted action from an executed return, refund or cancellation.
