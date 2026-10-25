"""Score change requests end to end: uv run python server/tests/change_eval.py [file].

Each case starts a change (a field, or none for "What would you like to update?"),
sends its turns, then says yes to every read-back, as the least careful listener
would. Whatever lands in ``profile_update`` is compared with the expected change:
- correct: exactly the expected values ({} expected: nothing changed);
- miss: a change was expected, but Mochi asked again and nothing changed;
- wrong: any other value. Wrong values must be 0.
No health value is printed for passing cases.
"""

import json
import math
import sys
from datetime import date
from pathlib import Path

from lifetwin.change.models import ChangeStartRequest, ChangeTurnRequest
from lifetwin.change.service import ChangeService

DATA = Path(__file__).parent / "data"
TODAY = date(2026, 10, 24)


def same(got: dict, expected: dict) -> bool:
    if got.keys() != expected.keys():
        return False
    return all(
        got[k] == v
        if isinstance(v, (str, bool)) or isinstance(got[k], (str, bool))
        else math.isclose(got[k], v, rel_tol=0.006, abs_tol=0.06)
        for k, v in expected.items()
    )


def run(case: dict, base: dict, service: ChangeService | None = None) -> tuple[str, dict]:
    """("correct" | "miss" | "wrong", details) for one case."""
    service = service or ChangeService(clock=lambda: TODAY)
    profile = {**base, **case["profile"]}
    consent = case["consent"]
    response = service.start(
        ChangeStartRequest(profile=profile, field=case["field"], memory_consent=consent)
    )
    paused = False
    for said in case["turns"]:
        action, text = ("resume", None) if said == "@resume" else ("reply", said)
        response = service.turn(
            ChangeTurnRequest(
                action=action,
                state=response.state,
                profile=profile,
                memory_consent=consent,
                text=text,
                input_mode=case["mode"],
            )
        )
        paused = paused or response.emergency
    for _ in range(3):
        if response.state.phase == "probing":
            reply = "no"
        elif response.state.phase == "confirming":
            reply = "yes"
        else:
            break
        response = service.turn(
            ChangeTurnRequest(
                action="reply",
                state=response.state,
                profile=profile,
                memory_consent=consent,
                text=reply,
                input_mode=case["mode"],
            )
        )
    got = response.profile_update.model_dump(exclude_none=True) if response.complete else {}
    details = {"got": got, "message": response.message, "phase": response.state.phase}
    if case.get("emergency") and not paused:
        return "wrong", details | {"reason": "no emergency pause"}
    if same(got, case["expected"]):
        return "correct", details
    if not got:
        return "miss", details
    return "wrong", details


def score(path: Path) -> dict:
    data = json.loads(path.read_text())
    counts = {"correct": 0, "miss": 0, "wrong": 0}
    failures = []
    for i, case in enumerate(data["cases"]):
        outcome, details = run(case, data["base_profile"])
        counts[outcome] += 1
        if outcome != "correct":
            failures.append((i, outcome, case, details))
    return {"counts": counts, "total": len(data["cases"]), "failures": failures}


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DATA / "change_heldout.json"
    result = score(path)
    counts, total = result["counts"], result["total"]
    print(f"{path.name}: {total} cases")
    for outcome in ("correct", "miss", "wrong"):
        print(f"  {outcome}: {counts[outcome]} ({100 * counts[outcome] / total:.0f}%)")
    for i, outcome, case, details in result["failures"]:
        print(f"  {outcome.upper()} #{i} {case['why']}: {case['turns']} -> {details}")
