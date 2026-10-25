# iOS testing

The Flutter app and device helpers are implemented. Product requirements are in [MASTER_PLAN.md](../MASTER_PLAN.md); stack decisions are in [tech-stack.md](tech-stack.md).

## Hosted backend (default helper workflow)

From the repository root:

```sh
bash scripts/run-app.sh -d "iPhone 18 Pro"  # booted simulator
scripts/ios-device.sh                     # connected physical iPhone
```

Both commands load `.env.deploy/flutter.json`. This ignored local file must contain
the deployed `API_BASE_URL` and the project's **public legacy anon JWT** as
`SUPABASE_ANON_KEY`; see the [deployment guide](../supabase/functions/lifetwin-api/README.md).
On a fresh checkout, create the file with those two JSON string properties using
the function base in that guide and the public anon key from the LifeTwin
Supabase project's API settings. Never put provider or service-role keys in it.
The helper stops with instructions if the file is missing.

A plain `flutter run` does not load this file: without build defines the app
defaults to `http://localhost:8000`. A missing local server then causes the
“I can't reach LifeTwin” message before any voice conversation can start.
Changing build defines requires stopping and relaunching the app; hot reload
does not update them.

Device testing runs on Daniel's Mac, where the test iPhone (iPhone 13 Pro, iOS 26.6) is connected and signing is set up
(team `A5C3J42JT3`). Other Macs can use the simulator, which needs no signing.

## One-time setup

- On the phone: **Settings → Privacy & Security → Developer Mode → On**, then restart and confirm.
- On the Mac: Xcode 27.1, Flutter 3.47.8 and CocoaPods are installed. `flutter doctor` passes for Xcode (the Android warning
  doesn't matter).

## Local server on the iPhone

```sh
python3 contracts/stub_server.py &      # or point at the deployed API
scripts/ios-device.sh --dart-define=API_BASE_URL=http://Overpriced-Hardware.local:8000
```

In the app, read the base URL with:

```dart
const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
```

- `scripts/ios-device.sh` finds the connected iPhone, stops with instructions if Developer Mode is off, then runs `flutter run`
  (hot reload `r`, restart `R`, quit `q`). Extra arguments go straight to `flutter run` (e.g. `--release`).
- `localhost` on the phone means the phone itself. Use the Mac's `.local` name (above) or the deployed HTTPS API.
- The app's `Info.plist` allows plain HTTP on the local network (`NSAllowsLocalNetworking`) and includes the Local Network
  prompt text. Accept that prompt on first launch.

## Simulator

```sh
cd app && flutter run -d "iPhone 17"    # localhost:8000 works directly here
```

This local-server command requires a server listening on the Mac's port 8000.
Use the hosted helper above when no local server is running. An explicit
`--dart-define=API_BASE_URL=…` or `--dart-define-from-file=…` passed to either
helper takes precedence over the default hosted configuration.

## Your own iPhone

In Xcode open `app/ios/Runner.xcworkspace`, pick your own team under Runner → Signing & Capabilities (change the bundle ID if
asked), and don't commit that change.
