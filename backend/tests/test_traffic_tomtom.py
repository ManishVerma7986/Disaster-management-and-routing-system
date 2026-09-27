import httpx
import pytest
from types import SimpleNamespace

from backend.app import services
from backend.app.config import settings


ROAD = SimpleNamespace(
    id="A",
    geometry=[[12.9716, 77.5946], [12.972, 77.595]],
)


def response(status: int, payload: dict) -> httpx.Response:
    return httpx.Response(
        status,
        json=payload,
        request=httpx.Request("GET", "https://api.tomtom.com"),
    )


def test_tomtom_success_is_normalized(monkeypatch):
    calls = []

    def success(url, **kwargs):
        calls.append((url, kwargs))
        return response(200, {
                "flowSegmentData": {
                    "currentSpeed": 18,
                    "freeFlowSpeed": 60,
                    "confidence": 0.88,
                    "roadClosure": False,
                }
            })

    monkeypatch.setattr(settings, "tomtom_api_key", "test-key")
    monkeypatch.setattr(services.httpx, "get", success)

    result = services.TrafficProvider().current(["A"], [ROAD])

    assert result["A"]["current_speed"] == 18.0
    assert result["A"]["free_flow_speed"] == 60.0
    assert result["A"]["traffic_ratio"] == 0.3
    assert result["A"]["congestion"] == "CRITICAL"
    assert result["A"]["source"] == "TomTom Traffic Flow"
    assert calls[0][1]["params"]["point"] == "12.9716,77.5946"
    assert calls[0][1]["params"]["key"] == "test-key"
    assert calls[0][1]["timeout"] == 7


def test_tomtom_http_failure_is_reported(monkeypatch):
    monkeypatch.setattr(settings, "tomtom_api_key", "test-key")
    monkeypatch.setattr(
        services.httpx,
        "get",
        lambda *args, **kwargs: response(500, {}),
    )

    with pytest.raises(httpx.HTTPStatusError):
        services.TrafficProvider().current(["A"], [ROAD])


def test_tomtom_timeout_is_reported(monkeypatch):
    monkeypatch.setattr(settings, "tomtom_api_key", "test-key")

    def timeout(*args, **kwargs):
        raise httpx.TimeoutException("timeout")

    monkeypatch.setattr(services.httpx, "get", timeout)
    with pytest.raises(httpx.TimeoutException):
        services.TrafficProvider().current(["A"], [ROAD])


def test_tomtom_invalid_key_is_reported(monkeypatch):
    monkeypatch.setattr(settings, "tomtom_api_key", "invalid-key")
    monkeypatch.setattr(
        services.httpx,
        "get",
        lambda *args, **kwargs: response(403, {"error": "forbidden"}),
    )

    with pytest.raises(httpx.HTTPStatusError):
        services.TrafficProvider().current(["A"], [ROAD])


def test_tomtom_malformed_response_is_reported(monkeypatch):
    monkeypatch.setattr(settings, "tomtom_api_key", "test-key")
    monkeypatch.setattr(
        services.httpx,
        "get",
        lambda *args, **kwargs: response(200, {"unexpected": True}),
    )

    with pytest.raises(ValueError):
        services.TrafficProvider().current(["A"], [ROAD])


def test_missing_tomtom_key_is_reported(monkeypatch):
    monkeypatch.setattr(settings, "tomtom_api_key", None)
    monkeypatch.setattr(settings, "traffic_api_url", None)
    monkeypatch.setattr(settings, "traffic_api_key", None)

    with pytest.raises(RuntimeError, match="Traffic API key not configured"):
        services.TrafficProvider().current(["A"], [ROAD])
