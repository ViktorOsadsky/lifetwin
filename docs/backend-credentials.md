# Private backend credentials

Provider keys belong on the backend, including the deployed Supabase Edge API. The app receives only its API address
and any public gateway configuration. This helper prepares local configuration;
it does not deploy a service, validate account/model access, or send provider requests.

Run from the repository with the backend's installed Python environment:

```sh
uv run python scripts/server_env.py --env-file /path/to/your.env
```

The default private copy is `.env.deploy/server.env`, in a directory with mode
`0700`; the file has mode `0600` and is gitignored. The source remains unchanged.
Only names accepted by the backend's `Settings` are retained. Values are parsed
as dotenv data, validated without ambient environment overrides, and never printed.
Malformed settings, duplicate names, control characters and `${…}` interpolation
expressions fail without writing output. Shell commands in values are never run.

For future updates, reuse the protected copy and enter replacement values at a
terminal prompt that hides input:

```sh
uv run python scripts/server_env.py \
  --env-file .env.deploy/server.env \
  --output .env.deploy/next.env \
  --prompt-key ANTHROPIC_API_KEY \
  --prompt-key CLAUDE_MODEL
```

`--prompt` asks for the Muse, Anthropic and Cartesia credentials; blank input keeps
an imported value. `--replace` explicitly permits replacing an existing private
output. Source and output must always differ. Prompts require an interactive
terminal, so redirected input cannot accidentally echo credentials.

Load this file as dotenv data with the Bridge updater below. Never source it
in a shell, add it to Flutter assets/build defines, or pass its values in
command-line arguments. Local permissions do not protect copies in backups or an already
compromised account; delete obsolete private copies when no longer needed.

## Public Supabase app configuration

For the deployed LifeTwin Edge API, build Flutter with `API_BASE_URL` set to the
HTTPS `/functions/v1/lifetwin-api` function base and `SUPABASE_ANON_KEY` set to
that project's **public legacy anon JWT**. This key is public app configuration;
never substitute a provider key or service-role key.
`SUPABASE_GATEWAY_URL` optionally selects the exact function base when several
API candidates exist; otherwise matching bases come from `API_BASE_URL`.

The shared HTTP client adds `Authorization: Bearer …` and `apikey` only for the
configured HTTPS origin and LifeTwin function path, and refuses automatic
redirects for authenticated requests. Unrelated origins, sibling functions,
lookalike path prefixes and local Python endpoints receive no added credentials.
An empty anon key preserves existing local behavior. This supports the public
project gateway check, not per-user authentication or private health storage.


## Update or deploy through MCP Bridge

The existing saved `supabase` server must be connected in MCP Bridge, use its
shared app session, and have `project_ref=plpywefoeepfunptjujc` in its official
Supabase MCP URL. The updater refuses other projects and never changes the
connection, extracts its credential, or falls back to a direct session.

Apply the repository's `20261025082417_lifetwin_backend_credentials.sql` migration before
first provisioning. This helper deliberately does not create or migrate schema.
To replace the server configuration using a complete protected file:

```sh
uv run python scripts/supabase_bridge.py \
  --provision-env-file .env.deploy/next.env
```

Only the Edge API's 19 supported setting names can enter the provider-config RPC.
`CORS_ORIGINS` is accepted as an alias for `LIFETWIN_CORS_ORIGINS`; both use the
server's exact-origin validation. Supabase administrative tokens and unrelated
settings are discarded. This replaces the entire stored configuration, so retain
all desired keys and model choices in the file. The administrative SQL request
travels through Bridge stdin, never command arguments; the encrypted Vault stores
provider configuration only. The function can cache it for up to 60 seconds, and
managed Edge environment settings take precedence over Vault settings.

Deploy the current committed/reviewed function sources separately, or combine
`--deploy` with provisioning:

```sh
uv run python scripts/supabase_bridge.py --deploy
```

Deployment keeps JWT verification enabled, includes production TypeScript, JSON
assets and Deno configuration, and excludes tests, env files and the local
`deno.lock` (its format can be newer than the hosted bundler). Direct npm imports
remain pinned to exact versions in the source imports. The helper explicitly
selects `deno.json` as the import-map/configuration path on every deploy, avoiding
a stale absolute configuration path retained from a previous deployment. Both actions
inspect live tool schemas and withhold raw tool output. A successful command
means Bridge accepted the operation; verify remote health, provider readiness and
contracts afterward. A timeout or failure can follow an upstream mutation: the
helper never retries automatically. Reconcile the project state before retrying;
if a combined operation partially completed, its earlier update remains applied.
