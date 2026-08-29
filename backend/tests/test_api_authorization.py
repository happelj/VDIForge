from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.auth.claims import AuthenticatedUser
from app.main import create_app
from app.models.entities import Desktop


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


def mark_ready(db_session: Session, desktop_id: str) -> None:
    desktop = db_session.get(Desktop, desktop_id)
    assert desktop is not None
    desktop.observed_state = "READY"
    db_session.commit()


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


def test_connect_requires_ready_owned_desktop(
    client: TestClient,
    db_session: Session,
    users: dict[str, AuthenticatedUser],
) -> None:
    desktop = create_devops_desktop(client)

    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "DESKTOP_NOT_READY"

    mark_ready(db_session, desktop["id"])
    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")
    assert response.status_code == 200
    payload = response.json()
    assert payload["desktop_id"] == desktop["id"]
    assert payload["protocol"] == "rdp"
    assert "connection_url" in payload
    assert "password" not in response.text.lower()

    override_user(client, users["user"])
    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "DESKTOP_ACCESS_DENIED"


def test_connect_allows_admin_for_ready_desktop(
    client: TestClient,
    db_session: Session,
    users: dict[str, AuthenticatedUser],
) -> None:
    desktop = create_devops_desktop(client, "admin-connect")
    mark_ready(db_session, desktop["id"])

    override_user(client, users["admin"])
    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")
    assert response.status_code == 200
    assert response.json()["desktop_id"] == desktop["id"]


def test_connect_rejects_missing_and_terminated_desktops(
    client: TestClient,
    db_session: Session,
) -> None:
    response = client.post("/api/v1/desktops/not-a-real-id/connect")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "DESKTOP_NOT_FOUND"

    desktop = create_devops_desktop(client, "terminated-connect")
    item = db_session.get(Desktop, desktop["id"])
    assert item is not None
    item.observed_state = "TERMINATED"
    db_session.commit()

    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "DESKTOP_NOT_READY"


def test_app_factory_exposes_health() -> None:
    app = create_app()
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["version"] == "0.9.0"


def test_app_factory_allows_portal_cors_origin() -> None:
    app = create_app()
    with TestClient(app) as client:
        response = client.options(
            "/api/v1/images",
            headers={
                "Access-Control-Request-Method": "GET",
                "Origin": "https://vdiforge.local",
            },
        )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://vdiforge.local"
