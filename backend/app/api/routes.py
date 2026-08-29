from __future__ import annotations

import json
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import __version__
from app.api.dependencies import current_settings, get_current_user, get_remote_access_service
from app.api.errors import ApiError
from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings
from app.db.session import get_db
from app.models.entities import Desktop
from app.observability.metrics import (
    generate_prometheus_metrics,
    record_desktop_provision_request,
    refresh_desktop_gauges,
)
from app.schemas.api import (
    AuditEventListResponse,
    AuditEventResponse,
    DesktopConnectionResponse,
    DesktopCreateRequest,
    DesktopListResponse,
    DesktopResponse,
    HealthResponse,
    ImageResponse,
    ImageVersionResponse,
    LoadTestResponse,
    ReadyResponse,
)
from app.security.rate_limit import api_rate_limiter
from app.services.desktops import DesktopService
from app.services.image_catalog import ImageCatalogService
from app.services.remote_access import RemoteAccessService

router = APIRouter()


def source_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    if request.client:
        return request.client.host
    return None


def enforce_rate_limit(
    *,
    request: Request,
    user: AuthenticatedUser,
    settings: Settings,
    scope: str,
    limit: int,
    window_seconds: int,
) -> None:
    if not settings.api_rate_limit_enabled:
        return
    key = f"{scope}:{user.subject}:{source_ip(request) or 'unknown'}"
    decision = api_rate_limiter.check(key, limit=limit, window_seconds=window_seconds)
    if not decision.allowed:
        raise ApiError(
            429,
            "RATE_LIMIT_EXCEEDED",
            f"Too many requests for this operation. Retry after {decision.retry_after_seconds} seconds.",
        )


@router.get("/health", response_model=HealthResponse, tags=["system"])
def health() -> HealthResponse:
    return HealthResponse(status="ok", version=__version__)


