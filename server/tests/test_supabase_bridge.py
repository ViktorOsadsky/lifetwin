"""Fake MCP Bridge subprocesses: never contact Supabase or use real secrets."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("supabase_bridge", SCRIPTS / "supabase_bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)
SECRET = "invented-private-secret-never-print"


def schema(name, *, project_id=False):
    properties = (
        {"query": {"type": "string"}}
        if name == "execute_sql"
        else {
            "name": {"type": "string"},
            "entrypoint_path": {"type": "string"},
            "import_map_path": {"type": "string"},
            "verify_jwt": {"type": "boolean"},
            "files": {"type": "array"},
        }
    )
    if project_id:
        properties["project_id"] = {"type": "string"}
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties),
        "additionalProperties": False,
    }


def shown(project=bridge.PROJECT_REF):
    return {
        "ok": True,
        "configuration": {
            "enabled": True,
            "transport": "http",
            "keepConnected": True,
            "url": f"https://mcp.supabase.com/mcp?project_ref={project}",
        },
    }


class FakeRunner:
    def __init__(self, response=None, exit_code=0, failure=None):
        self.response = response
        self.exit_code = exit_code
        self.failure = failure
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if self.failure:
            raise self.failure
        if "show" in command:
            response = shown()
        elif "describe" in command:
            name = command[command.index("describe") + 2]
            response = {"ok": True, "result": {"name": name, "inputSchema": schema(name)}}
        else:
            response = (
                self.response
                if self.response is not None
                else {"ok": True, "result": {"content": []}}
            )
        return SimpleNamespace(
            returncode=self.exit_code, stdout=json.dumps(response), stderr=SECRET
        )


def private_source(tmp_path, content):
    directory = tmp_path / "private"
    directory.mkdir(mode=0o700)
    path = directory / "settings.env"
    path.write_text(content)
    path.chmod(0o600)
    return path


def test_bridge_requires_the_specific_project_and_shared_session():
    for project in ["", "different", bridge.PROJECT_REF + "&project_ref=another"]:

        class WrongProject(FakeRunner):
            def __call__(self, command, selected_project=project, **kwargs):
                return SimpleNamespace(
                    returncode=0, stdout=json.dumps(shown(selected_project)), stderr=""
                )

        with pytest.raises(bridge.BridgeFailure, match="scoped"):
            bridge.BridgeClient(runner=WrongProject()).verify_project()


def test_provider_file_filters_non_edge_settings_and_rejects_public_tokens(tmp_path):
    path = private_source(
        tmp_path,
        f"LLM_API_KEY={SECRET}\nAPI_GATEWAY_TOKEN=obsolete\nSUPABASE_SERVICE_ROLE_KEY=never-copy\nMODEL_ARTIFACT_PATH=/tmp/model\n",
    )
    assert bridge.provision_values(path) == {"LLM_API_KEY": SECRET}
    assert len(bridge.SETTING_NAMES) == 19


@pytest.mark.parametrize("cors_name", ["CORS_ORIGINS", "LIFETWIN_CORS_ORIGINS"])
def test_explicit_edge_cors_uses_server_validation(tmp_path, cors_name):
    path = private_source(tmp_path, f"{cors_name}=https://demo.example\n")
    assert bridge.provision_values(path) == {"LIFETWIN_CORS_ORIGINS": "https://demo.example"}
    path.write_text(f"{cors_name}=*\n")
    with pytest.raises(bridge.BridgeFailure):
        bridge.provision_values(path)


def test_insecure_file_rejected_before_any_bridge_call(tmp_path, capsys):
    path = private_source(tmp_path, f"LLM_API_KEY={SECRET}\n")
    path.chmod(0o644)
    runner = FakeRunner()
    assert (
        bridge.main(["--provision-env-file", str(path)], client=bridge.BridgeClient(runner=runner))
        == 1
    )
    assert runner.calls == []
    assert SECRET not in capsys.readouterr().err


def test_sql_quotes_json_as_data_and_accepts_only_edge_names():
    query = bridge.provisioning_query({"LLM_API_KEY": "a'$evil$); drop table example; --"})
    prefix = "select public.lifetwin_set_provider_config("
    assert query.startswith(prefix)
    delimiter = query[len(prefix) :].split("$", 2)
    delimiter = "$" + delimiter[1] + "$"
    payload = query[len(prefix) + len(delimiter) : -len(delimiter + "::jsonb);")]
    assert json.loads(payload) == {"LLM_API_KEY": "a'$evil$); drop table example; --"}
    with pytest.raises(bridge.BridgeFailure):
        bridge.provisioning_query({"SUPABASE_SERVICE_ROLE_KEY": SECRET})


def test_provision_sends_values_only_on_stdin_and_withholds_success_response(tmp_path, capsys):
    source = private_source(tmp_path, f"LLM_API_KEY={SECRET}\n")
    runner = FakeRunner({"ok": True, "result": {"content": [{"type": "text", "text": SECRET}]}})
    assert (
        bridge.main(
            ["--provision-env-file", str(source)], client=bridge.BridgeClient(runner=runner)
        )
        == 0
    )
    mutations = [(cmd, kwargs) for cmd, kwargs in runner.calls if "call" in cmd]
    assert len(mutations) == 1
    command, options = mutations[0]
    assert "--stdin" in command and "--session" in command and "--direct" not in command
    assert SECRET not in " ".join(command)
    assert SECRET in json.loads(options["input"])["query"]
    output = capsys.readouterr()
    assert SECRET not in output.out + output.err


@pytest.mark.parametrize(
    "response,code",
    [
        ({"ok": False, "error": {"message": SECRET}}, 2),
        ({"ok": False, "result": {"isError": True, "content": [{"text": SECRET}]}}, 4),
        ({"ok": True, "result": {"isError": True}}, 0),
        ({"ok": False, "error": {"message": SECRET}}, 5),
    ],
)
def test_mutation_failures_are_redacted_and_never_retried(tmp_path, capsys, response, code):
    source = private_source(tmp_path, f"LLM_API_KEY={SECRET}\n")
    runner = FakeRunner(response, code)
    # Metadata succeeds; only the mutation returns this failure.
    original = runner.__call__

    def run(command, **kwargs):
        if "call" not in command:
            saved = runner.exit_code
            runner.exit_code = 0
            try:
                return original(command, **kwargs)
            finally:
                runner.exit_code = saved
        return original(command, **kwargs)

    assert (
        bridge.main(["--provision-env-file", str(source)], client=bridge.BridgeClient(runner=run))
        == 1
    )
    assert len([cmd for cmd, _ in runner.calls if "call" in cmd]) == 1
    captured = capsys.readouterr()
    assert SECRET not in captured.out + captured.err
    assert "Reconcile" in captured.err


def test_transport_timeout_does_not_retry_or_expose_subprocess_input(tmp_path, capsys):
    source = private_source(tmp_path, f"LLM_API_KEY={SECRET}\n")
    runner = FakeRunner()

    def run(command, **kwargs):
        if "call" in command:
            runner.calls.append((command, kwargs))
            raise subprocess.TimeoutExpired(command, 100, output=SECRET, stderr=SECRET)
        return runner(command, **kwargs)

    assert (
        bridge.main(["--provision-env-file", str(source)], client=bridge.BridgeClient(runner=run))
        == 1
    )
    assert len([cmd for cmd, _ in runner.calls if "call" in cmd]) == 1
    output = capsys.readouterr()
    assert SECRET not in output.out + output.err


def test_schema_supports_explicit_project_ids_but_rejects_unknown_required_fields():
    runner = FakeRunner()
    client = bridge.BridgeClient(runner=runner)
    client.call("execute_sql", {"query": "select 1"}, schema("execute_sql", project_id=True))
    payload = json.loads(runner.calls[-1][1]["input"])
    assert payload["project_id"] == bridge.PROJECT_REF
    altered = schema("execute_sql")
    altered["required"].append("unexpected")
    before = len(runner.calls)
    with pytest.raises(bridge.BridgeFailure):
        client.call("execute_sql", {"query": SECRET}, altered)
    assert len(runner.calls) == before


def test_bundle_includes_runtime_assets_and_excludes_tests_or_private_files(tmp_path):
    for name, content in {
        "index.ts": "Deno.serve(() => new Response('ok'));",
        "providers.ts": "export {};",
        "deno.json": "{}",
        "deno.lock": "{}",
        "schemas.json": "{}",
        "providers.test.ts": "test-only",
        "helper_test.ts": "test-only",
        ".env": SECRET,
        ".env.private.json": SECRET,
        "notes.md": "do not deploy",
    }.items():
        (tmp_path / name).write_text(content)
    args = bridge.deployment_arguments(tmp_path)
    assert args["verify_jwt"] is True
    assert args["import_map_path"] == "deno.json"
    assert {file["name"] for file in args["files"]} == {
        "index.ts",
        "providers.ts",
        "deno.json",
        "schemas.json",
    }
    assert SECRET not in json.dumps(args)
    assert "deno.lock" not in {file["name"] for file in args["files"]}


def test_bundle_refuses_symlinked_dependencies(tmp_path):
    directory = tmp_path / "function"
    directory.mkdir()
    (directory / "index.ts").write_text("")
    (directory / "deno.json").write_text("{}")
    outside = tmp_path / "secret.json"
    outside.write_text(SECRET)
    (directory / "config.json").symlink_to(outside)
    with pytest.raises(bridge.BridgeFailure, match="symlink"):
        bridge.deployment_arguments(directory)


@pytest.mark.parametrize("error_code", [-32603, SECRET, {"nested": SECRET}, True])
def test_only_numeric_failure_diagnostics_are_displayed(error_code):
    runner = FakeRunner({"ok": False, "error": {"code": error_code, "message": SECRET}}, 4)
    with pytest.raises(bridge.BridgeFailure) as captured:
        bridge.BridgeClient(runner=runner).command(
            ["call", "supabase", "execute_sql"], {"query": SECRET}, mutation=True
        )
    message = str(captured.value)
    assert "upstream tool error" in message
    assert "exit=4" in message
    if type(error_code) is int:
        assert f"error_code={error_code}" in message
    else:
        assert "error_code=" not in message
    assert SECRET not in message
    assert len(runner.calls) == 1
