"""POST /api/coach/plan: Mochi's daily plan. Stateless; the phone keeps the history."""

import logging

from fastapi import APIRouter, HTTPException, Request

import lifetwin.onboarding  # noqa: F401,I001  (first: lifetwin.coach.* alone hit an import cycle)
from lifetwin.coach.models import CoachPlanRequest, CoachPlanResponse
from lifetwin.coach.phrasing import DailyCap, reword
from lifetwin.coach.planner import Planner, StaleRevision, check_revision
from lifetwin.coach.safety import is_emergency
from lifetwin.core.models import ApiError
from lifetwin.onboarding.models import MascotEvent
from lifetwin.personalize.providers import Personalizer

logger = logging.getLogger("lifetwin.coach")
router = APIRouter(tags=["coach"])

MASCOT = {
    "happy": "celebrating",
    "proud": "celebrating",
    "celebrate": "celebrating",
    "cozy": "idle",
    "waiting": "idle",
    "concerned": "concerned",
}


async def plan(
    req: CoachPlanRequest,
    phraser: Personalizer | None,
    cap: DailyCap | None,
    client: str,
    timeout: float = 8,
) -> CoachPlanResponse:
    check_revision(req)
    try:
        result = Planner(req).run()
    except Exception as exc:  # a planner bug must give a safe general plan, never a 500
        logger.error("coach planner failed: %s", type(exc).__name__)
        result = Planner(
            CoachPlanRequest(
                local_date=req.local_date,
                said=req.said if is_emergency(req.said) else None,
                limits=req.limits,
                movement_paused=req.movement_paused
                or bool(req.previous_plan and all(i.id != "move" for i in req.previous_plan.items)),
            )
        ).run()
    items, lines = result.items, result.lines
    phrased_by, status = "templates", "not_requested"
    wanted = bool(req.outside_ai_consent.get(phraser.name)) if phraser else False
    if wanted and not result.provider_blocked and result.drafts and not result.reused_previous:
        if not phraser.configured:
            status = "not_configured"
        elif cap is not None and not cap.take(client):
            status = "daily_cap"
        else:
            reworded, status = await reword(phraser, result.drafts, timeout)
            if reworded:
                swap = {}
                new_items = []
                for item in items:
                    if item.id in reworded:
                        swap[item.message] = reworded[item.id]
                        item = item.model_copy(update={"message": reworded[item.id]})
                    new_items.append(item)
                items, lines = new_items, [swap.get(line, line) for line in lines]
                phrased_by = phraser.name
    # Counts only, never content.
    logger.info("coach plan: status=%s provider=%s", result.status, status)
    return CoachPlanResponse(
        status=result.status,
        revision_id=result.revision_id,
        based_on=result.based_on,
        local_date=req.local_date,
        inputs=result.inputs,
        plan_type=result.plan_type,
        reused_previous=result.reused_previous,
        clarify=result.clarify,
        alert=result.alert,
        notices=result.notices,
        lines=lines,
        reply=result.reply,
        items=items,
        changes=result.changes,
        trace=result.trace,
        mood=result.mood,
        mascot_events=[MascotEvent(state=MASCOT[result.mood], caption=lines[0])],
        emergency=result.emergency,
        movement_paused=result.movement_paused,
        memory_instruction=result.memory_instruction,
        phrased_by=phrased_by,
        provider_status=status,
    )


@router.post("/coach/plan", response_model=CoachPlanResponse)
async def coach_plan(payload: CoachPlanRequest, request: Request) -> CoachPlanResponse:
    # Never log the payload: it holds the profile, notes and the person's words.
    state = request.app.state
    try:
        return await plan(
            payload,
            getattr(state, "coach_phraser", None),
            getattr(state, "coach_cap", None),
            request.client.host if request.client else "unknown",
            getattr(state, "coach_timeout", 8),
        )
    except StaleRevision as exc:
        raise HTTPException(
            status_code=409,
            detail=ApiError(code="stale_revision", message=exc.message).model_dump(),
        ) from None


__all__ = ["DailyCap", "plan", "router"]
