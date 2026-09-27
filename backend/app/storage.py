from datetime import datetime, timezone
from typing import Any, Optional
from sqlalchemy import JSON, DateTime, Float, Integer, String, Text, create_engine, select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from .config import settings
from .models import Road, RiskLevel, Role, User
from .services import Facility


class Base(DeclarativeBase):
    pass


class RoadRow(Base):
    __tablename__ = "roads"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    start_node: Mapped[str] = mapped_column(String(64))
    end_node: Mapped[str] = mapped_column(String(64))
    distance_km: Mapped[float] = mapped_column(Float)
    travel_time_minutes: Mapped[float] = mapped_column(Float)
    flood_risk: Mapped[str] = mapped_column(String(16))
    landslide_risk: Mapped[str] = mapped_column(String(16))
    confidence: Mapped[int] = mapped_column(Integer)
    geometry: Mapped[list[list[float]]] = mapped_column(JSON)
    closure_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    closure_severity: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    closure_start_time: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    closure_end_time: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class UserRow(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(16))


class ReportRow(Base):
    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    client_id: Mapped[Optional[str]] = mapped_column(String(100), unique=True, nullable=True, index=True)
    user_id: Mapped[str] = mapped_column(String(64))
    problem_type: Mapped[str] = mapped_column(String(40))
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    description: Mapped[str] = mapped_column(Text)
    photo_data: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(16))
    confidence: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AuditLogRow(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor: Mapped[str] = mapped_column(String(255))
    action: Mapped[str] = mapped_column(String(64))
    road_id: Mapped[str] = mapped_column(String(32))
    reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class IncidentRow(Base):
    __tablename__ = "incidents"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    incident_type: Mapped[str] = mapped_column("type", String(40))
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    severity: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16))
    confidence: Mapped[int] = mapped_column(Integer)
    report_ids: Mapped[list[str]] = mapped_column(JSON)
    source: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class FacilityRow(Base):
    __tablename__ = "emergency_facilities"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(160))
    facility_type: Mapped[str] = mapped_column("type", String(40))
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    risk_level: Mapped[str] = mapped_column(String(16))
    contact: Mapped[str] = mapped_column(String(64))
    source: Mapped[str] = mapped_column(String(120))


class DeviceTokenRow(Base):
    __tablename__ = "device_tokens"

    token: Mapped[str] = mapped_column(String(4096), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    platform: Mapped[str] = mapped_column(String(20))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SyncStateRow(Base):
    __tablename__ = "sync_state"

    key: Mapped[str] = mapped_column(String(32), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SosRow(Base):
    __tablename__ = "sos_events"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    message: Mapped[str] = mapped_column(String(300))
    status: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class WarningRow(Base):
    __tablename__ = "warnings"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(500))
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    radius_km: Mapped[float] = mapped_column(Float)
    severity: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    source: Mapped[str] = mapped_column(String(120))


connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {"connect_timeout": 5}
storage_mode = "configured"

try:
    engine = create_engine(settings.database_url, connect_args=connect_args, connect_args_timeout=5 if not settings.database_url.startswith("sqlite") else None, pool_pre_ping=True)
except ModuleNotFoundError as error:
    if not settings.database_url.startswith("postgresql") or error.name != "psycopg":
        raise
    engine = create_engine("sqlite:///./disaster_routing.db", connect_args={"check_same_thread": False})
    storage_mode = "sqlite-fallback"
except (Exception, TimeoutError):
    # Fall back to SQLite if PostgreSQL connection times out or fails
    engine = create_engine("sqlite:///./disaster_routing.db", connect_args={"check_same_thread": False})
    storage_mode = "sqlite-fallback"
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_storage_mode() -> str:
    return storage_mode


def use_sqlite_fallback() -> None:
    global engine, SessionLocal, storage_mode
    engine = create_engine("sqlite:///./disaster_routing.db", connect_args={"check_same_thread": False})
    SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)
    storage_mode = "sqlite-fallback"


