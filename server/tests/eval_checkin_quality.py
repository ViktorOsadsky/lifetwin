"""Score the check-in eval sets: pass, miss (asked again) and wrong, reported apart.

    uv run python server/tests/eval_checkin_quality.py [-v]

- ``checkin_replies.json``: the development corpus (also run by test_checkin.py).
- ``quick_checkin_heldout*.json``: the quick check-in held-out sets.
- ``checkin_quality_heldout.json``: a blind held-out set (people in their 20s, 40s and
  70s) written before the check-in quality work and never tuned on. A line may state
  values for later questions of the same check-in too; those count as well. A value
  heard that differs from the expected one, or that nobody said, is wrong; values that
  all agree but leave some expected ones out are a miss. Its ``safety_cases`` check
  the emergency reply in both directions.

Not collected by pytest. Wrong values must stay 0.
"""

import json
import math
import sys
from datetime import date
from pathlib import Path

from eval_quick_heldout import DEFAULT as QUICK_SETS
from eval_quick_heldout import score as score_quick

from lifetwin.checkin.models import CheckinState, CheckinTurnRequest
from lifetwin.checkin.scripts import DAILY, PAIRS, quick_script
from lifetwin.checkin.service import CheckinService

DATA = Path(__file__).parent / "data"
HELDOUT = DATA / "checkin_quality_heldout.json"
SERVICE = CheckinService(clock=lambda: date(2026, 10, 24))


def _close(got, expected) -> bool:
    if isinstance(expected, str) or isinstance(got, str):
        return got == expected
    return math.isclose(got, expected, rel_tol=0.006, abs_tol=0.06)


def _state(case: dict) -> tuple[CheckinState, list[str]]:
    """The check-in at the case's question, earlier questions skipped, and the fields
    this and the later questions fill."""
    field = case["field"]
    if case["kind"] == "daily":
        questions, extra = list(DAILY), {}
    else:
        topics = ["sleep", "activity", "feeling" if field == "wellbeing" else "sitting"]
        questions = list(quick_script(topics, False))
        extra = {"local_date": "2026-10-24", "activity_day": case.get("activity_day", "yesterday")}
    at = questions.index(field)
    state = CheckinState(
        kind=case["kind"],
        questions=questions,
        current_field=field,
        skipped_fields=questions[:at],
        **extra,
    )
    later = questions[at:]
    return state, later + [PAIRS[f] for f in later if f in PAIRS]


def _say(state: CheckinState, text: str, mode: str):
    return SERVICE.turn(CheckinTurnRequest(action="reply", state=state, text=text, input_mode=mode))


def score_heldout(path: Path = HELDOUT) -> dict:
    data = json.loads(path.read_text())
    tally = {"cases": 0, "pass": 0, "miss": 0, "wrong": 0, "error": 0}
    notes = []
    for case in data["cases"]:
        tally["cases"] += 1
        try:
            state, fields = _state(case)
            result = _say(state, case["text"], case.get("mode", "text"))
        except Exception as exc:  # noqa: BLE001 - a broken case is reported, not hidden
            tally["error"] += 1
            notes.append(("ERROR", case["text"], type(exc).__name__))
            continue
        got = result.state.pending.model_dump(exclude_none=True)
        got |= {k: v for k, v in result.state.confirmed.model_dump(exclude_none=True).items()}
        expected = {k: v for k, v in (case["expected"] or {}).items() if k in fields}
        if case["expected"] is None:
            outcome = "pass" if not got else "wrong"
        elif any(k not in expected or not _close(v, expected[k]) for k, v in got.items()):
            outcome = "wrong"
        elif got.keys() == expected.keys():
            outcome = "pass"
        else:
            outcome = "miss"
        tally[outcome] += 1
        if outcome != "pass":
            notes.append((outcome.upper(), case["text"], f"{got} vs {case['expected']}"))
    safety = {"cases": 0, "pass": 0, "missed_emergency": 0, "false_alarm": 0}
    for case in data.get("safety_cases", []):
        safety["cases"] += 1
        kind = "daily" if case["field"] == "exercise_minutes_today" else "quick"
        state, _ = _state({"kind": kind, "field": case["field"]})
        flagged = _say(state, case["text"], "text").emergency
        if flagged == case["emergency"]:
            safety["pass"] += 1
        else:
            safety["false_alarm" if flagged else "missed_emergency"] += 1
            notes.append(("SAFETY", case["text"], f"emergency={flagged}"))
    return {"values": tally, "safety": safety, "notes": notes}


def score_corpus() -> dict:
    sys.path.insert(0, str(Path(__file__).parent))
    import test_checkin as corpus  # noqa: PLC0415 - the development corpus' own helpers

    tally = {"cases": 0, "pass": 0, "miss": 0, "wrong": 0}
    notes = []
    for case in corpus.CASES:
        tally["cases"] += 1
        extra = {"confirmed": case["confirmed"]} if "confirmed" in case else {}
        state = corpus.at(case["script"], case["field"], case["previous"], **extra)
        got = corpus.pending(corpus.say(state, case["text"], case["mode"]))
        if case["expected"] is None:
            outcome = "pass" if not got else "wrong"
        elif corpus.same(got, case["expected"]):
            outcome = "pass"
        else:
            outcome = "wrong" if got else "miss"
        tally[outcome] += 1
        if outcome == "wrong":
            notes.append(("WRONG", case["text"], f"{got} vs {case['expected']}"))
    return {"values": tally, "notes": notes}


def main() -> None:
    verbose = "-v" in sys.argv
    corpus = score_corpus()
    print("checkin_replies.json:", corpus["values"])
    for text in corpus["notes"]:
        print("  ", *text)
    for path in QUICK_SETS:
        result = score_quick(path)
        print(
            f"{path.name}: cases {result['cases']}, pass {result['correct']}, "
            f"miss {result['miss']}, wrong {result['wrong']}, errors {result['error']}"
        )
        for text, why in result["wrong_cases"]:
            print("   WRONG", text, why)
    held = score_heldout()
    print(f"{HELDOUT.name}: {held['values']}")
    print(f"{HELDOUT.name} safety: {held['safety']}")
    for kind, text, why in held["notes"]:
        if verbose:  # held-out lines are shown only on request: never tuned on
            print("  ", kind, repr(text), why)


if __name__ == "__main__":
    main()
