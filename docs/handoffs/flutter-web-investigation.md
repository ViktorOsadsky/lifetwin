# Flutter web deployment handoff — October 25, 2026

Track / task: C, Flutter web compatibility and delivery. The owner-authorized
release is live at [lifetwin-tau.vercel.app](https://lifetwin-tau.vercel.app).
Browser feature parity remains incomplete; the boundaries below still apply.
The static landing and recorded demo in [draft #230](https://github.com/ViktorOsadsky/lifetwin/pull/230)
are a separate product surface; do not replace or publish that branch.

## Result and validation

Investigated `main` at `45e89e0` using Flutter 3.47.8 / Dart 3.13.7, in an isolated
checkout. The initial production build failed because `app/web/` was absent.
Generating a scaffold allowed compilation, but the real browser failed to load
the model with `Unsupported operation: _newZLibInflateFilter`.

The merged foundation supplies a small LifeTwin web scaffold and replaces native-only gzip
decoding in the app and its vendored model loader with `archive`'s portable
`GZipDecoder`. `archive` 4.5.2 was already locked transitively; it is now an explicit
dependency. Model artifacts, coefficients, support rules and output schemas are
unchanged. The vendored Flutter loader intentionally differs from the original
`model_handoff/` loader in this platform adapter only. BLE's Android MTU selection
uses Flutter platform detection rather than `dart:io.Platform`; this does not
establish browser Bluetooth support.

Checks actually run:

- Production JavaScript release builds: normal entry and existing `DEMO_SEED=1`.
- A release with `/lifetwin/` base href and local renderer resources (command below).
- `flutter analyze --no-pub`: clean.
- 26 tests: `test/demo/demo_seed_test.dart`, `test/backend_http_client_test.dart`.
- 92 tests: `test/twin/health_score_test.dart`,
  `test/twin/critical_score_lifespan_test.dart`, `test/twin/rough_missing_test.dart`,
  `test/band/band_ble_test.dart` (fake radio, not physical Bluetooth).
- 36 tests: native-inbox unavailable/deletion regressions and the existing
  band-file intake suite.
- 2 tests in `app/packages/lifetwin_on_device`: actual asset loading, Cox output,
  neural golden outputs and annual projection consistency, all passed.
- Browser release smoke: guest entry, guest continuation, typing/AI-consent
  screens; synthetic Rosa home renders the actual model's +0.61 score and survey
  comparison. During the initial localhost investigation, the typed conversation
  displayed retry because that origin was not allowed by production CORS. The
  selected deployed origin is now allowed, as verified below. No microphone or
  real document was sent during this investigation.

The final root-path bundle contains 463 files / 77,916,444 bytes; its largest
file is 7,284,602 bytes. The small scaffold removes Flutter placeholder icons. Neither
private env files nor source maps appeared in the inspected output. The deployed
archive contains 462 release files: the generated `.last_build_id` was excluded.
The initial investigation changed no live services; the subsequent authorized
Vercel deployment and exact-origin Supabase update are recorded below. No iPhone,
Xcode settings or DNS changes are part of this delivery.

## Reproducible builds

Run from `app/`, after supplying only public configuration through the existing
gitignored `../.env.deploy/flutter.json` (`API_BASE_URL`, `SUPABASE_ANON_KEY`, and
optional `SUPABASE_GATEWAY_URL`). These values are visible to website visitors;
never use the server env file, provider keys, service-role key or Supabase PAT.

```sh
# Current Vercel release at https://lifetwin-tau.vercel.app/ (root base path).
flutter build web --release --no-web-resources-cdn \
  --dart-define-from-file=../.env.deploy/flutter.json

# GitHub project-site path: https://viktorosadsky.github.io/lifetwin/
flutter build web --release --no-web-resources-cdn --base-href=/lifetwin/ \
  --dart-define-from-file=../.env.deploy/flutter.json
```

Upload **only `app/build/web/`**, never the repo or `.env.deploy/`. The investigation
also used `--output=build/lifetwin` to test that exact subpath on localhost. The
existing opt-in `--dart-define=DEMO_SEED=1` is useful for a synthetic walkthrough;
it is not a live onboarding acceptance test. Do not silently turn it on for a
general release. Use the JavaScript build first; Wasm dry-run success alone does
not validate Wasm/browser compatibility or its additional hosting requirements.

Keep the default hash URL strategy for the first release; the app currently uses
in-app routes rather than public deep links. A future path URL strategy requires
host rewrites. Serve HTML/bootstrap/manifests with revalidation to avoid stale
releases; give long cache lifetimes only to versioned assets. Test a fresh browser
and a reload after every deployment. [Flutter deployment guidance](https://docs.flutter.dev/deployment/web),
[base paths and URL strategy](https://docs.flutter.dev/ui/navigation/url-strategies).

## Verified Vercel deployment

The user selected **Vercel through the separate MCP Bridge connection**. OAuth
completed and root used the authenticated Vercel MCP tools to upload the compiled
release and create the deployment. The native plugin's disabled state did not
establish a restriction on this independently authorized connection.

| Deployment evidence | Result |
| --- | --- |
| Public canonical URL | [https://lifetwin-tau.vercel.app](https://lifetwin-tau.vercel.app), HTTP 200 |
| Team alias | `https://lifetwin-flareyuns-projects.vercel.app`, protected HTTP 302; it is not the public demo link |
| Deployment | `dpl_2SYmv5ESWTi6T3Rz4DMPtgURTQcF`, state `READY` |
| Project / team | `prj_PPSIQxTSjp8ar5gGvxb50tz0DoJ2` / `team_xZNZsGb4I5XtLwgChXWdOVUx` |
| Source | [#236](https://github.com/ViktorOsadsky/lifetwin/pull/236), merged at `a6bfa44fea1e8a04ca9aba5adeb9d2959f71e2a9`; compiled app code matches the tested `0fefb9d` source |
| Build mode | Flutter 3.47.8, release JavaScript, `/` base path, `--no-web-resources-cdn`, no `DEMO_SEED` |
| Public app config | Existing Supabase API URL and anon JWT only; provider/service-role/admin credentials remain outside the release |
| Supabase origin | Only `https://lifetwin-tau.vercel.app` added to `LIFETWIN_CORS_ORIGINS`, retaining existing provider keys and model configuration |
| CORS probes | OPTIONS 204 and capabilities 200 return `Access-Control-Allow-Origin: https://lifetwin-tau.vercel.app` |
| Served-byte checks | Index, bootstrap, `main.dart.js` and model reference exactly match the tested release files |
| Browser acceptance | Public guest entry, typing choice, AI opt-out and the live text/memory prompt verified; a synthetic reply was sent, with its resulting turn still pending verification at this checkpoint |

The canonical alias was already public; **no deployment protection or access
settings were changed**. The team alias remains protected. Preview aliases have
different origins and are not automatically authorized by Supabase. Do not add
`*.vercel.app`, wildcard CORS or an API proxy to bypass origin configuration.

The actual MCP deployment path avoided uploading hundreds of individual assets:
462 release files were archived (46,592,212 bytes, SHA-256
`dc2e7e787b8bc02586244c47e4338993d28b5df5a294a8bca7f70b21b566f147`),
split into eight ordered parts of at most 6 MB, then uploaded with `upload_file`.
`create_deployment` used **Other** (`framework: null`), an empty `installCommand`,
`outputDirectory: public`, and this unpack-only build command:

```sh
mkdir -p public && cat release.part-* | tar -xz -C public
```

The archive parts contain only compiled files; they are not committed. This
Vercel build does not run Flutter or install app dependencies: Flutter compilation
happened locally before packaging. Retain the same ordered, zero-padded part
names and verify the archive hash when repeating that procedure. Never archive
the repository or private env directory. A future Git-import build needs its own
pinned Flutter environment and public build defines; default Node/Next.js build
settings are insufficient.

The current hash routing needs no catch-all rewrite; preserve filesystem asset
paths. The deployment introduces no serverless Vercel API, analytics, persistence,
OAuth app accounts or native feature adapters. Future cache and routing changes
should follow [Vercel build configuration](https://vercel.com/docs/builds/configure-a-build)
and [static project configuration](https://vercel.com/docs/project-configuration/vercel-json),
then be verified against a fresh browser and a reload.

## Earlier hosting alternatives

Before the Vercel choice, **GitHub Pages was evaluated** as an existing-account
option: this repository is public and the existing GitHub account has write
access. Its Pages API returned 404, so Pages is not established as configured and
repository Pages settings/permissions still need checking. Once authorized,
enable Actions publishing and upload the build artifact using `configure-pages`,
`upload-pages-artifact`, `deploy-pages` with the protected `github-pages`
environment and `pages: write` / `id-token: write` permissions. Build Flutter before
artifact upload; do not run Jekyll. Preserve `/lifetwin/` unless the selected URL
differs. This is a demo recommendation, not a commercial SaaS hosting decision;
GitHub publishes usage restrictions and a 1 GB site limit.
[Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages),
[Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).

**Cloudflare Pages** is a straightforward alternative if the owner connects an
account: build locally/CI, then Direct Upload the static output to a chosen Pages
project. The measured bundle fits Wrangler's 20,000-file / 25 MiB-per-file limits.
No Cloudflare account, project or credential was inspected or created. Choose
Direct Upload versus Git integration deliberately; a Direct Upload project cannot
later switch to Git integration. Firebase Hosting is another supported static-host
option, but no Firebase access is established and it adds another account setup.
[Cloudflare Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/),
[Firebase Hosting](https://firebase.google.com/docs/hosting/).

## Remaining browser integration work

| Area | Observed boundary / next change |
| --- | --- |
| Live API | The selected canonical origin is configured and CORS probes pass. Keep JWT verification, public anon headers and the exact-origin allowlist; additional aliases need a separately coordinated update. |
| Config update | The backend provisioning helper **replaces the entire config**. Add the chosen origin to the complete protected configuration while retaining all provider keys/models; do not provision an origin-only file. It can take 60 seconds to refresh. See [credential procedure](../backend-credentials.md). The current allowed origin is `https://lifetwin-tau.vercel.app` (no path). |
| Health probe | `/health` returns before loading the origin config, so it currently sends no CORS headers even after an origin is set. A single `API_BASE_URL` skips the app's health race; use one URL. Coordinate a backend change before relying on cross-origin health probes/multiple candidates. |
| Documents | `ChannelDocumentOcr` / `PdfPicker` call iOS `lifetwin/documents`; there is no browser picker or Vision OCR. Add a bounded browser PDF picker that returns in-memory bytes to the existing per-document consent and `/api/documents/read` flow. Preserve page/size/password/error handling. Local OCR decline needs a supported browser alternative or an honest unavailable state. Apple Vision camera/photos do not work on the web. |
| Apple Health | The health plugin and custom workout channel have no web HealthKit implementation. Hide/disable the import with a clear explanation; typing/PDF remain alternatives. |
| Voice | `record` has a web backend and the WebSocket transport is browser-capable, but `flutter_pcm_sound` 3.3.3 declares only iOS/Android/macOS. Add a browser PCM player behind `PcmPlayer` or explicitly disable web voice with a complete text path. Validate mic HTTPS/permission denial, PCM format, user-gesture audio unlock, stop/replay/cancel and Cartesia token/WebSocket flow. No long-lived provider key in the browser. [Plugin source](https://github.com/chipweinberger/flutter_pcm_sound/blob/master/pubspec.yaml), [microphone security](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia). |
| Data | The iOS protected store falls back to **session memory**, as seen in browser logs. Refresh loses the guest choice/profile/history/look. Do not claim persistent or protected web storage. Keep session-only for the first demo, adjust copy, and review an opt-in browser persistence design separately. |
| Band | BLE plugin has a web implementation, but scanning/pairing needs secure-context/user-gesture/browser validation; Safari is not presumed supported. Native Files/Open-in channels have no web implementation. Missing-plugin file picks now show an explicit unavailable error, and clearing a nonexistent native inbox is harmless. A real browser picker is still absent. Existing labelled band demo remains separate from measured inputs. |
| Reminders | Actual seeded browser run logs `zonedSchedule() is not supported on the web` (caught). The app's permission path resolves iOS implementation only. Disable web scheduling and explain it; do not promise background reminders. A browser notification redesign is separate work. |
| Presentation | Landscape browser room crops the phone-composed character; responsive review is still needed. Test phone-sized Safari/Chrome and desktop, keyboard, accessibility and reduced motion. Icons/install/offline PWA behavior are not delivered by the minimal manifest. |

PR / merge state: foundation [#236](https://github.com/ViktorOsadsky/lifetwin/pull/236)
merged at `a6bfa44`; the deployment is `READY`. This deployment-record update is a
separate documentation PR pending merge.
Contracts / model versions affected: none. Model assets are byte-unchanged.
Next dependency: finish live typed-conversation acceptance, implement honest
platform capability gates and browser PDF input (plus PCM if voice is required),
then complete a synthetic upload → confirm → forecast → experiment → quiz
walkthrough on the canonical URL. Existing track owners remain unchanged.
