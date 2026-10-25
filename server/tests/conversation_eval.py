"""Score the held-out conversation v2 replies through the public onboarding API.

Run from the repository root: ``uv run python server/tests/conversation_eval.py [a|b] [-v]``.

Each reply is sent once, to a state built from the case, and its result is scored:

- ``correct``: the expected outcome (unknown recorded, the expected values pending,
  the expected topic opened, or the expected habit note).
- ``miss``: a safe miss. Nothing wrong was recorded; the person is asked again.
- ``wrong``: a health value that differs from the reply, a value nobody said, or a
  habit note field that differs from the person's words. Must stay 0.

A request the API rejects (for example a field it does not know yet) is a miss.
"""

import json
import math
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from lifetwin.onboarding import ConversationService, get_service, router

DATA = Path(__file__).parent / "data"
# Set A was written before any v2 code; set B after the owner's blood pressure,
# proxy and steering direction, before that behaviour was built.
CASE_FILES = {"a": DATA / "conversation_v2_eval.json", "b": DATA / "conversation_v2_eval_b.json"}


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(router, prefix="/api")
    service = ConversationService(clock=lambda: date(2026, 10, 24))
    app.dependency_overrides[get_service] = lambda: service
    return TestClient(app)


def _state(case: dict) -> dict:
    if case["kind"] == "probe":
        return {
            "phase": "probing",
            "current_probe": case["probe"],
            "probes_asked": [case["probe"]],
        }
    state = {
        "phase": "asking",
        "current_field": case["field"],
        "confirmed_profile": case.get("confirmed", {}),
    }
    if "health_offered" in case:
        state["health_offered"] = case["health_offered"]
    if case.get("proxy"):
        state["proxy_field"] = case["field"]
    return state


def _same(a, b) -> bool:
    if isinstance(a, bool) or isinstance(b, bool) or isinstance(a, str) or isinstance(b, str):
        return a == b
    return math.isclose(float(a), float(b), rel_tol=1e-3, abs_tol=0.01)


def _note_fields(note: dict) -> dict:
    return {
        key: value
        for key, value in note.items()
        if value is not None and key not in {"topic", "source"}
    }


def _note_verdict(expected: dict | None, notes: list[dict], exhaustive: bool) -> str:
    if expected is None:
        return "correct" if not notes else "wrong"
    found = [note for note in notes if note.get("topic") == expected["topic"]]
    if not found:
        return "miss"
    got = _note_fields(found[-1])
    want = {key: value for key, value in expected.items() if key != "topic"}
    for key, value in got.items():
        if key in want and str(value).lower() != str(want[key]).lower():
            return "wrong"
        if key not in want and exhaustive:
            return "wrong"
    if all(str(got.get(key, "")).lower() == str(value).lower() for key, value in want.items()):
        return "correct"
    return "miss"


