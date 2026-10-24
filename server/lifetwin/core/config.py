"""Blank-by-default provider settings; never require credentials to start."""

from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

    app_env: Literal["development", "test", "production"] = "development"
    openai_api_key: SecretStr = SecretStr("")
    openai_model: str = ""
    # Conversation-guide provider: "openai" keeps the OPENAI_* settings above.
    llm_provider: Literal["openai", "chat_completions"] = "openai"
    llm_base_url: str = ""
    llm_model: str = ""
    llm_api_key: SecretStr = SecretStr("")
    # Reasoning models (e.g. Muse) spend the token budget thinking unless effort is limited.
    llm_reasoning_effort: Literal["", "minimal", "low", "medium", "high"] = "minimal"
    # Coach rewording (Muse, with consent): calls per client per day, and its time budget.
    coach_llm_daily_cap: int = Field(default=30, ge=0, le=10000)
    coach_llm_timeout_seconds: float = Field(default=10, gt=0, le=20)
    tavily_api_key: SecretStr = SecretStr("")
    cartesia_api_key: SecretStr = SecretStr("")
    cartesia_version: str = "2026-08-14"
    cartesia_tts_model: str = "sonic-3.6"
    cartesia_stt_model: str = "ink-2"
    cartesia_voice_id: str = ""
    cartesia_tts_speed: float = Field(default=0.9, ge=0.6, le=1.5)
    cartesia_token_ttl_seconds: int = Field(default=300, ge=60, le=900)
    # Folder holding model.keras, preprocessor.joblib, baseline_hazard.csv and metrics.json.
    # Blank means the repository root. Missing files keep /api/predict deferred (501).
    model_artifact_path: str = ""
    provider_timeout_seconds: float = Field(
        default=12, gt=0, le=30, validation_alias="API_PROVIDER_TIMEOUT_SECONDS"
    )
    request_timeout_seconds: float = Field(
        default=25, gt=0, le=60, validation_alias="API_REQUEST_TIMEOUT_SECONDS"
    )
    max_body_bytes: int = Field(
        default=32768, ge=128, le=1048576, validation_alias="API_MAX_BODY_BYTES"
    )
    rate_limit_per_minute: int = Field(
        default=60, ge=1, le=10000, validation_alias="API_RATE_LIMIT_PER_MINUTE"
    )
    max_concurrent_requests: int = Field(
        default=16, ge=1, le=128, validation_alias="API_MAX_CONCURRENT_REQUESTS"
    )
    cors_origins: str = ""

    @field_validator("llm_provider", mode="before")
    @classmethod
    def blank_provider_is_default(cls, value):
        return "openai" if isinstance(value, str) and not value.strip() else value

    @field_validator("cors_origins")
    @classmethod
    def exact_origins_only(cls, value: str) -> str:
        normalized = []
        for origin in filter(None, (part.strip(" ") for part in value.split(","))):
            if any(
                character.isspace() or ord(character) < 32 or ord(character) == 127
                for character in origin
            ):
                raise ValueError("CORS origins cannot contain whitespace or control characters")
            parsed = urlsplit(origin)
            # Accessing .port validates nonnumeric and out-of-range ports.
            port = parsed.port
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or "*" in origin
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path not in {"", "/"}
                or "?" in origin
                or "#" in origin
                or port == 0
            ):
                raise ValueError("CORS origins must be explicit HTTP(S) origins")
            host = parsed.hostname.encode("idna").decode("ascii").lower()
            if ":" in host:
                host = f"[{host}]"
            if port is not None and port != {"http": 80, "https": 443}[parsed.scheme]:
                host += f":{port}"
            canonical = f"{parsed.scheme}://{host}"
            if canonical not in normalized:
                normalized.append(canonical)
        return ",".join(normalized)

    @property
    def llm_endpoint(self) -> str:
        if self.llm_provider != "chat_completions":
            return ""
        return self.llm_base_url.strip() or "https://api.meta.ai/v1"

    @property
    def llm_configured(self) -> bool:
        if self.llm_provider == "chat_completions":
            return bool(
                self.llm_api_key.get_secret_value().strip()
                and self.llm_model.strip()
                and self.llm_endpoint
            )
        return bool(self.openai_api_key.get_secret_value().strip() and self.openai_model.strip())

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip().rstrip("/") for origin in self.cors_origins.split(",") if origin.strip()
        ]
