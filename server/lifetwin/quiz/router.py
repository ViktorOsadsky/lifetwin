"""Quiz delivery only; Flutter owns immediate deterministic local scoring."""

from typing import Annotated

from fastapi import APIRouter, HTTPException, Path, Query

from lifetwin.core.models import ApiError
from lifetwin.quiz.models import QuizBankResponse, QuizDifficulty, QuizQuestion, QuizTopic
from lifetwin.quiz.service import load_bank

router = APIRouter(prefix="/quiz", tags=["quiz"])


@router.get("/questions", response_model=QuizBankResponse)
def questions(
    topic: QuizTopic | None = None,
    difficulty: QuizDifficulty | None = None,
    limit: Annotated[int, Query(ge=1, le=20)] = 20,
) -> QuizBankResponse:
    """Answers are intentionally included for local/offline educational play."""
    bank = load_bank()
    matches = [
        question
        for question in bank.questions
        if (topic is None or question.topic == topic)
        and (difficulty is None or question.difficulty == difficulty)
    ]
    return QuizBankResponse(
        bank_version=bank.bank_version,
        local_scoring=bank.local_scoring,
        total=len(matches),
        questions=matches[:limit],
    )


@router.get("/questions/{question_id}", response_model=QuizQuestion)
def question_detail(
    question_id: Annotated[
        str, Path(min_length=6, max_length=66, pattern=r"^[a-z][a-z0-9-]{2,60}\.v[1-9][0-9]{0,2}$")
    ],
) -> QuizQuestion:
    for question in load_bank().questions:
        if question.id == question_id:
            return question
    raise HTTPException(
        status_code=404,
        detail=ApiError(
            code="quiz_question_not_found", message="Quiz question not found."
        ).model_dump(),
    )
