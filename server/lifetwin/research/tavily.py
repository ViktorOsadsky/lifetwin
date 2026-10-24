"""Bounded Tavily extract of reviewed pages, with no raw-profile or arbitrary-URL input.

API reference: https://docs.tavily.com/documentation/api-reference/endpoint/extract.
The reviewed URLs are fixed, so no search step is needed: one extract call checks
that those pages are reachable. Retrieval is not evidence validation and cannot
rewrite the reviewed educational plan.
"""

import asyncio
import json
from urllib.parse import urlsplit

import httpx

from lifetwin.research.models import ResearchResult, ResearchStatus, ResearchTopic
from lifetwin.research.sources import SOURCES, curated_sources

MAX_TOPICS = 3
MAX_PAGES = 5
MAX_RESPONSE_BYTES = 256_000
MAX_PAGE_CHARS = 40_000
ALLOWED_HOSTS = frozenset({"www.cdc.gov", "www.niddk.nih.gov", "ods.od.nih.gov"})

REVIEWED_NOTE = "Your tips still come from health websites our team already reviewed."
LIMITATIONS: dict[ResearchStatus, str] = {
    "not_requested": f"We did not go online for this plan. {REVIEWED_NOTE}",
    "unconfigured": f"Website checking is not set up, so we did not go online. {REVIEWED_NOTE}",
    "unavailable": f"We could not check the websites right now. {REVIEWED_NOTE}",
    "partial": f"We could check only some of the health websites right now. {REVIEWED_NOTE}",
    "retrieved": "We checked that the health websites are online. The tips themselves were "
    "already reviewed by our team.",
}


class _InvalidProviderResponse(Exception):
    """Internal marker only; provider content must not appear in error output."""


def _page_key(value: object) -> str | None:
    """Compare page URLs while tolerating a trailing slash or index.html suffix."""
    if not isinstance(value, str) or len(value) > 500:
        return None
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError:
        return None
    if (
        parsed.scheme != "https"
        or parsed.hostname not in ALLOWED_HOSTS
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.query
        or parsed.fragment
    ):
        return None
    path = parsed.path.removesuffix("/index.html").removesuffix("/")
    return f"{parsed.hostname}{path}"


class TavilyResearch:
    def __init__(
        self,
        api_key: str = "",
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        timeout_seconds: float = 4.0,
        total_timeout_seconds: float = 12.0,
    ) -> None:
        self._api_key = api_key.strip()
        self._transport = transport
        # Server-side ceilings cannot be expanded by a client request.
        self._timeout = min(max(timeout_seconds, 0.01), 6.0)
        self._total_timeout = min(max(total_timeout_seconds, 0.01), 15.0)

    async def _post(self, client: httpx.AsyncClient, path: str, body: dict) -> dict:
        # Only these fixed HTTPS API paths are called, with redirects disabled.
        async with client.stream("POST", path, json=body) as response:
            response.raise_for_status()
            data = bytearray()
            async for chunk in response.aiter_bytes():
                if len(data) + len(chunk) > MAX_RESPONSE_BYTES:
                    raise _InvalidProviderResponse
                data.extend(chunk)
        try:
            payload = json.loads(data)
        except (ValueError, RecursionError):
            raise _InvalidProviderResponse from None
        if not isinstance(payload, dict):
            raise _InvalidProviderResponse
        return payload

    async def research(self, topics: list[ResearchTopic]) -> ResearchResult:
        if not topics or len(topics) > MAX_TOPICS or len(set(topics)) != len(topics):
            raise ValueError("Research requires one to three distinct reviewed topics.")
        if any(topic not in SOURCES for topic in topics):
            raise ValueError("Only reviewed research topics are supported.")
        sources = curated_sources(topics)
        if not self._api_key:
            return ResearchResult(
                status="unconfigured", sources=sources, limitation=LIMITATIONS["unconfigured"]
            )

        # Only the fixed reviewed page URLs leave the server: no query text at all.
        urls = [source.url for source in sources]
        source_by_key = {_page_key(source.url): source.id for source in sources}
        found: set[str] = set()
        try:
            async with asyncio.timeout(self._total_timeout):
                async with httpx.AsyncClient(
                    base_url="https://api.tavily.com",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    timeout=self._timeout,
                    follow_redirects=False,
                    trust_env=False,
                    transport=self._transport,
                ) as client:
                    extracted = await self._post(
                        client,
                        "/extract",
                        {
                            "urls": urls,
                            "extract_depth": "basic",
                            "format": "text",
                            "include_images": False,
                        },
                    )
            rows = extracted.get("results")
            failed_rows = extracted.get("failed_results", [])
            if (
                not isinstance(rows, list)
                or len(rows) > MAX_PAGES
                or not isinstance(failed_rows, list)
                or len(failed_rows) > MAX_PAGES
            ):
                raise _InvalidProviderResponse
            failed_keys = {
                _page_key(row.get("url")) for row in failed_rows if isinstance(row, dict)
            }
            for row in rows:
                if not isinstance(row, dict):
                    raise _InvalidProviderResponse
                key = _page_key(row.get("url"))
                content = row.get("raw_content")
                # Content is deliberately discarded, never interpolated into
                # prompts, returned to clients, logged, or used as instructions.
                if (
                    key in source_by_key
                    and key not in failed_keys
                    and isinstance(content, str)
                    and 20 <= len(content.strip()) <= MAX_PAGE_CHARS
                ):
                    found.add(source_by_key[key])
        except (httpx.HTTPError, TimeoutError, _InvalidProviderResponse):
            # No provider exception strings, keys, response bodies, or URLs in logs.
            found = set()

        retrieved = [source.id for source in sources if source.id in found]
        status: ResearchStatus = "retrieved" if len(retrieved) == len(sources) else "partial"
        if not retrieved:
            status = "unavailable"
        return ResearchResult(
            status=status,
            sources=sources,
            retrieved_source_ids=retrieved,
            page_count=len(urls),
            limitation=LIMITATIONS[status],
        )
