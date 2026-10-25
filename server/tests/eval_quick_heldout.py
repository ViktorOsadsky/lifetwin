"""Score the quick check-in held-out sets once: correct, asked again (miss), or wrong.

    uv run python server/tests/eval_quick_heldout.py [path ...]

A case is the first reply to one question. "Correct" means the values heard (quick)
or read back (weekly) are exactly the expected values, or Mochi asked again when the
expected value is null.
"Miss" means Mochi asked again although a value was expected (safe). "Wrong" means
any other value was read back, or a value was read back when none was expected.
The goal is zero wrong values. Not collected by pytest, and never used for tuning.
"""

import json
import math
import sys
from datetime import date
from pathlib import Path

from lifetwin.checkin.models import CheckinState, CheckinTurnRequest
from lifetwin.checkin.scripts import WEEKLY, quick_script
from lifetwin.checkin.service import CheckinService

DATA = Path(__file__).parent / "data"
DEFAULT = [DATA / "quick_checkin_heldout.json", DATA / "quick_checkin_heldout_independent.json"]
SERVICE = CheckinService(clock=lambda: date(2026, 10, 24))


def state_for(case: dict) -> CheckinState:
    field = case["field"]
    confirmed = case.get("confirmed", {})
    if case["kind"] == "weekly":
        questions, extra = list(WEEKLY), {}
    else:
        topics = ["feeling"] if field == "wellbeing" else ["sleep", "activity", "sitting"]
        questions = list(quick_script(topics, field == "sleep_hours_night_before"))
        extra = {"local_date": "2026-10-24", "activity_day": case.get("activity_day", "yesterday")}
    before = [name for name in questions[: questions.index(field)] if name not in confirmed]
    return CheckinState(
        kind=case["kind"],
        questions=questions,
        current_field=field,
        previous=case.get("previous", {}),
        confirmed=confirmed,
        skipped_fields=before,
        **extra,
    )


def close(got: dict, expected: dict) -> bool:
    if got.keys() != expected.keys():
        return False
    return all(
        got[k] == v if isinstance(v, str) else math.isclose(got[k], v, abs_tol=0.06)
        for k, v in expected.items()
    )


def score(path: Path) -> dict:
    cases = json.loads(path.read_text())["cases"]
    tally = {"correct": 0, "miss": 0, "wrong": 0, "error": 0}
    wrong = []
    for case in cases:
        try:
            request = CheckinTurnRequest(
                action="reply",
                state=state_for(case),
                text=case["text"],
                input_mode=case.get("mode", "text"),
            )
            result = SERVICE.turn(request)
        except Exception as exc:  # noqa: BLE001 - a broken case is reported, not hidden
            tally["error"] += 1
            wrong.append((case["text"], f"error: {type(exc).__name__}"))
            continue
        got = result.state.pending.model_dump(exclude_none=True)
        # Quick: a value the check question asks about ("Did I hear 15 hours of sleep?")
        # is not heard yet, so it counts as asked again.
        got = {k: v for k, v in got.items() if k not in result.state.checking}
        expected = case["expected"]
        if expected is None:
            outcome = "correct" if not got else "wrong"
        elif not got:
            outcome = "miss"
        else:
            outcome = "correct" if close(got, expected) else "wrong"
        tally[outcome] += 1
        if outcome == "wrong":
            wrong.append((case["text"], f"{got} != {expected}"))
    return {"cases": len(cases), **tally, "wrong_cases": wrong}


def main() -> None:
    paths = [Path(p) for p in sys.argv[1:]] or DEFAULT
    for path in paths:
        result = score(path)
        print(f"{path.name}: {result['cases']} cases")
        print(
            f"  correct {result['correct']}, asked again {result['miss']}, "
            f"wrong {result['wrong']}, errors {result['error']}"
        )
        for text, why in result["wrong_cases"]:
            print(f"  WRONG {text!r}: {why}")


if __name__ == "__main__":
    main()
