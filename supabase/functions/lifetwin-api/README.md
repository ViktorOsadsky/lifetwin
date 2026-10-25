# LifeTwin Supabase backend

The hosted API runs TypeScript/Deno on Supabase Edge Functions, as selected by
the owner on October 25. Python/FastAPI remains the local reference
implementation. The Flutter app retains its on-device Cox model. Keys stay on
the backend.

Function base:
`https://plpywefoeepfunptjujc.supabase.co/functions/v1/lifetwin-api`. Append
existing API paths such as `/api/onboarding/turn` or `/api/voice/token`.
Supabase verifies the public project's legacy anon JWT at ingress. This does not
create user accounts or private user storage. The app supplies its public anon
key, never the service-role key or provider credentials.

## Provision and deploy through MCP Bridge

Use the existing saved `supabase` server with
`project_ref=plpywefoeepfunptjujc`, a credential with project access, and its
shared session connected. The helper refuses a differently scoped endpoint.
Apply `supabase/migrations/20261025082417_lifetwin_backend_credentials.sql`
using Bridge's `apply_migration` before the first deployment. No provider values
are in that file.

```sh
uv run python scripts/server_env.py --env-file /path/to/private.env
uv run python scripts/supabase_bridge.py --provision-env-file .env.deploy/server.env
uv run python scripts/supabase_bridge.py --deploy
```

Provisioning replaces the complete configuration. Keys are parsed as data and
sent to the owner-only Vault setter over tool stdin; raw tool results are
withheld. The Edge Function retrieves only the LifeTwin configuration through a
service-role-only RPC, caching it for at most 60 seconds. Managed Edge secrets
override Vault settings. The service-role key is provided by Supabase at
runtime. See
[credential entry and updates](../../../docs/backend-credentials.md).

Apply the later `lifetwin_pdf_provider_config` migration before configuring PDF
options, and `lifetwin_conversation_provider_config` before setting
`CONVERSATION_PROVIDER`. Set that value to `claude` for conversation turns;
`PERSONALIZE_PROVIDER=muse` keeps Ideas, coach and recommendations on Muse.
Claude still requires the person's provider consent. `local` disables conversation
AI; `muse` is available as an explicit override. Changing this setting does not
grant consent or change the PDF provider.

The database stores encrypted provider configuration and anonymous aggregate
provider-call counters only. It stores no profiles, documents, transcripts or
audio. Anonymous and authenticated app roles cannot invoke the config getter,
setter or budget RPC. Each project allows at most 200 LLM attempts and 100 voice
token attempts per UTC day, and 20 per minute per kind; attempted/failed calls
consume budget. An unavailable budget store prevents provider calls.

## API behavior and limits

The hosted implementation includes guided onboarding, confirmation, Health
import, daily/weekly/quick check-ins, changing saved answers, reviewed quizzes,
curated advisor plans, recommendations, conservative general coach plans,
parser-only OCR text extraction, consent-gated Claude PDF reading, and Cartesia
token minting. Outside-AI intake extraction requires consent for the selected
provider, proposes an exact quoted span, and passes the deterministic parser
before a confirmation. It never writes confirmed health inputs on the provider's
authority.

Requests and responses use the existing 29 JSON schemas. Ordinary bodies are
limited to 32 KiB and document bodies to 384 KiB, with a five-second body
deadline. Whole-PDF JSON is capped at 14,000,000 bytes (10 MiB decoded, 20
pages) with a ten-second upload deadline and only one PDF request per isolate.
Claude PDF findings are checked against PDF text and the local parser; scans
carry low confidence and an unverified-quote limitation. Provider calls have
explicit deadlines, fixed hosts and bounded responses. An isolate also limits
concurrency to 16 and traffic to 120 requests per minute. These isolate limits
supplement the shared provider budgets; they are not a per-person identity or a
distributed general API rate limiter. No request payloads, provider responses or
credentials are logged by this code. Browser CORS requires an exact HTTPS origin
in `LIFETWIN_CORS_ORIGINS`; native Flutter needs no CORS.

This is a bounded port, not full FastAPI parity: advanced transcript parsing,
proxy estimates, optional habit probes, completion recommendations and optional
LLM wording remain reference-server features. OCR text extraction uses the local
parser without AI; whole-PDF reading uses Claude only after consent for that
document. The hosted coach gives reviewed general plans without the Python
planner's individualized progression or memory callbacks. Web research is
unconfigured. `/api/predict`, `/api/compare` and `/api/sensitivity` return
honest 501 responses; no survival model was ported to Deno and no estimates are
fabricated.

## App and checks

Build with `API_BASE_URL` equal to the function base and `SUPABASE_ANON_KEY`
equal to the public legacy anon JWT. The local `.env.deploy/flutter.json`
contains these public defines. From `app/`, use:

```sh
flutter run --dart-define-from-file=../.env.deploy/flutter.json
```

For plain `flutter run`, copy this **public-only** JSON file to
`app/assets/config/backend.json` once. Startup loads that gitignored asset
before creating API clients. Explicit `API_BASE_URL` build defines override it.
Never bundle private server configuration, provider keys or service-role
credentials.

```sh
cd supabase/functions/lifetwin-api
deno check index.ts
deno test --allow-read --allow-env '*.test.ts'
```

Run the deployed smoke checker with the public anon key in its environment:

```sh
uv run python scripts/deployment_smoke.py --base-url https://plpywefoeepfunptjujc.supabase.co/functions/v1/lifetwin-api --allow-deferred-prediction --require-providers --verify-voice
```

`--verify-voice` makes a real token request and discards the result. It does not
establish audio playback or physical-device acceptance. Default smoke checks use
synthetic data and make no provider calls.

Source references: [Edge runtime](https://supabase.com/docs/guides/functions),
[Vault](https://supabase.com/docs/guides/database/vault),
[function secrets](https://supabase.com/docs/guides/functions/secrets), and
[database function privileges](https://supabase.com/docs/guides/database/functions).
