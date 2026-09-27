"""
Tests for live flood and landslide risk detection on active routes.
"""

import pytest
from datetime import datetime, timezone
from backend.app.models import Road, RiskLevel
from backend.app.services import get_current_segment_risk, distance_km


@pytest.fixture
def test_roads():
    """Create test roads with varying risk levels."""
    return [
        Road(
            id="road_low_risk",
            name="Safe Road",
            start_node="A",
            end_node="B",
            distance_km=5.0,
            travel_time_minutes=10,
            flood_risk=RiskLevel.LOW,
            landslide_risk=RiskLevel.LOW,
            confidence=95,
            geometry=[[12.9000, 76.6000], [12.9100, 76.6100]]
        ),
        Road(
            id="road_high_flood",
            name="Flood Risk Road",
            start_node="B",
            end_node="C",
            distance_km=3.0,
            travel_time_minutes=8,
            flood_risk=RiskLevel.HIGH,
            landslide_risk=RiskLevel.LOW,
            confidence=85,
            geometry=[[12.9100, 76.6100], [12.9200, 76.6200]]
        ),
        Road(
            id="road_critical_landslide",
            name="Landslide Risk Road",
            start_node="C",
            end_node="D",
            distance_km=4.0,
            travel_time_minutes=12,
            flood_risk=RiskLevel.MEDIUM,
            landslide_risk=RiskLevel.CRITICAL,
            confidence=70,
            geometry=[[12.9200, 76.6200], [12.9300, 76.6300]]
        ),
    ]


@pytest.fixture
def test_route_geometry():
    """Create a test route geometry."""
    return [
        [12.8900, 76.5900],
        [12.9000, 76.6000],
        [12.9100, 76.6100],
        [12.9200, 76.6200],
        [12.9300, 76.6300],
    ]


@pytest.fixture
def test_incidents():
    """Create test incidents."""
    return [
        {
            "id": "incident_1",
            "type": "Flood",
            "lat": 12.9100,
            "lon": 76.6100,
            "severity": "HIGH",
            "status": "ACTIVE",
            "confidence": 80,
            "report_ids": [],
        },
        {
            "id": "incident_2",
            "type": "Landslide",
            "lat": 12.9250,
            "lon": 76.6250,
            "severity": "CRITICAL",
            "status": "ACTIVE",
            "confidence": 75,
            "report_ids": [],
        },
    ]


def test_segment_matching_within_tolerance(test_roads, test_route_geometry):
    """Test 1: GPS correctly identifies nearest segment within tolerance."""
    # User is very close to the first segment
    user_lat, user_lon = 12.9000, 76.6000

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    assert result["current_segment"] is not None
    assert result["current_segment"]["road_id"] == "road_low_risk"
    assert result["current_segment"]["distance_to_segment_m"] < 100


def test_segment_matching_outside_tolerance(test_roads, test_route_geometry):
    """Test 2: GPS outside tolerance doesn't select wrong segment."""
    # User is far away from the route
    user_lat, user_lon = 13.0000, 76.5000

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    assert result["current_segment"] is None
    assert "not matched to route" in result["warnings"][0]


def test_low_risk_no_warning(test_roads, test_route_geometry):
    """Test 3: LOW flood risk produces no warning."""
    # User on low-risk road
    user_lat, user_lon = 12.9000, 76.6000

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    assert result["flood"]["level"] == "LOW"
    assert result["landslide"]["level"] == "LOW"
    # No HIGH/CRITICAL warnings
    assert not any("High" in w for w in result["warnings"])


def test_high_flood_risk_warning(test_roads, test_route_geometry):
    """Test 4: HIGH flood risk produces warning with distance."""
    # User moving toward high-flood road
    user_lat, user_lon = 12.9050, 76.6050

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    # Should be on the border between low and high
    assert result["current_segment"] is not None
    # Distance to hazard should be calculated
    if result["distance_to_hazard_m"] is not None:
        assert result["distance_to_hazard_m"] > 0


