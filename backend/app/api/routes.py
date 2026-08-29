from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header, Query, Request, Response
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app import __version__
from app.api.dependencies import current_settings, get_current_user, get_remote_access_service
from app.api.errors import ApiError
from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings
from app.db.session import get_db
from app.models.entities import Desktop
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
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> Desktop:
    return DesktopService(db, settings).create_desktop(
        request=body,
        user=user,
        idempotency_key=idempotency_key,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


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
    desktop_id: str,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    return DesktopService(db, settings).get_desktop(desktop_id=desktop_id, user=user)


@router.post("/desktops/{desktop_id}/connect", response_model=DesktopConnectionResponse, tags=["desktops"])
def connect_desktop(
    desktop_id: str,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    remote_access: Annotated[RemoteAccessService, Depends(get_remote_access_service)],
    db: Annotated[Session, Depends(get_db)],
) -> DesktopConnectionResponse:
    return DesktopService(db, settings).connect_desktop(
        desktop_id=desktop_id,
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
        remote_access=remote_access,
    )


@router.post("/desktops/{desktop_id}/start", response_model=DesktopResponse, tags=["desktops"])
def start_desktop(
    desktop_id: str,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    return DesktopService(db, settings).start_desktop(
        desktop_id=desktop_id,
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


@router.post("/desktops/{desktop_id}/stop", response_model=DesktopResponse, tags=["desktops"])
def stop_desktop(
    desktop_id: str,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    return DesktopService(db, settings).stop_desktop(
        desktop_id=desktop_id,
        user=user,
        request_id=request.state.request_id,
        source_ip=source_ip(request),
    )


@router.delete("/desktops/{desktop_id}", response_model=DesktopResponse, status_code=202, tags=["desktops"])
def delete_desktop(
    desktop_id: str,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(current_settings)],
    db: Annotated[Session, Depends(get_db)],
) -> Desktop:
    return DesktopService(db, settings).delete_desktop(
        desktop_id=desktop_id,
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
) -> AuditEventListResponse:
    events = DesktopService(db, settings).audit_events(user=user, limit=limit)
    return AuditEventListResponse(audit_events=[AuditEventResponse.model_validate(event) for event in events])


@router.get("/metrics", tags=["system"])
def metrics(db: Annotated[Session, Depends(get_db)]) -> Response:
    counts = dict(db.execute(select(Desktop.observed_state, func.count()).group_by(Desktop.observed_state)).all())
    total = sum(int(value) for value in counts.values())
    lines = [
        "# HELP vdiforge_desktops_total Number of VDIForge desktop records by observed state.",
        "# TYPE vdiforge_desktops_total gauge",
    ]
    for state, count in sorted(counts.items()):
        lines.append(f'vdiforge_desktops_total{{state="{state}"}} {count}')
    lines.append("# HELP vdiforge_desktops_all_total Total number of VDIForge desktop records.")
    lines.append("# TYPE vdiforge_desktops_all_total gauge")
    lines.append(f"vdiforge_desktops_all_total {total}")
    return Response("\n".join(lines) + "\n", media_type="text/plain; version=0.0.4")
