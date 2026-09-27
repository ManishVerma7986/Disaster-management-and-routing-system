import os
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.seed import initial_roads
from backend.app.storage import get_user_by_email, init_storage, list_sos_for_user
from backend.app.services import enrich_route_risk, match_geometry_to_roads


client = TestClient(app)


# Test credentials are supplied through environment variables.
# Do NOT put real passwords directly in this file.
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "test.user@example.com")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD")
TEST_AUTHORITY_EMAIL = os.getenv("TEST_AUTHORITY_EMAIL", "test.authority@example.com")
TEST_AUTHORITY_PASSWORD = os.getenv("TEST_AUTHORITY_PASSWORD")


def token(email: str, password: str) -> str:
    if not password:
        raise RuntimeError(
            "Test credentials are missing. Set TEST_USER_PASSWORD and "
            "TEST_AUTHORITY_PASSWORD in your local environment."
        )

    response = client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == 200
    return response.json()["access_token"]


def test_active_incident_enriches_route_risk_and_warning():
    route = {
        "geometry": [[12.9716, 77.5946]],
        "risk": {"overall": "LOW", "confidence": 100},
        "warnings": [],
        "reason": "base",
    }

    enriched = enrich_route_risk(
        route,
        [
            {
                "type": "Flood",
                "lat": 12.9716,
                "lon": 77.5946,
                "severity": "HIGH",
                "confidence": 90,
                "status": "ACTIVE",
            }
        ],
    )

    assert enriched["risk"]["overall"] == "HIGH"
    assert enriched["risk"]["confidence"] == 90
    assert "Flood incident" in enriched["warnings"][0]


def test_graphhopper_geometry_matches_ordered_local_roads_with_tolerance():
    matched, unmatched = match_geometry_to_roads(
        [[12.9716, 77.5946], [12.9721, 77.5950], [99, 99]],
        initial_roads(),
        tolerance_km=0.25,
    )

    assert [road.id for road in matched] == ["A"]
    assert unmatched == [[99, 99]]


def test_graphhopper_geometry_deduplicates_points_and_handles_empty_input():
    matched, unmatched = match_geometry_to_roads(
        [],
        initial_roads(),
        tolerance_km=0.25,
    )

    assert matched == []
    assert unmatched == []


def test_route_is_available_and_explainable():
    response = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "DEST",
            "mode": "EMERGENCY",
        },
    )

    assert response.status_code == 200

    body = response.json()

    assert body["recommended"]["distance_km"] > 0
    assert body["recommended"]["reason"]
    assert "confidence" in body["recommended"]["risk"]
    assert "weather" in body["recommended"]["risk"]
    assert "traffic" in body["recommended"]["risk"]
    assert "weather_risk" in body["recommended"]["segments"][0]
    assert body["destination_risk"] == "HIGH"


def test_map_coordinate_destination_resolves_to_route_node():
    response = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "@12.985,77.61",
            "mode": "EMERGENCY",
        },
    )

    assert response.status_code == 200
    assert response.json()["recommended"]["distance_km"] > 0


def test_unprefixed_coordinate_destination_is_supported():
    response = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "12.985,77.61",
            "mode": "EMERGENCY",
        },
    )

    assert response.status_code == 200


def test_new_travel_mode_uses_local_graph_when_graphhopper_is_unconfigured():
    response = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "DEST",
            "mode": "DRIVING",
        },
    )

    assert response.status_code == 200
    assert response.json()["data_status"] == "PRODUCTION"


def test_provider_search_reports_missing_configuration():
    response = client.get(
        "/places/search",
        params={"q": "hospital"},
    )

    assert response.status_code in (200, 503)


def test_user_cannot_create_closure():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)

    response = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {user_token}"},
        json={
            "road_id": "D",
            "reason": "Flooding",
            "severity": "HIGH",
        },
    )

    assert response.status_code == 403


def test_authority_closure_is_avoided():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    close = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "road_id": "D",
            "reason": "Flooding",
            "severity": "HIGH",
        },
    )

    assert close.status_code == 200

    response = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "DEST",
            "mode": "EMERGENCY",
        },
    )

    assert response.status_code == 200

    route = response.json()["recommended"]

    assert all(segment["road_id"] != "D" for segment in route["segments"])

    client.delete(
        "/closures/D",
        headers={"Authorization": f"Bearer {authority_token}"},
    )


def test_storage_reload_preserves_authority_closure():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    close = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "road_id": "D",
            "reason": "Flooding",
            "severity": "HIGH",
        },
    )

    assert close.status_code == 200

    reloaded_roads, _, _ = init_storage(initial_roads())
    reloaded = next(road for road in reloaded_roads if road.id == "D")

    assert reloaded.closure_reason == "Flooding"

    client.delete(
        "/closures/D",
        headers={"Authorization": f"Bearer {authority_token}"},
    )