def score_case(client: TestClient, case: dict) -> dict:
    body = {
        "action": "reply",
        "state": _state(case),
        "text": case["text"],
        "input_mode": case.get("mode", "text"),
    }
    response = client.post("/api/onboarding/turn", json=body)
    if response.status_code != 200:
        verdict = {"verdict": "miss", "reason": f"http {response.status_code}"}
        if case["kind"] == "value" and "note" in case:
            verdict["note"] = "miss"
        return verdict
    state = response.json()["state"]
    pending = {k: v for k, v in (state.get("pending_profile") or {}).items() if v is not None}
    unknown = state.get("unknown_fields") or []
    notes = state.get("habit_notes") or []
    kind = case["kind"]
    result: dict = {}
    if kind == "unknown":
        field = case["field"]
        if field in pending:
            result["verdict"] = "wrong"
        elif field in unknown or state.get("proxy_field") == field:
            result["verdict"] = "correct"
        else:
            result["verdict"] = "miss"
    elif kind == "value":
        expect = case["expect"]
        if any(k not in expect or not _same(v, expect[k]) for k, v in pending.items()):
            result["verdict"] = "wrong"
        elif pending.keys() == expect.keys():
            result["verdict"] = "correct"
        else:
            result["verdict"] = "miss"
        if case["field"] in unknown:
            result["false_unknown"] = True
        if "note" in case:
            result["note"] = _note_verdict(case["note"], notes, exhaustive=False)
    elif kind in {"novalue", "smalltalk"}:
        message = response.json()["message"].lower()
        if pending:
            result["verdict"] = "wrong"
        elif state.get("phase") != "asking" or state.get("current_field") != case["field"]:
            result["verdict"] = "miss"
        elif kind == "smalltalk" and ("didn't catch" in message or "can't answer" in message):
            result["verdict"] = "miss"
        else:
            result["verdict"] = "correct"
        if "note" in case:
            result["note"] = _note_verdict(case["note"], notes, exhaustive=False)
    elif kind == "steer":
        if state.get("phase") == "confirming":
            confirmed = client.post(
                "/api/onboarding/turn", json={"action": "confirm", "state": state}
            )
            if confirmed.status_code == 200:
                state = confirmed.json()["state"]
                message = confirmed.json()["message"]
                expect = case["expect"]
                right = state.get("current_field") == expect["current_field"]
                said = expect["mentions"].lower() in message.lower()
                result["verdict"] = "correct" if right and said else "miss"
            else:
                result["verdict"] = "miss"
        else:
            result["verdict"] = "miss"
    elif kind == "jump":
        if pending:
            result["verdict"] = "wrong"
        elif (
            state.get("phase") == "asking"
            and state.get("current_field") == case["expect"]["current_field"]
        ):
            result["verdict"] = "correct"
        else:
            result["verdict"] = "miss"
    elif kind == "probe":
        if pending:
            result["verdict"] = "wrong"
        else:
            result["verdict"] = _note_verdict(case["note"], notes, exhaustive=True)
            if state.get("phase") == "probing":
                result["verdict"] = "miss" if result["verdict"] == "correct" else result["verdict"]
    return result


def score(which: str = "a") -> dict:
    cases = json.loads(CASE_FILES[which].read_text())
    client = _client()
    by_kind: dict[str, Counter] = defaultdict(Counter)
    notes: Counter = Counter()
    details = []
    for case in cases:
        result = score_case(client, case)
        by_kind[case["kind"]][result["verdict"]] += 1
        if result.get("false_unknown"):
            by_kind[case["kind"]]["false_unknown"] += 1
        if "note" in result:
            notes[result["note"]] += 1
        details.append({"id": case["id"], **result})
    total = Counter()
    for counts in by_kind.values():
        total.update({k: v for k, v in counts.items() if k != "false_unknown"})
    # Cases with an expected value, scored apart from the cases that must be asked again.
    ask_again = Counter()
    for kind in ("novalue", "smalltalk"):
        ask_again.update(
            {
                "asked_again": by_kind[kind]["correct"],
                "took_a_value": by_kind[kind]["wrong"],
                "other": by_kind[kind]["miss"],
            }
        )
    return {
        "cases": len(cases),
        "value_only": {k: v for k, v in by_kind["value"].items() if k != "false_unknown"},
        "ask_again": dict(ask_again),
        "by_kind": {kind: dict(counts) for kind, counts in sorted(by_kind.items())},
        "volunteered_notes": dict(notes),
        "total": dict(total),
        "wrong_values": sum(
            by_kind[kind]["wrong"]
            for kind in ("unknown", "value", "jump", "novalue", "smalltalk", "steer")
        ),
        "details": details,
    }


if __name__ == "__main__":
    for which in [arg for arg in sys.argv[1:] if arg in CASE_FILES] or list(CASE_FILES):
        report = score(which)
        if "-v" not in sys.argv:
            report.pop("details")
        print(which, json.dumps(report, indent=1))
