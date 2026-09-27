from time import perf_counter

import httpx

from backend.app import services
from backend.app.config import settings
from backend.app.main import app
from fastapi.testclient import TestClient


client = TestClient(app)


def auth_header() -> dict[str, str]:
    response = client.post("/auth/login", json={"email": "test.user@example.com", "password": "TestUser123!"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_protected_operations_reject_missing_or_invalid_tokens():
    assert client.get("/auth/me").status_code == 401
    assert client.post("/sync", headers={"Authorization": "Bearer malformed"}).status_code == 401
    assert client.get("/audit-logs").status_code == 401
    assert client.post("/closures", headers=auth_header(), json={"road_id": "A", "reason": "x", "severity": "HIGH"}).status_code == 403


def test_malformed_input_and_sql_injection_style_values_are_rejected_or_isolated():
    assert client.post("/route", json={"source": "' OR 1=1 --", "destination": "DEST", "mode": "EMERGENCY"}).status_code in (404, 422)
    assert client.post("/auth/login", json={"email": "' OR 1=1 --", "password": "anything"}).status_code in (401, 422)
    assert client.post("/reports", headers=auth_header(), json={"problem_type": "Flood", "lat": 0, "lon": 0, "description": "x"}).status_code == 422
    assert "password_hash" not in client.get("/auth/me", headers=auth_header()).json()


def test_provider_missing_key_and_failure_modes(monkeypatch):
    monkeypatch.setattr(settings, "geoapify_api_key", None)
    assert client.get("/places/search", params={"q": "hospital"}).status_code == 503

    def timeout(*args, **kwargs):
        raise httpx.TimeoutException("timeout")

    monkeypatch.setattr(services.httpx, "get", timeout)
    monkeypatch.setattr(settings, "weather_api_key", "configured")
    assert client.get("/weather", params={"lat": 12.97, "lon": 77.59}).status_code == 503

    monkeypatch.setattr(settings, "traffic_api_url", "https://traffic.invalid")
    monkeypatch.setattr(settings, "traffic_api_key", "configured")
    assert client.get("/traffic").status_code == 503


def test_provider_invalid_payloads_are_rejected_without_secret_leakage(monkeypatch):
    def invalid(*args, **kwargs):
        return httpx.Response(200, json={"features": [{"properties": {}, "geometry": {"coordinates": [None, None]}}]})

    monkeypatch.setattr(services.httpx, "get", invalid)
    monkeypatch.setattr(settings, "geoapify_api_key", "do-not-leak")
    response = client.get("/places/search", params={"q": "hospital"})
    assert response.status_code in (502, 503)
    assert "do-not-leak" not in response.text


def test_core_endpoints_complete_within_local_budget(monkeypatch):
    monkeypatch.setattr(services.GEOAPIFY, "nearby", lambda **kwargs: [])
    start = perf_counter()
    for _ in range(10):
        assert client.get("/health").status_code == 200
        assert client.get("/roads").status_code == 200
        assert client.post("/route", json={"source": "START", "destination": "DEST", "mode": "EMERGENCY"}).status_code == 200
        assert client.get("/facilities", params={"lat": 12.97, "lon": 77.59}).status_code == 200
        assert client.get("/warnings/nearby", params={"lat": 12.97, "lon": 77.59}).status_code == 200
    assert perf_counter() - start < 10