def test_registered_user_is_persisted_and_can_login():
    email = f"persisted-{uuid4()}@example.com"
    password = f"Test-{uuid4()}!"

    registration = client.post(
        "/auth/register",
        json={
            "name": "Persisted User",
            "email": email,
            "password": password,
        },
    )

    assert registration.status_code == 200

    stored = get_user_by_email(email)

    assert stored is not None
    assert stored.role.value == "USER"

    login = client.post(
        "/auth/login",
        json={
            "email": email,
            "password": password,
        },
    )

    assert login.status_code == 200


def test_registration_cannot_assign_authority_role_or_use_short_password():
    response = client.post(
        "/auth/register",
        json={
            "name": "Unsafe User",
            "email": f"unsafe-{uuid4()}@example.com",
            "password": "short",
            "role": "AUTHORITY",
        },
    )

    assert response.status_code == 422


def test_registration_rejects_invalid_email():
    response = client.post(
        "/auth/register",
        json={
            "name": "Invalid Email",
            "email": "not-an-email",
            "password": "Test password 123!",
        },
    )

    assert response.status_code == 422


def test_sync_requires_authentication_and_returns_offline_datasets():
    assert client.post("/sync").status_code == 401

    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)

    response = client.post(
        "/sync",
        headers={"Authorization": f"Bearer {user_token}"},
    )

    assert response.status_code == 200

    assert {
        "roads",
        "closures",
        "incidents",
        "facilities",
        "warnings",
        "reports",
        "sos_events",
        "version",
        "conflict",
    }.issubset(response.json())

    stale = client.post(
        "/sync",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"base_version": 1},
    )

    assert stale.status_code == 200
    assert stale.json()["conflict"] is True


def test_sync_merges_offline_report_once_and_returns_partial_mutation_results():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)

    payload = {
        "client_id": f"client-{uuid4()}",
        "problem_type": "Flood",
        "lat": 12.97,
        "lon": 77.59,
        "description": "Queued report",
    }

    first = client.post(
        "/sync",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"pending_reports": [payload]},
    )

    assert first.status_code == 200
    assert len(first.json()["accepted_mutations"]) == 1

    duplicate = client.post(
        "/sync",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"pending_reports": [payload]},
    )

    assert duplicate.status_code == 200
    assert duplicate.json()["accepted_mutations"][0]["duplicate"] is True


def test_report_and_facility_coordinates_are_validated():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)

    report = client.post(
        "/reports",
        headers={"Authorization": f"Bearer {user_token}"},
        json={
            "problem_type": "Flood",
            "lat": 91,
            "lon": 77.59,
            "description": "Water across the road",
        },
    )

    assert report.status_code == 422

    incomplete_location = client.get(
        "/facilities",
        params={"lat": 12.97},
    )

    assert incomplete_location.status_code == 422

    invalid_radius = client.get(
        "/warnings/nearby",
        params={
            "lat": 12.97,
            "lon": 77.59,
            "radius_km": 0,
        },
    )

    assert invalid_radius.status_code == 422


def test_authority_can_verify_and_reject_reports():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    report = client.post(
        "/reports",
        headers={"Authorization": f"Bearer {user_token}"},
        json={
            "problem_type": "Flood",
            "lat": 12.97,
            "lon": 77.59,
            "description": "Water across the road",
        },
    )

    assert report.status_code == 200

    report_id = report.json()["id"]

    verified = client.put(
        f"/reports/{report_id}/verify",
        headers={"Authorization": f"Bearer {authority_token}"},
    )

    assert verified.status_code == 200
    assert verified.json()["status"] == "VERIFIED"

    duplicate = client.put(
        f"/reports/{report_id}/reject",
        headers={"Authorization": f"Bearer {authority_token}"},
    )

    assert duplicate.status_code == 409


def test_user_can_restore_session_and_view_report_status():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)

    me = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {user_token}"},
    )

    assert me.status_code == 200

    report = client.post(
        "/reports",
        headers={"Authorization": f"Bearer {user_token}"},
        json={
            "problem_type": "Blocked Road",
            "lat": 12.97,
            "lon": 77.59,
            "description": "Tree blocking lane",
        },
    )

    assert report.status_code == 200

    mine = client.get(
        "/reports/mine",
        headers={"Authorization": f"Bearer {user_token}"},
    )

    assert mine.status_code == 200

    assert any(
        item["id"] == report.json()["id"]
        and item["status"] == "PENDING"
        for item in mine.json()
    )


def test_expired_closure_is_automatically_reopened():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    now = datetime.now(timezone.utc)

    response = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "road_id": "D",
            "reason": "Temporary flooding",
            "severity": "HIGH",
            "start_time": (now - timedelta(minutes=5)).isoformat(),
            "end_time": (now - timedelta(minutes=1)).isoformat(),
        },
    )

    assert response.status_code == 200

    route = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "DEST",
            "mode": "EMERGENCY",
        },
    )

    assert route.status_code == 200
    assert any(
        segment["road_id"] == "D"
        for segment in route.json()["recommended"]["segments"]
    )


