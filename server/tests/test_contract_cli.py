"""Check the developer-facing contract commands, including their coverage claims."""

import json
import os
import runpy
import shutil
import subprocess
import sys
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator

from lifetwin.app import create_app
from lifetwin.core.config import Settings

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"


def run_contract_script(script, *args):
    return subprocess.run(
        [sys.executable, f"contracts/{script}", *args],
        cwd=ROOT,
        env={**os.environ, "OPENAI_API_KEY": "", "OPENAI_MODEL": "", "TAVILY_API_KEY": ""},
        text=True,
        capture_output=True,
        timeout=20,
    )


def run_checker(*args):
    return run_contract_script("check.py", *args)


def load_script(monkeypatch, script):
    monkeypatch.syspath_prepend(str(CONTRACTS))
    return runpy.run_path(str(CONTRACTS / script))


def schema(name):
    return Draft202012Validator(json.loads((CONTRACTS / name).read_text()))


def test_in_process_replays_success_and_error_contracts_without_sockets():
    result = run_checker("--in-process")
    assert result.returncode == 0, result.stderr
    assert "Validated 16 schemas and 18 request fixtures" in result.stdout
    assert "22 responses checked across 22 cases in process" in result.stdout
    assert "PASS invalid-conversation-transition (API response checked)" in result.stdout
    assert "PASS missing-quiz-version (API response checked)" in result.stdout
    assert "PASS quiz-question-detail (API response checked)" in result.stdout


def test_offline_mode_does_not_claim_to_check_missing_response_fixtures():
    result = run_checker()
    assert result.returncode == 0, result.stderr
    assert "3 responses checked across 22 cases offline" in result.stdout
    assert "PASS compare-deferred (static response checked)" in result.stdout
    assert "SKIP quiz-bank (requires API replay)" in result.stdout
    assert "request fixture only; response not checked" in result.stdout


def test_replay_targets_are_mutually_exclusive():
    result = run_checker("--in-process", "--base-url", "http://127.0.0.1:1")
    assert result.returncode == 2
    assert "not allowed with argument" in result.stderr


def test_exported_schemas_are_current():
    result = run_contract_script("export.py", "--check")
    assert result.returncode == 0, result.stderr
    assert "Checked 16 API schemas." in result.stdout


def test_export_check_rejects_schema_files_missing_from_registry(monkeypatch, tmp_path):
    exporter = load_script(monkeypatch, "export.py")
    for path in CONTRACTS.glob("*.schema.json"):
        shutil.copy(path, tmp_path / path.name)
    shutil.copy(CONTRACTS / "quiz.schema.json", tmp_path / "old.schema.json")
    monkeypatch.setitem(exporter["main"].__globals__, "ROOT", tmp_path)
    monkeypatch.setattr(sys, "argv", ["export.py", "--check"])
    with pytest.raises(SystemExit) as failure:
        exporter["main"]()
    assert "old.schema.json" in str(failure.value)


def test_response_schemas_require_defaulted_safety_markers():
    assert not schema("prediction.schema.json").is_valid({})
    assert not schema("compare.schema.json").is_valid({})
    assert not schema("error.schema.json").is_valid(
        {"code": "invalid_request", "message": "Request fields or values are invalid."}
    )
    client = keyless_client()
    turn = client.post("/api/onboarding/turn", json={"action": "start"}).json()
    advice = client.post("/api/advisor", json={"topics": ["sleep"]}).json()
    bank = client.get("/api/quiz/questions").json()
    assert schema("conversation.schema.json").is_valid(turn)
    assert schema("advisor.schema.json").is_valid(advice)
    assert schema("quiz.schema.json").is_valid(bank)
    for field in ("voice_status", "provider_status", "limitations"):
        assert not schema("conversation.schema.json").is_valid(
            {k: v for k, v in turn.items() if k != field}
        )
    for field in ("status", "mode"):
        assert not schema("advisor.schema.json").is_valid(
            {k: v for k, v in advice.items() if k != field}
        )
    stripped_action = {k: v for k, v in advice["actions"][0].items() if k != "modeled_effect"}
    assert not schema("advisor.schema.json").is_valid({**advice, "actions": [stripped_action]})
    assert not schema("quiz.schema.json").is_valid(
        {k: v for k, v in bank.items() if k != "local_scoring"}
    )


def test_request_schemas_keep_defaulted_fields_optional():
    assert schema("prediction.request.schema.json").is_valid({})
    assert schema("conversation.request.schema.json").is_valid({"action": "start"})


