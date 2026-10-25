"""Claude by Anthropic over the official SDK: one short, schema-constrained JSON reply.

Built for voice latency on Claude Haiku 5.5: thinking off (accepted at effort "low"), a
short ``max_tokens``, one attempt inside a ~6 s budget (no SDK retries, which would
multiply the wall-clock time). The stable system prompt carries a cache breakpoint.
Structured outputs (``output_config.format``) constrain the reply; the caller still
validates and grounds it. Sampling parameters and prefill are never sent (both 400 on
this model). Any failure raises ``ClaudeUnavailable``; only the error type or the stop
reason is logged, never the prompt, the person's words or the reply.
"""

import logging

import anthropic

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-haiku-5-5"
# JSON Schema keywords structured outputs does not accept; pydantic re-checks them locally.
_UNSUPPORTED = frozenset(
    {
        "minLength",
        "maxLength",
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "multipleOf",
        "minItems",
        "maxItems",
        "uniqueItems",
    }
)


class ClaudeUnavailable(Exception):
    """No usable reply; the caller falls back to its templates or local parser."""


def api_schema(schema: object) -> object:
    """The schema without unsupported keywords, every object closed (additionalProperties false)."""
    if isinstance(schema, list):
        return [api_schema(item) for item in schema]
    if not isinstance(schema, dict):
        return schema
    out = {}
    for key, value in schema.items():
        if key in _UNSUPPORTED:
            continue
        if key in {"properties", "$defs"} and isinstance(value, dict):
            # Property and definition names are data, not keywords: keep every one.
            out[key] = {name: api_schema(sub) for name, sub in value.items()}
        else:
            out[key] = api_schema(value)
    if out.get("type") == "object":
        out["additionalProperties"] = False
    return out


class ClaudeJSON:
    def __init__(
        self,
        *,
        api_key: str = "",
        model: str = DEFAULT_MODEL,
        timeout_seconds: float = 6,
        max_tokens: int = 800,
        client: anthropic.AsyncAnthropic | None = None,
    ):
        self._api_key = api_key.strip()
        self._model = model.strip()
        # Voice callers pass ~6 s; reading a whole PDF needs up to ~25 s.
        self._timeout = max(0.1, min(timeout_seconds, 30.0))
        self._max_tokens = max_tokens
        self._client = client

    @property
    def configured(self) -> bool:
        return bool(self._api_key and self._model)

    def request(self, system: str, user: str | list[dict], schema: dict) -> dict:
        """The Messages API arguments (kept separate so tests can check the shape).

        ``user`` is plain text, or content blocks (a PDF ``document`` block, then text).
        """
        return {
            "model": self._model,
            "max_tokens": self._max_tokens,
            # The stable instructions first, with a cache breakpoint; the data comes after.
            "system": [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            "messages": [{"role": "user", "content": user}],
            "thinking": {"type": "disabled"},
            "output_config": {
                "effort": "low",
                "format": {"type": "json_schema", "schema": api_schema(schema)},
            },
        }

    async def complete(self, system: str, user: str | list[dict], schema: dict) -> str:
        """The reply's JSON text, or ClaudeUnavailable."""
        if not self.configured:
            raise ClaudeUnavailable()
        if self._client is None:
            # Only ever built with an explicit key: never the SDK's ambient credentials.
            self._client = anthropic.AsyncAnthropic(
                api_key=self._api_key, timeout=self._timeout, max_retries=0
            )
        try:
            message = await self._client.messages.create(**self.request(system, user, schema))
        except anthropic.APIError as exc:  # status, connection and timeout errors
            logger.warning("claude request failed: %s", type(exc).__name__)
            raise ClaudeUnavailable() from exc
        try:
            stop_reason = message.stop_reason
            # refusal, max_tokens (cut-off JSON) or anything unexpected: never used.
            if stop_reason != "end_turn":
                logger.warning("claude reply not used: %s", stop_reason)
                raise ClaudeUnavailable()
            texts = [block.text for block in message.content if block.type == "text"]
        except (AttributeError, TypeError) as exc:
            logger.warning("claude reply not used: %s", type(exc).__name__)
            raise ClaudeUnavailable() from exc
        if len(texts) != 1 or not isinstance(texts[0], str):
            raise ClaudeUnavailable()
        return texts[0]
