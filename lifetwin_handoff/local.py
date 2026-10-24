"""Run a LifeTwin assessment from a JSON file without starting a server.

Examples:
    python -m lifetwin_handoff.local lifetwin_handoff/examples/snapshot_request.json
    python -m lifetwin_handoff.local lifetwin_handoff/examples/compare_request.json --compare
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .service import AssessmentRequest, ComparisonRequest, assess, compare


def main() -> None:
    parser = argparse.ArgumentParser(description='Local LifeTwin survival and wellness inference')
    parser.add_argument('request_file', type=Path, help='JSON request file')
    parser.add_argument('--compare', action='store_true', help='Use the comparison request format')
    args = parser.parse_args()
    request = json.loads(args.request_file.read_text(encoding='utf-8'))
    if args.compare:
        result = compare(ComparisonRequest.model_validate(request))
    else:
        result = assess(AssessmentRequest.model_validate(request))
    print(json.dumps(result, indent=2, allow_nan=False, default=str))


if __name__ == '__main__':
    main()
