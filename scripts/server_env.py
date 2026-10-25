#!/usr/bin/env python3
"""Import backend configuration without executing or displaying supplied values."""

from __future__ import annotations

import argparse
import getpass
import io
import os
import secrets
import stat
import subprocess
import sys
import warnings
from pathlib import Path

from dotenv.parser import parse_stream
from pydantic import ValidationError

REPOSITORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY / "server"))

from lifetwin.core.config import Settings  # noqa: E402

MAX_SOURCE_BYTES = 65536
DEFAULT_OUTPUT = REPOSITORY / ".env.deploy" / "server.env"
DEFAULT_PROMPTS = (
    "LLM_API_KEY",
    "ANTHROPIC_API_KEY",
    "CARTESIA_API_KEY",
    "CARTESIA_VOICE_ID",
)


class ImportFailure(Exception):
    """A safe error whose message never contains supplied configuration values."""


class ImportedSettings(Settings):
    @classmethod
    def settings_customise_sources(cls, settings_cls, init_settings, **sources):
        # Do not silently mix the user's file with this process's environment or .env.
        return (init_settings,)


def setting_names() -> dict[str, str]:
    """Only settings accepted by the actual server, including API_* aliases."""
    return {
        (field.validation_alias or name.upper()): name
        for name, field in Settings.model_fields.items()
    }


def parse_values(source: str) -> dict[str, str]:
    accepted = setting_names()
    result: dict[str, str] = {}
    for binding in parse_stream(io.StringIO(source)):
        if binding.error:
            raise ImportFailure("Invalid dotenv syntax; no output was written.")
        if binding.key is None:
            continue
        if binding.value is None:
            raise ImportFailure("Each setting must have a value after '='.")
        if binding.key not in accepted:
            continue
        if binding.key in result:
            raise ImportFailure("Duplicate server setting; no output was written.")
        check_value(binding.value)
        result[binding.key] = binding.value
    return result


def check_value(value: str) -> None:
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ImportFailure("Settings must be single-line text without control characters.")
    if "${" in value:
        # python-dotenv's later load interpolates even single-quoted values. Fail closed.
        raise ImportFailure("Environment interpolation expressions are not accepted.")


def validate_values(values: dict[str, str]) -> None:
    if not values:
        raise ImportFailure("No recognized server settings were provided.")
    accepted = setting_names()
    try:
        ImportedSettings(**{accepted[key]: value for key, value in values.items()})
    except ValidationError:
        raise ImportFailure(
            "Server configuration validation failed; check setting formats."
        ) from None


def read_values(path: Path) -> dict[str, str]:
    try:
        with path.open("rb") as source:
            raw = source.read(MAX_SOURCE_BYTES + 1)
        if len(raw) > MAX_SOURCE_BYTES:
            raise ImportFailure("Configuration file exceeds the 64 KiB limit.")
        return parse_values(raw.decode("utf-8-sig"))
    except (OSError, UnicodeError):
        raise ImportFailure("Cannot read the configuration file as UTF-8 text.") from None


def serialize_values(values: dict[str, str]) -> str:
    lines = ["# Private LifeTwin backend configuration. Never commit or source in a shell."]
    for name, value in sorted(values.items()):
        escaped = value.replace("\\", "\\\\").replace("'", "\\'")
        lines.append(f"{name}='{escaped}'")
    return "\n".join(lines) + "\n"


def write_private(values: dict[str, str], output: Path, *, replace: bool = False) -> None:
    output = output.absolute()
    # Refuse tracked/unignored destinations in this checkout before creating anything.
    if output.is_relative_to(REPOSITORY):
        ignored = subprocess.run(
            ["git", "check-ignore", "--quiet", "--", str(output)],
            cwd=REPOSITORY,
            capture_output=True,
            check=False,
        )
        if ignored.returncode != 0:
            raise ImportFailure("Output inside the repository must be gitignored.")
    parent = output.parent
    try:
        parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        parent_stat = parent.lstat()
        if not stat.S_ISDIR(parent_stat.st_mode) or stat.S_IMODE(parent_stat.st_mode) != 0o700:
            raise ImportFailure("Output directory must be a real directory with mode 0700.")
        directory = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        temporary = f".server-env-{secrets.token_hex(12)}"
        try:
            try:
                existing = os.stat(output.name, dir_fd=directory, follow_symlinks=False)
            except FileNotFoundError:
                existing = None
            if existing is not None and not stat.S_ISREG(existing.st_mode):
                raise ImportFailure("Output must not be a symlink or special file.")
            if existing is not None and not replace:
                raise ImportFailure("Output exists; use --replace to replace the private copy.")
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=directory,
            )
            try:
                with os.fdopen(descriptor, "w", encoding="utf-8") as target:
                    os.fchmod(target.fileno(), 0o600)
                    target.write(serialize_values(values))
                    target.flush()
                    os.fsync(target.fileno())
                if replace:
                    os.replace(temporary, output.name, src_dir_fd=directory, dst_dir_fd=directory)
                else:
                    # Atomic create without overwriting a concurrently created destination.
                    os.link(temporary, output.name, src_dir_fd=directory, dst_dir_fd=directory)
                    os.unlink(temporary, dir_fd=directory)
                os.fsync(directory)
            finally:
                try:
                    os.unlink(temporary, dir_fd=directory)
                except FileNotFoundError:
                    pass
        finally:
            os.close(directory)
    except OSError:
        raise ImportFailure("Cannot securely write the private configuration file.") from None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--env-file", type=Path, help="Read settings as data; never source this file"
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--replace", action="store_true", help="Replace an existing private copy")
    parser.add_argument("--prompt", action="store_true", help="Prompt privately for provider keys")
    parser.add_argument(
        "--prompt-key",
        action="append",
        default=[],
        choices=sorted(setting_names()),
        help="Prompt privately for a named setting; repeat to override several settings",
    )
    args = parser.parse_args(argv)
    if not args.env_file and not args.prompt and not args.prompt_key:
        parser.error("provide --env-file, --prompt, or --prompt-key")
    try:
        if args.env_file and args.env_file.resolve() == args.output.resolve():
            raise ImportFailure("Source and output must be different files.")
        if args.env_file and args.output.exists() and os.path.samefile(args.env_file, args.output):
            raise ImportFailure("Source and output must be different files.")
        values = read_values(args.env_file) if args.env_file else {}
        prompts = list(dict.fromkeys([*(DEFAULT_PROMPTS if args.prompt else ()), *args.prompt_key]))
        if prompts and not sys.stdin.isatty():
            # getpass otherwise falls back to an echoed input stream.
            raise ImportFailure("Hidden key entry requires an interactive terminal.")
        for name in prompts:
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                value = getpass.getpass(f"{name} (blank keeps current value): ")
            if value:
                check_value(value)
                values[name] = value
        validate_values(values)
        write_private(values, args.output, replace=args.replace)
    except (ImportFailure, OSError, EOFError, KeyboardInterrupt, getpass.GetPassWarning) as error:
        message = (
            str(error) if isinstance(error, ImportFailure) else "Configuration import stopped."
        )
        print(f"Error: {message}", file=sys.stderr)
        return 1
    print(f"Saved {len(values)} server settings privately (values hidden).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
