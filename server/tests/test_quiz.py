"""Quiz content coherence, bounded delivery, and isolation from clinical state."""

import json
from copy import deepcopy
from datetime import date
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from lifetwin.quiz import router as quiz_router
from lifetwin.quiz.models import QuizBankResponse
from lifetwin.quiz.router import router
from lifetwin.quiz.service import load_bank, parse_bank_json


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(router, prefix="/api")
    with TestClient(app) as test_client:
        yield test_client


def bank_data():
    return load_bank().model_dump(mode="json")


def test_reviewed_bank_has_sources_and_complete_recovery():
    bank = load_bank()
    assert bank.total == len(bank.questions) == 38
    assert {q.topic for q in bank.questions} == {
        "food_safety",
        "nutrition",
        "activity",
        "sleep",
        "habits",
    }
    for question in bank.questions:
        assert question.review_status == "reviewed"
        assert question.sources
        assert question.correct_option_id in {o.id for o in question.options}
        assert question.wrong_effect.game_health_delta == -5
        assert question.wrong_effect.mascot_event == "quiz_sick"
        assert question.review_effect.game_health_delta == 5
        assert question.review_effect.mascot_event == "quiz_recovering"
        assert question.review_effect.reduced_motion_text


def test_endpoint_delivers_local_answer_metadata_and_isolation_rules(client):
    response = client.get("/api/quiz/questions")
    assert response.status_code == 200
    payload = response.json()
    assert payload["total"] == 38
    assert len(payload["questions"]) == 20
    rules = payload["local_scoring"]
    assert rules["state_scope"] == "game_health_only"
    assert rules["affects_confirmed_profile"] is False
    assert rules["affects_prediction"] is False
    assert rules["score_once_per_question_version"] is True
    assert rules["review_once_after_wrong_answer"] is True
    assert rules["retry_after_review_is_unscored"] is True
    assert rules["network_failure_is_unscored"] is True
    assert rules["clamp_after_each_effect"] is True
    assert "correct_option_id" in payload["questions"][0]
    assert client.post("/api/quiz/questions", json={"answer": "a"}).status_code == 405
    assert client.get("/api/quiz/questions").json() == payload


def test_filter_limit_and_empty_matches(client):
    payload = client.get(
        "/api/quiz/questions?topic=nutrition&difficulty=challenging&limit=1"
    ).json()
    assert payload["total"] == 4
    assert len(payload["questions"]) == 1
    assert payload["questions"][0]["topic"] == "nutrition"
    assert payload["questions"][0]["difficulty"] == "challenging"
    empty = client.get("/api/quiz/questions?topic=activity&difficulty=moderate").json()
    assert empty["total"] == 6
    assert len(empty["questions"]) == 6


@pytest.mark.parametrize(
    "query", ["limit=0", "limit=101", "limit=bad", "topic=medical", "difficulty=easy"]
)
def test_invalid_filters_rejected(client, query):
    assert client.get("/api/quiz/questions?" + query).status_code == 422


def test_detail_unknown_version_and_invalid_id(client):
    question = load_bank().questions[0]
    response = client.get("/api/quiz/questions/" + question.id)
    assert response.status_code == 200
    assert response.json() == question.model_dump(mode="json")
    assert client.get("/api/quiz/questions/missing-question.v1").status_code == 404
    missing_version = question.id.rsplit(".v", 1)[0] + ".v99"
    assert client.get("/api/quiz/questions/" + missing_version).status_code == 404
    assert client.get("/api/quiz/questions/invalid").status_code == 422


def test_bank_copy_cannot_change_future_delivery():
    bank = load_bank()
    bank.questions.clear()
    assert len(load_bank().questions) == 38


@pytest.mark.parametrize(
    "mutation",
    [
        lambda b: b["questions"].append(deepcopy(b["questions"][0])),
        lambda b: b["questions"][0]["options"][1].update(id="a"),
        lambda b: b["questions"][0]["options"][1].update(
            text=b["questions"][0]["options"][0]["text"]
        ),
        lambda b: b["questions"][0].update(correct_option_id="d"),
        lambda b: b["questions"][0].update(sources=[]),
        lambda b: b["questions"][0]["sources"][0].update(url="https://example.com/fake"),
        lambda b: b["questions"][0]["sources"][0].update(publisher="CDC"),
        lambda b: b["questions"][0]["sources"][0].update(accessed_on="2026-10-24"),
        lambda b: b["questions"][0]["wrong_effect"].update(game_health_delta=-11),
        lambda b: b["questions"][0]["wrong_effect"].update(game_health_delta=5),
        lambda b: b["questions"][0]["review_effect"].update(game_health_delta=1),
        lambda b: b["questions"][0].update(review_status="draft"),
        lambda b: b["questions"][0].update(prediction={"value": 42}),
        lambda b: b.update(total=99),
        lambda b: b.update(questions=[], total=0),
    ],
)
def test_rejects_malformed_or_unsafe_bank(mutation):
    data = bank_data()
    mutation(data)
    with pytest.raises((ValidationError, ValueError)):
        parse_bank_json(json.dumps(data))


def test_resource_loading_independent_of_working_directory(monkeypatch, tmp_path):
    from lifetwin.quiz.service import _bundled_bank

    _bundled_bank.cache_clear()
    monkeypatch.chdir(tmp_path)
    assert load_bank().total == 38


def test_every_question_can_be_listed_when_bank_exceeds_twenty(client, monkeypatch):
    base = load_bank()
    extra = [
        base.questions[0].model_copy(update={"id": f"extra-question-{index}.v1"})
        for index in range(25)
    ]
    big = QuizBankResponse(bank_version="9.0", total=len(extra), questions=extra)
    monkeypatch.setattr(quiz_router, "load_bank", lambda: big)
    payload = client.get("/api/quiz/questions?limit=100").json()
    assert payload["total"] == 25
    assert len(payload["questions"]) == 25


