"""Daily and weekly check-ins with Mochi: stateless, read back, nothing stored."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from lifetwin.checkin.models import (
    CheckinResponse,
    CheckinStartRequest,
    CheckinState,
    CheckinTurnRequest,
)
from lifetwin.checkin.service import CheckinService

router = APIRouter(tags=["checkin"])
_service = CheckinService()


def get_service(request: Request) -> CheckinService:
    return getattr(request.app.state, "checkin_service", _service)


@router.post("/checkin/start", response_model=CheckinResponse)
def checkin_start(
    request: CheckinStartRequest,
    service: Annotated[CheckinService, Depends(get_service)],
) -> CheckinResponse:
    return service.start(request)


@router.post("/checkin/turn", response_model=CheckinResponse)
async def checkin_turn(
    request: CheckinTurnRequest,
    service: Annotated[CheckinService, Depends(get_service)],
) -> CheckinResponse:
    return await service.aturn(request)


__all__ = [
    "CheckinResponse",
    "CheckinService",
    "CheckinStartRequest",
    "CheckinState",
    "CheckinTurnRequest",
    "router",
]
