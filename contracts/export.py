"""Export or check the schemas generated from server request/response models."""

import argparse
import json
from pathlib import Path

from schema_registry import SCHEMAS

ROOT = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="Fail on missing or stale schema files"
    )
    args = parser.parse_args()
    changed = []
    for name, model in SCHEMAS.items():
        schema = model.model_json_schema()
        schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
        rendered = json.dumps(schema, indent=2, sort_keys=True) + "\n"
        path = ROOT / name
        if args.check:
            if not path.exists() or path.read_text() != rendered:
                changed.append(name)
        else:
            path.write_text(rendered)
    if changed:
        raise SystemExit("Stale schemas: " + ", ".join(changed))
    print(f"{'Checked' if args.check else 'Exported'} {len(SCHEMAS)} API schemas.")


if __name__ == "__main__":
    main()
