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
    tavily_api_key: SecretStr = SecretStr("")
    # Reserved; never read or loaded by this backend.
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

    @field_validator("cors_origins")
    @classmethod
    def exact_origins_only(cls, value: str) -> str:
        for origin in filter(None, (part.strip() for part in value.split(","))):
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or "*" in origin
                or parsed.username
                or parsed.password
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError("CORS origins must be explicit HTTP(S) origins")
        return value

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip().rstrip("/") for origin in self.cors_origins.split(",") if origin.strip()
        ]
