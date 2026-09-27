from dataclasses import dataclass
from datetime import datetime, timezone
from math import asin, cos, radians, sin, sqrt
from uuid import uuid4
import httpx
from .config import settings
from .models import RiskLevel, RouteSegment


@dataclass(frozen=True)
class Facility:
    id: str
    name: str
    kind: str
    lat: float
    lon: float
    risk_level: RiskLevel
    contact: str


@dataclass(frozen=True)
class WeatherReading:
    rainfall_mm: float
    condition: str
    source: str
    observed_at: datetime
    temp_celsius: float | None = None
    feels_like_celsius: float | None = None
    humidity_percent: int | None = None
    wind_speed_ms: float | None = None
    location_name: str | None = None


class WeatherProvider:
    def current(self, lat: float, lon: float) -> WeatherReading:
        if not settings.weather_api_key:
            raise RuntimeError("Weather API key not configured")
        response = httpx.get(settings.weather_api_url, params={"lat": lat, "lon": lon, "appid": settings.weather_api_key, "units": "metric"}, timeout=5)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("Weather provider returned an invalid response")
        main = payload.get("main", {})
        wind = payload.get("wind", {})
        return WeatherReading(
            rainfall_mm=float(payload.get("rain", {}).get("1h", 0)),
            condition=str(payload.get("weather", [{}])[0].get("description", "unknown")),
            source="OpenWeather",
            observed_at=datetime.now(timezone.utc),
            temp_celsius=float(main.get("temp", 0)) if main.get("temp") is not None else None,
            feels_like_celsius=float(main.get("feels_like", 0)) if main.get("feels_like") is not None else None,
            humidity_percent=int(main.get("humidity", 0)) if main.get("humidity") is not None else None,
            wind_speed_ms=float(wind.get("speed", 0)) if wind.get("speed") is not None else None,
            location_name=payload.get("name")
        )


class TrafficProvider:
    tomtom_url = "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json"

    def current(self, road_ids: list[str], roads: list | None = None) -> dict[str, dict]:
        if settings.tomtom_api_key:
            return self._tomtom_current(road_ids, roads or [])
        if settings.traffic_api_url and settings.traffic_api_key:
            response = httpx.get(settings.traffic_api_url, params={"road_ids": ",".join(road_ids), "key": settings.traffic_api_key}, timeout=5)
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("Traffic provider returned an invalid response")
            return payload
        raise RuntimeError("Traffic API key not configured")

    def _tomtom_current(self, road_ids: list[str], roads: list) -> dict[str, dict]:
        road_points = {
            road.id: (road.geometry[0][0], road.geometry[0][1])
            for road in roads
            if road.id in road_ids and road.geometry and len(road.geometry[0]) >= 2
        }
        if set(road_ids) - road_points.keys():
            raise ValueError("Traffic road geometry is unavailable")
        result = {}
        for road_id in road_ids:
            latitude, longitude = road_points[road_id]
            response = httpx.get(
                self.tomtom_url,
                params={
                    "key": settings.tomtom_api_key,
                    "point": f"{latitude},{longitude}",
                    "unit": "kmph",
                },
                timeout=7,
            )
            response.raise_for_status()
            payload = response.json()
            flow = payload.get("flowSegmentData") if isinstance(payload, dict) else None
            if not isinstance(flow, dict):
                raise ValueError("TomTom traffic response is invalid")
            current = self._number(flow.get("currentSpeed"))
            free_flow = self._number(flow.get("freeFlowSpeed"))
            if current is None or free_flow is None or free_flow <= 0:
                raise ValueError("TomTom traffic response has no speed data")
            ratio = max(0.0, min(1.0, current / free_flow))
            result[road_id] = {
                "speed_factor": round(ratio, 3),
                "status": "CLOSED" if flow.get("roadClosure") is True else "LIVE",
                "congestion": self._congestion(ratio),
                "current_speed": current,
                "free_flow_speed": free_flow,
                "traffic_ratio": round(ratio, 3),
                "confidence": flow.get("confidence"),
                "source": "TomTom Traffic Flow",
            }
        return result

    @staticmethod
    def _number(value):
        return float(value) if isinstance(value, (int, float)) else None

    @staticmethod
    def _congestion(ratio: float) -> str:
        if ratio < 0.35:
            return "CRITICAL"
        if ratio < 0.55:
            return "HIGH"
        if ratio < 0.75:
            return "MEDIUM"
        return "LOW"


