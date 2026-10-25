"""POST /api/recommendations: the client sends the profile and habit notes; nothing is kept."""

from fastapi import APIRouter, Request

from lifetwin.recommendations.models import RecommendationRequest, RecommendationResponse
from lifetwin.recommendations.service import recommend

router = APIRouter(tags=["recommendations"])


@router.post("/recommendations", response_model=RecommendationResponse)
async def recommendations(
    payload: RecommendationRequest, request: Request
) -> RecommendationResponse:
    # Never log the profile or the notes.
    return await recommend(payload, getattr(request.app.state, "personalizer", None))
