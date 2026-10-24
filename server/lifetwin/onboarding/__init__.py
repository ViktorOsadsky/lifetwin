"""Mascot conversation boundary with replaceable optional extraction."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from lifetwin.onboarding.models import ConversationState, TurnRequest, TurnResponse
from lifetwin.onboarding.providers import ChatCompletionsExtractor, OpenAIExtractor
from lifetwin.onboarding.service import ConversationService

router = APIRouter(tags=["onboarding"])
_guided_service = ConversationService()


def get_service(request: Request) -> ConversationService:
    return getattr(request.app.state, "conversation_service", _guided_service)


@router.post("/onboarding/turn", response_model=TurnResponse)
async def conversation_turn(
    request: TurnRequest,
    service: Annotated[ConversationService, Depends(get_service)],
) -> TurnResponse:
    return await service.turn(request)


__all__ = [
    "ChatCompletionsExtractor",
    "ConversationService",
    "ConversationState",
    "OpenAIExtractor",
    "TurnRequest",
    "TurnResponse",
    "router",
]
