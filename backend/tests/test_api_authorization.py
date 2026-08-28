from __future__ import annotations

from fastapi.testclient import TestClient

from app.api.dependencies import get_current_user
from app.auth.claims import AuthenticatedUser
from app.main import create_app


def override_user(client: TestClient, user: AuthenticatedUser) -> None:
    client.app.dependency_overrides[get_current_user] = lambda: user


def create_devops_desktop(client: TestClient, key: str = "launch-1") -> dict:
    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": key},
        json={"image_id": "ubuntu-devops", "resource_profile": "small"},
    )
    assert response.status_code == 202, response.text
    return response.json()


def test_image_catalog_returns_only_authorized_available_images(
    client: TestClient,
    users: dict[str, AuthenticatedUser],
) -> None:
    override_user(client, users["user"])
    response = client.get("/api/v1/images")
    assert response.status_code == 200
    assert response.json() == []

    override_user(client, users["devops"])
    response = client.get("/api/v1/images")
    assert response.status_code == 200
    payload = response.json()
    assert [item["id"] for item in payload] == ["ubuntu-devops"]


def test_launch_requires_idempotency_key(client: TestClient) -> None:
    response = client.post("/api/v1/desktops", json={"image_id": "ubuntu-devops", "resource_profile": "small"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "IDEMPOTENCY_KEY_REQUIRED"


def test_launch_is_idempotent_and_conflict_is_rejected(client: TestClient) -> None:
    first = create_devops_desktop(client, "same-key")
    second = create_devops_desktop(client, "same-key")
    assert second["id"] == first["id"]

    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": "same-key"},
        json={"image_id": "ubuntu-devops", "resource_profile": "standard"},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "IDEMPOTENCY_CONFLICT"


def test_quota_blocks_second_active_desktop(client: TestClient) -> None:
    create_devops_desktop(client, "launch-1")
    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": "launch-2"},
        json={"image_id": "ubuntu-devops", "resource_profile": "small"},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "DESKTOP_QUOTA_EXCEEDED"


def test_ownership_and_admin_listing(
    client: TestClient,
    users: dict[str, AuthenticatedUser],
) -> None:
    override_user(client, users["devops"])
    desktop = create_devops_desktop(client)

    override_user(client, users["user"])
    response = client.get(f"/api/v1/desktops/{desktop['id']}")
    assert response.status_code == 403

    response = client.get("/api/v1/desktops?all_users=true")
    assert response.status_code == 403

    override_user(client, users["admin"])
    response = client.get("/api/v1/desktops?all_users=true")
    assert response.status_code == 200
    assert response.json()["desktops"][0]["id"] == desktop["id"]


def test_admin_only_audit_endpoint(client: TestClient, users: dict[str, AuthenticatedUser]) -> None:
    create_devops_desktop(client)

    override_user(client, users["devops"])
    response = client.get("/api/v1/audit-events")
    assert response.status_code == 403

    override_user(client, users["admin"])
    response = client.get("/api/v1/audit-events")
    assert response.status_code == 200
    assert response.json()["audit_events"][0]["action"] == "DESKTOP_REQUESTED"


def test_app_factory_exposes_health() -> None:
    app = create_app()
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["version"] == "0.7.0"