class GeoapifyProvider:
    def search(self, query: str, limit: int = 5) -> list[dict]:
        if not settings.geoapify_api_key:
            raise RuntimeError("Geoapify is not configured")
        response = httpx.get(settings.geoapify_api_url, params={"text": query, "limit": limit, "apiKey": settings.geoapify_api_key}, timeout=8)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("Geoapify returned an invalid response")
        features = payload.get("features", [])
        if not isinstance(features, list):
            raise ValueError("Geoapify returned invalid features")
        return [self._place(feature) for feature in features if feature.get("geometry", {}).get("coordinates")]

    def reverse(self, lat: float, lon: float) -> dict:
        if not settings.geoapify_api_key:
            raise RuntimeError("Geoapify is not configured")
        response = httpx.get(settings.geoapify_reverse_url, params={"lat": lat, "lon": lon, "apiKey": settings.geoapify_api_key}, timeout=8)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict) or not isinstance(payload.get("features"), list):
            raise ValueError("Geoapify returned an invalid response")
        feature = (payload.get("features") or [{}])[0]
        return self._place(feature)

    def nearby(self, lat: float, lon: float, categories: str, radius_m: int = 5000, limit: int = 20) -> list[dict]:
        if not settings.geoapify_api_key:
            raise RuntimeError("Geoapify is not configured")
        params = {
            "categories": categories,
            "filter": f"circle:{lon},{lat},{radius_m}",
            "bias": f"proximity:{lon},{lat}",
            "limit": min(limit, 500),
            "apiKey": settings.geoapify_api_key,
        }
        response = httpx.get(settings.geoapify_places_url, params=params, timeout=10)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("Geoapify returned an invalid response")
        features = payload.get("features", [])
        if not isinstance(features, list):
            raise ValueError("Geoapify returned invalid features")
        return [self._nearby_place(feature) for feature in features if feature.get("geometry", {}).get("coordinates")]

    def _nearby_place(self, feature: dict) -> dict:
        properties = feature.get("properties", {})
        coordinates = feature.get("geometry", {}).get("coordinates", [None, None])
        if not isinstance(coordinates, list) or len(coordinates) < 2 or not all(isinstance(value, (int, float)) for value in coordinates[:2]):
            raise ValueError("Provider place has invalid coordinates")
        return {
            "id": properties.get("place_id") or feature.get("id"),
            "name": properties.get("name") or properties.get("formatted", "Unknown place"),
            "formatted_address": properties.get("formatted", ""),
            "lat": coordinates[1],
            "lon": coordinates[0],
            "categories": properties.get("categories", []),
            "distance_m": properties.get("distance"),
            "contact": {
                "phone": properties.get("contact", {}).get("phone") if isinstance(properties.get("contact"), dict) else None,
                "website": properties.get("website") or (properties.get("contact", {}).get("website") if isinstance(properties.get("contact"), dict) else None),
            },
            "opening_hours": properties.get("opening_hours"),
            "source": "Geoapify Places",
        }

    def _place(self, feature: dict) -> dict:
        properties = feature.get("properties", {})
        coordinates = feature.get("geometry", {}).get("coordinates", [None, None])
        if not isinstance(coordinates, list) or len(coordinates) < 2 or not all(isinstance(value, (int, float)) for value in coordinates[:2]):
            raise ValueError("Provider place has invalid coordinates")
        return {"id": feature.get("properties", {}).get("place_id") or feature.get("id"), "name": properties.get("name") or properties.get("formatted", "Selected location"), "formatted_address": properties.get("formatted", "Selected location"), "lat": coordinates[1], "lon": coordinates[0], "category": (properties.get("categories") or ["place"])[0], "source": "Geoapify"}


