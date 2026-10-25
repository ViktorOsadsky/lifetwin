"""Answers given to the wrong question, offline (no consent, no provider): never a wrong
value, and what works keeps working. The Muse comparison is tests/cross_answer_eval.py."""

import pytest
from cross_answer_eval import evaluate, load, tally

FLOOR = {"dev": 95, "heldout": 0}


@pytest.mark.parametrize("split", ["dev", "heldout"])
def test_cross_answers_never_record_a_wrong_value(split):
    run = evaluate(load(split), "none", provider=False, workers=1)
    results = run["results"]
    totals = tally(results)
    not_right = [(r["id"], r["why"]) for r in results if r["verdict"] != "correct"]
    assert totals["wrong"] == 0, [r["why"] for r in results if r["verdict"] == "wrong"]
    assert not any(r.get("crash") for r in results), not_right
    assert totals["correct"] >= FLOOR[split], not_right
