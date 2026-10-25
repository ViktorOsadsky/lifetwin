"""Exercise the secret import boundary without using real provider credentials."""

import importlib.util
import os
import stat
from pathlib import Path

import pytest
from dotenv import dotenv_values

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "server_env.py"
SPEC = importlib.util.spec_from_file_location("server_env", SCRIPT)
server_env = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server_env)


def test_only_backend_settings_are_retained_and_not_interpolated(tmp_path):
    marker = tmp_path / "must-not-exist"
    supplied = (
        "UNRELATED_SECRET=discard-this\n"
        "export LLM_API_KEY='literal-$UNDEFINED'\n"
        f"LLM_MODEL='$(touch {marker})'\n"
        "API_RATE_LIMIT_PER_MINUTE=12\n"
    )
    values = server_env.parse_values(supplied)
    server_env.validate_values(values)
    assert set(values) == {"LLM_API_KEY", "LLM_MODEL", "API_RATE_LIMIT_PER_MINUTE"}
    assert values["LLM_API_KEY"] == "literal-$UNDEFINED"
    assert not marker.exists()


def test_validation_ignores_ambient_and_project_env(monkeypatch):
    monkeypatch.setenv("API_RATE_LIMIT_PER_MINUTE", "invalid-ambient-value")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "ambient-secret")
    server_env.validate_values({"LLM_PROVIDER": "openai"})
    actual = server_env.ImportedSettings()
    assert actual.anthropic_api_key.get_secret_value() == ""
    assert actual.rate_limit_per_minute == 60


@pytest.mark.parametrize(
    "source",
    [
        "LLM_API_KEY='unclosed\n",
        "LLM_API_KEY=one\nLLM_API_KEY=two\n",
        "LLM_API_KEY\n",
        "LLM_API_KEY='${AMBIENT_SECRET}'\n",
        "LLM_API_KEY='line\nbreak'\n",
        "LLM_API_KEY='bad\x00value'\n",
    ],
)
def test_unsafe_input_rejected_without_echo(source):
    with pytest.raises(server_env.ImportFailure) as error:
        server_env.parse_values(source)
    assert source not in str(error.value)
    assert "AMBIENT_SECRET" not in str(error.value)


def test_bad_settings_redacted_and_no_output(tmp_path, capsys):
    source = tmp_path / "input.env"
    secret = "private-invalid-format-should-never-be-printed"
    source.write_text(f"API_MAX_BODY_BYTES={secret}\n")
    destination = tmp_path / "private" / "server.env"
    assert server_env.main(["--env-file", str(source), "--output", str(destination)]) == 1
    output = capsys.readouterr()
    assert secret not in output.out + output.err
    assert not destination.exists()


def test_private_copy_round_trips_values_and_keeps_source(tmp_path, capsys):
    source = tmp_path / "input.env"
    original = "LLM_API_KEY='test-quote\\'and\\\\slash-$literal'\nLLM_MODEL=demo\n"
    source.write_text(original)
    destination = tmp_path / "private" / "server.env"
    assert server_env.main(["--env-file", str(source), "--output", str(destination)]) == 0
    assert source.read_text() == original
    assert stat.S_IMODE(destination.stat().st_mode) == 0o600
    assert stat.S_IMODE(destination.parent.stat().st_mode) == 0o700
    assert dotenv_values(destination, interpolate=False) == server_env.parse_values(original)
    captured = capsys.readouterr()
    assert "test-quote" not in captured.out + captured.err


def test_existing_file_requires_explicit_replace(tmp_path):
    destination = tmp_path / "private" / "server.env"
    server_env.write_private({"LLM_API_KEY": "old"}, destination)
    with pytest.raises(server_env.ImportFailure, match="Output exists"):
        server_env.write_private({"LLM_API_KEY": "new"}, destination)
    assert dotenv_values(destination)["LLM_API_KEY"] == "old"
    server_env.write_private({"LLM_API_KEY": "new"}, destination, replace=True)
    assert dotenv_values(destination)["LLM_API_KEY"] == "new"
    assert stat.S_IMODE(destination.stat().st_mode) == 0o600
    assert list(destination.parent.iterdir()) == [destination]


