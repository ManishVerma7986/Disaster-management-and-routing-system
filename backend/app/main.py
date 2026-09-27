from datetime import datetime, timezone
import re
import asyncio
import httpx
import jwt
from uuid import uuid4
from fastapi import Depends, FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .models import ClosureRequest, CreateAdminRequest, DeviceTokenRequest, IncidentRequest, LoginRequest, PredictionRequest, RegisterRequest, ReportRequest, RiskLevel, Role, RouteRequest, RouteResponse, SosRequest, SyncRequest, User, WarningRequest, WeatherRequest
from .routing import find_paths, summarize
from .seed import initial_roads
from .security import create_token, current_user, hash_password, require_roles, verify_password
from .storage import current_sync_version, get_report_by_client_id, get_reports_for_user, get_storage_mode, get_user, get_user_by_email, init_storage, list_facilities, save_facility, delete_facility, list_incidents, list_sos_for_user, list_warnings, save_audit_log, save_device_token, save_incident, save_report, save_road, save_sos, save_user, save_warning, seed_facilities, update_incident_status, update_report_status
from .services import GEOAPIFY, GRAPHHOPPER, INCIDENTS, TRAFFIC, WEATHER, annotate_online_route, enrich_route_risk, group_incident, predict_risk, facilities_near
from .services import distance_km

app = FastAPI(title=settings.app_name, version="0.1.0", description="Explainable disaster-aware routing API")
app.add_middleware(CORSMiddleware, allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
COORDINATE_PATTERN = re.compile(r"@?\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)")

roads, reports, audit_logs = init_storage(initial_roads())
# seed_facilities(FACILITIES)  # Removed - using real-time Geoapify data
INCIDENTS.extend(list_incidents())


class IncidentConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[WebSocket, tuple[asyncio.AbstractEventLoop, asyncio.Queue[dict]]] = {}

    def add(self, websocket: WebSocket, loop: asyncio.AbstractEventLoop, queue: asyncio.Queue[dict]) -> None:
        self._connections[websocket] = (loop, queue)

    def remove(self, websocket: WebSocket) -> None:
        self._connections.pop(websocket, None)

    def publish(self, incident: dict) -> None:
        event = {"event": "incident_updated", "incident": incident}
        for loop, queue in tuple(self._connections.values()):
            loop.call_soon_threadsafe(queue.put_nowait, event)


incident_connections = IncidentConnectionManager()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "data_status": "PRODUCTION", "storage_mode": get_storage_mode(), "updated_at": datetime.now(timezone.utc).isoformat()}


@app.post("/auth/register")
def register(request: RegisterRequest) -> dict:
    if get_user_by_email(request.email):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(id=str(uuid4()), name=request.name, email=request.email, password_hash=hash_password(request.password), role=Role.USER)
    save_user(user)
    return {"access_token": create_token(user), "token_type": "bearer", "user": user.model_dump(exclude={"password_hash"})}


@app.post("/auth/login")
def login(request: LoginRequest) -> dict:
    user = get_user_by_email(request.email)
    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return {"access_token": create_token(user), "token_type": "bearer", "user": user.model_dump(exclude={"password_hash"})}


@app.get("/auth/me")
def me(user: User = Depends(current_user)) -> dict:
    return user.model_dump(exclude={"password_hash"})


@app.post("/auth/create-admin")
def create_admin(request: CreateAdminRequest, admin: User = Depends(require_roles(Role.ADMIN, Role.AUTHORITY))) -> dict:
    """Create a new admin or authority account. Only accessible by existing admins or authorities."""
    if get_user_by_email(request.email):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(id=str(uuid4()), name=request.name, email=request.email, password_hash=hash_password(request.password), role=request.role)
    save_user(user)
    entry = {"actor": admin.email, "action": "CREATE_ADMIN", "road_id": user.id, "reason": f"Created {request.role.value} account", "created_at": datetime.now(timezone.utc).isoformat()}
    audit_logs.append(entry)
    save_audit_log(entry)
    return {"access_token": create_token(user), "token_type": "bearer", "user": user.model_dump(exclude={"password_hash"})}


