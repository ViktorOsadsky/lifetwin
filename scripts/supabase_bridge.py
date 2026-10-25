#!/usr/bin/env python3
"""Provision LifeTwin provider settings or deploy its API using the saved Bridge session."""

from __future__ import annotations

import argparse
import json
import secrets
import stat
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import server_env
from dotenv import dotenv_values
from jsonschema import Draft7Validator

PROJECT_REF = "plpywefoeepfunptjujc"
BRIDGE = Path("/Users/flare/Documents/GitHub/MCPBridge/dist/MCP-Bridge-1.2.0/mcp-bridge")
PROFILE = Path("/Users/flare/Library/Application Support/MCP Bridge/profile.json")
FUNCTION_DIRECTORY = server_env.REPOSITORY / "supabase" / "functions" / "lifetwin-api"
SETTING_NAMES = frozenset(
    {
        "LLM_PROVIDER",
        "LLM_BASE_URL",
        "LLM_MODEL",
        "LLM_API_KEY",
        "LLM_ALLOW_CONTRIBUTOR",
        "LLM_REASONING_EFFORT",
        "PERSONALIZE_PROVIDER",
        "ANTHROPIC_API_KEY",
        "CLAUDE_MODEL",
        "CARTESIA_API_KEY",
        "CARTESIA_VOICE_ID",
        "CARTESIA_VERSION",
        "CARTESIA_TTS_MODEL",
        "CARTESIA_STT_MODEL",
        "CARTESIA_TTS_SPEED",
        "CARTESIA_TOKEN_TTL_SECONDS",
        "ONBOARDING_DEMO",
        "DOCUMENT_MUSE_ENABLED",
        "LIFETWIN_CORS_ORIGINS",
    }
)


class BridgeFailure(Exception):
    """Only fixed messages and validated numeric diagnostics reach the terminal."""


class BridgeClient:
    def __init__(self, executable: Path = BRIDGE, profile: Path = PROFILE, runner=None):
        self.executable = executable
        self.profile = profile
        self.runner = runner or subprocess.run

    def command(self, arguments: list[str], payload=None, *, mutation: bool = False):
        command = [str(self.executable), "--config", str(self.profile), *arguments]
        encoded = json.dumps(payload) if payload is not None else None
        if encoded is not None and len(encoded.encode("utf-8")) > 16 * 1048576:
            raise BridgeFailure("Bridge input exceeds its upload limit; no mutation sent.")
        diagnostic = ""
        classification = "process failure"
        try:
            completed = self.runner(
                command,
                input=encoded,
                capture_output=True,
                text=True,
                timeout=100,
                check=False,
            )
            exit_code = completed.returncode
            if type(exit_code) is int and -255 <= exit_code <= 255:
                diagnostic = f" (exit={exit_code})"
                classification = {
                    2: "input or configuration failure",
                    3: "connection or protocol failure",
                    4: "upstream tool error",
                    5: "timeout",
                }.get(exit_code, "unexpected response")
            response = json.loads(completed.stdout)
            if isinstance(response, dict) and isinstance(response.get("error"), dict):
                error_code = response["error"].get("code")
                if type(error_code) is int and -(2**31) <= error_code < 2**31:
                    diagnostic = (
                        diagnostic[:-1] + f", error_code={error_code})"
                        if diagnostic
                        else f" (error_code={error_code})"
                    )
            if (
                completed.returncode != 0
                or not isinstance(response, dict)
                or response.get("ok") is not True
                or isinstance(response.get("result"), dict)
                and response["result"].get("isError") is True
            ):
                raise ValueError("withheld")
            return response
        except (OSError, subprocess.TimeoutExpired, ValueError, TypeError) as failure:
            if isinstance(failure, subprocess.TimeoutExpired):
                classification = "timeout"
            if mutation:
                raise BridgeFailure(
                    f"Bridge {classification}{diagnostic}; mutation outcome is unconfirmed; response withheld. "
                    "Reconcile project state before retrying. No retry was attempted."
                ) from None
            raise BridgeFailure(
                f"Bridge {classification}{diagnostic}; metadata unavailable; response withheld."
            ) from None

    def verify_project(self):
        shown = self.command(["server", "show", "supabase"])
        configuration = shown.get("configuration", {})
        try:
            url = urlsplit(configuration.get("url", ""))
            projects = parse_qs(url.query).get("project_ref", [])
            correct = (
                configuration.get("enabled") is True
                and configuration.get("transport") == "http"
                and configuration.get("keepConnected") is True
                and url.scheme == "https"
                and url.hostname == "mcp.supabase.com"
                and url.path == "/mcp"
                and url.username is None
                and url.password is None
                and url.port in (None, 443)
                and projects == [PROJECT_REF]
            )
        except (AttributeError, TypeError, ValueError):
            correct = False
        if not correct:
            raise BridgeFailure(
                "Saved Supabase Bridge session must be scoped to the LifeTwin project."
            )

    def describe(self, name: str):
        # Refresh once before mutation so a stale project-wide catalog cannot
        # silently change which parameters are required. No fallback or retries.
        response = self.command(["tools", "describe", "supabase", name, "--live", "--session"])
        tool = response.get("result", {})
        if not isinstance(tool, dict) or tool.get("name") != name:
            raise BridgeFailure("Unexpected Bridge tool metadata; response withheld.")
        schema = tool.get("inputSchema")
        if not isinstance(schema, dict) or schema.get("type") != "object":
            raise BridgeFailure("Unsupported Bridge tool schema; no mutation sent.")
        return schema

    def call(self, name: str, payload: dict, schema: dict):
        properties = schema.get("properties", {})
        if not isinstance(properties, dict):
            raise BridgeFailure("Unsupported Bridge tool schema; no mutation sent.")
        if "project_id" in properties:
            payload = {**payload, "project_id": PROJECT_REF}
        if set(payload) - set(properties):
            raise BridgeFailure("Bridge tool schema changed; no mutation sent.")
        try:
            Draft7Validator.check_schema(schema)
            if not Draft7Validator(schema).is_valid(payload):
                raise ValueError("withheld")
        except Exception:
            # Validator diagnostics may embed the supplied configuration.
            raise BridgeFailure(
                "Bridge tool arguments failed validation; no mutation sent."
            ) from None
        self.verify_project()
        self.command(
            ["call", "supabase", name, "--stdin", "--session", "--timeout", "90"],
            payload,
            mutation=True,
        )