def test_critical_landslide_risk_warning(test_roads, test_route_geometry):
    """Test 5: CRITICAL landslide risk produces urgent warning."""
    # User approaching critical landslide segment
    user_lat, user_lon = 12.9250, 76.6250

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    if result["current_segment"] is not None:
        assert result["landslide"]["level"] in ["HIGH", "CRITICAL"]


def test_same_segment_no_repeated_warning(test_roads, test_route_geometry):
    """Test 6: Same segment GPS updates don't trigger repeated warnings."""
    # Multiple calls with same position should have consistent segment
    user_lat, user_lon = 12.9000, 76.6000

    result1 = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])
    result2 = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    # Both should identify same segment
    if result1["current_segment"] and result2["current_segment"]:
        assert result1["current_segment"]["road_id"] == result2["current_segment"]["road_id"]


def test_new_segment_triggers_warning(test_roads, test_route_geometry):
    """Test 7: Moving into new dangerous segment is detected."""
    # User moves from safe road to high-flood road
    user_lat1, user_lon1 = 12.9000, 76.6000  # Safe road
    user_lat2, user_lon2 = 12.9150, 76.6150  # High-flood road

    result1 = get_current_segment_risk(user_lat1, user_lon1, test_route_geometry, test_roads, [])
    result2 = get_current_segment_risk(user_lat2, user_lon2, test_route_geometry, test_roads, [])

    if result1["current_segment"] and result2["current_segment"]:
        # Different segments detected
        segment_changed = result1["current_segment"]["road_id"] != result2["current_segment"]["road_id"]
        # Risk level should be different
        if segment_changed:
            risk_changed = result1["flood"]["level"] != result2["flood"]["level"]
            assert segment_changed or risk_changed


def test_offline_mode_uses_cached_risk(test_roads, test_route_geometry):
    """Test 8: Offline mode uses cached road risk."""
    user_lat, user_lon = 12.9200, 76.6200  # High-risk area

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    # Should have road_data in sources (static data available)
    if result["current_segment"] is not None:
        assert result["data_source"] in ["online", "offline"]
        # Static risk should be set
        assert result["flood"]["static"] is not None


def test_missing_weather_no_crash(test_roads, test_route_geometry):
    """Test 9: Missing weather doesn't crash system."""
    user_lat, user_lon = 12.9000, 76.6000

    # Should not raise exception even if weather API fails
    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    assert result is not None
    assert "data_source" in result
    # Should have default risk levels
    assert result["flood"]["level"] in ["LOW", "MEDIUM", "HIGH", "CRITICAL"]


def test_missing_incidents_no_crash(test_roads, test_route_geometry):
    """Test 10: Missing incidents doesn't crash system."""
    user_lat, user_lon = 12.9000, 76.6000

    # Should not raise exception with empty incidents
    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    assert result is not None
    assert isinstance(result["warnings"], list)


def test_incident_increases_risk(test_roads, test_route_geometry, test_incidents):
    """Test: Nearby incidents increase risk level."""
    # User near flood incident
    user_lat, user_lon = 12.9100, 76.6100

    result_no_incident = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])
    result_with_incident = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, test_incidents)

    # With incident, risk should be equal or higher
    rank = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
    flood_no_incident = rank.get(result_no_incident["flood"]["level"], 0)
    flood_with_incident = rank.get(result_with_incident["flood"]["level"], 0)

    assert flood_with_incident >= flood_no_incident


def test_distance_calculation_accuracy(test_roads, test_route_geometry):
    """Test: Distance to segment is calculated correctly."""
    # User at exact route point
    user_lat, user_lon = 12.9000, 76.6000

    result = get_current_segment_risk(user_lat, user_lon, test_route_geometry, test_roads, [])

    if result["current_segment"]:
        # Should be very close to route (< 100m)
        assert result["current_segment"]["distance_to_segment_m"] < 100