def _road_from_row(row: RoadRow) -> Road:
    return Road(id=row.id, name=row.name, start_node=row.start_node, end_node=row.end_node, distance_km=row.distance_km, travel_time_minutes=row.travel_time_minutes, flood_risk=RiskLevel(row.flood_risk), landslide_risk=RiskLevel(row.landslide_risk), confidence=row.confidence, geometry=row.geometry, closure_reason=row.closure_reason, closure_severity=RiskLevel(row.closure_severity) if row.closure_severity else None, closure_start_time=as_utc(row.closure_start_time), closure_end_time=as_utc(row.closure_end_time), updated_at=as_utc(row.updated_at) or datetime.now(timezone.utc))


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def init_storage(initial_roads: list[Road]) -> tuple[list[Road], list[dict], list[dict]]:
    global storage_mode
    try:
        Base.metadata.create_all(engine)
        with engine.connect() as connection:
            connection.exec_driver_sql("SELECT 1")
    except OperationalError:
        use_sqlite_fallback()
        Base.metadata.create_all(engine)
    storage_mode = storage_mode if storage_mode == "sqlite-fallback" else "configured"
    migrate_road_closure_columns()
    migrate_report_client_id_column()
    migrate_report_photo_column()
    with SessionLocal() as session:
        if session.scalar(select(RoadRow.id).limit(1)) is None:
            session.add_all(RoadRow(id=road.id, name=road.name, start_node=road.start_node, end_node=road.end_node, distance_km=road.distance_km, travel_time_minutes=road.travel_time_minutes, flood_risk=road.flood_risk.value, landslide_risk=road.landslide_risk.value, confidence=road.confidence, geometry=road.geometry, closure_reason=road.closure_reason, closure_severity=road.closure_severity.value if road.closure_severity else None, closure_start_time=road.closure_start_time, closure_end_time=road.closure_end_time, updated_at=road.updated_at) for road in initial_roads)
            session.commit()
        roads = [_road_from_row(row) for row in session.scalars(select(RoadRow).order_by(RoadRow.id))]
        reports = [report_to_dict(row) for row in session.scalars(select(ReportRow).order_by(ReportRow.created_at))]
        audit_logs = [audit_to_dict(row) for row in session.scalars(select(AuditLogRow).order_by(AuditLogRow.id))]
        return roads, reports, audit_logs


def seed_facilities(facilities: list[Facility]) -> None:
    # Skip seeding facilities - using real-time Geoapify data instead
    print("ℹ️ Skipping facility seeding - using real-time Geoapify data")


def current_sync_version() -> int:
    with SessionLocal.begin() as session:
        row = session.get(SyncStateRow, "global")
        if row is None:
            row = SyncStateRow(key="global", version=1, updated_at=datetime.now(timezone.utc))
            session.add(row)
            return row.version
        return row.version


def save_sos(event: dict[str, Any]) -> None:
    with SessionLocal.begin() as session:
        session.add(SosRow(id=event["id"], user_id=event["user_id"], lat=event["lat"], lon=event["lon"], message=event["message"], status=event["status"], created_at=datetime.fromisoformat(event["created_at"])))
    bump_sync_version()


def list_sos_for_user(user_id: str) -> list[dict[str, Any]]:
    with SessionLocal() as session:
        return [{"id": row.id, "user_id": row.user_id, "lat": row.lat, "lon": row.lon, "message": row.message, "status": row.status, "created_at": row.created_at.isoformat()} for row in session.scalars(select(SosRow).where(SosRow.user_id == user_id).order_by(SosRow.created_at.desc()))]


def save_warning(warning: dict[str, Any]) -> None:
    with SessionLocal.begin() as session:
        session.add(WarningRow(id=warning["id"], title=warning["title"], description=warning["description"], lat=warning["lat"], lon=warning["lon"], radius_km=warning["radius_km"], severity=warning["severity"], status=warning["status"], expires_at=datetime.fromisoformat(warning["expires_at"]) if warning.get("expires_at") else None, created_at=datetime.fromisoformat(warning["created_at"]), source=warning["source"]))
    bump_sync_version()


