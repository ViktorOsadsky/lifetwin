#!/usr/bin/env bash
# Run from any directory; load the hosted backend unless explicitly overridden.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir/app"

explicit_backend=false
previous_arg=''
for arg in "$@"; do
  if [[ $previous_arg == --dart-define && $arg == API_BASE_URL=* ]]; then
    explicit_backend=true
  fi
  case "$arg" in
    --dart-define=API_BASE_URL=*|--dart-define-from-file|--dart-define-from-file=*) explicit_backend=true ;;
  esac
  previous_arg="$arg"
done

if [[ $explicit_backend == true ]]; then
  exec flutter run "$@"
fi

config="$repo_dir/.env.deploy/flutter.json"
if [[ ! -f "$config" ]]; then
  echo 'Missing .env.deploy/flutter.json (public API_BASE_URL and SUPABASE_ANON_KEY).' >&2
  echo 'See docs/ios-testing.md, or pass --dart-define=API_BASE_URL=http://<server>:8000 for a local server.' >&2
  exit 1
fi

exec flutter run --dart-define-from-file="$config" "$@"
