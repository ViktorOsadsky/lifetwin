"""Fault-injecting proxy for the qa_* integration tests (stdlib only).

    python3 app/integration_test/support/qa_proxy.py 8051 http://127.0.0.1:8050

The app talks to this proxy (API_BASE_URL=http://127.0.0.1:8051); tests switch faults with
GET /__qa/mode?m=<mode>[&path=<prefix>][&times=<n>][&delay=<seconds>]:
  pass        forward unchanged (default)
  down        close the connection without an answer, like a stopped server
  slow        wait `delay` seconds, then forward
  429         the server's own rate-limit answer
  html        200 with an HTML page instead of JSON
  html403     403 with an HTML page (a captive portal or a proxy in the way)
  500         the server's own internal-error answer
  501         the server without its model files (the forecast is "still learning")
`path` limits the fault to requests whose path starts with it; `times` reverts to pass after
that many faulted requests. GET /__qa/log lists the forwarded requests (path and onboarding
action only, never bodies); GET /__qa/reset clears the log and the mode.
"""

import json
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

BACKEND = "http://127.0.0.1:8050"
LOCK = threading.Lock()
MODE = {"m": "pass", "path": "", "times": -1, "delay": 0.0}
LOG: list[dict] = []

HTML = b"<!doctype html><html><body><h1>Welcome to Hotel Wi-Fi</h1></body></html>"


def _api_error(code: str, message: str) -> bytes:
    return json.dumps({"code": code, "message": message, "request_id": "qa"}).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # keep the console quiet
        pass

    def _send(self, status: int, body: bytes, kind: str = "application/json", extra=None):
        self.send_response(status)
        self.send_header("content-type", kind)
        self.send_header("content-length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _control(self, url):
        q = {k: v[-1] for k, v in parse_qs(url.query).items()}
        with LOCK:
            if url.path == "/__qa/mode":
                MODE.update(
                    m=q.get("m", "pass"),
                    path=q.get("path", ""),
                    times=int(q.get("times", "-1")),
                    delay=float(q.get("delay", "0")),
                )
                body = dict(MODE)
            elif url.path == "/__qa/reset":
                MODE.update(m="pass", path="", times=-1, delay=0.0)
                LOG.clear()
                body = {"ok": True}
            else:
                body = {"log": list(LOG)}
        self._send(200, json.dumps(body).encode())

    def _fault(self, path: str) -> str:
        with LOCK:
            if MODE["m"] == "pass" or not path.startswith(MODE["path"] or "/"):
                return "pass"
            if MODE["times"] == 0:
                return "pass"
            if MODE["times"] > 0:
                MODE["times"] -= 1
            return MODE["m"]

    def _handle(self):
        url = urlsplit(self.path)
        if url.path.startswith("/__qa/"):
            return self._control(url)
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        action = None
        if url.path == "/api/onboarding/turn":
            try:
                action = json.loads(body).get("action")
            except ValueError:
                pass
        fault = self._fault(url.path)
        with LOCK:
            LOG.append({"path": url.path, "action": action, "fault": fault, "t": time.time()})
        if fault == "down":
            self.close_connection = True
            self.connection.close()
            return
        if fault == "429":
            msg = "Too many tries in a short time. Please wait one minute, then try again."
            return self._send(
                429, _api_error("rate_limit_exceeded", msg), extra={"Retry-After": "60"}
            )
        if fault == "html":
            return self._send(200, HTML, "text/html")
        if fault == "html403":
            return self._send(403, HTML, "text/html")
        if fault == "500":
            msg = "Something went wrong on our side. Please try again in a moment."
            return self._send(500, _api_error("internal_error", msg))
        if fault == "501":  # the server without its model files (DeferredFeature)
            return self._send(
                501, json.dumps({"status": "deferred", "detail": "Not implemented yet."}).encode()
            )
        if fault == "slow":
            time.sleep(MODE["delay"])
        req = urllib.request.Request(
            BACKEND + self.path,
            data=body if self.command == "POST" else None,
            method=self.command,
            headers={"content-type": self.headers.get("content-type", "application/json")},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                status, data, kind = r.status, r.read(), r.headers.get("content-type", "")
        except urllib.error.HTTPError as e:
            status, data, kind = e.code, e.read(), e.headers.get("content-type", "")
        except OSError:
            self.close_connection = True
            self.connection.close()
            return
        try:
            self._send(status, data, kind or "application/json")
        except OSError:
            pass  # the app gave up waiting

    do_GET = _handle
    do_POST = _handle


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8051
    BACKEND = sys.argv[2] if len(sys.argv) > 2 else BACKEND
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
