"""POST /api/recommendations: the client sends the profile and habit notes; nothing is kept."""

from fastapi import APIRouter

from lifetwin.recommendations.models import RecommendationRequest, RecommendationResponse
from lifetwin.recommendations.service import recommend

router = APIRouter(tags=["recommendations"])


@router.post("/recommendations", response_model=RecommendationResponse)
async def recommendations(request: RecommendationRequest) -> RecommendationResponse:
    # Never log the profile or the notes.
    return recommend(request)
