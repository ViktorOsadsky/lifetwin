"""Bounded Tavily search/extract, with no raw-profile or arbitrary-URL input.

API reference: https://docs.tavily.com/documentation/api-reference/endpoint/search
and /extract. Raw retrieval only confirms that a reviewed source was returned;
it is not evidence validation and cannot rewrite the reviewed educational plan.
"""

import asyncio
import json
from urllib.parse import urlsplit

import httpx

from lifetwin.research.models import ResearchResult, ResearchTopic
from lifetwin.research.sources import SOURCES, TOPIC_QUERIES, curated_sources

MAX_QUERIES = 3
MAX_PAGES = 5
MAX_RESPONSE_BYTES = 256_000
MAX_PAGE_CHARS = 40_000
ALLOWED_HOSTS = frozenset({"www.cdc.gov", "www.niddk.nih.gov", "ods.od.nih.gov"})


class _InvalidProviderResponse(Exception):
    """Internal marker only; provider content must not appear in error output."""


def _reviewed_url(value: object, permitted: set[str]) -> str | None:
    if not isinstance(value, str) or value not in permitted:
        return None
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.hostname not in ALLOWED_HOSTS
        or parsed.username is not None
        or parsed.password is not None
        or parsed.port is not None
        or parsed.query
        or parsed.fragment
    ):
        return None
    return value


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
                data.extend(chunk)
                if len(data) > MAX_RESPONSE_BYTES:
                    raise _InvalidProviderResponse
        try:
            payload = json.loads(data)
        except (ValueError, UnicodeError):
            raise _InvalidProviderResponse from None
        if not isinstance(payload, dict):
            raise _InvalidProviderResponse
        return payload

    async def research(self, topics: list[ResearchTopic]) -> ResearchResult:
        if not topics or len(topics) > MAX_QUERIES or len(set(topics)) != len(topics):
            raise ValueError("Research requires one to three distinct reviewed topics.")
        if any(topic not in SOURCES for topic in topics):
            raise ValueError("Only reviewed research topics are supported.")
        sources = curated_sources(topics)
        if not self._api_key:
            return ResearchResult(
                status="unconfigured",
                sources=sources,
                limitation="Web research is unconfigured. These are locally reviewed sources; "
                "no provider was contacted.",
            )

        queries = 0
        pages = 0
        retrieved: list[str] = []
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
                    candidates: dict[str, str] = {}
                    for topic in topics:
                        source = SOURCES[topic]
                        queries += 1
                        payload = await self._post(
                            client,
                            "/search",
                            {
                                "query": TOPIC_QUERIES[topic],
                                "topic": "general",
                                "search_depth": "basic",
                                "max_results": MAX_PAGES,
                                "include_domains": [urlsplit(source.url).hostname],
                                "include_answer": False,
                                "include_raw_content": False,
                                "include_images": False,
                                "auto_parameters": False,
                            },
                        )
                        rows = payload.get("results")
                        if not isinstance(rows, list) or len(rows) > MAX_PAGES:
                            raise _InvalidProviderResponse
                        for row in rows:
                            if not isinstance(row, dict):
                                raise _InvalidProviderResponse
                            url = _reviewed_url(row.get("url"), {source.url})
                            if url is not None:
                                candidates[url] = source.id

                    if candidates:
                        urls = list(candidates)[:MAX_PAGES]
                        pages = len(urls)
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
                        failed_urls = {
                            row.get("url")
                            for row in failed_rows
                            if isinstance(row, dict) and isinstance(row.get("url"), str)
                        }
                        for row in rows:
                            if not isinstance(row, dict):
                                raise _InvalidProviderResponse
                            url = _reviewed_url(row.get("url"), set(urls))
                            content = row.get("raw_content")
                            # Content is deliberately discarded, never interpolated into
                            # prompts, returned to clients, logged, or used as instructions.
                            if (
                                url is not None
                                and url not in failed_urls
                                and isinstance(content, str)
                                and 20 <= len(content.strip()) <= MAX_PAGE_CHARS
                                and candidates[url] not in retrieved
                            ):
                                retrieved.append(candidates[url])
        except (httpx.HTTPError, TimeoutError, _InvalidProviderResponse):
            # No provider exception strings, keys, response bodies, or queries in logs.
            return ResearchResult(
                status="unavailable",
                sources=sources,
                query_count=queries,
                page_count=pages,
                limitation="Web research did not complete. The plan uses locally reviewed "
                "guidance; no fresh evidence has been established.",
            )

        status = "retrieved" if len(retrieved) == len(sources) else "partial"
        if not retrieved:
            status = "unavailable"
        return ResearchResult(
            status=status,
            sources=sources,
            retrieved_source_ids=retrieved,
            query_count=queries,
            page_count=pages,
            limitation="Provider retrieval checks source availability only. Plan claims "
            "remain locally reviewed guidance, not a fresh medical evidence review.",
        )
