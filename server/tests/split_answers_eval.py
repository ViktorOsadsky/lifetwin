"""Score split, cut-off and multi-fact answers through the public services.

    uv run python server/tests/split_answers_eval.py [-v]

Each case in data/split_answers_heldout.json plays a few turns in order. A turn is the
question that was open (``asked``) and what the person said (``text``). After every
reply a read-back is confirmed, as the app does when the person says yes. At the end:

- ``expect``: the answers this case must have saved, exactly (units: cm, kg, minutes).
- ``unknown``: fields that must be recorded as "I don't know".
- ``ends_on``: the question that must be open at the end (so a fragment kept the
  question, or an answered question was skipped).
- ``quiet``: a turn index list whose reply must not say "didn't catch that".

correct: all of it holds. wrong: a saved value that was not expected (or differs).
miss: nothing wrong was saved, but something expected is missing.
"""

import asyncio
import json
import math
from datetime import date
from pathlib import Path

from lifetwin.checkin.models import CheckinStartRequest, CheckinTurnRequest, QuickPlan
from lifetwin.checkin.service import CheckinService
from lifetwin.onboarding import ConversationService
from lifetwin.onboarding.models import ConversationState, TurnRequest

DATA = Path(__file__).parent / "data" / "split_answers_heldout.json"
TODAY = date(2026, 10, 21)  # a Wednesday: no daily habit question
CAUGHT = ("didn't catch", "did not catch", "couldn't catch")


def same(a, b) -> bool:
    if isinstance(a, (bool, str)) or isinstance(b, (bool, str)):
        return a == b
    return math.isclose(float(a), float(b), rel_tol=0.015, abs_tol=0.06)


def verdict(got: dict, expect: dict, extras_ok: bool = False) -> tuple[str, list[str]]:
    why = []
    for key, value in got.items():
        if key not in expect:
            why.append(f"extra {key}={value}")
        elif not same(value, expect[key]):
            why.append(f"{key}={value} != {expect[key]}")
    if why:
        return "wrong", why
    missing = [k for k in expect if k not in got]
    return ("miss", [f"missing {k}" for k in missing]) if missing else ("correct", [])


def play_onboarding(case: dict) -> tuple[dict, list, str | None, list[str]]:
    service = ConversationService(clock=lambda: TODAY, seed=lambda: 3)
    setup = case.get("setup", {})
    turns = case["turns"]
    state = ConversationState(
        phase="asking",
        current_field=turns[0]["asked"],
        confirmed_profile=setup,
        memory_consent=False,
    )
    messages = []
    for turn in turns:
        if state.phase in {"asking", "offering"} and state.current_field != turn["asked"]:
            # The test names the open question; Apple Health's offer is not part of it.
            state.phase, state.current_field = "asking", turn["asked"]
        response = asyncio.run(
            service.turn(TurnRequest(action="reply", state=state, text=turn["say"]))
        )
        messages.append(response.message)
        state = response.state
        for _ in range(3):
            if state.phase != "confirming":
                break
            response = asyncio.run(service.turn(TurnRequest(action="confirm", state=state)))
            state = response.state
    confirmed = {
        k: v
        for k, v in state.confirmed_profile.model_dump(exclude_none=True).items()
        if k not in setup or not same(setup[k], v)
    }
    return confirmed, list(state.unknown_fields), state.current_field, messages


def play_checkin(case: dict) -> tuple[dict, list, str | None, list[str]]:
    service = CheckinService(clock=lambda: TODAY)
    kind = case["kind"]
    turns = case["turns"]
    plan = None
    if kind == "quick":
        plan = QuickPlan(topics=["sleep", "activity", "sitting"], activity_day="yesterday")
    state = service.start(
        CheckinStartRequest(kind=kind, local_date=TODAY.isoformat(), quick=plan)
    ).state
    setup = case.get("setup", {})
    if setup:
        state.confirmed = state.confirmed.model_copy(update=setup)
    messages = []
    for turn in turns:
        if state.phase == "asking" and state.current_field != turn["asked"]:
            state.current_field = turn["asked"]
            state.skipped_fields = [f for f in state.skipped_fields if f != turn["asked"]]
        response = service.turn(CheckinTurnRequest(action="reply", state=state, text=turn["say"]))
        messages.append(response.message)
        state = response.state
        if kind == "weekly" and state.phase == "confirming":
            state = service.turn(CheckinTurnRequest(action="confirm", state=state)).state
    got = {
        **state.confirmed.model_dump(exclude_none=True),
        **{
            k: v
            for k, v in state.pending.model_dump(exclude_none=True).items()
            if k not in state.checking
        },
    }
    got = {k: v for k, v in got.items() if k not in setup or not same(setup[k], v)}
    unknown = list(state.unknown_fields)
    return got, unknown, state.current_field, messages


def score_case(case: dict) -> dict:
    play = play_onboarding if case["kind"] == "onboarding" else play_checkin
    try:
        got, unknown, open_field, messages = play(case)
    except Exception as exc:  # noqa: BLE001 - a broken case is reported, not hidden
        return {"id": case["id"], "verdict": "miss", "why": [f"error {type(exc).__name__}: {exc}"]}
    outcome, why = verdict(got, case["expect"])
    if outcome != "wrong":
        for field in case.get("unknown", []):
            if field not in unknown:
                outcome, why = "miss", why + [f"{field} not recorded as unknown"]
        if "ends_on" in case and open_field != case["ends_on"]:
            outcome, why = "miss", why + [f"open question {open_field}, wanted {case['ends_on']}"]
        for index in case.get("quiet", []):
            if any(phrase in messages[index].lower() for phrase in CAUGHT):
                outcome, why = "miss", why + [f"turn {index} said it didn't catch that"]
    for field in case.get("unknown", []):
        if outcome != "wrong" and field in got:
            outcome, why = "wrong", why + [f"{field} saved and unknown"]
    return {"id": case["id"], "verdict": outcome, "why": why, "text": case["turns"][-1]["say"]}


def score() -> dict:
    cases = json.loads(DATA.read_text())["cases"]
    results = [score_case(case) for case in cases]
    tally = {v: sum(r["verdict"] == v for r in results) for v in ("correct", "miss", "wrong")}
    return {"cases": len(cases), **tally, "results": results}


def main() -> None:
    result = score()
    print(
        f"{result['cases']} cases: correct {result['correct']}, "
        f"miss {result['miss']}, wrong {result['wrong']}"
    )
    for r in result["results"]:
        if r["verdict"] != "correct":
            print(f"  {r['verdict'].upper():5} {r['id']} {r['text']!r}: {'; '.join(r['why'])}")


if __name__ == "__main__":
    main()
