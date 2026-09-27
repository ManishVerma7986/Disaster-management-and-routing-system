from datetime import datetime, timezone
from enum import Enum
import re
from pydantic import BaseModel, Field, model_validator
from pydantic import field_validator


class Role(str, Enum):
    USER = "USER"
    AUTHORITY = "AUTHORITY"
    ADMIN = "ADMIN"


class RiskLevel(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class RoutingMode(str, Enum):
    EMERGENCY = "EMERGENCY"
    DRIVING = "DRIVING"
    WALKING = "WALKING"
    CYCLING = "CYCLING"


class User(BaseModel):
    id: str
    name: str
    email: str
    password_hash: str
    role: Role


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
            raise ValueError("email must be valid")
        return normalized


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.strip().lower()


class Road(BaseModel):
    id: str
    name: str
    start_node: str
    end_node: str
    distance_km: float
    travel_time_minutes: float
    flood_risk: RiskLevel
    landslide_risk: RiskLevel
    confidence: int = Field(ge=0, le=100)
    geometry: list[list[float]]
    closure_reason: str | None = None
    closure_severity: RiskLevel | None = None
    closure_start_time: datetime | None = None
    closure_end_time: datetime | None = None
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class RouteRequest(BaseModel):
    source: str = Field(min_length=1, max_length=200)
    destination: str = Field(min_length=1, max_length=200)
    mode: RoutingMode = RoutingMode.EMERGENCY


class RouteSegment(BaseModel):
    road_id: str
    road_name: str
    distance_km: float
    travel_time_minutes: float
    flood_risk: RiskLevel
    landslide_risk: RiskLevel
    closure_status: str
    warning: str | None = None
    geometry: list[list[float]]
    weather_risk: RiskLevel = RiskLevel.LOW
    traffic_status: str = "UNKNOWN"
    traffic_speed_factor: float = 1.0


class RouteResult(BaseModel):
    route_id: str
    recommended: bool
    distance_km: float
    eta_minutes: float
    risk: dict
    warnings: list[str]
    reason: str
    geometry: list[list[float]]
    segments: list[RouteSegment]


class RouteResponse(BaseModel):
    recommended: RouteResult
    alternatives: list[RouteResult]
    destination_risk: RiskLevel
    data_status: str = "PRODUCTION"


class ClosureRequest(BaseModel):
    road_id: str
    reason: str = Field(min_length=3, max_length=200)
    severity: RiskLevel
    start_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    end_time: datetime | None = None

    @model_validator(mode="after")
    def normalize_times(self):
        if self.start_time.tzinfo is None:
            self.start_time = self.start_time.replace(tzinfo=timezone.utc)
        if self.end_time is not None and self.end_time.tzinfo is None:
            self.end_time = self.end_time.replace(tzinfo=timezone.utc)
        return self

    @property
    def is_valid_window(self) -> bool:
        return self.end_time is None or self.end_time > self.start_time


class ReportRequest(BaseModel):
    client_id: str | None = Field(default=None, min_length=8, max_length=100)
    problem_type: str = Field(min_length=2, max_length=40)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    description: str = Field(min_length=3, max_length=1000)
    photo_data: str | None = Field(default=None, max_length=8_000_000)


class IncidentRequest(BaseModel):
    problem_type: str = Field(min_length=2, max_length=40)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    severity: RiskLevel = RiskLevel.MEDIUM
    report_id: str | None = None


class WarningRequest(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(min_length=3, max_length=500)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    radius_km: float = Field(default=5, gt=0, le=250)
    severity: RiskLevel = RiskLevel.MEDIUM
    expires_at: datetime | None = None

    @model_validator(mode="after")
    def normalize_expiry(self):
        if self.expires_at is not None and self.expires_at.tzinfo is None:
            self.expires_at = self.expires_at.replace(tzinfo=timezone.utc)
        return self


class WeatherRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class PredictionRequest(WeatherRequest):
    slope: float = Field(default=0, ge=0, le=90)


class SosRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    message: str = Field(default="Emergency assistance requested", max_length=300)


class SyncRequest(BaseModel):
    base_version: int | None = Field(default=None, ge=1)
    pending_reports: list[ReportRequest] = Field(default_factory=list, max_length=50)


class DeviceTokenRequest(BaseModel):
    token: str = Field(min_length=10, max_length=4096)
    platform: str = Field(min_length=2, max_length=20)


class CreateAdminRequest(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    role: Role = Field(default=Role.ADMIN)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
            raise ValueError("email must be valid")
        return normalized
