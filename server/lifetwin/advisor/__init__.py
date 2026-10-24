"""Cited educational advisor endpoint; no model-backed personalization yet."""

from fastapi import APIRouter, Request

from lifetwin.advisor.models import AdvisorRequest, AdvisorResponse
from lifetwin.advisor.service import build_plan

router = APIRouter(tags=["advisor"])


@router.post("/advisor", response_model=AdvisorResponse)
async def advisor(payload: AdvisorRequest, request: Request) -> AdvisorResponse:
    return await build_plan(payload, getattr(request.app.state, "research_client", None))