def list_warnings() -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    with SessionLocal() as session:
        return [{"id": row.id, "title": row.title, "description": row.description, "lat": row.lat, "lon": row.lon, "radius_km": row.radius_km, "severity": row.severity, "status": row.status if row.expires_at is None or as_utc(row.expires_at) > now else "EXPIRED", "expires_at": as_utc(row.expires_at).isoformat() if row.expires_at else None, "created_at": as_utc(row.created_at).isoformat(), "source": row.source} for row in session.scalars(select(WarningRow).order_by(WarningRow.created_at.desc()))]


def bump_sync_version() -> int:
    with SessionLocal.begin() as session:
        row = session.get(SyncStateRow, "global")
        if row is None:
            row = SyncStateRow(key="global", version=2, updated_at=datetime.now(timezone.utc))
            session.add(row)
        else:
            row.version += 1
            row.updated_at = datetime.now(timezone.utc)
        return row.version


def save_incident(incident: dict[str, Any]) -> None:
    changed = False
    with SessionLocal.begin() as session:
        existing = session.get(IncidentRow, incident["id"])
        if existing:
            existing.confidence = incident["confidence"]
            existing.report_ids = incident["report_ids"]
            changed = True
        else:
            session.add(IncidentRow(id=incident["id"], incident_type=incident["type"], lat=incident["lat"], lon=incident["lon"], severity=incident["severity"], status=incident["status"], confidence=incident["confidence"], report_ids=incident["report_ids"], source=incident["source"], created_at=datetime.fromisoformat(incident["created_at"])))
            changed = True
    if changed:
        bump_sync_version()


def update_incident_status(incident_id: str, new_status: str) -> bool:
    """Update the status of an incident (e.g., ACTIVE -> RESOLVED)."""
    with SessionLocal.begin() as session:
        existing = session.get(IncidentRow, incident_id)
        if existing:
            existing.status = new_status
            bump_sync_version()
            return True
        return False


def list_incidents() -> list[dict[str, Any]]:
    with SessionLocal() as session:
        return [{"id": row.id, "type": row.incident_type, "lat": row.lat, "lon": row.lon, "severity": row.severity, "status": row.status, "confidence": row.confidence, "report_ids": row.report_ids, "source": row.source, "created_at": row.created_at.isoformat()} for row in session.scalars(select(IncidentRow).order_by(IncidentRow.created_at.desc()))]


def list_facilities() -> list[dict[str, Any]]:
    with SessionLocal() as session:
        return [{"id": row.id, "name": row.name, "type": row.facility_type, "lat": row.lat, "lon": row.lon, "risk_level": row.risk_level, "contact": row.contact, "source": row.source} for row in session.scalars(select(FacilityRow).order_by(FacilityRow.name))]


def save_facility(facility: dict[str, Any]) -> None:
    """Save an emergency facility locally (user favorite)."""
    with SessionLocal.begin() as session:
        existing = session.get(FacilityRow, facility["id"])
        if not existing:
            session.add(FacilityRow(
                id=facility["id"],
                name=facility["name"],
                facility_type=facility.get("type", "UNKNOWN"),
                lat=facility["lat"],
                lon=facility["lon"],
                risk_level=facility.get("risk_level", "LOW"),
                contact=facility.get("contact", ""),
                source=facility.get("source", "USER_SAVED")
            ))


def delete_facility(facility_id: str) -> None:
    """Delete a saved emergency facility."""
    with SessionLocal.begin() as session:
        row = session.get(FacilityRow, facility_id)
        if row:
            session.delete(row)


def save_device_token(user_id: str, token: str, platform: str) -> None:
    with SessionLocal.begin() as session:
        row = session.get(DeviceTokenRow, token)
        if row:
            row.user_id = user_id
            row.platform = platform
            row.updated_at = datetime.now(timezone.utc)
        else:
            session.add(DeviceTokenRow(token=token, user_id=user_id, platform=platform, updated_at=datetime.now(timezone.utc)))


def migrate_road_closure_columns() -> None:
    from sqlalchemy import inspect, text
    columns = {column["name"] for column in inspect(engine).get_columns("roads")}
    with engine.begin() as connection:
        if "closure_start_time" not in columns:
            connection.execute(text("ALTER TABLE roads ADD COLUMN closure_start_time TIMESTAMP"))
        if "closure_end_time" not in columns:
            connection.execute(text("ALTER TABLE roads ADD COLUMN closure_end_time TIMESTAMP"))


