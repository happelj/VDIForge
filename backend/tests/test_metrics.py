from __future__ import annotations

import re

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.entities import Desktop
from app.observability.metrics import (
    observe_desktop_provision_duration,
    observe_reconcile,
    record_desktop_provision_failure,
)


def create_devops_desktop(client: TestClient, key: str = "metrics-launch") -> dict:
    response = client.post(
        "/api/v1/desktops",
        headers={"Idempotency-Key": key},
        json={"image_id": "ubuntu-devops", "resource_profile": "small"},
    )
    assert response.status_code == 202, response.text
    return response.json()


def scrape_metrics(client: TestClient) -> str:
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    return response.text


def test_metrics_endpoint_exports_phase11_metrics(client: TestClient) -> None:
    client.get("/api/v1/health")
    record_desktop_provision_failure("ubuntu-devops", "test")
    observe_desktop_provision_duration("ubuntu-devops", "succeeded", 12.0)
    observe_reconcile("success", 0.05)
    text = scrape_metrics(client)

    expected_metrics = [
        "vdiforge_api_requests_total",
        "vdiforge_api_request_duration_seconds_bucket",
        "vdiforge_desktop_provision_requests_total",
        "vdiforge_desktop_provision_failures_total",
        "vdiforge_desktop_provision_duration_seconds_bucket",
        "vdiforge_desktops_active",
        "vdiforge_desktops_by_state",
        "vdiforge_remote_sessions_active",
        "vdiforge_provisioner_reconcile_total",
        "vdiforge_provisioner_reconcile_failures_total",
        "vdiforge_provisioner_reconcile_duration_seconds_bucket",
        "vdiforge_provisioner_pending_operations",
    ]
    for metric in expected_metrics:
        assert metric in text


def test_api_metrics_use_normalized_routes(client: TestClient) -> None:
    desktop = create_devops_desktop(client)
    response = client.get(f"/api/v1/desktops/{desktop['id']}")
    assert response.status_code == 200

    text = scrape_metrics(client)
    assert 'route="/api/v1/desktops/{desktop_id}"' in text
    assert desktop["id"] not in text


def test_desktop_gauges_reflect_database_state(
    client: TestClient,
    db_session: Session,
) -> None:
    desktop = create_devops_desktop(client, "metrics-state")
    item = db_session.get(Desktop, desktop["id"])
    assert item is not None
    item.observed_state = "READY"
    db_session.commit()

    text = scrape_metrics(client)
    assert 'vdiforge_desktops_by_state{state="READY"}' in text
    assert re.search(r"vdiforge_desktops_active\s+[1-9]", text)


def test_metrics_do_not_use_forbidden_high_cardinality_labels(client: TestClient) -> None:
    create_devops_desktop(client)
    text = scrape_metrics(client)

    forbidden_labels = (
        "request_id",
        "user_id",
        "username",
        "desktop_id",
        "subject",
        "token",
        "connection_id",
        "guacamole_connection_id",
    )
    for label in forbidden_labels:
        assert not re.search(rf"(^|[{{,]){label}=", text)
