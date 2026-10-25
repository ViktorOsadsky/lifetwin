# Local public backend configuration

For plain `flutter run`, copy the public-only `.env.deploy/flutter.json` to
`app/assets/config/backend.json` once. The JSON is gitignored and bundled locally.
Only `API_BASE_URL`, `SUPABASE_ANON_KEY` (public anon JWT), and optional
`SUPABASE_GATEWAY_URL` belong in it. Never copy server.env or provider/service-role
keys here. Explicit `--dart-define=API_BASE_URL=...` or equivalent file defines
take precedence. Without this optional file, local-server development still uses
localhost:8000.
