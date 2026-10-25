"""Cut-off, split and multi-fact answers: never a wrong value, and the fixed ones stay fixed."""

import split_answers_eval


def test_split_answers_have_no_wrong_values_and_keep_what_works():
    result = split_answers_eval.score()
    assert result["wrong"] == 0
    assert result["correct"] >= 60, [r for r in result["results"] if r["verdict"] != "correct"]
