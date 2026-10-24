"""Validate schemas/fixtures, optionally replay requests against a running server."""

import argparse
import json
from contextlib import ExitStack
from pathlib import Path

import httpx
from jsonschema import Draft202012Validator, FormatChecker, ValidationError
from schema_registry import SCHEMAS

ROOT = Path(__file__).resolve().parent


def assert_subset(actual: object, expected: object, path: str = "response") -> None:
    """Check fixture semantics without duplicating an entire quiz/content bank.

    ``{"$each": subset}`` requires a nonempty list whose every element matches ``subset``.
    """
    if isinstance(expected, dict) and set(expected) == {"$each"}:
        if not isinstance(actual, list) or not actual:
            raise AssertionError(f"{path}: expected a nonempty list")
        for index, item in enumerate(actual):
            assert_subset(item, expected["$each"], f"{path}[{index}]")
    elif isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise AssertionError(f"{path}: expected an object")
        for key, value in expected.items():
            if key not in actual:
                raise AssertionError(f"{path}.{key}: missing field")
            assert_subset(actual[key], value, f"{path}.{key}")
    elif type(actual) is not type(expected) or actual != expected:
        # Do not print actual values: an API response may contain health data.
        raise AssertionError(f"{path}: differs from the expected fixture")


def main() -> None:
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group()
    target.add_argument(
        "--base-url", help="Replay fixtures against an explicitly selected keyless API"
    )
    target.add_argument(
        "--in-process",
        action="store_true",
        help="Replay against the keyless ASGI app without a socket",
    )
    args = parser.parse_args()
    validators = {}
    for name in SCHEMAS:
        schema = json.loads((ROOT / name).read_text())
        Draft202012Validator.check_schema(schema)
        validators[name] = Draft202012Validator(schema, format_checker=FormatChecker())
    cases = json.loads((ROOT / "fixtures" / "cases.json").read_text())
    checked_responses = 0
    checked_requests = 0
    with ExitStack() as stack:
        client = None
        if args.in_process:
            from fastapi.testclient import TestClient

            from lifetwin.app import create_app
            from lifetwin.core.config import Settings

            client = stack.enter_context(
                TestClient(
                    create_app(
                        Settings(
                            _env_file=None,
                            app_env="test",
                            openai_api_key="",
                            openai_model="",
                            tavily_api_key="",
                        )
                    )
                )
            )
        elif args.base_url:
            client = stack.enter_context(
                httpx.Client(timeout=15, follow_redirects=False, trust_env=False)
            )
        for case in cases:
            if "request_schema" in case:
                # Schema-valid requests the server still rejects pin known schema drift.
                expected_valid = case.get("request_schema_valid", True)
                if expected_valid:
                    validators[case["request_schema"]].validate(case["request"])
                elif validators[case["request_schema"]].is_valid(case["request"]):
                    raise SystemExit(
                        f"{case['name']}: request unexpectedly matches {case['request_schema']}"
                    )
                checked_requests += 1
            if "response" in case:
                validators[case["response_schema"]].validate(case["response"])
            if client is not None:
                response = client.request(
                    case["method"],
                    (args.base_url or "").rstrip("/") + case["path"],
                    **({"json": case["request"]} if "request" in case else {}),
                )
                if response.status_code != case["status"]:
                    raise SystemExit(f"{case['name']}: unexpected HTTP {response.status_code}")
                try:
                    body = response.json()
                    validators[case["response_schema"]].validate(body)
                except (ValueError, ValidationError):
                    # jsonschema's default traceback prints the complete instance.
                    raise SystemExit(
                        f"{case['name']}: invalid API response for {case['response_schema']}"
                    ) from None
                if "response" in case and response.json() != case["response"]:
                    raise SystemExit(f"{case['name']}: response differs from fixture")
                if "response_subset" in case:
                    assert_subset(response.json(), case["response_subset"], case["name"])
                checked_responses += 1
            elif "response" in case:
                checked_responses += 1
            if client is not None:
                print(f"PASS {case['name']} (API response checked)")
            elif "response" in case:
                print(f"PASS {case['name']} (static response checked)")
            elif "request_schema" in case:
                print(f"PASS {case['name']} (request fixture only; response not checked)")
            else:
                print(f"SKIP {case['name']} (requires API replay)")
    print(
        f"Validated {len(validators)} schemas and {checked_requests} request fixtures; "
        f"{checked_responses} responses checked across {len(cases)} cases"
        + (
            " against live API."
            if args.base_url
            else " in process."
            if args.in_process
            else " offline."
        )
    )


if __name__ == "__main__":
    main()