def test_correct_answers_are_spread_across_option_positions():
    bank = load_bank()
    positions = [q.correct_option_id for q in bank.questions]
    assert max(positions.count(p) for p in set(positions)) <= len(positions) / 2


def test_option_text_never_looks_like_an_answer_letter():
    for question in load_bank().questions:
        for option in question.options:
            assert not (
                len(option.text) > 1 and option.text[0] in "ABCD" and option.text[1] in ":)."
            ), option.text


def test_game_feedback_is_clearly_game_only_and_honest_at_full_health():
    for question in load_bank().questions:
        wrong = question.wrong_effect.reduced_motion_text
        assert "only a game" in wrong
        assert "real health has not changed" in wrong
        assert "game health" in wrong
        correct = question.correct_effect.reduced_motion_text
        # Game health starts at 100, so a correct answer must not promise a visible change.
        assert "below 100" in correct
        for effect in (question.wrong_effect, question.correct_effect, question.review_effect):
            assert str(abs(effect.game_health_delta)) in effect.reduced_motion_text


def test_older_adult_activity_question_covers_balance():
    question = next(q for q in load_bank().questions if q.id == "activity-missing-piece.v2")
    correct = next(o for o in question.options if o.id == question.correct_option_id)
    assert "balance" in correct.text
    assert "65" in question.scenario
    assert "older-adults" in question.sources[0].url


def test_chicken_explanation_states_not_to_wash():
    question = next(q for q in load_bank().questions if q.id.startswith("chicken-salad-prep."))
    assert "Do not wash raw chicken" in question.explanation
    assert "165 degrees F" in question.explanation


SCORING_CASES = Path(__file__).resolve().parents[1] / "content" / "quiz_scoring_cases.json"


def replay(case, bank):
    """Reference reducer for the client's local, game-health-only scoring rules."""
    rules = bank.local_scoring
    questions = {question.id: question for question in bank.questions}
    health = case["start_game_health"]
    answered, awaiting_review = set(), set()
    for step in case["steps"]:
        question = questions[step["question_id"]]
        effect = None
        if step["event"] == "answer" and question.id not in answered:
            answered.add(question.id)
            if step["option_id"] == question.correct_option_id:
                effect = question.correct_effect
            else:
                effect = question.wrong_effect
                awaiting_review.add(question.id)
        elif step["event"] == "review" and question.id in awaiting_review:
            awaiting_review.discard(question.id)
            effect = question.review_effect
        else:
            assert step["event"] in {"answer", "review", "network_failure"}
        if effect is not None:
            health += effect.game_health_delta
            health = min(max(health, rules.minimum_game_health), rules.maximum_game_health)
        yield {
            "game_health": health,
            "mascot_event": effect.mascot_event if effect else None,
            "scored": effect is not None,
        }


def test_scoring_vectors_match_reference_reducer():
    data = json.loads(SCORING_CASES.read_text(encoding="utf-8"))
    bank = load_bank()
    assert data["bank_version"] == bank.bank_version
    assert len(data["cases"]) >= 5
    for case in data["cases"]:
        expected = [step["expect"] for step in case["steps"]]
        assert list(replay(case, bank)) == expected, case["name"]


@pytest.mark.parametrize("topic", ["sleep", "habits"])
def test_sleep_and_habit_filters_deliver_both_difficulties(client, topic):
    response = client.get("/api/quiz/questions", params={"topic": topic})
    assert response.status_code == 200
    questions = response.json()["questions"]
    assert len(questions) == 7
    assert {q["topic"] for q in questions} == {topic}
    assert {q["difficulty"] for q in questions} == {"moderate", "challenging"}


@pytest.mark.parametrize("host", ["www.nhlbi.nih.gov", "www.nia.nih.gov"])
def test_nih_citations_require_an_exact_reviewed_institute_host(host):
    from lifetwin.quiz.models import QuizSource

    source = QuizSource(
        title="Reviewed NIH guidance",
        publisher="NIH",
        url=f"https://{host}/health/sleep",
        accessed_on=date(2026, 10, 24),
    )
    assert source.publisher == "NIH"
    for unsafe in [
        f"http://{host}/health/sleep",
        f"https://{host}.example.com/health/sleep",
        f"https://{host}/health/sleep?redirect=https://example.com",
        f"https://{host}/health/sleep#fragment",
        f"https://user@{host}/health/sleep",
        "https://unreviewed.nih.gov/health/sleep",
        "https://www.cdc.gov/sleep/about/index.html",
    ]:
        with pytest.raises(ValidationError):
            source.model_validate({**source.model_dump(), "url": unsafe})
    with pytest.raises(ValidationError):
        source.model_validate({**source.model_dump(), "publisher": "CDC"})


def test_expanded_bank_all_versions_are_reachable_without_changing_originals(client):
    questions = client.get("/api/quiz/questions?limit=100").json()["questions"]
    assert len(questions) == 38
    assert {q["id"] for q in questions} == {q.id for q in load_bank().questions}
    assert [q["id"] for q in questions[:8]] == [
        "soup-serving-check.v2",
        "sodium-label-decoder.v2",
        "yogurt-sugar-accounting.v2",
        "serving-size-meaning.v2",
        "small-activity-windows.v2",
        "activity-missing-piece.v2",
        "chicken-salad-prep.v2",
        "leftovers-next-step.v2",
    ]
    for question in questions[8:]:
        assert question["id"].endswith(".v1")
        detail = client.get("/api/quiz/questions/" + question["id"])
        assert detail.status_code == 200
        assert detail.json() == question
