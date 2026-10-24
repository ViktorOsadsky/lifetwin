"""Check the developer-facing contract commands, including their coverage claims."""

import os
import runpy
import subprocess
import sys
from pathlib import Path

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[2]


def run_checker(*args):
    return subprocess.run(
        [sys.executable, "contracts/check.py", *args],
        cwd=ROOT,
        env={**os.environ, "OPENAI_API_KEY": "", "OPENAI_MODEL": "", "TAVILY_API_KEY": ""},
        text=True,
        capture_output=True,
        timeout=20,
    )


def test_in_process_replays_success_and_error_contracts_without_sockets():
    result = run_checker("--in-process")
    assert result.returncode == 0, result.stderr
    assert "11 responses checked across 11 cases in process" in result.stdout
    assert "PASS invalid-conversation-transition (API response checked)" in result.stdout
    assert "PASS missing-quiz-version (API response checked)" in result.stdout


def test_offline_mode_does_not_claim_to_check_missing_response_fixtures():
    result = run_checker()
    assert result.returncode == 0, result.stderr
    assert "1 responses checked across 11 cases offline" in result.stdout
    assert "SKIP quiz-bank (requires API replay)" in result.stdout
    assert "request fixture only; response not checked" in result.stdout


def test_replay_targets_are_mutually_exclusive():
    result = run_checker("--in-process", "--base-url", "http://127.0.0.1:1")
    assert result.returncode == 2
    assert "not allowed with argument" in result.stderr


def test_bad_api_response_diagnostic_omits_response_values(monkeypatch):
    checker = runpy.run_path(str(ROOT / "contracts/check.py"))
    original = httpx.Client
    private = "private-health-text-must-not-be-printed"

    def fake_client(**kwargs):
        return original(
            transport=httpx.MockTransport(
                lambda _: httpx.Response(501, json={"sensitive": private})
            ),
            **kwargs,
        )

    monkeypatch.setattr(httpx, "Client", fake_client)
    monkeypatch.setattr(sys, "argv", ["check.py", "--base-url", "http://test"])
    with pytest.raises(SystemExit) as failure:
        checker["main"]()
    assert "prediction-deferred: invalid API response" in str(failure.value)
    assert private not in str(failure.value)
