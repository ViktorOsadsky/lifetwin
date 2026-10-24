"""Validate schemas/fixtures, optionally replay requests against a running server."""

import argparse
import json
from pathlib import Path

import httpx
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", help="Replay fixtures against an explicitly selected API")
    args = parser.parse_args()
    validators = {}
    for path in ROOT.glob("*.schema.json"):
        schema = json.loads(path.read_text())
        Draft202012Validator.check_schema(schema)
        validators[path.name] = Draft202012Validator(schema, format_checker=FormatChecker())
    cases = json.loads((ROOT / "fixtures" / "cases.json").read_text())
    with httpx.Client(timeout=15, follow_redirects=False, trust_env=False) as client:
        for case in cases:
            if "request_schema" in case:
                validators[case["request_schema"]].validate(case["request"])
            if "response" in case:
                validators[case["response_schema"]].validate(case["response"])
            if args.base_url:
                response = client.request(
                    case["method"],
                    args.base_url.rstrip("/") + case["path"],
                    **({"json": case["request"]} if "request" in case else {}),
                )
                if response.status_code != case["status"]:
                    raise SystemExit(f"{case['name']}: unexpected HTTP {response.status_code}")
                validators[case["response_schema"]].validate(response.json())
                if "response" in case and response.json() != case["response"]:
                    raise SystemExit(f"{case['name']}: response differs from fixture")
            print(f"PASS {case['name']}")
    print(
        f"Validated {len(validators)} schemas and {len(cases)} fixtures"
        + (" against live API." if args.base_url else " offline.")
    )


if __name__ == "__main__":
    main()
