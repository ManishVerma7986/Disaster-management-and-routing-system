from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import model_validator


BACKEND_DIR = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    app_name: str = "Disaster Aware Routing API"
    environment: str = "development"
    jwt_secret: str = "development-only-secret"
    jwt_expire_minutes: int = 60
    cors_origins: str = "http://127.0.0.1:8000,http://localhost:8000"
    database_url: str = "sqlite:///./disaster_routing.db"
    weather_api_key: str | None = None
    weather_api_url: str = "https://api.openweathermap.org/data/2.5/weather"
    traffic_api_key: str | None = None
    traffic_api_url: str | None = None
    tomtom_api_key: str | None = None
    geoapify_api_key: str | None = None
    geoapify_api_url: str = "https://api.geoapify.com/v1/geocode/search"
    geoapify_reverse_url: str = "https://api.geoapify.com/v1/geocode/reverse"
    geoapify_places_url: str = "https://api.geoapify.com/v2/places"
    graphhopper_api_key: str | None = None
    graphhopper_api_url: str = "https://graphhopper.com/api/1/route"
    graphhopper_match_tolerance_km: float = 0.25

    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", extra="ignore")

    @model_validator(mode="after")
    def validate_production_secret(self):
        if self.environment.lower() == "production" and (self.jwt_secret == "development-only-secret" or len(self.jwt_secret) < 32):
            raise ValueError("production requires a JWT_SECRET of at least 32 characters")
        return self


settings = Settings()