class GraphHopperProvider:
    profiles = {"DRIVING": "car", "WALKING": "foot", "CYCLING": "bike"}

    def route(self, points: list[tuple[float, float]], mode: str) -> dict:
        return self.route_candidates(points, mode)[0]

    def route_candidates(self, points: list[tuple[float, float]], mode: str) -> list[dict]:
        if not settings.graphhopper_api_key:
            raise RuntimeError("GraphHopper is not configured")
        profile = self.profiles.get(mode.upper(), "car")
        params = [("profile", profile), ("points_encoded", "false"), ("instructions", "true"), ("locale", "en"), ("algorithm", "alternative_route"), ("alternative_route.max_paths", "3"), ("key", settings.graphhopper_api_key)]
        params.extend(("point", f"{lat},{lon}") for lat, lon in points)
        response = httpx.get(settings.graphhopper_api_url, params=params, timeout=12)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("GraphHopper returned an invalid response")
        paths = payload.get("paths") or []
        if not paths:
            raise RuntimeError("GraphHopper returned no route")
        candidates = []
        for index, path in enumerate(paths[:3]):
            coordinates = path.get("points", {}).get("coordinates", [])
            if not isinstance(coordinates, list):
                coordinates = []
            geometry = [[point[1], point[0]] for point in coordinates if len(point) >= 2]
            candidates.append({"route_id": f"graphhopper-online-{index}", "recommended": index == 0, "distance_km": round(float(path.get("distance", 0)) / 1000, 2), "eta_minutes": round(float(path.get("time", 0)) / 60000), "risk": {"overall": "UNKNOWN", "confidence": 0, "flood": "UNKNOWN", "landslide": "UNKNOWN"}, "warnings": [], "reason": "Online route calculated by GraphHopper.", "geometry": geometry, "segments": [], "provider": "GraphHopper", "is_offline": False, "mode": mode})
        candidates[0]["alternatives"] = candidates[1:]
        return candidates


def _point_to_segment_km(point: list[float], start: list[float], end: list[float]) -> float:
    lat_scale = 111.0
    lon_scale = 111.0 * cos(radians(point[0]))
    px, py = point[1] * lon_scale, point[0] * lat_scale
    ax, ay = start[1] * lon_scale, start[0] * lat_scale
    bx, by = end[1] * lon_scale, end[0] * lat_scale
    dx, dy = bx - ax, by - ay
    length_squared = dx * dx + dy * dy
    projection = 0.0 if length_squared == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_squared))
    return sqrt((px - (ax + projection * dx)) ** 2 + (py - (ay + projection * dy)) ** 2)


def match_geometry_to_roads(geometry: list[list[float]], roads, tolerance_km: float | None = None) -> tuple[list, list[list[float]]]:
    tolerance = settings.graphhopper_match_tolerance_km if tolerance_km is None else tolerance_km
    valid_points = [point for point in geometry if isinstance(point, list) and len(point) >= 2 and all(isinstance(value, (int, float)) for value in point[:2])]
    ordered = []
    unmatched = []
    for point in valid_points:
        candidates = []
        for road in roads:
            road_geometry = road.geometry or []
            for start, end in zip(road_geometry, road_geometry[1:]):
                if len(start) >= 2 and len(end) >= 2:
                    candidates.append((_point_to_segment_km(point, start, end), road))
        if not candidates:
            unmatched.append(point)
            continue
        distance, road = min(candidates, key=lambda item: item[0])
        if distance <= tolerance:
            if not ordered or ordered[-1].id != road.id:
                ordered.append(road)
        else:
            unmatched.append(point)
    return ordered, unmatched


