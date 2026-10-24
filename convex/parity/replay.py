"""Replay the FastAPI reference fixture against a running server, byte for byte.

    uv run python convex/parity/replay.py --base-url http://127.0.0.1:3211

Compares status, content type, Allow header and the exact response body
(request IDs masked) for every HTTP case in convex/tests/fixtures/parity.json.
Mismatches print the case and both bodies; fixtures are synthetic test inputs.
"""

import argparse
import base64
import json
import re
import sys
from pathlib import Path

import httpx

FIXTURE = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "parity.json"
REQUEST_ID = re.compile(r'"request_id":"[0-9a-f]{32}"')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--show", type=int, default=10, help="mismatches to print")
    args = parser.parse_args()
    cases = json.loads(FIXTURE.read_text(encoding="utf-8"))["http"]
    failures = []
    with httpx.Client(timeout=30, follow_redirects=False, trust_env=False) as client:
        for case in cases:
            headers = {"content-type": case["content_type"]} if case["content_type"] else {}
            if case.get("body_b64"):
                content = base64.b64decode(case["body_b64"])
            else:
                content = case["body"].encode("utf-8") if case["body"] is not None else None
            response = client.request(
                case["method"],
                args.base_url.rstrip("/") + case["path"],
                content=content,
                headers=headers,
            )
            body = REQUEST_ID.sub('"request_id":"<id>"', response.text)
            problems = []
            location = response.headers.get("location")
            if location is not None:
                location = location.removeprefix(args.base_url.rstrip("/"))
            if location != case.get("location"):
                problems.append(f"location {location!r} != {case.get('location')!r}")
            if response.status_code != case["status"]:
                problems.append(f"status {response.status_code} != {case['status']}")
            if response.headers.get("content-type") != case["response_content_type"]:
                problems.append(
                    f"content-type {response.headers.get('content-type')!r} != {case['response_content_type']!r}"
                )
            if response.headers.get("allow") != case["allow"]:
                problems.append(f"allow {response.headers.get('allow')!r} != {case['allow']!r}")
            if body != case["response"]:
                problems.append("body differs")
            if "x-request-id" not in response.headers:
                problems.append("missing x-request-id")
            if problems:
                failures.append((case, problems, body))
    for case, problems, body in failures[: args.show]:
        print(
            f"FAIL {case['method']} {case['path'][:80]} body={str(case['body'])[:80]!r}: {problems}"
        )
        if "body differs" in problems:
            print(f"  expected: {case['response'][:400]}")
            print(f"  actual:   {body[:400]}")
    print(f"{len(cases) - len(failures)}/{len(cases)} HTTP parity cases identical")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
