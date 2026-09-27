from .models import RiskLevel, Road


def initial_roads() -> list[Road]:
    """Initial road network for the routing system."""
    return [
        Road(id="A", name="Road A", start_node="START", end_node="B", distance_km=2.0, travel_time_minutes=4, flood_risk=RiskLevel.LOW, landslide_risk=RiskLevel.LOW, confidence=94, geometry=[[12.9716, 77.5946], [12.9750, 77.6000]]),
        Road(id="B", name="Road B", start_node="B", end_node="C", distance_km=2.2, travel_time_minutes=4, flood_risk=RiskLevel.HIGH, landslide_risk=RiskLevel.LOW, confidence=87, geometry=[[12.9750, 77.6000], [12.9800, 77.6050]]),
        Road(id="C", name="Road C", start_node="C", end_node="DEST", distance_km=2.0, travel_time_minutes=5, flood_risk=RiskLevel.LOW, landslide_risk=RiskLevel.HIGH, confidence=82, geometry=[[12.9800, 77.6050], [12.9850, 77.6100]]),
        Road(id="D", name="Road D", start_node="B", end_node="D", distance_km=1.8, travel_time_minutes=4, flood_risk=RiskLevel.LOW, landslide_risk=RiskLevel.LOW, confidence=91, geometry=[[12.9750, 77.6000], [12.9780, 77.6100]]),
        Road(id="E", name="Road E", start_node="D", end_node="DEST", distance_km=3.4, travel_time_minutes=7, flood_risk=RiskLevel.LOW, landslide_risk=RiskLevel.LOW, confidence=95, geometry=[[12.9780, 77.6100], [12.9850, 77.6100]]),
        Road(id="F", name="Road F", start_node="START", end_node="D", distance_km=4.5, travel_time_minutes=8, flood_risk=RiskLevel.MEDIUM, landslide_risk=RiskLevel.LOW, confidence=90, geometry=[[12.9716, 77.5946], [12.9780, 77.6100]]),
    ]
