"""Bound JSON API requests without storing request payloads or user profiles."""

import asyncio
import logging
import math
import time
from collections import OrderedDict, deque
from secrets import token_hex

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from lifetwin.core.config import Settings
from lifetwin.core.models import ApiError

logger = logging.getLogger("lifetwin.request")


class RequestBudgetMiddleware:
    """Single-process limits; deployment ingress must enforce global limits."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self.settings = settings
        self.active = 0
        # IP + timestamps only, bounded memory; never health data or transcripts.
        self.buckets: OrderedDict[str, deque[float]] = OrderedDict()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request_id = token_hex(16)
        scope.setdefault("state", {})["request_id"] = request_id
        started = False

        async def send_with_headers(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
                message = dict(message)
                message["headers"] = list(message.get("headers", [])) + [
                    (b"x-request-id", request_id.encode()),
                    (b"cache-control", b"no-store"),
                    (b"x-content-type-options", b"nosniff"),
                ]
            await send(message)

        async def error(
            status: int, code: str, message: str, retry_after: int | None = None
        ) -> None:
            response = JSONResponse(
                status_code=status,
                content=ApiError(code=code, message=message, request_id=request_id).model_dump(),
                headers={"Retry-After": str(retry_after)} if retry_after else None,
            )
            await response(scope, receive, send_with_headers)

        if scope["path"] in {"/health", "/ready"}:
            # A saturated request pool must not make healthy workers fail probes.
            await self.app(scope, receive, send_with_headers)
            return
        else:
            now = time.monotonic()
            client = scope.get("client")
            address = client[0] if client else "unknown"
            bucket = self.buckets.setdefault(address, deque())
            self.buckets.move_to_end(address)
            while bucket and bucket[0] <= now - 60:
                bucket.popleft()
            while len(self.buckets) > 2048:
                self.buckets.popitem(last=False)
            if len(bucket) >= self.settings.rate_limit_per_minute:
                wait = max(1, math.ceil(bucket[0] + 60 - now))
                await error(
                    429,
                    "rate_limit_exceeded",
                    "Too many tries in a short time. Please wait one minute, then try again.",
                    retry_after=wait,
                )
                return
            if self.active >= self.settings.max_concurrent_requests:
                # Busy rejections must not use up the caller's per-minute quota.
                await error(
                    429,
                    "server_busy",
                    "We are helping a lot of people right now. Please try again in a few seconds.",
                    retry_after=2,
                )
                return
            bucket.append(now)
        self.active += 1
        try:
            pdf = scope["path"] == "/api/documents/read"
            deadline = self.settings.request_timeout_seconds
            if pdf:
                # Room for Claude's own time budget, so its timeout answers "unavailable".
                deadline = max(deadline, self.settings.document_read_timeout_seconds + 5)
            async with asyncio.timeout(deadline):
                # Buffer a bounded JSON body so chunked requests cannot bypass the limit.
                body = bytearray()
                limit = (
                    self.settings.max_pdf_body_bytes
                    if pdf
                    else self.settings.max_document_body_bytes
                    if scope["path"] == "/api/documents/extract"
                    else self.settings.max_body_bytes
                )
                while True:
                    incoming = await receive()
                    if incoming["type"] == "http.disconnect":
                        return
                    if incoming["type"] != "http.request":
                        continue
                    chunk = incoming.get("body", b"")
                    if len(body) + len(chunk) > limit:
                        await error(
                            413,
                            "body_too_large",
                            "That PDF is too big to send. Please choose one under 10 MB, "
                            "or read it on this phone."
                            if pdf
                            else "That message is too long. Please shorten it and try again.",
                        )
                        return
                    body.extend(chunk)
                    if not incoming.get("more_body", False):
                        break
                delivered = False
                disconnected = asyncio.Event()

                async def bounded_receive() -> Message:
                    nonlocal delivered
                    if not delivered:
                        delivered = True
                        return {"type": "http.request", "body": bytes(body), "more_body": False}
                    await disconnected.wait()
                    return {"type": "http.disconnect"}

                async def watch_disconnect() -> None:
                    while True:
                        if (await receive())["type"] == "http.disconnect":
                            disconnected.set()
                            return

                # Observe disconnects even when a JSON endpoint no longer reads
                # the body. Cancelling this task propagates into provider calls.
                operation = asyncio.create_task(self.app(scope, bounded_receive, send_with_headers))
                watcher = asyncio.create_task(watch_disconnect())
                try:
                    done, _ = await asyncio.wait(
                        {operation, watcher}, return_when=asyncio.FIRST_COMPLETED
                    )
                    if operation in done:
                        await operation
                    else:
                        operation.cancel()
                        await asyncio.gather(operation, return_exceptions=True)
                finally:
                    operation.cancel()
                    watcher.cancel()
                    await asyncio.gather(operation, watcher, return_exceptions=True)
        except TimeoutError:
            if not started:
                await error(504, "request_timeout", "This is taking too long. Please try again.")
        except Exception as exc:
            # Never log bodies, headers or exception text: they may hold health data.
            route = scope.get("route")
            logger.error(
                "unhandled error request_id=%s method=%s route=%s exception=%s",
                request_id,
                scope.get("method"),
                getattr(route, "path", "unmatched"),
                type(exc).__name__,
            )
            if not started:
                await error(
                    500,
                    "internal_error",
                    "Something went wrong on our side. Please try again in a moment.",
                )
        finally:
            self.active -= 1
