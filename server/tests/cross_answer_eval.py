"""Score answers given to the wrong question, with and without the AI helper (Muse).

    cd server && uv run python tests/cross_answer_eval.py --split dev --mode none -v
    cd server && uv run --env-file <repo>/.env python tests/cross_answer_eval.py --mode both

Cases live in data/cross_answers/{dev,heldout}.json (synthetic people, split before any
result was looked at; tune on dev only). Each case starts the public API in a given
phase (an open question, a read-back, the memory or Apple Health question, a habit
follow-up, the end, or a check-in question), sends the reply, says yes to every
read-back (as the app does when the person agrees) and reads the final state.

Modes: ``muse`` sends the person's consent for the AI helper (``provider_consent``, so
``guide_mode`` may be ``llm``) and for Muse wording (``outside_ai_consent.muse``);
``none`` sends no consent, so only Mochi's templates and the deterministic parser run.
Check-ins never call a provider, so their two modes match by design.

Per case: correct (every expected value, nothing wrong or extra, skips honoured,
conflicts surfaced, the expected next question), missing (nothing wrong, but something
expected is absent) or WRONG (a value the person didn't say, or a confirmed answer
overwritten without a read-back). Wrong is worse than missing.
"""

import argparse
import json
import math
import re
import statistics
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings

DATA = Path(__file__).parent / "data" / "cross_answers"
TODAY = date(2026, 10, 24)
CAUGHT = ("didn't catch", "did not catch", "couldn't catch", "couldn't read that")
PROBE_IDS = ["activity", "sleep_pattern", "smoking_history", "sitting_activities", "health_feeling"]
CONSENT = {"muse": {"provider_consent": True, "outside_ai_consent": {"muse": True}}, "none": {}}


def load(split: str) -> list[dict]:
    names = ["dev", "heldout"] if split == "all" else [split]
    return [case for name in names for case in json.loads((DATA / f"{name}.json").read_text())["cases"]]


def same(got, want) -> bool:
    if isinstance(want, list):
        return any(same(got, option) for option in want)
    if isinstance(got, (bool, str)) or isinstance(want, (bool, str)) or got is None:
        return got == want
    return math.isclose(float(got), float(want), rel_tol=0.015, abs_tol=0.06)


class Meter:
    """Counts provider calls and their latency; never sees or keeps their content."""

    def __init__(self):
        self.lock = threading.Lock()
        self.calls = 0
        self.failed = 0
        self.seconds: list[float] = []

    def wrap(self, obj, name: str) -> None:
        original = getattr(obj, name)

        async def timed(*args, **kwargs):
            start = time.perf_counter()
            ok = False
            try:
                result = await original(*args, **kwargs)
                ok = True
                return result
            finally:
                with self.lock:
                    self.calls += 1
                    self.failed += not ok
                    self.seconds.append(time.perf_counter() - start)

        setattr(obj, name, timed)


def build_app(provider: bool, meter: Meter | None = None):
    """The real app. ``provider=False`` blanks the provider settings (an offline run)."""
    blank = {} if provider else {"llm_api_key": "", "llm_model": "", "openai_api_key": ""}
    app = create_app(Settings(rate_limit_per_minute=10000, max_concurrent_requests=64, **blank))
    app.state.conversation_service.clock = lambda: TODAY
    app.state.checkin_service.clock = lambda: TODAY
    if meter is not None and provider:
        extractor = app.state.conversation_service.extractor
        meter.wrap(extractor, "complete_json" if hasattr(extractor, "complete_json") else "extract")
        meter.wrap(app.state.personalizer, "phrase")
    return app


# -- playing a case -------------------------------------------------------------------


def _post(client, path: str, body: dict, log: list) -> dict:
    start = time.perf_counter()
    response = client.post(path, json=body)
    log.append(time.perf_counter() - start)
    if response.status_code != 200:
        raise RuntimeError(f"HTTP {response.status_code} on {path}")
    return response.json()


