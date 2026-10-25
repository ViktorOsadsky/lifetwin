"""Outside-AI providers that may phrase Mochi's lines. They never decide values.

Owner ruling (2026-10-25, "switch out to Claude API officially"): Claude by Anthropic
(Claude Haiku 5.5) is the provider; without ANTHROPIC_API_KEY it is unconfigured and
Mochi's own wording is used. Muse by Meta is an explicit opt-in only
(``PERSONALIZE_PROVIDER=muse``). Consent is per provider, so switching providers asks the
person again. Keys stay server-side. Payloads and replies are never logged.
"""

import json
import logging
from typing import Literal, Protocol

import httpx

from lifetwin.core.claude import DEFAULT_MODEL, ClaudeJSON, ClaudeUnavailable

logger = logging.getLogger(__name__)

ProviderName = Literal["muse", "claude"]
DISPLAY_NAMES: dict[ProviderName, str] = {
    "muse": "Muse by Meta",
    "claude": "Claude by Anthropic",
}
COMPANIES: dict[ProviderName, str] = {"muse": "Meta", "claude": "Anthropic"}


class PhrasingUnavailable(Exception):
    """The provider could not answer; Mochi's own wording is used."""


class Personalizer(Protocol):
    name: ProviderName

    @property
    def configured(self) -> bool: ...

    @property
    def may_train_on_content(self) -> bool: ...

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
        allow_contributor: bool = False,
        client: httpx.AsyncClient | None = None,
    ):
        self._allow_contributor = allow_contributor
        self._base_url = (base_url.strip() or "https://api.meta.ai/v1").rstrip("/")
        self._api_key = api_key.strip()
        self._model = model.strip()
        self._timeout = max(0.1, min(timeout_seconds, 15.0))
        self._effort = reasoning_effort.strip()
        self._client = client

    @property
    def configured(self) -> bool:
        # "-contributor" variants may train on content: only with the explicit opt-in.
        return bool(
            self._api_key
            and self._model
            and (self._allow_contributor or not self.may_train_on_content)
        )

    @property
    def may_train_on_content(self) -> bool:
        return "contributor" in self._model.lower()

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


# Every phrasing reply is {"lines": [...]} or {"line": "..."}; the instructions say which.
PHRASE_SCHEMA = {
    "type": "object",
    "properties": {
        "lines": {"type": "array", "items": {"type": "string"}},
        "line": {"type": "string"},
    },
    "additionalProperties": False,
}


class ClaudePersonalizer:
    """Claude by Anthropic over the official SDK (structured outputs, low latency).

    There is no contributor mode: LLM_ALLOW_CONTRIBUTOR does not apply.
    """

    name: ProviderName = "claude"
    may_train_on_content = False

    def __init__(
        self,
        *,
        api_key: str = "",
        model: str = DEFAULT_MODEL,
        timeout_seconds: float = 6,
        client=None,
    ):
        self._claude = ClaudeJSON(
            api_key=api_key, model=model, timeout_seconds=timeout_seconds, client=client
        )

    @property
    def configured(self) -> bool:
        return self._claude.configured

    async def phrase(self, instructions: str, facts: dict) -> dict:
        try:
            text = await self._claude.complete(
                instructions, json.dumps(facts, ensure_ascii=False), PHRASE_SCHEMA
            )
            result = json.loads(text)
        except (ClaudeUnavailable, ValueError, RecursionError) as exc:
            raise PhrasingUnavailable() from exc
        if not isinstance(result, dict):
            raise PhrasingUnavailable()
        return result
