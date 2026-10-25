"""Export/check the committed API schemas bundled with the Supabase function.

Reads only contract schemas, never request fixtures or provider configuration.
Run contracts/export.py --check first to verify these source schemas against the
Python request and response models. --check compares JSON without rewriting files.
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "supabase/functions/lifetwin-api/schemas.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the saved export is stale")
    args = parser.parse_args(argv)
    try:
        content = {
            path.name: json.loads(path.read_text())
            for path in sorted((ROOT / "contracts").glob("*.schema.json"))
        }
    except (OSError, ValueError):
        print("Cannot read valid source contract schemas.")
        return 1
    if not content:
        print("No source contract schemas found.")
        return 1
    if args.check:
        try:
            current = json.loads(DESTINATION.read_text())
        except (OSError, ValueError):
            print("Edge contract export is missing or invalid; regenerate it.")
            return 1
        if current != content:
            print("Edge contract export differs from source schemas; regenerate it.")
            return 1
        print(f"Edge contract export matches all {len(content)} source schemas.")
        return 0
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_text(json.dumps(content, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Exported {len(content)} API schemas; no requests or provider configuration included.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
