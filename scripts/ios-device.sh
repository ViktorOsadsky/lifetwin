#!/usr/bin/env bash
# Run the Flutter app on a connected iPhone (hot reload: r, restart: R, quit: q).
#
#   scripts/ios-device.sh [extra flutter run args, e.g. --release --dart-define=API_BASE_URL=http://<mac-ip>:8000]
#
# Env: DEVICE (UDID; default: first connected physical iPhone)
set -euo pipefail
cd "$(dirname "$0")/../app"

if [[ -z ${DEVICE:-} ]]; then
  json=$(mktemp)
  xcrun devicectl list devices --quiet --json-output "$json" >/dev/null 2>&1 || true
  DEVICE=$(python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d["hardwareProperties"], d["connectionProperties"]
    if hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical" and conn.get("tunnelState") == "connected":
        print(hw["udid"]); break' "$json")
  rm -f "$json"
fi
[[ -n ${DEVICE:-} ]] || { echo "No connected iPhone found (xcrun devicectl list devices)." >&2; exit 1; }

info=$(xcrun devicectl device info details --device "$DEVICE" 2>&1 || true)
if [[ $info == *"Developer Mode Status: Disabled"* ]]; then
  echo "Developer Mode is off on $DEVICE: Settings > Privacy & Security > Developer Mode, then restart." >&2
  exit 1
fi

exec bash ../scripts/run-app.sh -d "$DEVICE" "$@"
