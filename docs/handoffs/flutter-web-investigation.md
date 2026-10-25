# Flutter web investigation — October 25, 2026

Track / task: C, investigate deployment of the existing Flutter app. This is a
compatibility foundation, not a completed web release. The static landing and
recorded demo in [draft #230](https://github.com/ViktorOsadsky/lifetwin/pull/230)
are a separate product surface; do not replace or publish that branch.

## Result and validation

Investigated `main` at `45e89e0` using Flutter 3.47.8 / Dart 3.13.7, in an isolated
checkout. The initial production build failed because `app/web/` was absent.
Generating a scaffold allowed compilation, but the real browser failed to load
the model with `Unsupported operation: _newZLibInflateFilter`.

This patch supplies a small LifeTwin web scaffold and replaces native-only gzip
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
  comparison. The live typed conversation displays the retry state because the
  local website origin is not allowed by production CORS. No microphone or
  real document was sent, and no live browser provider flow is claimed.

The final root-path bundle contains 463 files / 77,916,444 bytes; its largest
file is 7,284,602 bytes. The small scaffold removes Flutter placeholder icons. Neither
private env files nor source maps appeared in the inspected output. No iPhone,
Xcode settings, live backend settings, hosting account, DNS or deployment changed.

## Reproducible builds

Run from `app/`, after supplying only public configuration through the existing
gitignored `../.env.deploy/flutter.json` (`API_BASE_URL`, `SUPABASE_ANON_KEY`, and
optional `SUPABASE_GATEWAY_URL`). These values are visible to website visitors;
never use the server env file, provider keys, service-role key or Supabase PAT.

```sh
# Root-domain host (for example, a selected Cloudflare Pages domain).
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

## Hosting recommendation

**Owner choice after this investigation began: Vercel through MCP Bridge.** The
user selected the separate MCP Bridge connection. Root configured the official
Vercel MCP endpoint through its OAuth adapter; user authentication is underway,
and deployment remains pending root. The native Vercel plugin's disabled state
does not establish a restriction on this separately authorized connection. The
root-path release is prepared locally at `app/build/web/`; it has no demo seed and
uses only public API configuration.

After MCP Bridge authentication completes, inspect Vercel's actual deployment tools before choosing
an upload flow. For a static-artifact deployment, stage only the release files,
select the **Other** framework (`framework: null`), disable the build command,
and serve that artifact directory. Do not deploy the repository root as static
content. A Git-import flow instead needs an explicitly configured Flutter 3.47.8
build environment; a default Next.js/Node build will not build Flutter. A static
Vercel configuration for a directory containing the built `index.html` is:

```json
{
  "framework": null,
  "buildCommand": "",
  "outputDirectory": ".",
  "headers": [
    {"source": "/", "headers": [{"key": "Cache-Control", "value": "no-cache"}]},
    {"source": "/index.html", "headers": [{"key": "Cache-Control", "value": "no-cache"}]},
    {"source": "/flutter_bootstrap.js", "headers": [{"key": "Cache-Control", "value": "no-cache"}]},
    {"source": "/manifest.json", "headers": [{"key": "Cache-Control", "value": "no-cache"}]}
  ]
}
```

This configuration is a documented recipe, not a Vercel-validated deployment. The
current hash routing needs no catch-all rewrite; preserve filesystem assets and
return a real 404 for missing asset paths. Do not add proxy rewrites for the API.
After deployment, use the actual stable HTTPS Vercel origin for the separately
coordinated Supabase CORS change. Preview aliases each have distinct origins;
never allow `*.vercel.app` or all sites. [Vercel build configuration](https://vercel.com/docs/builds/configure-a-build),
[static project configuration](https://vercel.com/docs/project-configuration/vercel-json).

The following hosting alternatives were evaluated before the Vercel choice:

For a synthetic hackathon demo, **GitHub Pages is the first account option to
evaluate**: this repository is public and the existing GitHub account has write
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

## Blocking integration work before a useful public release

| Area | Observed boundary / next change |
| --- | --- |
| Live API | Production permits only exact HTTPS origins configured in `LIFETWIN_CORS_ORIGINS`; none is selected for this app. Read-only probes returned OPTIONS 204 and capabilities 200 **without** an allow-origin header for a prospective origin. Choose the real host first, then coordinate one exact-origin config update through the existing backend procedure. Keep JWT verification and public anon headers. No wildcard and no browser CORS bypass. |
| Config update | The backend provisioning helper **replaces the entire config**. Add the chosen origin to the complete protected configuration while retaining all provider keys/models; do not provision an origin-only file. It can take 60 seconds to refresh. See [credential procedure](../backend-credentials.md). For Pages the origin is `https://viktorosadsky.github.io` (no `/lifetwin/` path). |
| Health probe | `/health` returns before loading the origin config, so it currently sends no CORS headers even after an origin is set. A single `API_BASE_URL` skips the app's health race; use one URL. Coordinate a backend change before relying on cross-origin health probes/multiple candidates. |
| Documents | `ChannelDocumentOcr` / `PdfPicker` call iOS `lifetwin/documents`; there is no browser picker or Vision OCR. Add a bounded browser PDF picker that returns in-memory bytes to the existing per-document consent and `/api/documents/read` flow. Preserve page/size/password/error handling. Local OCR decline needs a supported browser alternative or an honest unavailable state. Apple Vision camera/photos do not work on the web. |
| Apple Health | The health plugin and custom workout channel have no web HealthKit implementation. Hide/disable the import with a clear explanation; typing/PDF remain alternatives. |
| Voice | `record` has a web backend and the WebSocket transport is browser-capable, but `flutter_pcm_sound` 3.3.3 declares only iOS/Android/macOS. Add a browser PCM player behind `PcmPlayer` or explicitly disable web voice with a complete text path. Validate mic HTTPS/permission denial, PCM format, user-gesture audio unlock, stop/replay/cancel and Cartesia token/WebSocket flow. No long-lived provider key in the browser. [Plugin source](https://github.com/chipweinberger/flutter_pcm_sound/blob/master/pubspec.yaml), [microphone security](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia). |
| Data | The iOS protected store falls back to **session memory**, as seen in browser logs. Refresh loses the guest choice/profile/history/look. Do not claim persistent or protected web storage. Keep session-only for the first demo, adjust copy, and review an opt-in browser persistence design separately. |
| Band | BLE plugin has a web implementation, but scanning/pairing needs secure-context/user-gesture/browser validation; Safari is not presumed supported. Native Files/Open-in channels have no web implementation. Missing-plugin file picks now show an explicit unavailable error, and clearing a nonexistent native inbox is harmless. A real browser picker is still absent. Existing labelled band demo remains separate from measured inputs. |
| Reminders | Actual seeded browser run logs `zonedSchedule() is not supported on the web` (caught). The app's permission path resolves iOS implementation only. Disable web scheduling and explain it; do not promise background reminders. A browser notification redesign is separate work. |
| Presentation | Landscape browser room crops the phone-composed character; responsive review is still needed. Test phone-sized Safari/Chrome and desktop, keyboard, accessibility and reduced motion. Icons/install/offline PWA behavior are not delivered by the minimal manifest. |

PR / merge state: reviewable investigation PR; no merge or production publication.
Contracts / model versions affected: none. Model assets are byte-unchanged.
Next dependency: agree the scope of the web demo, implement honest platform
capability gates and browser PDF input (plus PCM if voice is required), select a
hosting origin, then perform the exact-origin backend config update and a full
synthetic upload → confirm → forecast → experiment → quiz walkthrough in the
deployed browser. Existing track owners remain unchanged.
