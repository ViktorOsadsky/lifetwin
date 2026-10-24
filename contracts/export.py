"""Export or check the schemas generated from server request/response models."""

import argparse
import json
from pathlib import Path

from pydantic.json_schema import GenerateJsonSchema
from schema_registry import SCHEMAS

ROOT = Path(__file__).resolve().parent


class ResponseJsonSchema(GenerateJsonSchema):
    """Responses always emit defaulted fields, so clients may rely on them being present."""

    def field_is_required(self, field, total):
        if self.mode == "serialization":
            return not field.get("serialization_exclude")
        return super().field_is_required(field, total)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="Fail on missing, stale or orphan schema files"
    )
    args = parser.parse_args()
    changed = []
    for name, (model, mode) in SCHEMAS.items():
        schema = model.model_json_schema(mode=mode, schema_generator=ResponseJsonSchema)
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
    orphans = sorted({path.name for path in ROOT.glob("*.schema.json")} - set(SCHEMAS))
    if orphans:
        raise SystemExit("Schemas missing from the registry: " + ", ".join(orphans))
    print(f"{'Checked' if args.check else 'Exported'} {len(SCHEMAS)} API schemas.")


if __name__ == "__main__":
    main()
