from __future__ import annotations

import threading
import time
from datetime import UTC, datetime, timedelta

from fastapi import Request
from prometheus_client import Counter, Gauge, Histogram, generate_latest, start_http_server
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from starlette.routing import Match

from app.auth.policy import TERMINAL_STATES
from app.models.entities import Desktop, ProvisioningOperation

HTTP_DURATION_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
PROVISION_DURATION_BUCKETS = (15.0, 30.0, 60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0)
RECONCILE_DURATION_BUCKETS = (0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0)

DESKTOP_STATES = (
    "REQUESTED",
    "PROVISIONING",
    "BOOTING",
    "READY",
    "CONNECTED",
    "STOPPING",
    "STOPPED",
    "TERMINATING",
    "TERMINATED",
    "FAILED",
)

API_REQUESTS = Counter(
    "vdiforge_api_requests_total",
    "Total VDIForge API HTTP requests.",
    ("method", "route", "status_code"),
)
API_REQUEST_DURATION = Histogram(
    "vdiforge_api_request_duration_seconds",
    "VDIForge API HTTP request duration in seconds.",
    ("method", "route", "status_code"),
    buckets=HTTP_DURATION_BUCKETS,
)
DESKTOP_PROVISION_REQUESTS = Counter(
    "vdiforge_desktop_provision_requests_total",
    "Total VDIForge desktop provision requests by image and result.",
    ("image_id", "result"),
)
DESKTOP_PROVISION_FAILURES = Counter(
    "vdiforge_desktop_provision_failures_total",
    "Total VDIForge desktop provisioning failures by image and reason.",
    ("image_id", "reason"),
)
DESKTOP_PROVISION_DURATION = Histogram(
    "vdiforge_desktop_provision_duration_seconds",
    "VDIForge desktop provisioning duration from request to terminal provisioning result.",
    ("image_id", "result"),
    buckets=PROVISION_DURATION_BUCKETS,
)
DESKTOPS_ACTIVE = Gauge(
    "vdiforge_desktops_active",
    "Number of active VDIForge desktops excluding terminal states.",
)
DESKTOPS_BY_STATE = Gauge(
    "vdiforge_desktops_by_state",
    "Number of VDIForge desktops by observed lifecycle state.",
    ("state",),
)
REMOTE_SESSIONS_ACTIVE = Gauge(
    "vdiforge_remote_sessions_active",
    "Approximate active brokered remote desktop sessions by protocol within the configured session TTL.",
    ("protocol",),
)
PROVISIONER_RECONCILE_TOTAL = Counter(
    "vdiforge_provisioner_reconcile_total",
    "Total VDIForge provisioner reconcile iterations by result.",
    ("result",),
)
PROVISIONER_RECONCILE_FAILURES = Counter(
    "vdiforge_provisioner_reconcile_failures_total",
    "Total VDIForge provisioner reconcile failures by reason.",
    ("reason",),
)
PROVISIONER_RECONCILE_DURATION = Histogram(
    "vdiforge_provisioner_reconcile_duration_seconds",
    "VDIForge provisioner reconcile iteration duration in seconds.",
    ("result",),
    buckets=RECONCILE_DURATION_BUCKETS,
)
PROVISIONER_PENDING_OPERATIONS = Gauge(
    "vdiforge_provisioner_pending_operations",
    "Number of pending VDIForge provisioning operations.",
)

_METRICS_SERVER_STARTED = False
_METRICS_SERVER_LOCK = threading.Lock()


def normalized_route(request: Request) -> str:
    for candidate in request.app.routes:
        match, _ = candidate.matches(request.scope)
        if match == Match.FULL:
            candidate_path = getattr(candidate, "path", None)
            if candidate_path:
                return str(candidate_path)

    route = request.scope.get("route")
    path = getattr(route, "path", None)
    if path:
        route_path = str(path)
        api_prefix = getattr(request.app.state, "vdiforge_api_prefix", "")
        request_path = str(request.scope.get("path", ""))
        if api_prefix and request_path.startswith(f"{api_prefix}/") and not route_path.startswith(api_prefix):
            return f"{api_prefix}{route_path}"
        return route_path

    return "unmatched"


def observe_api_request(method: str, route: str, status_code: int | str, duration_seconds: float) -> None:
    status = str(status_code)
    labels = (method.upper(), route, status)
    API_REQUESTS.labels(*labels).inc()
    API_REQUEST_DURATION.labels(*labels).observe(duration_seconds)


def record_desktop_provision_request(image_id: str, result: str) -> None:
    DESKTOP_PROVISION_REQUESTS.labels(image_id=image_id, result=result).inc()


def record_desktop_provision_failure(image_id: str, reason: str) -> None:
    DESKTOP_PROVISION_FAILURES.labels(image_id=image_id, reason=reason).inc()


def observe_desktop_provision_duration(image_id: str, result: str, duration_seconds: float) -> None:
    DESKTOP_PROVISION_DURATION.labels(image_id=image_id, result=result).observe(max(duration_seconds, 0.0))


def observe_reconcile(result: str, duration_seconds: float) -> None:
    PROVISIONER_RECONCILE_TOTAL.labels(result=result).inc()
    PROVISIONER_RECONCILE_DURATION.labels(result=result).observe(max(duration_seconds, 0.0))


def record_reconcile_failure(reason: str) -> None:
    PROVISIONER_RECONCILE_FAILURES.labels(reason=reason).inc()


def refresh_desktop_gauges(db: Session, *, remote_session_ttl_seconds: int, remote_desktop_protocol: str) -> None:
    counts = dict(db.execute(select(Desktop.observed_state, func.count()).group_by(Desktop.observed_state)).all())
    for state in DESKTOP_STATES:
        DESKTOPS_BY_STATE.labels(state=state).set(int(counts.get(state, 0)))

    active_count = sum(int(count) for state, count in counts.items() if state not in TERMINAL_STATES)
    DESKTOPS_ACTIVE.set(active_count)

    cutoff = _now() - timedelta(seconds=remote_session_ttl_seconds)
    session_count = db.scalar(
        select(func.count())
        .select_from(Desktop)
        .where(
            Desktop.last_connected_at.is_not(None),
            Desktop.last_connected_at >= cutoff,
            Desktop.observed_state.in_(["READY", "CONNECTED"]),
        )
    )
    REMOTE_SESSIONS_ACTIVE.labels(protocol=remote_desktop_protocol).set(int(session_count or 0))

    pending_count = db.scalar(
        select(func.count())
        .select_from(ProvisioningOperation)
        .where(ProvisioningOperation.status == "PENDING")
    )
    PROVISIONER_PENDING_OPERATIONS.set(int(pending_count or 0))


def generate_prometheus_metrics() -> bytes:
    return generate_latest()


def start_provisioner_metrics_server(port: int) -> None:
    global _METRICS_SERVER_STARTED
    with _METRICS_SERVER_LOCK:
        if _METRICS_SERVER_STARTED:
            return
        start_http_server(port)
        _METRICS_SERVER_STARTED = True


def monotonic_time() -> float:
    return time.perf_counter()


def elapsed_since(started_at: float) -> float:
    return time.perf_counter() - started_at


def seconds_between(start: datetime, end: datetime) -> float:
    return (_with_timezone(end) - _with_timezone(start)).total_seconds()


def _now() -> datetime:
    return datetime.now(UTC)


def _with_timezone(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value
