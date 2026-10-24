#!/bin/bash
# Acts on the simulator for the qa_* integration tests, which print "QA-ACTION <verb> [name]".
#   integration_test/support/qa_watch.sh <test output log> <screenshot dir> &
#   flutter test integration_test/qa_voice_test.dart ... > <test output log> 2>&1
# Verbs: background (Home, back after 4 s), settings (screenshot the Settings app, then
# back), shot <name> (screenshot), stopserver / startserver (the backend on QA_PORT).
LOG=$1; DIR=$2
SIM=${QA_SIM:-booted}; APP=${QA_APP:-com.danielqi.lifesim}; PORT=${QA_PORT:-8050}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "$DIR"
tail -n0 -F "$LOG" 2>/dev/null | while read -r line; do
  case "$line" in
    *"QA-ACTION background"*)
      sleep 0.5; xcrun simctl launch "$SIM" com.apple.Preferences >/dev/null; sleep 4
      xcrun simctl launch "$SIM" "$APP" >/dev/null; echo "did background" ;;
    *"QA-ACTION settings"*)
      sleep 2.5; xcrun simctl io "$SIM" screenshot "$DIR/settings-app.png" >/dev/null 2>&1
      xcrun simctl launch "$SIM" "$APP" >/dev/null; echo "did settings" ;;
    *"QA-ACTION stopserver"*)
      kill $(lsof -tiTCP:"$PORT" -sTCP:LISTEN) 2>/dev/null; echo "did stopserver" ;;
    *"QA-ACTION startserver"*)
      (cd "$REPO" && nohup uv run uvicorn lifetwin.app:app --host 0.0.0.0 --port "$PORT" >/dev/null 2>&1 &)
      for _ in $(seq 1 40); do curl -sf "localhost:$PORT/health" >/dev/null && break; sleep 0.5; done
      echo "did startserver" ;;
    *"QA-ACTION shot "*)
      name=$(echo "$line" | sed 's/.*QA-ACTION shot //' | tr -cd 'A-Za-z0-9_.-')
      xcrun simctl io "$SIM" screenshot "$DIR/$name.png" >/dev/null 2>&1; echo "shot $name" ;;
  esac
done
