"""Voice token contracts; the Cartesia API key never appears in any model."""

from typing import Literal

from pydantic import Field

from lifetwin.core.models import SCHEMA_VERSION, ApiModel


class VoiceTokenRequest(ApiModel):
    # Only an explicit true is accepted; false or missing is rejected as 422.
    voice_consent: Literal[True]


class SttSettings(ApiModel):
    model: str
    encoding: Literal["pcm_s16le"] = "pcm_s16le"
    sample_rate: Literal[16000] = 16000
    url: str = "wss://api.cartesia.ai/stt/websocket"


class TtsSettings(ApiModel):
    model: str
    voice_id: str
    encoding: Literal["pcm_s16le"] = "pcm_s16le"
    sample_rate: Literal[24000] = 24000
    speed: float = Field(ge=0.6, le=1.5)
    emotion: Literal["calm"] = "calm"
    url: str = "wss://api.cartesia.ai/tts/websocket"


class VoiceTokenResponse(ApiModel):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    token: str
    expires_in: int = Field(ge=60, le=900)
    cartesia_version: str
    stt: SttSettings
    tts: TtsSettings
