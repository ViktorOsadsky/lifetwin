"""Acceptance corpus: everyday ways older adults answer each intake question.

Every case runs through the keyless guided service exactly as a phone reply
would. ``expected`` is what must be pending for confirmation afterwards; null
means nothing may be filled and the right response is a follow-up question.
"""

import asyncio
import json
import math
from datetime import date
from pathlib import Path

from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.models import ConversationState, TurnRequest

CASES = json.loads((Path(__file__).parent / "data" / "intake_variants_dev.json").read_text())
# The corpus was written on this date; birthdays are computed against it.
TODAY = date(2026, 10, 24)
MIN_ACCEPTED = 0.92


def pending_after_reply(service: ConversationService, field: str, text: str) -> dict:
    request = TurnRequest(
        action="reply",
        state=ConversationState(phase="asking", current_field=field),
        text=text,
    )
    response = asyncio.run(service.turn(request))
    return response.state.pending_profile.model_dump(exclude_none=True)


def same_value(got, expected) -> bool:
    if isinstance(expected, bool) or isinstance(got, bool) or isinstance(expected, str):
        return type(got) is type(expected) and got == expected
    return math.isclose(got, expected, rel_tol=0.006, abs_tol=0.06)


def same_profile(got: dict, expected: dict) -> bool:
    return got.keys() == expected.keys() and all(
        same_value(got[key], value) for key, value in expected.items()
    )


def evaluate(service: ConversationService, cases: list[dict]) -> dict:
    """Per-field counts plus the individual failures, for a readable report."""
    fields: dict[str, dict] = {}
    failures = {"wrong": [], "accepted_null": [], "missed": []}
    for case in cases:
        got = pending_after_reply(service, case["field"], case["text"])
        row = fields.setdefault(
            case["field"], {"positive": 0, "accepted": 0, "null": 0, "refused": 0, "wrong": 0}
        )
        if case["expected"] is None:
            row["null"] += 1
            if got:
                failures["accepted_null"].append((case, got))
            else:
                row["refused"] += 1
            continue
        row["positive"] += 1
        if same_profile(got, case["expected"]):
            row["accepted"] += 1
        elif got:
            row["wrong"] += 1
            failures["wrong"].append((case, got))
        else:
            failures["missed"].append((case, got))
    return {"fields": fields, **failures}


def report(result: dict) -> str:
    lines = [f"{'field':<26}{'accepted':>12}{'wrong':>7}{'null refused':>14}"]
    for field, row in result["fields"].items():
        lines.append(
            f"{field:<26}{row['accepted']:>6}/{row['positive']:<5}{row['wrong']:>7}"
            f"{row['refused']:>8}/{row['null']:<5}"
        )
    for kind in ("wrong", "accepted_null", "missed"):
        for case, got in result[kind]:
            lines.append(f"{kind}: [{case['field']}] {case['text']!r} -> {got} ({case['why']})")
    return "\n".join(lines)


def test_dev_variants_are_understood_without_accepting_a_wrong_value():
    result = evaluate(ConversationService(None, clock=lambda: TODAY), CASES)
    positives = sum(row["positive"] for row in result["fields"].values())
    accepted = sum(row["accepted"] for row in result["fields"].values())
    table = report(result)
    assert not result["wrong"], table
    assert not result["accepted_null"], table
    assert accepted >= MIN_ACCEPTED * positives, table