def _onboarding_state(client, start: dict, extra: dict, log: list) -> dict:
    if start["phase"] == "remembering":
        state = _post(client, "/api/onboarding/turn", {"action": "start", **extra}, log)["state"]
        state["seed"] = 3
        return state
    pending = start["pending"]
    state = {
        "phase": start["phase"],
        "current_field": start["field"] if start["phase"] == "asking" or len(pending) == 1 else None,
        "confirmed_profile": start["confirmed"],
        "pending_profile": pending,
        "unknown_fields": start["unknown"],
        "skipped_fields": start["skipped"],
        "memory_consent": start["memory_consent"],
        "health_offered": start["health_offered"],
        "seed": 3,
    }
    if start.get("probe"):
        others = [p for p in PROBE_IDS if p != start["probe"]][:2]
        state.update(current_probe=start["probe"], probes_asked=[start["probe"], *others])
    if start["phase"] in {"probing", "ready"}:
        state["current_field"] = None
    return state


def play_onboarding(client, case: dict, extra: dict, log: list) -> dict:
    state = _onboarding_state(client, case["start"], extra, log)
    setup = case["start"]["confirmed"]
    messages, read_backs, statuses, after_reply = [], [], [], False
    loop = False
    for text in case["turns"]:
        body = {"action": "reply", "state": state, "text": text, "input_mode": "transcript", **extra}
        result = _post(client, "/api/onboarding/turn", body, log)
        messages.append(result["message"])
        statuses.append((result["provider_status"], result["guide_mode"]))
        state = result["state"]
        after_reply = after_reply or state["phase"] == "confirming"
        for _ in range(4):
            if state["phase"] != "confirming":
                break
            read_backs.append({k: v for k, v in state["pending_profile"].items() if v is not None})
            body = {"action": "confirm", "state": state, **extra}
            result = _post(client, "/api/onboarding/turn", body, log)
            messages.append(result["message"])
            state = result["state"]
        else:
            loop = True
    final = {k: v for k, v in state["confirmed_profile"].items() if v is not None}
    got = {k: v for k, v in final.items() if not (k in setup and same(v, setup[k]))}
    return {
        "got": got,
        "final": final,
        "unknown": state["unknown_fields"],
        "settled": set(final) | set(state["unknown_fields"]) | set(state["skipped_fields"]),
        "where": state["current_field"] or state["phase"],
        "messages": messages,
        "read_backs": read_backs,
        "read_back": after_reply,
        "loop": loop,
        "memory_consent": state.get("memory_consent"),
        "llm": any(mode == "llm" for _, mode in statuses),
        "statuses": [status for status, _ in statuses],
    }


def play_checkin(client, case: dict, log: list) -> dict:
    start = case["start"]
    kind = start["kind"]
    body = {"kind": kind, "local_date": start["local_date"], "previous": {}}
    if kind == "quick":
        body["quick"] = {"topics": start["topics"], "activity_day": "yesterday"}
    state = _post(client, "/api/checkin/start", body, log)["state"]
    state["current_field"] = start["field"]
    state["skipped_fields"] = [f for f in state["skipped_fields"] if f != start["field"]]
    state["confirmed"] = {**state["confirmed"], **start["confirmed"]}
    state["pending"] = {**state["pending"], **start["pending"]}
    setup = {**start["confirmed"], **start["pending"]}
    messages, read_back = [], False
    for text in case["turns"]:
        body = {"action": "reply", "state": state, "text": text, "input_mode": "transcript"}
        result = _post(client, "/api/checkin/turn", body, log)
        messages.append(result["message"])
        state = result["state"]
        read_back = read_back or state["phase"] == "confirming"
        if kind == "weekly":
            for _ in range(4):
                if state["phase"] != "confirming":
                    break
                body = {"action": "confirm", "state": state}
                result = _post(client, "/api/checkin/turn", body, log)
                messages.append(result["message"])
                state = result["state"]
    checking = set(state.get("checking") or [])
    values = {}
    for part in ("early", "confirmed", "pending"):
        values.update({k: v for k, v in state[part].items() if v is not None and k not in checking})
    got = {k: v for k, v in values.items() if not (k in setup and same(v, setup[k]))}
    return {
        "got": got,
        "final": values,
        "unknown": state["unknown_fields"],
        "settled": set(values) | set(state["unknown_fields"]),
        "where": state["current_field"] if state["phase"] == "asking" else state["phase"],
        "messages": messages,
        "read_backs": [],
        "read_back": read_back or bool(got),
        "loop": False,
        "memory_consent": None,
        "llm": False,
        "statuses": [],
    }


