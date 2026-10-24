"""Mint short-lived Cartesia access tokens so the phone never sees the API key."""

import logging

import httpx

from lifetwin.core.config import Settings
from lifetwin.core.models import ApiError
from lifetwin.voice.models import SttSettings, TtsSettings, VoiceTokenResponse

logger = logging.getLogger("lifetwin.voice")

TOKEN_URL = "https://api.cartesia.ai/access-token"
UNAVAILABLE_MESSAGE = "Voice isn't available right now. You can keep going by typing."


class VoiceUnavailable(Exception):
    """Voice cannot be offered; carries no provider detail by design."""

    def error(self, request_id: str | None) -> ApiError:
        return ApiError(
            code="voice_unavailable", message=UNAVAILABLE_MESSAGE, request_id=request_id
        )


def voice_configured(settings: Settings) -> bool:
    return bool(
        settings.cartesia_api_key.get_secret_value().strip() and settings.cartesia_voice_id.strip()
    )


class VoiceService:
    def __init__(
        self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def mint_token(self) -> VoiceTokenResponse:
        s = self._settings
        if not voice_configured(s):
            raise VoiceUnavailable
        try:
            async with httpx.AsyncClient(
                timeout=s.provider_timeout_seconds, transport=self._transport, trust_env=False
            ) as client:
                response = await client.post(
                    TOKEN_URL,
                    headers={
                        "Authorization": f"Bearer {s.cartesia_api_key.get_secret_value()}",
                        "Cartesia-Version": s.cartesia_version,
                    },
                    json={
                        "grants": {"tts": True, "stt": True},
                        "expires_in": s.cartesia_token_ttl_seconds,
                    },
                )
            response.raise_for_status()
            token = response.json()["token"]
            if not isinstance(token, str) or not token:
                raise ValueError("empty token")
        except Exception as exc:
            # Log only the exception type: messages and bodies may echo secrets.
            logger.warning("Cartesia token request failed: %s", type(exc).__name__)
            raise VoiceUnavailable from None
        return VoiceTokenResponse(
            token=token,
            expires_in=s.cartesia_token_ttl_seconds,
            cartesia_version=s.cartesia_version,
            stt=SttSettings(model=s.cartesia_stt_model),
            tts=TtsSettings(
                model=s.cartesia_tts_model,
                voice_id=s.cartesia_voice_id,
                speed=s.cartesia_tts_speed,
            ),
        )
