"""The outside-AI phraser: Muse by Meta now, behind the same interface as
conversation-v2's ``lifetwin.personalize`` (``name``, ``configured``, ``phrase``), so
Claude can come later and the two modules can merge. Keys stay server-side; payloads
and replies are never logged.
"""

import json
import logging
from typing import Literal, Protocol

import httpx

logger = logging.getLogger("lifetwin.coach")

ProviderName = Literal["muse", "claude"]
DISPLAY_NAMES: dict[ProviderName, str] = {"muse": "Muse by Meta", "claude": "Claude by Anthropic"}


class PhrasingUnavailable(Exception):
    """The provider could not answer; Mochi's own wording is used."""


class Phraser(Protocol):
    name: ProviderName

    @property
    def configured(self) -> bool: ...

    async def phrase(self, instructions: str, facts: dict) -> dict: ...


class MusePhraser:
    """Muse over Meta's OpenAI-compatible Chat Completions endpoint (standard tier only)."""

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
        self.model = model.strip()
        self._timeout = max(0.1, min(timeout_seconds, 20.0))
        self._effort = reasoning_effort.strip()
        self._client = client

    @property
    def configured(self) -> bool:
        # "-contributor" variants may train on content (report §6a): never use them.
        return bool(self._api_key and self.model and "contributor" not in self.model.lower())

    async def phrase(self, instructions: str, facts: dict) -> dict:
        if not self.configured:
            raise PhrasingUnavailable()
        payload = {
            "model": self.model,
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
            logger.warning("coach phrasing provider failed: %s", type(exc).__name__)
            raise PhrasingUnavailable() from exc
        finally:
            if self._client is None:
                await client.aclose()