@router.get("/ready", response_model=ReadyResponse, tags=["system"])
def ready(
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> ReadyResponse:
    db.execute(text("select 1"))
    ImageCatalogService(settings).validate_catalog()
    return ReadyResponse(status="ok", database="ok", image_catalog="ok")


@router.get("/health/load-test", response_model=LoadTestResponse, tags=["system"])
def load_test(
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    iterations: Annotated[int | None, Query(ge=1_000, le=2_000_000)] = None,
) -> LoadTestResponse:
    if not settings.load_test_enabled:
        raise ApiError(404, "LOAD_TEST_DISABLED", "The local load-test endpoint is disabled.")

    requested_iterations = settings.load_test_default_iterations if iterations is None else iterations
    if requested_iterations > settings.load_test_max_iterations:
        raise ApiError(400, "LOAD_TEST_LIMIT_EXCEEDED", "Requested load-test work exceeds the configured limit.")

    checksum = 0
    subject_length = len(user.subject)
    for index in range(requested_iterations):
        checksum = ((checksum << 5) - checksum + index + subject_length) & 0xFFFFFFFF

    return LoadTestResponse(
        status="ok",
        iterations=requested_iterations,
        checksum=checksum,
        request_id=request.state.request_id,
    )


@router.get("/images", response_model=list[ImageResponse], tags=["images"])
def list_images(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
) -> list[ImageResponse]:
    images = ImageCatalogService(settings).list_authorized_images(user)
    return [
        ImageResponse(
            id=image.id,
            display_name=image.display_name,
            description=image.description,
            default_version=image.default_version,
            allowed_roles=image.allowed_roles,
            versions=[
                ImageVersionResponse(
                    version=version.version,
                    ubuntu_release=version.ubuntu_release,
                    architecture=version.architecture,
                    artifact_format=version.artifact_format,
                    lifecycle=version.lifecycle,
                )
                for version in image.versions
                if version.lifecycle == "available"
            ],
        )
        for image in images
    ]


@router.post("/desktops", response_model=DesktopResponse, status_code=202, tags=["desktops"])
def create_desktop(
    body: DesktopCreateRequest,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
    idempotency_key: Annotated[
        str | None,
        Header(alias="Idempotency-Key", min_length=8, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$"),
    ] = None,
) -> Desktop:
    enforce_rate_limit(
        request=request,
        user=user,
        settings=settings,
        scope="desktop-mutation",
        limit=settings.desktop_mutation_rate_limit,
        window_seconds=settings.desktop_mutation_rate_window_seconds,
    )
    try:
        return DesktopService(db, settings).create_desktop(
            request=body,
            user=user,
            idempotency_key=idempotency_key,
            request_id=request.state.request_id,
            source_ip=source_ip(request),
        )
    except ApiError:
        record_desktop_provision_request(body.image_id, "rejected")
        raise


@router.get("/desktops", response_model=DesktopListResponse, tags=["desktops"])
def list_desktops(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
    all_users: Annotated[bool, Query(alias="all_users")] = False,
) -> DesktopListResponse:
    desktops = DesktopService(db, settings).list_desktops(user=user, all_users=all_users)
    return DesktopListResponse(desktops=[DesktopResponse.model_validate(desktop) for desktop in desktops])


@router.get("/desktops/{desktop_id}", response_model=DesktopResponse, tags=["desktops"])
def get_desktop(
    desktop_id: UUID,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    return DesktopService(db, settings).get_desktop(desktop_id=str(desktop_id), user=user)


@router.post("/desktops/{desktop_id}/connect", response_model=DesktopConnectionResponse, tags=["desktops"])
def connect_desktop(
    desktop_id: UUID,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    remote_access: Annotated[RemoteAccessService, Depends(get_remote_access_service)],
    db: Annotated[Session, Depends(get_db)],
) -> DesktopConnectionResponse:
    enforce_rate_limit(
        request=request,
        user=user,
        settings=settings,
        scope="desktop-connect",
        limit=settings.desktop_connect_rate_limit,
        window_seconds=settings.desktop_connect_rate_window_seconds,
    )
    return DesktopService(db, settings).connect_desktop(
        desktop_id=str(desktop_id),
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
        remote_access=remote_access,
    )


@router.post("/desktops/{desktop_id}/start", response_model=DesktopResponse, tags=["desktops"])
def start_desktop(
    desktop_id: UUID,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    enforce_rate_limit(
        request=request,
        user=user,
        settings=settings,
        scope="desktop-mutation",
        limit=settings.desktop_mutation_rate_limit,
        window_seconds=settings.desktop_mutation_rate_window_seconds,
    )
    return DesktopService(db, settings).start_desktop(
        desktop_id=str(desktop_id),
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


@router.post("/desktops/{desktop_id}/stop", response_model=DesktopResponse, tags=["desktops"])
def stop_desktop(
    desktop_id: UUID,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    enforce_rate_limit(
        request=request,
        user=user,
        settings=settings,
        scope="desktop-mutation",
        limit=settings.desktop_mutation_rate_limit,
        window_seconds=settings.desktop_mutation_rate_window_seconds,
    )
    return DesktopService(db, settings).stop_desktop(
        desktop_id=str(desktop_id),
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


@router.delete("/desktops/{desktop_id}", response_model=DesktopResponse, status_code=202, tags=["desktops"])
def delete_desktop(
    desktop_id: UUID,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    enforce_rate_limit(
        request=request,
        user=user,
        settings=settings,
        scope="desktop-mutation",
        limit=settings.desktop_mutation_rate_limit,
        window_seconds=settings.desktop_mutation_rate_window_seconds,
    )
    return DesktopService(db, settings).delete_desktop(
        desktop_id=str(desktop_id),
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


@router.get("/audit-events", response_model=AuditEventListResponse, tags=["audit"])
def audit_events(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    action: Annotated[str | None, Query(pattern=r"^[A-Z0-9_]{3,64}$")] = None,
    result: Annotated[str | None, Query(pattern=r"^[A-Z0-9_]{2,32}$")] = None,
) -> AuditEventListResponse:
    events = DesktopService(db, settings).audit_events(user=user, limit=limit, action=action, result=result)
    return AuditEventListResponse(audit_events=[AuditEventResponse.model_validate(event) for event in events])


@router.get("/audit-events/export", tags=["audit"])
def audit_events_export(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
    limit: Annotated[int, Query(ge=1, le=1000)] = 200,
    action: Annotated[str | None, Query(pattern=r"^[A-Z0-9_]{3,64}$")] = None,
    result: Annotated[str | None, Query(pattern=r"^[A-Z0-9_]{2,32}$")] = None,
) -> Response:
    events = DesktopService(db, settings).audit_events(user=user, limit=limit, action=action, result=result)
    lines = [
        json.dumps(
            AuditEventResponse.model_validate(event).model_dump(mode="json"),
            sort_keys=True,
            separators=(",", ":"),
        )
        for event in events
    ]
    body = "\n".join(lines)
    if body:
        body += "\n"
    return Response(body, media_type="application/x-ndjson")


@router.get("/metrics", tags=["system"])
def metrics(
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Response:
    refresh_desktop_gauges(
        db,
        remote_session_ttl_seconds=settings.remote_session_ttl_seconds,
        remote_desktop_protocol=settings.remote_desktop_protocol,
    )
    return Response(generate_prometheus_metrics(), media_type=CONTENT_TYPE_LATEST)
