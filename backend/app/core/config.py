from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"), env_prefix="PAPER_", extra="ignore"
    )

    app_name: str = "NSE Options Paper Trading"
    environment: Literal["local", "test", "staging", "production"] = "local"
    debug: bool = False
    api_prefix: str = "/api/v1"
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/paper_trading"
    redis_url: str = "redis://localhost:6379/0"
    allowed_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])


@lru_cache
def get_settings() -> Settings:
    return Settings()
