import heapq
from dataclasses import dataclass
from datetime import datetime, timezone
from .models import Road, RiskLevel, RouteResult, RouteSegment, RoutingMode

RISK_VALUE = {RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 3, RiskLevel.CRITICAL: 8}
MODE_WEIGHTS = {
    RoutingMode.EMERGENCY: (0.8, 2.0, 2.0),
    RoutingMode.DRIVING: (1.0, 1.0, 1.0),
    RoutingMode.WALKING: (1.2, 1.0, 1.0),
    RoutingMode.CYCLING: (1.0, 1.2, 1.2),
}


@dataclass
class _Path:
    cost: float
    nodes: list[str]
    roads: list[Road]


def _cost(road: Road, mode: RoutingMode, traffic: dict[str, dict] | None = None, weather_risk: RiskLevel = RiskLevel.LOW) -> float:
    now = datetime.now(timezone.utc)
    closure_active = road.closure_reason and (road.closure_start_time is None or road.closure_start_time <= now) and (road.closure_end_time is None or now < road.closure_end_time)
    if closure_active:
        return float("inf")
    time_weight, flood_weight, slide_weight = MODE_WEIGHTS[mode]
    uncertainty = (100 - road.confidence) / 100
    traffic_value = (traffic or {}).get(road.id, {})
    speed_factor = max(0.1, min(1.0, float(traffic_value.get("speed_factor", 1.0))))
    traffic_penalty = road.travel_time_minutes * (1 - speed_factor)
    weather_penalty = RISK_VALUE[weather_risk] * (flood_weight + slide_weight) / 2
    return road.travel_time_minutes * time_weight + traffic_penalty + RISK_VALUE[road.flood_risk] * flood_weight + RISK_VALUE[road.landslide_risk] * slide_weight + weather_penalty + uncertainty


def find_paths(roads: list[Road], source: str, destination: str, mode: RoutingMode, limit: int = 3, traffic: dict[str, dict] | None = None, weather_risk: RiskLevel = RiskLevel.LOW) -> list[_Path]:
    graph: dict[str, list[Road]] = {}
    for road in roads:
        graph.setdefault(road.start_node, []).append(road)
    queue: list[tuple[float, tuple[str, ...], tuple[str, ...]]] = [(0, (source,), ())]
    results: list[_Path] = []
    seen: set[tuple[str, tuple[str, ...]]] = set()
    while queue and len(results) < limit:
        cost, nodes, road_ids = heapq.heappop(queue)
        current = nodes[-1]
        if current == destination:
            selected = [next(road for road in roads if road.id == road_id) for road_id in road_ids]
            results.append(_Path(cost, list(nodes), selected))
            continue
        state = (current, road_ids)
        if state in seen:
            continue
        seen.add(state)
        for road in graph.get(current, []):
            if road.id in road_ids:
                continue
            road_cost = _cost(road, mode, traffic, weather_risk)
            if road_cost != float("inf"):
                heapq.heappush(queue, (cost + road_cost, nodes + (road.end_node,), road_ids + (road.id,)))
    return results


def summarize(path: _Path, roads: list[Road], mode: RoutingMode, index: int, traffic: dict[str, dict] | None = None, weather_risk: RiskLevel = RiskLevel.LOW) -> RouteResult:
    flood = max((RISK_VALUE[road.flood_risk] for road in path.roads), default=0)
    slide = max((RISK_VALUE[road.landslide_risk] for road in path.roads), default=0)
    overall = max(flood, slide, RISK_VALUE[weather_risk])
    level = max((road.flood_risk for road in path.roads), key=RISK_VALUE.get, default=RiskLevel.LOW)
    slide_level = max((road.landslide_risk for road in path.roads), key=RISK_VALUE.get, default=RiskLevel.LOW)
    if RISK_VALUE[slide_level] > RISK_VALUE[level]:
        level = slide_level
    if RISK_VALUE[weather_risk] > RISK_VALUE[level]:
        level = weather_risk
    warnings = []
    segments = []
    geometry = []
    for road in path.roads:
        warning = None
        closure_status = "OPEN"
        now = datetime.now(timezone.utc)
        if road.closure_reason and road.closure_start_time and road.closure_start_time > now:
            closure_status = "SCHEDULED"
            warning = f"{road.name} is scheduled to close at {road.closure_start_time.isoformat()}."
        if road.flood_risk in (RiskLevel.HIGH, RiskLevel.CRITICAL):
            risk_warning = f"{road.name} has {road.flood_risk.value.lower()} flood risk."
            warning = f"{warning} {risk_warning}" if warning else risk_warning
        if road.landslide_risk in (RiskLevel.HIGH, RiskLevel.CRITICAL):
            slide_warning = f"{road.name} has {road.landslide_risk.value.lower()} landslide risk."
            warning = f"{warning} {slide_warning}" if warning else slide_warning
        traffic_value = (traffic or {}).get(road.id, {})
        speed_factor = max(0.1, min(1.0, float(traffic_value.get("speed_factor", 1.0))))
        traffic_status = str(traffic_value.get("status", "UNKNOWN"))
        if speed_factor < 0.7:
            traffic_warning = f"{road.name} has reduced traffic speed ({traffic_status.lower()})."
            warning = f"{warning} {traffic_warning}" if warning else traffic_warning
        if weather_risk in (RiskLevel.HIGH, RiskLevel.CRITICAL):
            weather_warning = f"Current weather contributes {weather_risk.value.lower()} route risk."
            warning = f"{warning} {weather_warning}" if warning else weather_warning
        if warning:
            warnings.append(warning)
        segments.append(RouteSegment(road_id=road.id, road_name=road.name, distance_km=road.distance_km, travel_time_minutes=road.travel_time_minutes, flood_risk=road.flood_risk, landslide_risk=road.landslide_risk, closure_status=closure_status, warning=warning, geometry=road.geometry, weather_risk=weather_risk, traffic_status=traffic_status, traffic_speed_factor=round(speed_factor, 2)))
        geometry.extend(road.geometry if not geometry else road.geometry[1:])
    flood_level = max((road.flood_risk for road in path.roads), key=RISK_VALUE.get, default=RiskLevel.LOW)
    landslide_level = max((road.landslide_risk for road in path.roads), key=RISK_VALUE.get, default=RiskLevel.LOW)
    traffic_level = RiskLevel.HIGH.value if any(float((traffic or {}).get(road.id, {}).get("speed_factor", 1.0)) < 0.7 for road in path.roads) else RiskLevel.LOW.value
    return RouteResult(route_id=f"route_{index}", recommended=index == 0, distance_km=round(sum(r.distance_km for r in path.roads), 2), eta_minutes=round(sum(r.travel_time_minutes for r in path.roads)), risk={"flood": flood_level.value, "landslide": landslide_level.value, "weather": weather_risk.value, "traffic": traffic_level, "overall": level.value, "confidence": min((r.confidence for r in path.roads), default=100)}, warnings=warnings, reason="Selected because it minimizes the configured time, traffic, weather, and disaster-risk cost." if index == 0 else "Alternative route retained for comparison.", geometry=geometry, segments=segments)
