# Voice backend launch fix

Track / task: C, restore backend configuration for voice onboarding.

Result: the inspected iOS build had no `API_BASE_URL` or `SUPABASE_ANON_KEY`
defines, no local server was listening on port 8000, and the ignored hosted
configuration was absent. Restored `.env.deploy/flutter.json` locally using
MCP Bridge's project-scoped public-key lookup. No keys are committed.

`bash scripts/run-app.sh` loads that configuration by default, fails with
instructions when it is absent, and preserves explicit local-server or custom
file overrides. `scripts/ios-device.sh` delegates to the same launcher.
Updated the voice and iOS setup guides with hosted and local workflows.

PR / merge state: branch `codex/c-voice-backend-launch`; the associated GitHub
PR records checks and merge status.

Contracts / models: unchanged. No Flutter application behavior or provider
configuration changes.

Validation: shell syntax and diff checks passed. Seven isolated mocked launch
checks covered missing config, hosted defaults, equals/separate argument forms
for URL/file overrides, and physical-device delegation. The real hosted health
and onboarding start endpoints returned HTTP 200. A real voice-token request
returned HTTP 200 and a 300-second token, discarded without printing it.
Rebuilt and launched on the booted iPhone 18 Pro simulator, verifying that the
generated build defines include the hosted URL and public gateway key.
All 26 existing tests in `backend_http_client_test.dart`,
`http_conversation_guide_test.dart`, and `voice_token_test.dart` passed.

Limits / next dependency: live microphone capture, Cartesia audio playback and
physical-device acceptance remain unverified. Stop and relaunch through the
helper after changing build defines; hot reload is insufficient. Unrelated
local iOS signing/plist/Podfile changes were excluded from this fix.
