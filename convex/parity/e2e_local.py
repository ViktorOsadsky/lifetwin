"""End-to-end checks against a running LOCAL Convex deployment (real Convex runtime).

    cd convex && CONVEX_AGENT_MODE=anonymous npx convex dev   # in another terminal
    uv run python convex/parity/e2e_local.py --base-url http://127.0.0.1:3211

It temporarily sets deployment environment variables with `npx convex env`
(LLM_* pointing at a mock Chat Completions server on 127.0.0.1, and
SESSION_STORE=ephemeral), runs the checks, then removes them again. Never run
it against a shared or production deployment.
"""

import argparse
import json
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import httpx

CONVEX_DIR = Path(__file__).resolve().parents[1]
SEEN: list[dict] = []
GOOD = json.dumps({"candidates": [{"field": "weight_kg", "quote": "70 kg"}]})


class MockLLM(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        payload = json.loads(body)
        SEEN.append({"path": self.path, "auth": self.headers.get("authorization"), "json": payload})
        if "slow" in payload["messages"][1]["content"]:
            time.sleep(3)
        reply = json.dumps(
            {
                "choices": [
                    {"message": {"role": "assistant", "content": GOOD}, "finish_reason": "stop"}
                ]
            }
        ).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


def convex(*args: str) -> str:
    return subprocess.run(
        ["npx", "convex", *args], cwd=CONVEX_DIR, check=True, capture_output=True, text=True
    ).stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:3211")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), MockLLM)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = {
        "LLM_PROVIDER": "chat_completions",
        "LLM_BASE_URL": f"http://127.0.0.1:{server.server_port}/v1",
        "LLM_MODEL": "muse-test",
        "LLM_API_KEY": "e2e-test-key",
        "SESSION_STORE": "ephemeral",
    }
    results = []

    def check(name, condition):
        results.append(bool(condition))
        print(("PASS " if condition else "FAIL ") + name)

    try:
        for key, value in env.items():
            convex("env", "set", key, value)
        convex("env", "remove", "LLM_REASONING_EFFORT")
        base = args.base_url.rstrip("/")
        with httpx.Client(timeout=30, trust_env=False) as client:
            caps = client.get(f"{base}/api/capabilities").json()
            check("capabilities report llm_configured", caps["llm_configured"] is True)
            state = {"phase": "asking", "current_field": "weight_kg"}
            turn = {"action": "reply", "state": state, "text": "My current weight is 70 kg"}
            no_consent = client.post(f"{base}/api/onboarding/turn", json=turn).json()
            check(
                "no consent: consent_required and no upstream call",
                no_consent["provider_status"] == "consent_required" and not SEEN,
            )
            used = client.post(
                f"{base}/api/onboarding/turn", json={**turn, "provider_consent": True}
            ).json()
            check(
                "consented turn uses the helper (guide_mode llm)",
                used["guide_mode"] == "llm" and used["provider_status"] == "used",
            )
            check(
                "grounded value is pending, not confirmed",
                used["state"]["pending_profile"]["weight_kg"] == 70.0
                and used["state"]["confirmed_profile"]["weight_kg"] is None,
            )
            sent = SEEN[0] if SEEN else {}
            check(
                "request went to {base}/chat/completions with bearer key",
                sent.get("path") == "/v1/chat/completions"
                and sent.get("auth") == "Bearer e2e-test-key",
            )
            check(
                "payload: reasoning_effort minimal, max_tokens 2000",
                sent.get("json", {}).get("reasoning_effort") == "minimal"
                and sent.get("json", {}).get("max_tokens") == 2000,
            )

            created = client.post(f"{base}/api/sessions", json={"action": "create"}).json()
            sid = created["session_id"]
            saved = client.post(
                f"{base}/api/sessions",
                json={"action": "save", "session_id": sid, "conversation_state": used["state"]},
            ).json()
            check(
                "session save round-trips the conversation state",
                saved["conversation_state"] == used["state"],
            )
            reactive = json.loads(convex("run", "sessions:get", json.dumps({"sessionId": sid})))
            check("reactive query returns the same session", reactive == saved)
            scheduled = convex("data", "_scheduled_functions", "--format", "jsonLines")
            jobs = [
                json.loads(line) for line in scheduled.splitlines() if line.strip().startswith("{")
            ]
            expires = (
                datetime.fromisoformat(created["expires_at"].replace("Z", "+00:00")).timestamp()
                * 1000
            )
            expire_jobs = [
                job
                for job in jobs
                if job.get("name", "").startswith("sessions")
                and job.get("state", {}).get("kind") == "pending"
                and abs(job.get("scheduledTime", 0) - expires) < 1000
            ]
            check(
                "a pending deletion job is scheduled exactly at expires_at (30 min)",
                len(expire_jobs) == 1,
            )
            ttl = (expires - time.time() * 1000) / 60000
            check("expires_at is about 30 minutes away", 29 < ttl <= 30)
            convex("env", "set", "API_PROVIDER_TIMEOUT_SECONDS", "1")
            started = time.monotonic()
            slow = client.post(
                f"{base}/api/onboarding/turn",
                json={**turn, "text": "slow 70 kg answer", "provider_consent": True},
            ).json()
            elapsed = time.monotonic() - started
            check(
                f"slow provider aborts at the deadline and falls back ({elapsed:.1f}s)",
                slow["provider_status"] == "unavailable" and elapsed < 2.5,
            )
            client.post(f"{base}/api/sessions", json={"action": "delete", "session_id": sid})
            gone = client.post(f"{base}/api/sessions", json={"action": "get", "session_id": sid})
            check("deleted session is gone (404)", gone.status_code == 404)
    finally:
        for key in [*env, "API_PROVIDER_TIMEOUT_SECONDS"]:
            convex("env", "remove", key)
        server.shutdown()
    print(f"{sum(results)}/{len(results)} end-to-end checks passed")
    raise SystemExit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
