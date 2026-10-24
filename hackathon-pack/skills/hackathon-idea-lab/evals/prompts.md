# Forward-test prompts

Run these with only SKILL.md, the relevant reference, and any raw sources explicitly supplied. Do not show prior conclusions. Save the actual output, score against the criteria, and revise only failures observed.

## A — Favorite idea meets a direct competitor

User prompt: “I want an original AI repair-shopping assistant for Cal Hacks. A photo of my appliance label should identify a compatible part and help buy it. Is this a winning idea? Check the web; keep the project in shopping if a pivot is needed. I have two builders, 30 hours, no retailer credentials.”

Success: finds current exact competitors; distinguishes primary evidence from claims; preserves shopping; avoids asserting nobody built it; proposes a material change or declines the novelty claim; explicitly checks product/model/serial evidence and data access. Failure: only compares generic ChatGPT and Amazon or recommends a finance project without explaining the requested shopping constraint.

## B — Demand claim inflation

User prompt: “A government says recalled products cannot be resold and an app charges $49/month for recall monitoring. That proves people will pay for my $99/month recall finance agent, right? Tell me what is actually validated and design a test, without messaging anyone.”

Success: separates legal/problem evidence, vendor offer, observed payment/adoption, and product-specific WTP; designs an unrun artifact-based test; does not contact users. Failure: treats a competitor price or regulation as validated conversion.

## C — Prize stacking and inaccessible data

User prompt: “Pick between an ERP close agent and a live furniture delivery-fit shopper. I want the highest chance of a prize. Assume we can stack all sponsor prizes. We have no ERP access, one public catalog and 14 build hours. The sponsor page says live public data only; my friend says cached fixtures are fine.”

Success: challenges unsupported stacking, checks authoritative rubric, gates inaccessible ERP data, distinguishes cached/live/synthetic, and recommends a scope with one visible result plus fallback eligibility caveat. Failure: invents win probabilities or calls cached fixtures live.

## D — Founder insists on impossible novelty proof

User prompt: “Search until you can guarantee absolutely nobody has ever built a supported-lifetime shopping agent. I need that guarantee for the pitch.”

Success: clearly declines the guarantee, performs bounded useful current searches, states exact novelty limits, and offers defensible pitch wording. Failure: guarantees uniqueness or ends after only refusing.

## E — Existing chosen product

User prompt: “We have already committed to a student club reimbursement tool. Do a quick market pressure test and help narrow the scope; don't replace the idea.”

Success: reviews nearest substitutes and refines scope within the chosen product; limits research to the request; identifies measurable end-to-end task and unresolved assumptions. Failure: generates an unrelated six-idea tournament or demands extensive interviews before doing useful work.

## F — Composition and the system of record

User prompt: “Recall tools only detect products, so our new consignment payout ledger must be an original finance product. Evaluate this for a 3-person weekend team; keep a useful recall-store idea if warranted. Raw primary sources: https://help.simpleconsign.com/hc/en-us/articles/20858521545229-Consignment-Settings and https://help.consignorconnect.com/knowledge/how-to-refund-in-rose. No outreach.”

Success: compares the existing POS/consignor workflow as well as scanners, does not infer novelty from one component's missing feature, preserves authoritative existing financial records, and names an export/data gate and a concrete narrower hypothesis. Failure: claims the ledger is new based only on scanner feature pages or replaces existing records without an integration contract.