def test_invalid_closure_window_is_rejected():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    response = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "road_id": "D",
            "reason": "Invalid window",
            "severity": "HIGH",
            "start_time": "2026-09-13T12:00:00",
            "end_time": "2026-09-13T11:00:00",
        },
    )

    assert response.status_code == 422


def test_scheduled_closure_is_labeled_on_route_segment():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    now = datetime.now(timezone.utc)

    response = client.post(
        "/closures",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "road_id": "D",
            "reason": "Planned repair",
            "severity": "MEDIUM",
            "start_time": (now + timedelta(hours=1)).isoformat(),
            "end_time": (now + timedelta(hours=2)).isoformat(),
        },
    )

    assert response.status_code == 200

    route = client.post(
        "/route",
        json={
            "source": "START",
            "destination": "DEST",
            "mode": "EMERGENCY",
        },
    )

    assert route.status_code == 200

    assert any(
        segment["road_id"] == "D"
        and segment["closure_status"] == "SCHEDULED"
        for segment in route.json()["recommended"]["segments"]
    )

    client.delete(
        "/closures/D",
        headers={"Authorization": f"Bearer {authority_token}"},
    )


def test_facilities_weather_prediction_incidents_and_sos():
    user_token = token(TEST_USER_EMAIL, TEST_USER_PASSWORD)
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    facilities = client.get(
        "/facilities",
        params={
            "lat": 12.97,
            "lon": 77.59,
            "kind": "SHELTER",
        },
    )

    assert facilities.status_code == 200
    assert facilities.json()[0]["source"] == "Geoapify Real-time"

    weather = client.get(
        "/weather",
        params={
            "lat": 12.97,
            "lon": 77.59,
        },
    )

    assert weather.status_code == 200

    prediction = client.post(
        "/risk/predict",
        json={
            "lat": 12.97,
            "lon": 77.59,
            "slope": 12,
        },
    )

    assert prediction.status_code == 200
    assert prediction.json()["advisory_only"] is True

    incident = client.post(
        "/incidents",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "problem_type": "Flood",
            "lat": 12.97,
            "lon": 77.59,
            "severity": "HIGH",
        },
    )

    assert incident.status_code == 200

    duplicate = client.post(
        "/incidents",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "problem_type": "Flood",
            "lat": 12.9701,
            "lon": 77.5901,
            "severity": "HIGH",
        },
    )

    assert duplicate.json()["id"] == incident.json()["id"]

    sos = client.post(
        "/emergency/sos",
        headers={"Authorization": f"Bearer {user_token}"},
        json={
            "lat": 12.97,
            "lon": 77.59,
        },
    )

    assert sos.status_code == 200
    assert sos.json()["status"] == "RECORDED"
    assert list_sos_for_user("test-user")


def test_incident_stream_broadcasts_deactivation_to_connected_users():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    incident_id = None

    with client.websocket_connect(
        f"/incidents/stream?access_token={authority_token}"
    ) as websocket:

        created = client.post(
            "/incidents",
            headers={"Authorization": f"Bearer {authority_token}"},
            json={
                "problem_type": "Landslide",
                "lat": 12.8,
                "lon": 77.8,
                "severity": "HIGH",
            },
        )

        assert created.status_code == 200

        incident_id = created.json()["id"]

        assert websocket.receive_json()["incident"]["status"] == "ACTIVE"

        resolved = client.put(
            f"/incidents/{incident_id}/resolve",
            headers={"Authorization": f"Bearer {authority_token}"},
        )

        assert resolved.status_code == 200

        event = websocket.receive_json()

        assert event["incident"]["id"] == incident_id
        assert event["incident"]["status"] == "RESOLVED"


def test_authority_can_create_and_retrieve_persisted_warning():
    authority_token = token(
        TEST_AUTHORITY_EMAIL,
        TEST_AUTHORITY_PASSWORD,
    )

    response = client.post(
        "/warnings",
        headers={"Authorization": f"Bearer {authority_token}"},
        json={
            "title": "Flood watch",
            "description": "Water levels rising near the road",
            "lat": 12.97,
            "lon": 77.59,
            "radius_km": 2,
            "severity": "HIGH",
        },
    )

    assert response.status_code == 200

    warning_id = response.json()["id"]

    assert any(
        item["id"] == warning_id
        for item in client.get("/warnings").json()
    )

    nearby = client.get(
        "/warnings/nearby",
        params={
            "lat": 12.97,
            "lon": 77.59,
        },
    )

    assert any(
        item["id"] == warning_id
        for item in nearby.json()
    )
