"""Healthy habits with Mochi: stateless; the phone stores the habit records."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from lifetwin.habits.models import (
    HabitProposeRequest,
    HabitProposeResponse,
    HabitQuestionRequest,
    HabitQuestionResponse,
    HabitUpdateRequest,
    HabitUpdateResponse,
    HabitWeekRequest,
    HabitWeekResponse,
)
from lifetwin.habits.service import HabitService

router = APIRouter(prefix="/habits", tags=["habits"])
_service = HabitService()


def get_service(request: Request) -> HabitService:
    return getattr(request.app.state, "habit_service", _service)


Service = Annotated[HabitService, Depends(get_service)]


@router.post("/propose", response_model=HabitProposeResponse)
def habits_propose(request: HabitProposeRequest, service: Service) -> HabitProposeResponse:
    return service.propose(request)


@router.post("/update", response_model=HabitUpdateResponse)
def habits_update(request: HabitUpdateRequest, service: Service) -> HabitUpdateResponse:
    return service.update(request)


@router.post("/question", response_model=HabitQuestionResponse)
def habits_question(request: HabitQuestionRequest, service: Service) -> HabitQuestionResponse:
    return service.question(request)


@router.post("/week", response_model=HabitWeekResponse)
def habits_week(request: HabitWeekRequest, service: Service) -> HabitWeekResponse:
    return service.week(request)


__all__ = ["HabitService", "router"]