def test_subset_each_matcher_checks_every_list_element(monkeypatch):
    assert_subset = load_script(monkeypatch, "check.py")["assert_subset"]
    expected = {"actions": {"$each": {"modeled_effect": None}}}
    assert_subset({"actions": [{"modeled_effect": None, "id": "a"}]}, expected, "case")
    with pytest.raises(AssertionError, match="expected a nonempty list"):
        assert_subset({"actions": []}, expected, "case")
    with pytest.raises(AssertionError, match=r"case\.actions\[1\]\.modeled_effect: differs"):
        assert_subset(
            {"actions": [{"modeled_effect": None}, {"modeled_effect": 3}]}, expected, "case"
        )


def test_declared_schema_invalid_request_must_fail_its_schema(monkeypatch, tmp_path):
    checker = load_script(monkeypatch, "check.py")
    for path in CONTRACTS.glob("*.schema.json"):
        shutil.copy(path, tmp_path / path.name)
    cases = json.loads((CONTRACTS / "fixtures" / "cases.json").read_text())
    case = next(c for c in cases if c["name"] == "advisor-rejects-client-prognosis")
    assert case["request_schema_valid"] is False
    case["request"] = {"topics": ["sleep"]}
    (tmp_path / "fixtures").mkdir()
    (tmp_path / "fixtures" / "cases.json").write_text(json.dumps(cases))
    monkeypatch.setitem(checker["main"].__globals__, "ROOT", tmp_path)
    monkeypatch.setattr(sys, "argv", ["check.py"])
    with pytest.raises(SystemExit) as failure:
        checker["main"]()
    assert "advisor-rejects-client-prognosis: request unexpectedly matches" in str(failure.value)


def keyless_client():
    return TestClient(
        create_app(
            Settings(
                _env_file=None,
                app_env="test",
                openai_api_key="",
                openai_model="",
                tavily_api_key="",
            )
        )
    )


def replay_against(monkeypatch, mutate):
    """Run the --base-url checker against the keyless app, rewriting chosen responses."""
    checker = load_script(monkeypatch, "check.py")
    app = keyless_client()
    original = httpx.Client

    def handler(request):
        upstream = app.request(
            request.method,
            request.url.raw_path.decode(),
            content=request.content,
            headers={"content-type": request.headers.get("content-type", "application/json")},
        )
        body = mutate(request.url.path, upstream.json())
        return httpx.Response(upstream.status_code, json=body)

    def fake_client(**kwargs):
        return original(transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(httpx, "Client", fake_client)
    monkeypatch.setattr(sys, "argv", ["check.py", "--base-url", "http://test"])
    return checker["main"]


def test_replay_passes_against_unmodified_keyless_app(monkeypatch, capsys):
    replay_against(monkeypatch, lambda _path, body: body)()
    assert "22 responses checked across 22 cases against live API." in capsys.readouterr().out


def test_bad_api_response_diagnostic_omits_response_values(monkeypatch):
    private = "private-health-text-must-not-be-printed"
    main = replay_against(monkeypatch, lambda _path, _body: {"sensitive": private})
    with pytest.raises(SystemExit) as failure:
        main()
    assert "prediction-deferred: invalid API response" in str(failure.value)
    assert private not in str(failure.value)


def test_replay_rejects_empty_deferred_compare_body(monkeypatch):
    main = replay_against(monkeypatch, lambda path, body: {} if path == "/api/compare" else body)
    with pytest.raises(SystemExit) as failure:
        main()
    assert "compare-deferred: invalid API response" in str(failure.value)


def test_replay_rejects_schema_valid_but_wrong_keyless_turn(monkeypatch):
    def mutate(path, body):
        if path == "/api/onboarding/turn" and body.get("state", {}).get("current_field") == "age":
            body["state"]["confirmed_profile"]["age"] = 97
        return body

    with pytest.raises(AssertionError) as failure:
        replay_against(monkeypatch, mutate)()
    message = str(failure.value)
    assert "mascot-start.state.confirmed_profile.age: differs" in message
    assert "97" not in message


def test_replay_rejects_used_provider_on_keyless_start(monkeypatch):
    def mutate(path, body):
        if path == "/api/onboarding/turn" and "provider_status" in body:
            body["provider_status"] = "used"
        return body

    with pytest.raises(AssertionError, match=r"mascot-start\.provider_status: differs"):
        replay_against(monkeypatch, mutate)()
