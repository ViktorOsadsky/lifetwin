"""Outside-AI providers that may phrase Mochi's lines. They never decide values.

Owner rulings (2026-10-24): Muse by Meta is the demo provider now; Claude by Anthropic
comes later behind the same interface (``PERSONALIZE_PROVIDER=claude``). Consent is
per provider, so switching providers asks the person again. Keys stay server-side.
Payloads and replies are never logged.
"""

import json
import logging
from typing import Literal, Protocol

import httpx

logger = logging.getLogger(__name__)

ProviderName = Literal["muse", "claude"]
DISPLAY_NAMES: dict[ProviderName, str] = {
    "muse": "Muse by Meta",
    "claude": "Claude by Anthropic",
}


class PhrasingUnavailable(Exception):
    """The provider could not answer; Mochi's own wording is used."""


class Personalizer(Protocol):
    name: ProviderName

    @property
    def configured(self) -> bool: ...

    async def phrase(self, instructions: str, facts: dict) -> dict: ...


class MusePersonalizer:
    """Meta Muse over its OpenAI-compatible Chat Completions endpoint."""

    name: ProviderName = "muse"

    def __init__(
        self,
        *,
        base_url: str = "",
        api_key: str = "",
        model: str = "",
        timeout_seconds: float = 8,
        reasoning_effort: str = "minimal",
        client: httpx.AsyncClient | None = None,
    ):
        self._base_url = (base_url.strip() or "https://api.meta.ai/v1").rstrip("/")
        self._api_key = api_key.strip()
        self._model = model.strip()
        self._timeout = max(0.1, min(timeout_seconds, 15.0))
        self._effort = reasoning_effort.strip()
        self._client = client

    @property
    def configured(self) -> bool:
        return bool(self._api_key and self._model)

    async def phrase(self, instructions: str, facts: dict) -> dict:
        if not self.configured:
            raise PhrasingUnavailable()
        payload = {
            "model": self._model,
            "max_tokens": 1200,
            "messages": [
                {"role": "system", "content": instructions},
                {"role": "user", "content": json.dumps(facts, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        if self._effort:
            payload["reasoning_effort"] = self._effort
        client = self._client or httpx.AsyncClient(follow_redirects=False, trust_env=False)
        try:
            response = await client.post(
                f"{self._base_url}/chat/completions",
                json=payload,
                headers={"Authorization": f"Bearer {self._api_key}"},
                timeout=self._timeout,
            )
            response.raise_for_status()
            if len(response.content) > 65536:
                raise PhrasingUnavailable()
            choice = response.json()["choices"][0]
            content = choice["message"]["content"]
            if choice.get("finish_reason") != "stop" or not isinstance(content, str):
                raise PhrasingUnavailable()
            result = json.loads(content)
            if not isinstance(result, dict):
                raise PhrasingUnavailable()
            return result
        except (httpx.HTTPError, ValueError, KeyError, TypeError, IndexError) as exc:
            # Only the type: never the payload or the reply.
            logger.warning("phrasing provider failed: %s", type(exc).__name__)
            raise PhrasingUnavailable() from exc
        finally:
            if self._client is None:
                await client.aclose()


class ClaudePersonalizer:
    """Claude by Anthropic: a placeholder until the owner switches it on (not wired yet)."""

    name: ProviderName = "claude"

    def __init__(self, *, api_key: str = "", model: str = ""):
        self._api_key = api_key.strip()
        self._model = model.strip()

    @property
    def configured(self) -> bool:
        # Not implemented yet: never reports ready, so templates are used.
        return False

    async def phrase(self, instructions: str, facts: dict) -> dict:
        raise PhrasingUnavailable()
