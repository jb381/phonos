from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    host: str = "0.0.0.0"
    port: int = 8765
    auth_token: str = ""
    model: str = "base.en"
    models: str = "tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3"
    device: str = "cpu"
    compute_type: str = "int8"
    vad_filter: bool = True

    model_config = {"env_prefix": "PHONOS_", "env_file": ".env"}

    def model_list(self) -> list[str]:
        return [m.strip() for m in self.models.split(",") if m.strip()]


@lru_cache()
def get_settings() -> Settings:
    return Settings()
