from fastapi.testclient import TestClient

from app.main import app


def test_health() -> None:
    response = TestClient(app).get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_demo_snapshot_and_market_order() -> None:
    client = TestClient(app)
    client.post("/api/v1/demo/reset")

    snapshot = client.get("/api/v1/demo/snapshot")
    order = client.post(
        "/api/v1/demo/orders",
        json={"symbol": "NIFTY11AUG2625000CE", "side": "BUY", "quantity": 65},
    )
    portfolio = client.get("/api/v1/demo/portfolio")

    assert snapshot.status_code == 200
    assert len(snapshot.json()["quotes"]) >= 6
    assert order.status_code == 201
    assert order.json()["status"] == "FILLED"
    assert portfolio.json()["positions"][0]["quantity"] == 75
