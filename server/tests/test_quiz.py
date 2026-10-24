"""Quiz content coherence, bounded delivery, and isolation from clinical state."""

import json
from copy import deepcopy

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

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
    assert bank.total == len(bank.questions) == 8
    assert {q.topic for q in bank.questions} == {"food_safety", "nutrition", "activity"}
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
    assert payload["total"] == 8
    assert len(payload["questions"]) == 8
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
    assert payload["total"] == 2
    assert len(payload["questions"]) == 1
    assert payload["questions"][0]["topic"] == "nutrition"
    assert payload["questions"][0]["difficulty"] == "challenging"
    empty = client.get("/api/quiz/questions?topic=activity&difficulty=moderate").json()
    assert empty["total"] == 1
    assert len(empty["questions"]) == 1


@pytest.mark.parametrize(
    "query", ["limit=0", "limit=21", "limit=bad", "topic=medical", "difficulty=easy"]
)
def test_invalid_filters_rejected(client, query):
    assert client.get("/api/quiz/questions?" + query).status_code == 422


def test_detail_unknown_version_and_invalid_id(client):
    question = load_bank().questions[0]
    response = client.get("/api/quiz/questions/" + question.id)
    assert response.status_code == 200
    assert response.json() == question.model_dump(mode="json")
    assert client.get("/api/quiz/questions/missing-question.v1").status_code == 404
    assert client.get("/api/quiz/questions/" + question.id.replace(".v1", ".v2")).status_code == 404
    assert client.get("/api/quiz/questions/invalid").status_code == 422


def test_bank_copy_cannot_change_future_delivery():
    bank = load_bank()
    bank.questions.clear()
    assert len(load_bank().questions) == 8


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
    assert load_bank().total == 8
