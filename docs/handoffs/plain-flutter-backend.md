# Plain Flutter launch backend configuration

Track / task: C, follow up on the voice backend launcher fix (#217).

Result: plain `flutter run` now loads the optional local public JSON asset
`app/assets/config/backend.json` before creating API clients. Installed that
gitignored file in this checkout from the public-only deployment config. No keys
are committed. An explicit `API_BASE_URL` build define selects build configuration
instead; absent both asset and defines, localhost:8000 remains the development
default. Scoped gateway authentication and redirect handling are preserved.

PR / merge state: branch `codex/c-plain-flutter-backend`; its GitHub PR records
the final merge state. Integrated the latest main before final validation.

Contracts / models: unchanged. No backend deployment or provider settings changed.

Validation: live hosted health and synthetic onboarding start returned HTTP 200.
Plain `flutter run -d <booted simulator>` rebuilt and launched the iPhone 18 Pro.
Debugger object inspection confirmed its runtime API URL and nonempty public key,
while generated iOS defines contained neither backend URL nor key. Hot restart
after main integration succeeded. `flutter analyze` passed and all 1,559 Flutter
tests passed, including four new config/routing/override regression cases. Diff
checks passed; existing local iOS project/plist/Podfile changes were excluded.

Limits / next dependency: fresh checkouts must install their public config asset
or use build defines (documented in the iOS guide). Microphone capture, Cartesia
audio playback and physical-device acceptance remain separate checks. A complete
restart is needed after adding/changing the asset. No raw health data was queried
or printed during debugger inspection.
