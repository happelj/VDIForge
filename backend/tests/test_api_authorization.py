from __future__ import annotations

import json
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.audit.service import record_audit_event
from app.auth.claims import AuthenticatedUser
from app.main import create_app
from app.models.entities import Desktop
from app.security.audit_integrity import audit_hash_payload, compute_audit_event_hash
from app.security.redaction import redact_text


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


def test_launch_rejects_unsafe_input(client: TestClient) -> None:
    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": "unsafe-input-1"},
        json={"image_id": "../ubuntu-devops", "resource_profile": "small"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"

    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": "unsafe-input-2"},
        json={"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "bad\nname"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"

    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": "bad key with spaces"},
        json={"image_id": "ubuntu-devops", "resource_profile": "small"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


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
    response = client.post("/api/v1/desktops/not-a-valid-uuid/connect")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"

    response = client.post(f"/api/v1/desktops/{uuid4()}/connect")
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
    assert response.json()["version"] == "0.12.0"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "strict-origin-when-cross-origin"
    assert "max-age=" in response.headers["strict-transport-security"]
    assert "default-src 'none'" in response.headers["content-security-policy"]


def test_load_test_endpoint_is_disabled_by_default(client: TestClient) -> None:
    response = client.get("/api/v1/health/load-test")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "LOAD_TEST_DISABLED"


def test_load_test_endpoint_runs_bounded_work(client: TestClient, settings) -> None:
    settings.load_test_enabled = True
    settings.load_test_default_iterations = 1_000
    settings.load_test_max_iterations = 2_000

    response = client.get("/api/v1/health/load-test")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["iterations"] == 1_000
    assert isinstance(payload["checksum"], int)
    assert payload["request_id"]

    response = client.get("/api/v1/health/load-test?iterations=1500")
    assert response.status_code == 200
    assert response.json()["iterations"] == 1_500

    response = client.get("/api/v1/health/load-test?iterations=2500")
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "LOAD_TEST_LIMIT_EXCEEDED"


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


def test_app_factory_rejects_unapproved_cors_origin() -> None:
    app = create_app()
    with TestClient(app) as client:
        response = client.options(
            "/api/v1/images",
            headers={
                "Access-Control-Request-Method": "GET",
                "Origin": "https://evil.example",
            },
        )
    assert response.headers.get("access-control-allow-origin") != "https://evil.example"


def test_connect_rate_limit_blocks_repeated_high_impact_operation(
    client: TestClient,
    db_session: Session,
    settings,
) -> None:
    settings.desktop_connect_rate_limit = 2
    settings.desktop_connect_rate_window_seconds = 60
    desktop = create_devops_desktop(client, "rate-limited-connect")
    mark_ready(db_session, desktop["id"])

    assert client.post(f"/api/v1/desktops/{desktop['id']}/connect").status_code == 200
    assert client.post(f"/api/v1/desktops/{desktop['id']}/connect").status_code == 200
    response = client.post(f"/api/v1/desktops/{desktop['id']}/connect")

    assert response.status_code == 429
    assert response.json()["error"]["code"] == "RATE_LIMIT_EXCEEDED"


def test_audit_events_are_redacted_and_hash_chained(
    db_session: Session,
    users: dict[str, AuthenticatedUser],
) -> None:
    jwt_like_value = "ey" + "JhbGciOiJIUzI1NiJ9.payload.signature"
    first = record_audit_event(
        db_session,
        request_id="req-audit-1",
        user=users["devops"],
        action="SECURITY_TEST",
        resource_type="Desktop",
        resource_id="desktop-a",
        source_ip="192.0.2.10",
        result="SUCCESS",
        details={
            "password": "plain-password",
            "nested": {"Authorization": f"Bearer {jwt_like_value}"},
            "kept": "safe-value",
        },
    )
    db_session.commit()
    second = record_audit_event(
        db_session,
        request_id="req-audit-2",
        user=users["devops"],
        action="SECURITY_TEST_SECOND",
        resource_type="Desktop",
        resource_id="desktop-b",
        source_ip="192.0.2.10",
        result="SUCCESS",
        details={},
    )
    db_session.commit()

    assert first.details["password"] == "[REDACTED]"  # noqa: S105
    assert first.details["nested"]["Authorization"] == "[REDACTED]"
    assert first.details["kept"] == "safe-value"
    assert first.event_hash is not None
    assert second.previous_event_hash == first.event_hash

    expected_first_hash = compute_audit_event_hash(
        audit_hash_payload(
            event_id=first.event_id,
            timestamp=first.timestamp,
            request_id=first.request_id,
            user_subject=first.user_subject,
            username=first.username,
            action=first.action,
            resource_type=first.resource_type,
            resource_id=first.resource_id,
            source_ip=first.source_ip,
            result=first.result,
            details=first.details,
            previous_event_hash=first.previous_event_hash,
        )
    )
    assert first.event_hash == expected_first_hash


def test_admin_only_audit_export_returns_json_lines(client: TestClient, users: dict[str, AuthenticatedUser]) -> None:
    create_devops_desktop(client, "audit-export")

    response = client.get("/api/v1/audit-events/export")
    assert response.status_code == 403

    override_user(client, users["admin"])
    response = client.get("/api/v1/audit-events/export?limit=10")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/x-ndjson")
    lines = [json.loads(line) for line in response.text.splitlines() if line]
    assert lines
    assert lines[0]["event_hash"]
    assert "password" not in response.text.lower()


def test_log_redaction_masks_sensitive_values() -> None:
    jwt_like_value = "ey" + "JhbGciOiJIUzI1NiJ9.payload.signature"
    rendered = redact_text(f"Authorization: Bearer {jwt_like_value} password=cleartext")
    assert jwt_like_value not in rendered
    assert "password=cleartext" not in rendered
    assert "Bearer [REDACTED]" in rendered
    assert "password=[REDACTED]" in rendered
