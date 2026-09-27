from uuid import uuid4

from fastapi.testclient import TestClient

from backend.app.main import app


client = TestClient(app)


def test_required_api_smoke_matrix_and_auth_boundaries():
    login = client.post("/auth/login", json={"email": "test.user@example.com", "password": "TestUser123!"})
    assert login.status_code == 200
    auth = {"Authorization": f"Bearer {login.json()['access_token']}"}

    register = client.post("/auth/register", json={"name": "Smoke User", "email": f"smoke-{uuid4()}@example.com", "password": "Valid123!"})
    assert register.status_code == 200

    responses = {
        "health": client.get("/health"),
        "me": client.get("/auth/me", headers=auth),
        "roads": client.get("/roads"),
        "route": client.post("/route", json={"source": "START", "destination": "DEST", "mode": "EMERGENCY"}),
        "places_search": client.get("/places/search", params={"q": "hospital"}),
        "places_reverse": client.get("/places/reverse", params={"lat": 12.97, "lon": 77.59}),
        "places_nearby": client.get("/places/nearby", params={"lat": 12.97, "lon": 77.59, "categories": "healthcare.hospital"}),
        "reports_mine": client.get("/reports/mine", headers=auth),
        "facilities": client.get("/facilities"),
        "nearest_safe": client.get("/facilities/nearest-safe", params={"lat": 12.97, "lon": 77.59}),
        "weather": client.get("/weather", params={"lat": 12.97, "lon": 77.59}),
        "traffic": client.get("/traffic"),
        "risk": client.post("/risk/predict", json={"lat": 12.97, "lon": 77.59}),
        "incidents": client.get("/incidents"),
        "warnings": client.get("/warnings/nearby", params={"lat": 12.97, "lon": 77.59}),
        "sync": client.post("/sync", headers=auth),
    }
    assert all(response.status_code < 500 for response in responses.values())
    assert client.get("/reports").status_code == 401
    assert client.post("/sync").status_code == 401