def annotate_online_route(route: dict, roads, tolerance_km: float | None = None) -> dict:
    matched, unmatched = match_geometry_to_roads(route.get("geometry", []), roads, tolerance_km)
    route["unmatched_geometry_points"] = unmatched
    if not matched:
        route["warnings"].append("Online geometry could not be matched to the local road graph; using online route data directly.")
        # Use the online route geometry directly when no local match exists
        # This allows real-world coordinates to work with the road network
        if "segments" not in route or not route["segments"]:
            # Create a synthetic segment from the online geometry
            geometry = route.get("geometry", [])
            if geometry:
                total_distance = route.get("distance", 0) / 1000.0  # Convert meters to km
                total_time = route.get("time", 0) / 60.0  # Convert seconds to minutes
                route["segments"] = [{
                    "road_id": "online_route",
                    "road_name": "Online Route",
                    "distance_km": total_distance,
                    "travel_time_minutes": total_time,
                    "flood_risk": "LOW",
                    "landslide_risk": "LOW",
                    "closure_status": "OPEN",
                    "warning": "Route based on online routing - local road network not available",
                    "geometry": geometry,
                    "weather_risk": "LOW",
                    "traffic_status": "UNKNOWN",
                    "traffic_speed_factor": 1.0
                }]
        return route
    now = datetime.now(timezone.utc)
    closed = [road for road in matched if road.closure_reason and (road.closure_start_time is None or road.closure_start_time <= now) and (road.closure_end_time is None or now < road.closure_end_time)]
    if closed:
        raise RuntimeError("Online route intersects an active local road closure")
    levels = [road.flood_risk for road in matched] + [road.landslide_risk for road in matched]
    level = max(levels, key={RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 2, RiskLevel.CRITICAL: 3}.get, default=RiskLevel.LOW)
    route["risk"]["overall"] = max((route["risk"].get("overall", RiskLevel.LOW.value), level.value), key={"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}.get)
    route["risk"]["confidence"] = min(road.confidence for road in matched)
    route["risk"]["flood"] = max((road.flood_risk.value for road in matched), key={"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}.get)
    route["risk"]["landslide"] = max((road.landslide_risk.value for road in matched), key={"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}.get)
    route["segments"] = [RouteSegment(road_id=road.id, road_name=road.name, distance_km=road.distance_km, travel_time_minutes=road.travel_time_minutes, flood_risk=road.flood_risk, landslide_risk=road.landslide_risk, closure_status="OPEN", warning=None, geometry=road.geometry).model_dump(mode="json") for road in matched]
    route["reason"] = "Online route matched to local road segments for closure and disaster-risk evaluation."
    return route


WEATHER = WeatherProvider()
TRAFFIC = TrafficProvider()
GEOAPIFY = GeoapifyProvider()
GRAPHHOPPER = GraphHopperProvider()
FACILITIES: list[Facility] = []
INCIDENTS: list[dict] = []


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius = 6371.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    value = sin(d_lat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    return earth_radius * 2 * asin(sqrt(value))


def incidents_near_route(geometry: list[list[float]], incidents: list[dict], radius_km: float = 1.0) -> list[dict]:
    matches = []
    for incident in incidents:
        if incident.get("status") != "ACTIVE":
            continue
        if any(distance_km(point[0], point[1], incident["lat"], incident["lon"]) <= radius_km for point in geometry):
            matches.append(incident)
    return matches


def enrich_route_risk(route: dict, incidents: list[dict]) -> dict:
    matches = incidents_near_route(route.get("geometry", []), incidents)
    if not matches:
        return route
    rank = {RiskLevel.LOW.value: 0, RiskLevel.MEDIUM.value: 1, RiskLevel.HIGH.value: 2, RiskLevel.CRITICAL.value: 3}
    current = route.setdefault("risk", {})
    highest = max(matches, key=lambda item: rank.get(item["severity"], 0))["severity"]
    if rank.get(highest, 0) > rank.get(current.get("overall", RiskLevel.LOW.value), 0):
        current["overall"] = highest
    current["confidence"] = min(current.get("confidence", 100), *(item.get("confidence", 50) for item in matches))
    route.setdefault("warnings", []).extend(f"{item['type']} incident reported near this route ({item['severity']} severity)." for item in matches)
    route["reason"] = f"Route risk includes {len(matches)} active incident(s) near the geometry."
    return route


def facilities_near(lat: float, lon: float, kind: str | None = None) -> list[dict]:
    """Fetch real-time emergency facilities from Geoapify based on user location."""
    try:
        # Map facility kinds to Geoapify categories
        category_mapping = {
            "HOSPITAL": "healthcare.hospital,healthcare.clinic",
            "POLICE": "service.police", 
            "FIRE_STATION": "service.fire_station",
            "SHELTER": "building.place_of_worship,accommodation"
        }
        
        categories = category_mapping.get(kind.upper() if kind else None, "healthcare.hospital,service.police,service.fire_station,building.place_of_worship,accommodation")
        
        print(f"🔍 Fetching real-time facilities near {lat}, {lon} with categories: {categories}")
        
        # Fetch nearby places from Geoapify
        places = GEOAPIFY.nearby(lat=lat, lon=lon, categories=categories, radius_m=10000, limit=20)
        
        print(f"✅ Found {len(places)} places from Geoapify")
        
        # Convert Geoapify places to facility format
        facilities = []
        for place in places:
            # Determine facility type from categories
            place_categories = str(place.get("categories", []))
            facility_type = "UNKNOWN"
            
            if "hospital" in place_categories or "clinic" in place_categories:
                facility_type = "HOSPITAL"
            elif "police" in place_categories:
                facility_type = "POLICE"
            elif "fire" in place_categories:
                facility_type = "FIRE_STATION"
            elif "shelter" in place_categories or "worship" in place_categories or "accommodation" in place_categories:
                facility_type = "SHELTER"
            
            # Filter by kind if specified
            if kind is not None and facility_type != kind.upper():
                continue
            
            # Calculate distance
            distance = distance_km(lat, lon, place["lat"], place["lon"])
            
            facility_dict = {
                "id": place.get("id", f"geo-{place.get('name', 'unknown')}"),
                "name": place.get("name", "Unknown Facility"),
                "type": facility_type,
                "lat": place["lat"],
                "lon": place["lon"],
                "risk_level": "LOW",  # Default risk level
                "contact": place.get("contact", {}).get("phone") if isinstance(place.get("contact"), dict) else "",
                "source": "Geoapify Real-time",
                "formatted_address": place.get("formatted_address", ""),
                "distance_km": round(distance, 2)
            }
            
            facilities.append(facility_dict)
        
        # Sort by distance
        facilities.sort(key=lambda f: f["distance_km"])
        
        print(f"✅ Returning {len(facilities)} facilities after filtering")
        return facilities[:10]  # Return top 10 closest facilities
        
    except RuntimeError as e:
        print(f"❌ Geoapify not configured: {e}")
        return []
    except (ValueError, httpx.HTTPError) as e:
        print(f"❌ Error fetching real-time facilities: {e}")
        return []


def facility_to_dict(facility: Facility, distance: float | None = None) -> dict:
    value = {
        "id": facility.id, 
        "name": facility.name, 
        "type": facility.kind, 
        "lat": facility.lat, 
        "lon": facility.lon, 
        "risk_level": facility.risk_level.value, 
        "contact": facility.contact, 
        "source": "GEOAPIFY",
        "formatted_address": facility.name
    }
    if distance is not None:
        value["distance_km"] = round(distance, 2)
    return value


def create_incident(problem_type: str, lat: float, lon: float, severity: RiskLevel, report_id: str | None = None) -> dict:
    incident = {"id": f"incident-{uuid4()}", "type": problem_type, "lat": lat, "lon": lon, "severity": severity.value, "status": "ACTIVE", "confidence": 90, "report_ids": [report_id] if report_id else [], "created_at": datetime.now(timezone.utc).isoformat(), "source": "AUTHORITY OR VERIFIED REPORT"}
    INCIDENTS.append(incident)
    return incident


def group_incident(problem_type: str, lat: float, lon: float, report_id: str, severity: RiskLevel = RiskLevel.MEDIUM, radius_km: float = 1.0) -> dict:
    for incident in INCIDENTS:
        if incident["type"] == problem_type and distance_km(lat, lon, incident["lat"], incident["lon"]) <= radius_km and incident["status"] == "ACTIVE":
            # Grouping is idempotent: retrying an authority action must not
            # artificially increase the confidence of an incident.
            if report_id not in incident["report_ids"]:
                incident["report_ids"].append(report_id)
                incident["confidence"] = min(99, incident["confidence"] + 2)
            return incident
    return create_incident(problem_type, lat, lon, severity, report_id)


def predict_risk(lat: float, lon: float, slope: float = 0.0) -> dict:
    weather = WEATHER.current(lat, lon)
    flood_score = min(100, weather.rainfall_mm * 2.0)
    landslide_score = min(100, weather.rainfall_mm * 1.2 + slope * 5.0)
    return {"flood": score_level(flood_score), "landslide": score_level(landslide_score), "flood_score": round(flood_score, 1), "landslide_score": round(landslide_score, 1), "source": "RISK PREDICTION MODEL", "advisory_only": True, "updated_at": weather.observed_at.isoformat()}


def score_level(score: float) -> str:
    if score >= 75:
        return RiskLevel.CRITICAL.value
    if score >= 50:
        return RiskLevel.HIGH.value
    if score >= 25:
        return RiskLevel.MEDIUM.value
    return RiskLevel.LOW.value


def get_current_segment_risk(lat: float, lon: float, route_geometry: list[list[float]], roads: list, incidents: list[dict] | None = None) -> dict:
    """
    Determine current flood/landslide risk for the user's current position on the active route.

    Matches GPS position to nearest route segment, combines static road risk with current
    weather and incident data, and identifies distance to next dangerous segment.

    Args:
        lat, lon: User's current GPS position
        route_geometry: List of [lat, lon] points representing the route
        roads: List of available Road objects for matching
        incidents: List of incident dictionaries (if None, uses global INCIDENTS)

    Returns:
        {
            "current_segment": {
                "road_id": str,
                "road_name": str,
                "distance_to_segment_m": float
            },
            "flood": {
                "level": str (LOW|MEDIUM|HIGH|CRITICAL),
                "static": str,
                "current": str,
                "confidence": int,
                "sources": list[str]
            },
            "landslide": {
                "level": str,
                "static": str,
                "current": str,
                "confidence": int,
                "sources": list[str]
            },
            "distance_to_hazard_m": float | None,
            "hazard_type": str | None,
            "warnings": list[str],
            "data_source": str
        }
    """
    if incidents is None:
        incidents = INCIDENTS

    tolerance_km = 0.1  # 100 meters
    rank = {RiskLevel.LOW.value: 0, RiskLevel.MEDIUM.value: 1, RiskLevel.HIGH.value: 2, RiskLevel.CRITICAL.value: 3}

    # Step 1: Find nearest segment in route
    nearest_distance_km = float("inf")
    current_segment_road = None
    segment_position_index = 0

    for idx, (start, end) in enumerate(zip(route_geometry, route_geometry[1:])):
        if len(start) >= 2 and len(end) >= 2:
            distance = _point_to_segment_km([lat, lon], start, end)
            if distance < nearest_distance_km:
                nearest_distance_km = distance
                segment_position_index = idx
                # Find road matching this segment
                for road in roads:
                    if road.geometry and len(road.geometry) >= 2:
                        for road_start, road_end in zip(road.geometry, road.geometry[1:]):
                            if len(road_start) >= 2 and len(road_end) >= 2:
                                road_distance = _point_to_segment_km([lat, lon], road_start, road_end)
                                if road_distance < tolerance_km:
                                    current_segment_road = road
                                    break
                    if current_segment_road:
                        break

    # Step 2: Check if match is within tolerance
    if nearest_distance_km > tolerance_km or current_segment_road is None:
        return {
            "current_segment": None,
            "flood": {"level": RiskLevel.LOW.value, "static": None, "current": None, "confidence": 0, "sources": []},
            "landslide": {"level": RiskLevel.LOW.value, "static": None, "current": None, "confidence": 0, "sources": []},
            "distance_to_hazard_m": None,
            "hazard_type": None,
            "warnings": ["GPS position not matched to route segment (outside tolerance)"],
            "data_source": "offline"
        }

    # Step 3: Get static road risk
    static_flood = current_segment_road.flood_risk.value if current_segment_road.flood_risk else RiskLevel.LOW.value
    static_landslide = current_segment_road.landslide_risk.value if current_segment_road.landslide_risk else RiskLevel.LOW.value

    # Step 4: Get weather-based risk
    try:
        weather_risk = predict_risk(lat, lon)
        weather_flood = weather_risk.get("flood", RiskLevel.LOW.value)
        weather_landslide = weather_risk.get("landslide", RiskLevel.LOW.value)
        weather_available = True
    except Exception:
        weather_flood = RiskLevel.LOW.value
        weather_landslide = RiskLevel.LOW.value
        weather_available = False

    # Step 5: Get incident-based risk
    nearby_incidents = [inc for inc in incidents if inc.get("status") == "ACTIVE" and distance_km(lat, lon, inc["lat"], inc["lon"]) <= 0.5]
    incident_flood_risk = RiskLevel.LOW.value
    incident_landslide_risk = RiskLevel.LOW.value

    for incident in nearby_incidents:
        incident_type = incident.get("type", "").lower()
        severity = incident.get("severity", RiskLevel.LOW.value)
        if "flood" in incident_type or "waterlog" in incident_type:
            if rank.get(severity, 0) > rank.get(incident_flood_risk, 0):
                incident_flood_risk = severity
        elif "landslide" in incident_type or "debris" in incident_type:
            if rank.get(severity, 0) > rank.get(incident_landslide_risk, 0):
                incident_landslide_risk = severity

    # Step 6: Combine risks (use maximum)
    combined_flood = max([static_flood, weather_flood, incident_flood_risk], key=lambda x: rank.get(x, 0))
    combined_landslide = max([static_landslide, weather_landslide, incident_landslide_risk], key=lambda x: rank.get(x, 0))

    # Step 7: Track sources
    flood_sources = []
    if static_flood != RiskLevel.LOW.value:
        flood_sources.append("road_data")
    if weather_available and weather_flood != RiskLevel.LOW.value:
        flood_sources.append("weather")
    if incident_flood_risk != RiskLevel.LOW.value:
        flood_sources.append("incident")

    landslide_sources = []
    if static_landslide != RiskLevel.LOW.value:
        landslide_sources.append("road_data")
    if weather_available and weather_landslide != RiskLevel.LOW.value:
        landslide_sources.append("weather")
    if incident_landslide_risk != RiskLevel.LOW.value:
        landslide_sources.append("incident")

    # Step 8: Find distance to next dangerous segment
    distance_to_hazard_m = None
    hazard_type = None
    accumulated_distance = 0.0

    for idx in range(segment_position_index + 1, len(route_geometry) - 1):
        start_point = route_geometry[idx]
        end_point = route_geometry[idx + 1]
        if len(start_point) >= 2 and len(end_point) >= 2:
            segment_length_m = distance_km(start_point[0], start_point[1], end_point[0], end_point[1]) * 1000

            # Find road for this segment
            for road in roads:
                if road.geometry and len(road.geometry) >= 2:
                    for road_start, road_end in zip(road.geometry, road.geometry[1:]):
                        if len(road_start) >= 2 and len(road_end) >= 2:
                            seg_distance = _point_to_segment_km(start_point, road_start, road_end)
                            if seg_distance < tolerance_km:
                                road_flood = road.flood_risk.value if road.flood_risk else RiskLevel.LOW.value
                                road_landslide = road.landslide_risk.value if road.landslide_risk else RiskLevel.LOW.value

                                if rank.get(road_flood, 0) >= 2:  # HIGH or CRITICAL
                                    distance_to_hazard_m = accumulated_distance + segment_length_m / 2
                                    hazard_type = "flood"
                                    break
                                if rank.get(road_landslide, 0) >= 2:
                                    if distance_to_hazard_m is None or accumulated_distance + segment_length_m / 2 < distance_to_hazard_m:
                                        distance_to_hazard_m = accumulated_distance + segment_length_m / 2
                                        hazard_type = "landslide"
                        if distance_to_hazard_m and hazard_type == "flood":
                            break
                if distance_to_hazard_m and hazard_type == "flood":
                    break

            accumulated_distance += segment_length_m
            if distance_to_hazard_m and accumulated_distance > distance_to_hazard_m + 1000:
                break  # Found hazard within 1km ahead

    # Step 9: Build warnings
    warnings = []
    if rank.get(combined_flood, 0) >= 2:
        warnings.append(f"High flood risk ahead (sources: {', '.join(flood_sources)})")
    if rank.get(combined_landslide, 0) >= 2:
        warnings.append(f"High landslide risk ahead (sources: {', '.join(landslide_sources)})")
    if current_segment_road.closure_reason:
        warnings.append(f"Road closure: {current_segment_road.closure_reason}")

    return {
        "current_segment": {
            "road_id": current_segment_road.id,
            "road_name": current_segment_road.name,
            "distance_to_segment_m": round(nearest_distance_km * 1000, 1)
        },
        "flood": {
            "level": combined_flood,
            "static": static_flood,
            "current": combined_flood,
            "confidence": current_segment_road.confidence if current_segment_road else 50,
            "sources": flood_sources
        },
        "landslide": {
            "level": combined_landslide,
            "static": static_landslide,
            "current": combined_landslide,
            "confidence": current_segment_road.confidence if current_segment_road else 50,
            "sources": landslide_sources
        },
        "distance_to_hazard_m": distance_to_hazard_m,
        "hazard_type": hazard_type,
        "warnings": warnings,
        "data_source": "online" if weather_available else "offline"
    }