def provision_values(path: Path) -> dict[str, str]:
    try:
        source = path.lstat()
        directory = path.parent.lstat()
        if (
            not stat.S_ISREG(source.st_mode)
            or stat.S_IMODE(source.st_mode) != 0o600
            or not stat.S_ISDIR(directory.st_mode)
            or stat.S_IMODE(directory.st_mode) != 0o700
        ):
            raise BridgeFailure(
                "Provisioning requires a private file (0600) in a private directory (0700)."
            )
        values = server_env.read_values(path)
        # Edge uses its own exact-origin name. Preserve the same server validator.
        edge_cors = dotenv_values(path, interpolate=False).get("LIFETWIN_CORS_ORIGINS")
        if edge_cors is not None:
            server_env.check_value(edge_cors)
            server_env.validate_values({"CORS_ORIGINS": edge_cors})
            values["LIFETWIN_CORS_ORIGINS"] = edge_cors
        elif "CORS_ORIGINS" in values:
            values["LIFETWIN_CORS_ORIGINS"] = values["CORS_ORIGINS"]
        server_env.validate_values(
            {name: value for name, value in values.items() if name != "LIFETWIN_CORS_ORIGINS"}
            or {"CORS_ORIGINS": values.get("LIFETWIN_CORS_ORIGINS", "")}
        )
        result = {name: value for name, value in values.items() if name in SETTING_NAMES}
        if not result:
            raise BridgeFailure("No supported Edge provider settings were supplied.")
        return result
    except (OSError, server_env.ImportFailure):
        raise BridgeFailure(
            "Cannot read or validate private provider settings; values withheld."
        ) from None


def provisioning_query(values: dict[str, str]) -> str:
    if (
        not values
        or set(values) - SETTING_NAMES
        or any(not isinstance(v, str) for v in values.values())
    ):
        raise BridgeFailure("Unsupported Edge provider settings; no mutation sent.")
    serialized = json.dumps(values, ensure_ascii=True)
    delimiter = f"$lifetwin_{secrets.token_hex(16)}$"
    while delimiter in serialized:
        delimiter = f"$lifetwin_{secrets.token_hex(16)}$"
    return f"select public.lifetwin_set_provider_config({delimiter}{serialized}{delimiter}::jsonb);"


def deployment_arguments(directory: Path = FUNCTION_DIRECTORY) -> dict:
    files = []
    total_bytes = 0
    for path in sorted(directory.rglob("*")):
        if any(part.startswith(".") for part in path.relative_to(directory).parts):
            continue
        if not path.is_file() or path.name.endswith((".test.ts", "_test.ts")):
            continue
        if path.suffix not in {".ts", ".json", ".jsonc"}:
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(directory.resolve()):
            raise BridgeFailure("Function bundle contains a symlink; no deployment sent.")
        raw = path.read_bytes()
        total_bytes += len(raw)
        if len(raw) > 1048576 or total_bytes > 8 * 1048576:
            raise BridgeFailure("Function bundle exceeds its upload limit; no deployment sent.")
        files.append(
            {"name": path.relative_to(directory).as_posix(), "content": raw.decode("utf-8")}
        )
    names = {file["name"] for file in files}
    if "index.ts" not in names or "deno.json" not in names:
        raise BridgeFailure(
            "Function entrypoint or Deno configuration missing; no deployment sent."
        )
    return {
        "name": "lifetwin-api",
        "entrypoint_path": "index.ts",
        # Updates otherwise retain the previous deployment's absolute temp path.
        "import_map_path": "deno.json",
        "verify_jwt": True,
        "files": files,
    }


def main(argv=None, *, client=None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "The backend-credentials migration must already be applied. Provider updates replace "
            "the stored configuration; supply the complete desired file. Never retry an uncertain mutation."
        ),
    )
    parser.add_argument("--provision-env-file", type=Path)
    parser.add_argument(
        "--deploy", action="store_true", help="Deploy the current repository function bundle"
    )
    args = parser.parse_args(argv)
    if not args.provision_env_file and not args.deploy:
        parser.error("provide --provision-env-file and/or --deploy")
    try:
        values = provision_values(args.provision_env_file) if args.provision_env_file else None
        bundle = deployment_arguments() if args.deploy else None
        bridge = client or BridgeClient()
        bridge.verify_project()
        # Inspect all schemas before any mutation, reducing partial application.
        provision_schema = bridge.describe("execute_sql") if values is not None else None
        deploy_schema = bridge.describe("deploy_edge_function") if bundle is not None else None
        if values is not None:
            bridge.call("execute_sql", {"query": provisioning_query(values)}, provision_schema)
            print("Provider configuration update accepted by MCP Bridge (values withheld).")
        if bundle is not None:
            bridge.call("deploy_edge_function", bundle, deploy_schema)
            print(
                "Function deployment accepted by MCP Bridge; verify its live health and contracts."
            )
    except (BridgeFailure, OSError, UnicodeError, ValueError):
        error = sys.exception()
        message = (
            str(error)
            if isinstance(error, BridgeFailure)
            else "Operation stopped; details withheld."
        )
        print(f"Error: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
