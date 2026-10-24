# iOS testing

Device testing runs on Daniel's Mac, where the test iPhone (iPhone 13 Pro, iOS 26.6) is connected and signing is set up
(team `A5C3J42JT3`). Other Macs can use the simulator, which needs no signing.

## One-time setup

- On the phone: **Settings → Privacy & Security → Developer Mode → On**, then restart and confirm.
- On the Mac: Xcode 27.1, Flutter 3.47.8 and CocoaPods are installed. `flutter doctor` passes for Xcode (the Android warning
  doesn't matter).

## Run on the iPhone

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

## Your own iPhone

In Xcode open `app/ios/Runner.xcworkspace`, pick your own team under Runner → Signing & Capabilities (change the bundle ID if
asked), and don't commit that change.