def test_source_cannot_be_overwritten_even_via_hardlink(tmp_path, capsys):
    source = tmp_path / "input.env"
    source.write_text("LLM_API_KEY=keep-me\n")
    directory = tmp_path / "private"
    directory.mkdir(mode=0o700)
    output = directory / "server.env"
    os.link(source, output)
    assert (
        server_env.main(
            [
                "--env-file",
                str(source),
                "--output",
                str(output),
                "--replace",
            ]
        )
        == 1
    )
    assert source.read_text() == "LLM_API_KEY=keep-me\n"
    assert "keep-me" not in capsys.readouterr().err


def test_symlink_output_and_insecure_directory_are_rejected(tmp_path):
    source = tmp_path / "untouched.env"
    source.write_text("untouched")
    directory = tmp_path / "private"
    directory.mkdir(mode=0o700)
    output = directory / "server.env"
    output.symlink_to(source)
    with pytest.raises(server_env.ImportFailure, match="symlink"):
        server_env.write_private({"LLM_API_KEY": "secret"}, output, replace=True)
    output.unlink()
    directory.chmod(0o755)
    with pytest.raises(server_env.ImportFailure, match="0700"):
        server_env.write_private({"LLM_API_KEY": "secret"}, output)
    assert source.read_text() == "untouched"


def test_hidden_prompts_refuse_redirected_input(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(server_env.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(server_env.getpass, "getpass", lambda _: pytest.fail("must not read"))
    output = tmp_path / "private" / "server.env"
    assert server_env.main(["--prompt", "--output", str(output)]) == 1
    assert "interactive terminal" in capsys.readouterr().err
    assert not output.exists()


def test_prompt_can_override_import_without_printing_values(tmp_path, monkeypatch, capsys):
    source = tmp_path / "input.env"
    source.write_text("LLM_API_KEY=old\n")
    monkeypatch.setattr(server_env.sys.stdin, "isatty", lambda: True)
    monkeypatch.setattr(server_env.getpass, "getpass", lambda _: "new-hidden-value")
    output = tmp_path / "private" / "server.env"
    assert (
        server_env.main(
            [
                "--env-file",
                str(source),
                "--output",
                str(output),
                "--prompt-key",
                "LLM_API_KEY",
            ]
        )
        == 0
    )
    assert dotenv_values(output)["LLM_API_KEY"] == "new-hidden-value"
    captured = capsys.readouterr()
    assert "new-hidden-value" not in captured.out + captured.err


def test_output_in_checkout_must_be_ignored():
    with pytest.raises(server_env.ImportFailure, match="gitignored"):
        server_env.write_private({"LLM_API_KEY": "secret"}, SCRIPT.parent / "accidental-secret.env")


def test_source_size_is_bounded(tmp_path):
    source = tmp_path / "input.env"
    source.write_bytes(b"x" * (server_env.MAX_SOURCE_BYTES + 1))
    with pytest.raises(server_env.ImportFailure, match="64 KiB"):
        server_env.read_values(source)


def test_getpass_fallback_warning_stops_without_echo(tmp_path, monkeypatch, capsys):
    import warnings

    monkeypatch.setattr(server_env.sys.stdin, "isatty", lambda: True)

    def unavailable_prompt(_):
        warnings.warn("fallback would echo", server_env.getpass.GetPassWarning, stacklevel=1)
        pytest.fail("must stop before echoed fallback")

    monkeypatch.setattr(server_env.getpass, "getpass", unavailable_prompt)
    output = tmp_path / "private" / "server.env"
    assert server_env.main(["--prompt", "--output", str(output)]) == 1
    assert "fallback would echo" not in capsys.readouterr().err
    assert not output.exists()
