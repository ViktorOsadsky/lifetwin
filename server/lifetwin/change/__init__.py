"""Change a saved answer by talking it through with Mochi: stateless, read back first.

The app has no edit fields for saved answers (owner ruling). Apart from onboarding,
check-ins, an Apple Health import with read-back and "Delete my data", this is the
only way a saved answer changes. Experiment levers never call it: they change only
the experimental copy of the profile.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from lifetwin.change.models import (
    ChangeResponse,
    ChangeStartRequest,
    ChangeState,
    ChangeTurnRequest,
)
from lifetwin.change.service import ChangeService

router = APIRouter(tags=["change"])
_service = ChangeService()


def get_service(request: Request) -> ChangeService:
    return getattr(request.app.state, "change_service", _service)


@router.post("/change/start", response_model=ChangeResponse)
def change_start(
    request: ChangeStartRequest,
    service: Annotated[ChangeService, Depends(get_service)],
) -> ChangeResponse:
    return service.start(request)


@router.post("/change/turn", response_model=ChangeResponse)
def change_turn(
    request: ChangeTurnRequest,
    service: Annotated[ChangeService, Depends(get_service)],
) -> ChangeResponse:
    return service.turn(request)


__all__ = [
    "ChangeResponse",
    "ChangeService",
    "ChangeStartRequest",
    "ChangeState",
    "ChangeTurnRequest",
    "router",
]