# -- scoring --------------------------------------------------------------------------


def score_case(case: dict, run: dict) -> dict:
    expect, allow = case["expect"], case.get("allow", {})
    conflict = case.get("conflict")
    got = run["got"]
    wrong, missing, skip_fail, conflict_fail = [], [], [], []
    final = run["final"]  # an expected value may be one that was already held
    setup = {**case["start"].get("confirmed", {}), **case["start"].get("pending", {})}
    for field, want in expect.items():
        if field not in final:
            missing.append(f"missing {field}")
        elif not same(final[field], want):
            # The old answer left in place is a miss; WRONG is a value nobody said.
            kept = field in setup and same(final[field], setup[field])
            (missing if kept else wrong).append(f"{field}={final[field]} (want {want})")
    for field, value in got.items():
        if field in expect or (conflict and field == conflict["field"]):
            continue
        if field in allow and same(value, allow[field]):
            continue
        wrong.append(f"extra {field}={value}")
    for field in case.get("unknown", []):
        if field not in run["unknown"]:
            missing.append(f"{field} not unknown")
    for field in case.get("skip", []):
        if field not in run["settled"] or run["where"] == field:
            skip_fail.append(f"{field} will be asked again")
    if case.get("next") and run["where"] != case["next"]:
        missing.append(f"next {run['where']} (want {case['next']})")
    if case.get("confirm") and not conflict and not run["read_back"]:
        missing.append("no read-back")
    if "memory_consent" in case and run["memory_consent"] != case["memory_consent"]:
        wrong.append(f"memory_consent={run['memory_consent']}")
    if conflict:
        field, new = conflict["field"], conflict["new"]
        now = final.get(field)
        read_back = any(same(rb.get(field), new) for rb in run["read_backs"])
        said = any(re.search(conflict["mention"], m, re.I) for m in run["messages"])
        if same(now, new) and not read_back:
            wrong.append(f"{field} silently overwritten")
            conflict_fail.append(field)
        elif not (same(now, new) or same(now, conflict["old"])):
            wrong.append(f"{field}={now} after conflict")
            conflict_fail.append(field)
        elif not (read_back or said):
            conflict_fail.append(f"{field} conflict not surfaced")
    if (expect or conflict) and any(c in run["messages"][0].lower() for c in CAUGHT):
        missing.append("said it didn't catch that")
    if run["loop"]:
        missing.append("read-back loop")
    verdict = (
        "wrong" if wrong else "missing" if (missing or skip_fail or conflict_fail) else "correct"
    )
    return {
        "id": case["id"],
        "category": case["category"],
        "split": case["split"],
        "verdict": verdict,
        "why": wrong + missing + skip_fail + [f"conflict: {c}" for c in conflict_fail],
        "skip_fail": bool(skip_fail),
        "conflict_fail": bool(conflict_fail),
        "fields": len(expect),
        "fields_right": sum(f in final and same(final[f], w) for f, w in expect.items()),
        "wrong_values": len(wrong),
        "llm": run["llm"],
        "unavailable": run["statuses"].count("unavailable"),
        "say": case["turns"][-1],
        "messages": run["messages"],
    }


def run_case(local, case: dict, mode: str, provider: bool, app, turn_log: list) -> dict:
    if not hasattr(local, "client"):
        local.client = TestClient(app)
    log: list[float] = []
    try:
        if case["flow"] == "onboarding":
            run = play_onboarding(local.client, case, CONSENT[mode], log)
        else:
            run = play_checkin(local.client, case, log)
    except Exception as exc:  # noqa: BLE001 - a crash is a reported result, not a stop
        result = {"id": case["id"], "category": case["category"], "split": case["split"]}
        return {**result, "verdict": "missing", "why": [f"crash {type(exc).__name__}: {exc}"],
                "skip_fail": False, "conflict_fail": False, "fields": len(case["expect"]),
                "fields_right": 0, "wrong_values": 0, "llm": False, "unavailable": 0,
                "say": case["turns"][-1], "crash": True}
    turn_log.extend(log)
    return score_case(case, run)