def migrate_report_client_id_column() -> None:
    from sqlalchemy import inspect, text
    columns = {column["name"] for column in inspect(engine).get_columns("reports")}
    if "client_id" not in columns:
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE reports ADD COLUMN client_id VARCHAR(100)"))


def migrate_report_photo_column() -> None:
    from sqlalchemy import inspect, text
    columns = {column["name"] for column in inspect(engine).get_columns("reports")}
    if "photo_data" not in columns:
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE reports ADD COLUMN photo_data TEXT"))


def get_user(user_id: str) -> User | None:
    with SessionLocal() as session:
        row = session.get(UserRow, user_id)
        return user_from_row(row) if row else None


def get_user_by_email(email: str) -> User | None:
    with SessionLocal() as session:
        row = session.scalar(select(UserRow).where(UserRow.email == email))
        return user_from_row(row) if row else None


def save_user(user: User) -> None:
    with SessionLocal.begin() as session:
        session.add(UserRow(id=user.id, name=user.name, email=user.email, password_hash=user.password_hash, role=user.role.value))


def user_from_row(row: UserRow) -> User:
    return User(id=row.id, name=row.name, email=row.email, password_hash=row.password_hash, role=Role(row.role))


def save_road(road: Road) -> None:
    with SessionLocal.begin() as session:
        row = session.get(RoadRow, road.id)
        if row is None:
            raise KeyError(road.id)
        row.closure_reason = road.closure_reason
        row.closure_severity = road.closure_severity.value if road.closure_severity else None
        row.closure_start_time = road.closure_start_time
        row.closure_end_time = road.closure_end_time
        row.updated_at = road.updated_at
    bump_sync_version()


def save_report(report: dict[str, Any]) -> None:
    with SessionLocal.begin() as session:
        session.add(ReportRow(id=report["id"], client_id=report.get("client_id"), user_id=report["user_id"], problem_type=report["problem_type"], lat=report["lat"], lon=report["lon"], description=report["description"], photo_data=report.get("photo_data"), status=report["status"], confidence=report["confidence"], created_at=datetime.fromisoformat(report["created_at"])))
    bump_sync_version()


def get_report_by_client_id(client_id: str, user_id: str) -> dict[str, Any] | None:
    with SessionLocal() as session:
        row = session.scalar(select(ReportRow).where(ReportRow.client_id == client_id, ReportRow.user_id == user_id))
        return report_to_dict(row) if row else None


def update_report_status(report_id: str, status: str, confidence: int) -> bool:
    with SessionLocal.begin() as session:
        row = session.get(ReportRow, report_id)
        if row is None:
            return False
        row.status = status
        row.confidence = confidence
    bump_sync_version()
    return True


def save_audit_log(entry: dict[str, Any]) -> None:
    with SessionLocal.begin() as session:
        session.add(AuditLogRow(actor=entry["actor"], action=entry["action"], road_id=entry["road_id"], reason=entry.get("reason"), created_at=datetime.fromisoformat(entry["created_at"])))


def report_to_dict(row: ReportRow) -> dict[str, Any]:
    return {"id": row.id, "client_id": row.client_id, "user_id": row.user_id, "problem_type": row.problem_type, "lat": row.lat, "lon": row.lon, "description": row.description, "photo_data": row.photo_data, "status": row.status, "confidence": row.confidence, "created_at": row.created_at.isoformat()}


def get_reports_for_user(user_id: str) -> list[dict[str, Any]]:
    with SessionLocal() as session:
        return [report_to_dict(row) for row in session.scalars(select(ReportRow).where(ReportRow.user_id == user_id).order_by(ReportRow.created_at.desc()))]


def audit_to_dict(row: AuditLogRow) -> dict[str, Any]:
    return {"actor": row.actor, "action": row.action, "road_id": row.road_id, "reason": row.reason, "created_at": row.created_at.isoformat()}
