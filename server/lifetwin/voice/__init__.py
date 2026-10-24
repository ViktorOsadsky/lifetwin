"""Cartesia voice token endpoint; audio goes phone-to-Cartesia, never through this server."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from lifetwin.voice.models import VoiceTokenRequest, VoiceTokenResponse
from lifetwin.voice.service import VoiceService, VoiceUnavailable, voice_configured

router = APIRouter(tags=["voice"])


def get_service(request: Request) -> VoiceService:
    return request.app.state.voice_service


@router.post("/voice/token", response_model=VoiceTokenResponse)
async def voice_token(
    payload: VoiceTokenRequest,
    request: Request,
    service: Annotated[VoiceService, Depends(get_service)],
) -> VoiceTokenResponse:
    try:
        result = await service.mint_token()
    except VoiceUnavailable as exc:
        error = exc.error(getattr(request.state, "request_id", None))
        raise HTTPException(503, detail=error.model_dump()) from None
    # The request-budget middleware adds Cache-Control: no-store to every response.
    return result


__all__ = ["VoiceService", "VoiceTokenRequest", "VoiceTokenResponse", "router", "voice_configured"]