def evaluate(cases: list[dict], mode: str, provider: bool, workers: int = 1) -> dict:
    meter = Meter()
    app = build_app(provider, meter)
    local = threading.local()
    turn_log: list[float] = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(lambda c: run_case(local, c, mode, provider, app, turn_log), cases))
    return {"mode": mode, "results": results, "calls": meter.calls, "failed_calls": meter.failed,
            "call_seconds": meter.seconds, "turn_seconds": turn_log}


def tally(results: list[dict]) -> dict:
    return {
        "n": len(results),
        "correct": sum(r["verdict"] == "correct" for r in results),
        "missing": sum(r["verdict"] == "missing" for r in results),
        "wrong": sum(r["verdict"] == "wrong" for r in results),
        "skip_fail": sum(r["skip_fail"] for r in results),
        "conflict_fail": sum(r["conflict_fail"] for r in results),
        "fields": sum(r["fields"] for r in results),
        "fields_right": sum(r["fields_right"] for r in results),
        "wrong_values": sum(r["wrong_values"] for r in results),
    }


def pct(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(q * (len(ordered) - 1))))]


def report(run: dict, verbose: bool = False) -> None:
    results = run["results"]
    print(f"\n== mode {run['mode']} ==")
    print(f"{'split/category':34} {'n':>3} {'ok':>3} {'miss':>4} {'WRONG':>5} {'skip':>4} {'confl':>5}")
    for split in sorted({r["split"] for r in results}):
        rows = [r for r in results if r["split"] == split]
        for category in sorted({r["category"] for r in rows}):
            t = tally([r for r in rows if r["category"] == category])
            print(f"{split + '/' + category:34} {t['n']:>3} {t['correct']:>3} {t['missing']:>4} "
                  f"{t['wrong']:>5} {t['skip_fail']:>4} {t['conflict_fail']:>5}")
        t = tally(rows)
        print(f"{split + '/ALL':34} {t['n']:>3} {t['correct']:>3} {t['missing']:>4} {t['wrong']:>5} "
              f"{t['skip_fail']:>4} {t['conflict_fail']:>5}  fields {t['fields_right']}/{t['fields']}, "
              f"wrong values {t['wrong_values']}")
    if run["calls"]:
        calls, turns = run["call_seconds"], run["turn_seconds"]
        print(f"provider calls {run['calls']} (failed {run['failed_calls']}); call p50 "
              f"{statistics.median(calls):.2f}s p95 {pct(calls, 0.95):.2f}s; turn p50 "
              f"{statistics.median(turns):.2f}s p95 {pct(turns, 0.95):.2f}s; "
              f"llm-mode turns {sum(r['llm'] for r in results)}")
    if verbose:
        for r in results:
            if r["verdict"] != "correct":
                print(f"  {r['verdict'].upper():7} {r['id']:28} {r['say']!r}: {'; '.join(r['why'])}")
                if verbose > 1:
                    for message in r.get("messages", []):
                        print(f"            mochi: {message[:160]}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--split", default="dev", choices=["dev", "heldout", "all"])
    parser.add_argument("--mode", default="none", choices=["none", "muse", "both"])
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--only", default="", help="regex on case ids")
    parser.add_argument("--out", default="", help="write scores (no transcripts) as JSON")
    parser.add_argument("-v", action="count", default=0)
    args = parser.parse_args()
    cases = [c for c in load(args.split) if re.search(args.only, c["id"])]
    modes = ["muse", "none"] if args.mode == "both" else [args.mode]
    runs = []
    for mode in modes:
        run = evaluate(cases, mode, provider=True, workers=args.workers)
        report(run, args.v)
        runs.append(run)
    if args.out:
        for run in runs:
            for result in run["results"]:
                result.pop("messages", None)  # scores only, no transcripts
        Path(args.out).write_text(json.dumps(runs, indent=1))
    if "muse" in modes and not runs[0]["calls"]:
        print("note: no provider calls were made (is the provider configured?)", file=sys.stderr)


if __name__ == "__main__":
    main()
