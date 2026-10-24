# Choose the correct Visa surface

This guide applies when the user chooses Visa developer/runtime integration. The Cal Hacks 13.0 starter pack says proprietary Visa APIs are not supplied for the event; no integration described below is an inferred event prerequisite. See [the event brief](cal-hacks-13.md) for project scope and the conflicting public rubric weights. Do not delay a discovery or shopping-decision prototype for optional runtime onboarding.

| Surface | Appropriate use | Access and evidence |
| --- | --- | --- |
| Visa Developer MCP | Discover products, references, schemas and integration guidance | `https://developer.visa.com/mcp`; read-only documentation; some capabilities may trigger OAuth. |
| VIC product MCP | Invoke the product tools enabled for an onboarded application | Official reference code uses a distinct runtime base URL, token manager and live tool discovery. |
| VIC direct API | Backend integration with the specific product API contract | Reference client applies X-Pay authentication and message-level encryption. |
| Local policy double | Test consent, budgets and UI states without network access | Never evidence of a Visa instruction or payment. |

The distinction is explicit in [Visa MCP overview](https://developer.visa.com/mcp-docs) and [Developer MCP setup](https://developer.visa.com/resources/mcp-get-started). The latter excludes runtime invocation and customer/merchant data; MLE is not required for its documentation service. Runtime security varies by product; do not carry that documentation-only exemption into VIC calls.

## Source-inspected implementation path

The official [visa/ai repository](https://github.com/visa/ai) was inspected locally at commit `1c544e5c1ed45c8c075ca57e9e76e7876e34fd42`. Read or clone that commit when implementing; do not rely on unpinned snippets that may change. The following source links are the evidence for this guide:

- [MCP client](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/packages/mcp-client/src/mcp-client.ts): `createVisaMcpClient()` appends `/mcp` to `VISA_MCP_BASE_URL`; connection uses Streamable HTTP and Bearer token obtained by `TokenManager`; `listTools()` returns live tool definitions.
- [Environment template](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/apps/vic-mcp-examples/.env.example): sandbox base is `https://sandbox.mcp.visa.com`; expected backend secrets include VIC/VTS keys, shared secrets, MLE certificate/private key/key ID, external identifiers, and user signing key. Values must come from the authorized onboarding process.
- [Token manager](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/packages/token-manager/src/index.ts): runtime authentication constructs signed/encrypted JWE credentials; use the maintained utility rather than handwritten auth guesses.
- [Initiate builder](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/apps/shared-utils/payload-builders/initiate-purchase-instruction.ts) and [mandate helper](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/apps/shared-utils/payload-helpers.ts): example instructions contain consumer/token references, assurance data and mandates. The demo defaults include merchant, amount, product and long expiry; replace them with actual user-approved values rather than treating sample defaults as authorization.
- [VIC API client](https://github.com/visa/ai/blob/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42/packages/api-client/src/clients/vic-client.ts): separate direct API path uses X-Pay and MLE; this is distinct from the runtime MCP Bearer transport.

The reference examples demonstrate `enroll-card`, `initiate-purchase-instruction`, `update-purchase-instruction`, `cancel-purchase-instruction`, `retrieve-payment-credentials`, and `confirm-transaction-events`. These names are **source-observed examples**, not a guaranteed current runtime tool catalog. Do not synthesize schemas around them. Also inspect [visa/vic-reference-agent](https://github.com/visa/vic-reference-agent) when evaluating an alternative starter; resolve and pin its current revision before using it.

## Bring up a real sandbox integration

1. Establish account/product/sandbox access and an exact permitted test scope. Keep signing keys and payment secrets server-side, with separate sandbox configuration.
2. Build the official packages according to their pinned READMEs and populate the environment template in the private backend. Check the final URL has one `/mcp` suffix.
3. Connect and call `listTools()`. Save sanitized tool names/input schemas and environment version as integration evidence. If connection or discovery fails, stop runtime assumptions at that point.
4. Map the immutable application cart to the discovered instruction schema. Translate integer minor units using the actual currency exponent; match merchant identity and every approved limit. Confirm token/consumer references belong to the approved user through the trusted backend.
5. Reserve a durable application request ID before invoking a mutating tool. Use documented product idempotency mechanisms if available; an application request ID is not automatically Visa idempotency support.
6. Interpret the actual product response, including pending events or required step-up. Credentials returned for checkout stay in a backend payment adapter. Do not echo them into an LLM tool result or browser logs.
7. Complete and confirm through the documented merchant/product flow. Retain sanitized instruction/correlation/receipt references and timing. Report a sandbox result as sandbox, even when all calls were real.

Do not replay an uncertain mutating call merely because the sample client can retry authentication errors. Inspect whether the original action took effect and reconcile by its references before reattempting. An unknown transport result is a state requiring recovery, not proof of failure.

## Access gaps observed on 2026-10-23

Public overview/setup pages were readable. The separately referenced `https://sandbox.mcp.visa.com/mcp/doc` was inaccessible to the web tool, and a direct HEAD request returned HTTP 404. This is method/path-specific, not evidence that runtime initialization is unavailable. Separate unauthenticated Streamable HTTP `POST initialize` probes to the documented `https://developer.visa.com/mcp` and `https://sandbox.mcp.visa.com/mcp` both returned HTTP 401. The Developer MCP response explicitly required a Bearer token and pointed to OAuth resource metadata. No tool invocation was attempted. A compatible client can proceed through the documented OAuth/onboarding flow when authorized credentials are available; these responses do not imply a service outage.

No VIC credentials, keys, certificates or runtime session were available. Consequently no live tool catalog/schema, successful sandbox tool call or merchant completion is claimed here.