@app.post("/devices/push-token")
def register_push_token(request: DeviceTokenRequest, user: User = Depends(current_user)) -> dict:
    save_device_token(user.id, request.token, request.platform)
    return {"registered": True, "platform": request.platform}


@app.get("/roads")
def get_roads() -> list[dict]:
    return [road.model_dump(mode="json") for road in roads]


@app.get("/closures")
def get_closures() -> list[dict]:
    refresh_expired_closures()
    return [road.model_dump(mode="json") for road in roads if road.closure_reason]


@app.post("/closures")
def create_closure(request: ClosureRequest, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    if not request.is_valid_window:
        raise HTTPException(status_code=422, detail="end_time must be later than start_time")
    road = next((road for road in roads if road.id == request.road_id), None)
    if not road:
        raise HTTPException(status_code=404, detail="Road not found")
    road.closure_reason = request.reason
    road.closure_severity = request.severity
    road.closure_start_time = request.start_time
    road.closure_end_time = request.end_time
    road.updated_at = datetime.now(timezone.utc)
    save_road(road)
    entry = {"actor": authority.email, "action": "CREATE_CLOSURE", "road_id": road.id, "reason": request.reason, "created_at": road.updated_at.isoformat()}
    audit_logs.append(entry)
    save_audit_log(entry)
    return road.model_dump(mode="json")


@app.delete("/closures/{road_id}")
def remove_closure(road_id: str, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    road = next((road for road in roads if road.id == road_id), None)
    if not road:
        raise HTTPException(status_code=404, detail="Road not found")
    road.closure_reason = None
    road.closure_severity = None
    road.closure_start_time = None
    road.closure_end_time = None
    road.updated_at = datetime.now(timezone.utc)
    save_road(road)
    entry = {"actor": authority.email, "action": "REMOVE_CLOSURE", "road_id": road.id, "created_at": road.updated_at.isoformat()}
    audit_logs.append(entry)
    save_audit_log(entry)
    return {"status": "OPEN", "road_id": road_id}


@app.post("/route", response_model=RouteResponse)
def route(request: RouteRequest) -> RouteResponse:
    print(f"🚀 Route request: source={request.source}, destination={request.destination}, mode={request.mode}")
    refresh_expired_closures()
    coordinate_points = [parse_coordinates(request.source), parse_coordinates(request.destination)]
    print(f"📍 Parsed coordinates: {coordinate_points}")
    
    traffic_data = {}
    try:
        traffic_data = TRAFFIC.current([road.id for road in roads], roads)
    except (RuntimeError, ValueError, httpx.HTTPError):
        traffic_data = {}
    weather_risk = RiskLevel.LOW
    weather_point = next((point for point in reversed(coordinate_points) if point is not None), None)
    if weather_point is None and roads and roads[0].geometry:
        weather_point = (roads[0].geometry[0][0], roads[0].geometry[0][1])
    if weather_point is not None:
        try:
            weather_risk = RiskLevel(predict_risk(weather_point[0], weather_point[1])["flood"])
        except (RuntimeError, ValueError, httpx.HTTPError):
            weather_risk = RiskLevel.LOW

    # Try online routing for DRIVING/WALKING/CYCLING modes and EMERGENCY mode
    # EMERGENCY mode uses online routing to handle real-world facility coordinates
    if all(point is not None for point in coordinate_points) and request.mode.value in ("DRIVING", "WALKING", "CYCLING", "EMERGENCY"):
        try:
            # For EMERGENCY mode, use DRIVING as the routing mode for GraphHopper
            routing_mode = request.mode.value if request.mode.value != "EMERGENCY" else "DRIVING"
            print(f"🌐 Attempting online routing with mode: {routing_mode}")
            online = GRAPHHOPPER.route([point for point in coordinate_points if point is not None], routing_mode)
            # Only use online route if geometry matching succeeds
            annotate_online_route(online, roads)
            if online.get("segments"):  # Only proceed if geometry was matched
                apply_environment_risk(online, weather_risk, traffic_data)
                online = enrich_route_risk(online, INCIDENTS)
                alternatives = []
                for alternative in online.get("alternatives", []):
                    apply_environment_risk(alternative, weather_risk, traffic_data)
                    annotate_online_route(alternative, roads)
                    if alternative.get("segments"):  # Only include if geometry matched
                        alternatives.append(enrich_route_risk(alternative, INCIDENTS))
                online["alternatives"] = alternatives
                destination_level = online["risk"].get("overall", RiskLevel.LOW.value)
                if destination_level not in RiskLevel._value2member_map_:
                    destination_level = RiskLevel.LOW.value
                print(f"✅ Online route calculated successfully")
                return RouteResponse(recommended=online, alternatives=online.pop("alternatives", []), destination_risk=RiskLevel(destination_level), data_status="GRAPHHOPPER ONLINE")
        except (RuntimeError, ValueError, httpx.HTTPError) as e:
            print(f"⚠️ Online routing failed, falling back to offline: {e}")
            pass  # Fall back to offline routing

    # Use offline routing for modes not supported by online routing or when online fails
    print(f"🔧 Using offline routing for mode: {request.mode}")
    source = resolve_route_node(request.source)
    destination = resolve_route_node(request.destination)
    print(f"🔧 Resolved nodes: source={source}, destination={destination}")
    
    paths = find_paths(roads, source, destination, request.mode, traffic=traffic_data, weather_risk=weather_risk)
    if not paths:
        print(f"❌ No paths found between {source} and {destination}")
        raise HTTPException(status_code=404, detail="No safe route is currently available")
    
    print(f"✅ Found {len(paths)} path(s)")
    routes = [summarize(path, roads, request.mode, index, traffic=traffic_data, weather_risk=weather_risk) for index, path in enumerate(paths)]
    for route_result in routes:
        enriched = enrich_route_risk(route_result.model_dump(mode="json"), INCIDENTS)
        route_result.risk = enriched["risk"]
        route_result.warnings = enriched["warnings"]
        route_result.reason = enriched["reason"]
    destination_risk = max_risk((road.flood_risk, road.landslide_risk) for road in roads if road.end_node == destination)
    print(f"✅ Route calculated: {routes[0].distance_km} km, {routes[0].eta_minutes} min")
    return RouteResponse(recommended=routes[0], alternatives=routes[1:], destination_risk=destination_risk)


def apply_environment_risk(route_result: dict, weather_risk: RiskLevel, traffic: dict[str, dict]) -> dict:
    rank = {RiskLevel.LOW.value: 0, RiskLevel.MEDIUM.value: 1, RiskLevel.HIGH.value: 2, RiskLevel.CRITICAL.value: 3}
    risk = route_result.setdefault("risk", {})
    risk["weather"] = weather_risk.value
    if rank[weather_risk.value] > rank.get(risk.get("overall", RiskLevel.LOW.value), 0):
        risk["overall"] = weather_risk.value

    # Only check for congestion if traffic data is actually available
    if traffic:  # Only process if traffic dict is not empty
        congested = [value for value in traffic.values() if float(value.get("speed_factor", 1.0)) < 0.7]
        if congested:
            risk["traffic"] = "HIGH"
            risk["confidence"] = min(risk.get("confidence", 100), 80)
            route_result.setdefault("warnings", []).append("Traffic provider reports congestion on the available road network.")
        else:
            risk["traffic"] = "LOW"
    else:
        risk["traffic"] = "UNKNOWN"  # No traffic data available
    return route_result


def parse_coordinates(value: str) -> tuple[float, float] | None:
    coordinate_match = COORDINATE_PATTERN.fullmatch(value.strip())
    if not coordinate_match:
        return None
    latitude, longitude = (float(part) for part in coordinate_match.groups())
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise HTTPException(status_code=422, detail="Map destination coordinates are invalid")
    return latitude, longitude


@app.get("/places/search")
def search_places(q: str = Query(min_length=3, max_length=200), limit: int = Query(default=5, ge=1, le=10)) -> list[dict]:
    try:
        return GEOAPIFY.search(q, limit)
    except RuntimeError:
        raise HTTPException(status_code=503, detail="Geoapify search is not configured")
    except httpx.HTTPError as error:
        raise HTTPException(status_code=502, detail="Geoapify search is temporarily unavailable") from error
    except ValueError as error:
        raise HTTPException(status_code=502, detail="Geoapify returned an invalid response") from error


@app.get("/places/reverse")
def reverse_place(lat: float = Query(ge=-90, le=90), lon: float = Query(ge=-180, le=180)) -> dict:
    try:
        return GEOAPIFY.reverse(lat, lon)
    except RuntimeError:
        raise HTTPException(status_code=503, detail="Geoapify reverse geocoding is not configured")
    except httpx.HTTPError as error:
        raise HTTPException(status_code=502, detail="Geoapify reverse geocoding is temporarily unavailable") from error
    except ValueError as error:
        raise HTTPException(status_code=502, detail="Geoapify returned an invalid response") from error


@app.get("/places/nearby")
def nearby_places(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    categories: str = Query(
        default="healthcare.hospital,service.police,service.fire_station",
        min_length=2,
        max_length=200,
        description="Comma-separated Geoapify category keys",
    ),
    radius_m: int = Query(default=5000, ge=100, le=50000, description="Radius in meters"),
    limit: int = Query(default=20, ge=1, le=100, description="Maximum number of results"),
) -> list[dict]:
    try:
        return GEOAPIFY.nearby(lat=lat, lon=lon, categories=categories, radius_m=radius_m, limit=limit)
    except RuntimeError:
        raise HTTPException(status_code=503, detail="Geoapify Places API is not configured")
    except httpx.HTTPError as error:
        raise HTTPException(status_code=502, detail="Geoapify Places API is temporarily unavailable") from error
    except ValueError as error:
        raise HTTPException(status_code=502, detail="Geoapify Places API returned an invalid response") from error


def resolve_route_node(value: str) -> str:
    coordinate_match = COORDINATE_PATTERN.fullmatch(value.strip())
    if not coordinate_match:
        return value.strip()
    latitude, longitude = (float(part) for part in coordinate_match.groups())
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise HTTPException(status_code=422, detail="Map destination coordinates are invalid")
    
    print(f"🔍 Resolving coordinate {latitude}, {longitude} to nearest road node")
    
    candidates = [(distance_km(latitude, longitude, point[0], point[1]), road.start_node) for road in roads for point in road.geometry]
    candidates.extend((distance_km(latitude, longitude, point[0], point[1]), road.end_node) for road in roads for point in road.geometry)
    
    if not candidates:
        raise HTTPException(status_code=404, detail="No route nodes are available")
    
    # Find the closest node
    closest_distance, closest_node = min(candidates, key=lambda item: item[0])
    print(f"🎯 Closest node: {closest_node} at distance {closest_distance:.2f} km")
    
    return closest_node


def refresh_expired_closures() -> None:
    now = datetime.now(timezone.utc)
    for road in roads:
        if road.closure_end_time and road.closure_end_time <= now and road.closure_reason:
            road.closure_reason = None
            road.closure_severity = None
            road.closure_start_time = None
            road.closure_end_time = None
            road.updated_at = now
            save_road(road)


def max_risk(risks) -> RiskLevel:
    values = {RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 2, RiskLevel.CRITICAL: 3}
    highest = max((risk for pair in risks for risk in pair), key=values.get, default=RiskLevel.LOW)
    return highest


@app.get("/risk/segment")
def get_segment_risk(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    geometry: str = Query(default="", description="Comma-separated lat,lon pairs representing route")
) -> dict:
    """
    Get current flood/landslide risk for user's position on active route.

    Matches GPS position to nearest route segment and returns combined risk from
    static road data, weather, and incidents.

    Query params:
    - lat, lon: User's current GPS position
    - geometry: Route as "lat1,lon1,lat2,lon2,..." (at least 4 values for 2 points)

    Returns:
    {
        "current_segment": {"road_id", "road_name", "distance_to_segment_m"},
        "flood": {"level", "static", "current", "confidence", "sources"},
        "landslide": {"level", "static", "current", "confidence", "sources"},
        "distance_to_hazard_m": float or null,
        "hazard_type": string or null,
        "warnings": [string],
        "data_source": "online|offline"
    }
    """
    try:
        # Parse geometry
        parts = [float(x.strip()) for x in geometry.split(",") if x.strip()]
        if len(parts) < 4:
            raise HTTPException(status_code=422, detail="Route geometry requires at least 2 points (lat,lon,lat,lon)")

        route_geometry = [[parts[i], parts[i + 1]] for i in range(0, len(parts), 2) if i + 1 < len(parts)]

        # Get current segment risk
        from .services import get_current_segment_risk
        result = get_current_segment_risk(lat, lon, route_geometry, roads, INCIDENTS)
        return result
    except ValueError as e:
        raise HTTPException(status_code=422, detail=f"Invalid geometry format: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error calculating segment risk: {str(e)}")


@app.post("/reports")
def submit_report(request: ReportRequest, user: User = Depends(require_roles(Role.USER, Role.AUTHORITY, Role.ADMIN))) -> dict:
    if request.client_id:
        existing = get_report_by_client_id(request.client_id, user.id)
        if existing:
            return existing
    report = {"id": f"report-{uuid4()}", "user_id": user.id, **request.model_dump(), "status": "PENDING", "confidence": 50, "created_at": datetime.now(timezone.utc).isoformat()}
    reports.append(report)
    save_report(report)
    return report


@app.get("/reports")
def get_reports(user: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> list[dict]:
    return reports


@app.get("/reports/mine")
def my_reports(user: User = Depends(current_user)) -> list[dict]:
    return get_reports_for_user(user.id)


@app.api_route("/reports/{report_id}/verify", methods=["PUT", "POST"])
def verify_report(report_id: str, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    report = next((item for item in reports if item["id"] == report_id), None)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    if report["status"] != "PENDING":
        raise HTTPException(status_code=409, detail="Only pending reports can be verified")
    report["status"] = "VERIFIED"
    report["confidence"] = 90
    update_report_status(report_id, report["status"], report["confidence"])
    incident = group_incident(report["problem_type"], report["lat"], report["lon"], report_id)
    save_incident(incident)
    incident_connections.publish(incident)
    entry = {"actor": authority.email, "action": "VERIFY_REPORT", "road_id": report_id, "created_at": datetime.now(timezone.utc).isoformat()}
    audit_logs.append(entry)
    save_audit_log(entry)
    return report


@app.api_route("/reports/{report_id}/reject", methods=["PUT", "POST"])
def reject_report(report_id: str, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    report = next((item for item in reports if item["id"] == report_id), None)
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    if report["status"] != "PENDING":
        raise HTTPException(status_code=409, detail="Only pending reports can be rejected")
    report["status"] = "REJECTED"
    report["confidence"] = 0
    update_report_status(report_id, report["status"], report["confidence"])
    entry = {"actor": authority.email, "action": "REJECT_REPORT", "road_id": report_id, "created_at": datetime.now(timezone.utc).isoformat()}
    audit_logs.append(entry)
    save_audit_log(entry)
    return report


@app.get("/audit-logs")
def get_audit_logs(user: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> list[dict]:
    return audit_logs


@app.get("/facilities/saved")
def get_saved_facilities(user: User = Depends(current_user)) -> list[dict]:
    """Get all saved emergency facilities for the user."""
    return list_facilities()


@app.post("/facilities/save")
def save_emergency_facility(
    facility_id: str = Query(min_length=1, max_length=100),
    name: str = Query(min_length=3, max_length=160),
    facility_type: str = Query(default="UNKNOWN", max_length=40),
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    contact: str = Query(default="", max_length=64),
    user: User = Depends(current_user)
) -> dict:
    """Save an emergency facility locally."""
    facility = {
        "id": facility_id,
        "name": name,
        "type": facility_type,
        "lat": lat,
        "lon": lon,
        "risk_level": "LOW",
        "contact": contact,
        "source": "USER_SAVED"
    }
    save_facility(facility)
    return facility


@app.delete("/facilities/remove/{facility_id}")
def remove_saved_facility(facility_id: str, user: User = Depends(current_user)) -> dict:
    """Remove a saved facility."""
    delete_facility(facility_id)
    return {"status": "removed", "facility_id": facility_id}


@app.api_route("/sync", methods=["GET", "POST"])
def sync(request: SyncRequest | None = None, user: User = Depends(current_user)) -> dict:
    synchronized_at = datetime.now(timezone.utc).isoformat()
    version = current_sync_version()
    accepted_mutations = []
    rejected_mutations = []
    for pending in request.pending_reports if request else []:
        try:
            existing = get_report_by_client_id(pending.client_id, user.id) if pending.client_id else None
            if existing:
                accepted_mutations.append({"client_id": pending.client_id, "record": existing, "duplicate": True})
                continue
            report = {"id": f"report-{uuid4()}", "user_id": user.id, **pending.model_dump(), "status": "PENDING", "confidence": 50, "created_at": synchronized_at}
            reports.append(report)
            save_report(report)
            accepted_mutations.append({"client_id": pending.client_id, "record": report, "duplicate": False})
        except Exception as error:
            rejected_mutations.append({"client_id": pending.client_id, "error": str(error)})
    version = current_sync_version()
    return {
        "version": version,
        "base_version": request.base_version if request else None,
        "conflict": request is not None and request.base_version is not None and request.base_version != version,
        "accepted_mutations": accepted_mutations,
        "rejected_mutations": rejected_mutations,
        "synchronized_at": synchronized_at,
        "data_status": "PRODUCTION",
        "roads": [road.model_dump(mode="json") for road in roads],
        "closures": [road.model_dump(mode="json") for road in roads if road.closure_reason],
        "incidents": list_incidents(),
        "facilities": list_facilities(),
        "warnings": [*list_warnings(), *[incident for incident in INCIDENTS if incident["status"] == "ACTIVE"]],
        "reports": get_reports_for_user(user.id),
        "sos_events": list_sos_for_user(user.id),
    }


def find_facilities(lat: float | None = None, lon: float | None = None, kind: str | None = None) -> list[dict]:
    """Find emergency facilities nearby using real-time Geoapify data."""
    if lat is None or lon is None:
        return []
    
    # Use the real-time facilities_near function from services
    return facilities_near(lat, lon, kind)


@app.get("/facilities")
def facilities(
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    kind: str | None = Query(default=None, min_length=2, max_length=40),
) -> list[dict]:
    if (lat is None) != (lon is None):
        raise HTTPException(status_code=422, detail="lat and lon must be provided together")
    return find_facilities(lat, lon, kind)


@app.get("/facilities/nearest-safe")
def nearest_safe_facility(lat: float, lon: float, kind: str = "SHELTER") -> dict:
    values = [item for item in find_facilities(lat, lon, kind) if item["risk_level"] in (RiskLevel.LOW.value, RiskLevel.MEDIUM.value)]
    if not values:
        raise HTTPException(status_code=404, detail="No safe facility is currently available")
    return values[0]


@app.get("/weather")
def weather(request: WeatherRequest = Depends()) -> dict:
    try:
        reading = WEATHER.current(request.lat, request.lon)
    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(status_code=503, detail="Weather provider is temporarily unavailable") from error
    return {
        "rainfall_mm": reading.rainfall_mm,
        "condition": reading.condition,
        "source": reading.source,
        "observed_at": reading.observed_at.isoformat(),
        "temp_celsius": reading.temp_celsius,
        "feels_like_celsius": reading.feels_like_celsius,
        "humidity_percent": reading.humidity_percent,
        "wind_speed_ms": reading.wind_speed_ms,
        "location_name": reading.location_name,
    }


@app.get("/traffic")
def traffic() -> dict:
    try:
        return TRAFFIC.current([road.id for road in roads], roads)
    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(status_code=503, detail="Traffic provider is temporarily unavailable") from error


@app.post("/risk/predict")
def predicted_risk(request: PredictionRequest) -> dict:
    return predict_risk(request.lat, request.lon, request.slope)


@app.get("/incidents")
def incidents() -> list[dict]:
    return list_incidents()


@app.websocket("/incidents/stream")
async def incident_stream(websocket: WebSocket) -> None:
    token = websocket.query_params.get("access_token")
    if not token:
        await websocket.close(code=1008)
        return
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        if not get_user(payload["sub"]):
            raise ValueError
    except (jwt.InvalidTokenError, KeyError, ValueError):
        await websocket.close(code=1008)
        return

    await websocket.accept()
    queue: asyncio.Queue[dict] = asyncio.Queue()
    incident_connections.add(websocket, asyncio.get_running_loop(), queue)
    try:
        while True:
            await websocket.send_json(await queue.get())
    except WebSocketDisconnect:
        pass
    finally:
        incident_connections.remove(websocket)


@app.get("/warnings")
def warnings() -> list[dict]:
    return list_warnings()


@app.post("/warnings")
def add_warning(request: WarningRequest, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    warning = {"id": f"warning-{uuid4()}", **request.model_dump(mode="json"), "status": "ACTIVE", "created_at": datetime.now(timezone.utc).isoformat(), "source": f"AUTHORITY:{authority.email}"}
    save_warning(warning)
    return warning


@app.post("/incidents")
def add_incident(request: IncidentRequest, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    incident = group_incident(request.problem_type, request.lat, request.lon, request.report_id or "authority-created", request.severity)
    save_incident(incident)
    incident_connections.publish(incident)
    return incident


@app.put("/incidents/{incident_id}/resolve")
def resolve_incident(incident_id: str, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    """Mark an incident as resolved by authority/admin."""
    if update_incident_status(incident_id, "RESOLVED"):
        incident = next((item for item in list_incidents() if item["id"] == incident_id), None)
        # Update global INCIDENTS list
        global INCIDENTS
        INCIDENTS = [inc for inc in INCIDENTS if inc["id"] != incident_id]
        if incident:
            incident_connections.publish(incident)
        return {"id": incident_id, "status": "RESOLVED", "message": "Incident marked as resolved and removed from active incidents"}
    raise HTTPException(status_code=404, detail="Incident not found")


@app.post("/reports/{report_id}/group")
def group_report(report_id: str, authority: User = Depends(require_roles(Role.AUTHORITY, Role.ADMIN))) -> dict:
    report = next((item for item in reports if item["id"] == report_id), None)
    if not report or report["status"] != "VERIFIED":
        raise HTTPException(status_code=404, detail="Verified report not found")
    incident = group_incident(report["problem_type"], report["lat"], report["lon"], report_id)
    save_incident(incident)
    incident_connections.publish(incident)
    return incident


@app.post("/emergency/sos")
def sos(request: SosRequest, user: User = Depends(current_user)) -> dict:
    try:
        facility = nearest_safe_facility(request.lat, request.lon)
    except HTTPException as error:
        if error.status_code != 404:
            raise
        facility = None
    event = {"id": f"sos-{uuid4()}", "status": "RECORDED", "user_id": user.id, "message": request.message, "lat": request.lat, "lon": request.lon, "created_at": datetime.now(timezone.utc).isoformat()}
    save_sos(event)
    return {**event, "location": {"lat": request.lat, "lon": request.lon}, "nearest_safe_shelter": facility, "next_action": "Call local emergency services if immediate danger exists."}


@app.get("/warnings/nearby")
def nearby_warnings(lat: float, lon: float, radius_km: float = Query(default=5.0, gt=0, le=250)) -> list[dict]:
    from .services import distance_km
    stored = [warning for warning in list_warnings() if warning["status"] == "ACTIVE" and distance_km(lat, lon, warning["lat"], warning["lon"]) <= radius_km + warning["radius_km"]]
    incidents = [{**incident, "title": f"{incident['type']} incident", "description": f"Active {incident['severity'].lower()} severity incident", "radius_km": 1.0} for incident in INCIDENTS if distance_km(lat, lon, incident["lat"], incident["lon"]) <= radius_km and incident["status"] == "ACTIVE"]
    return [*stored, *incidents]
