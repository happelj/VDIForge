from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.errors import ApiError
from app.audit.service import record_audit_event
from app.auth.claims import AuthenticatedUser
from app.auth.policy import TERMINAL_STATES, can_access_owned_resource, can_view_all_desktops, max_desktops_for_user
from app.config.settings import Settings
from app.models.entities import Desktop, ProvisioningOperation
from app.schemas.api import DesktopConnectionResponse, DesktopCreateRequest
from app.services.image_catalog import ImageCatalogService
from app.services.remote_access import RemoteAccessService
from app.services.resource_profiles import get_resource_profile


def _vm_safe_id() -> str:
    return uuid4().hex[:12]


def _now() -> datetime:
    return datetime.now(UTC)


class DesktopService:
    def __init__(self, db: Session, settings: Settings) -> None:
        self.db = db
        self.settings = settings
        self.catalog = ImageCatalogService(settings)

    def create_desktop(
        self,
        *,
        request: DesktopCreateRequest,
        user: AuthenticatedUser,
        idempotency_key: str | None,
        request_id: str,
        source_ip: str | None,
    ) -> Desktop:
        if not idempotency_key:
            raise ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "Desktop launch requires an Idempotency-Key header.")
        if len(idempotency_key) > 128:
            raise ApiError(400, "IDEMPOTENCY_KEY_TOO_LONG", "Idempotency-Key must be 128 characters or fewer.")

        existing = self.db.scalar(
            select(Desktop).where(Desktop.owner_subject == user.subject, Desktop.idempotency_key == idempotency_key)
        )
        if existing is not None:
            if (
                existing.image_id == request.image_id
                and existing.image_version == (request.image_version or existing.image_version)
                and existing.resource_profile == request.resource_profile
            ):
                return existing
            raise ApiError(409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key was already used with different inputs.")

        image, version = self.catalog.require_launchable_image(
            image_id=request.image_id,
            version=request.image_version,
            user=user,
        )
        profile = get_resource_profile(request.resource_profile)
        if profile is None:
            raise ApiError(400, "INVALID_RESOURCE_PROFILE", "The requested resource profile is not approved.")

        active_count = self._active_desktop_count(user)
        allowed_count = max_desktops_for_user(
            user,
            self.settings.max_desktops_per_user,
            self.settings.max_desktops_per_admin,
        )
        if active_count >= allowed_count:
            raise ApiError(409, "DESKTOP_QUOTA_EXCEEDED", "Desktop quota has been reached for this user.")

        suffix = _vm_safe_id()
        desktop = Desktop(
            display_name=request.display_name or image.display_name,
            owner_subject=user.subject,
            owner_username=user.username,
            image_id=image.id,
            image_version=version.version,
            resource_profile=profile.name,
            desired_state="RUNNING",
            observed_state="REQUESTED",
            kubevirt_vm_name=f"desktop-{suffix}",
            kubevirt_data_volume_name=f"desktop-{suffix}-root",
            kubevirt_service_name=f"desktop-{suffix}",
            source_pvc_name=version.source_pvc_name or "",
            idempotency_key=idempotency_key,
            request_id=request_id,
        )
        self.db.add(desktop)
        self.db.flush()
        self._operation(desktop, "DESKTOP_REQUESTED", "PENDING", request_id, idempotency_key)
        record_audit_event(
            self.db,
            request_id=request_id,
            user=user,
            action="DESKTOP_REQUESTED",
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=source_ip,
            result="SUCCESS",
            details={"image_id": desktop.image_id, "image_version": desktop.image_version, "profile": profile.name},
        )
        self.db.commit()
        self.db.refresh(desktop)
        return desktop

    def list_desktops(self, *, user: AuthenticatedUser, all_users: bool = False) -> list[Desktop]:
        statement = select(Desktop).order_by(Desktop.created_at.desc())
        if all_users:
            if not can_view_all_desktops(user):
                raise ApiError(403, "ADMIN_REQUIRED", "Only admins can list all desktops.")
        else:
            statement = statement.where(Desktop.owner_subject == user.subject)
        return list(self.db.scalars(statement))

    def get_desktop(self, *, desktop_id: str, user: AuthenticatedUser) -> Desktop:
        desktop = self.db.get(Desktop, desktop_id)
        if desktop is None:
            raise ApiError(404, "DESKTOP_NOT_FOUND", "Desktop was not found.")
        if not can_access_owned_resource(user, desktop.owner_subject):
            raise ApiError(403, "DESKTOP_ACCESS_DENIED", "You are not authorized to access this desktop.")
        return desktop

    def connect_desktop(
        self,
        *,
        desktop_id: str,
        user: AuthenticatedUser,
        request_id: str,
        source_ip: str | None,
        remote_access: RemoteAccessService | None = None,
    ) -> DesktopConnectionResponse:
        desktop = self.db.get(Desktop, desktop_id)
        if desktop is None:
            raise ApiError(404, "DESKTOP_NOT_FOUND", "Desktop was not found.")
        if not can_access_owned_resource(user, desktop.owner_subject):
            record_audit_event(
                self.db,
                request_id=request_id,
                user=user,
                action="DESKTOP_CONNECTION_DENIED",
                resource_type="Desktop",
                resource_id=desktop.id,
                source_ip=source_ip,
                result="DENIED",
                details={"reason": "ownership"},
            )
            self.db.commit()
            raise ApiError(403, "DESKTOP_ACCESS_DENIED", "You are not authorized to access this desktop.")
        if desktop.observed_state not in {"READY", "CONNECTED"}:
            record_audit_event(
                self.db,
                request_id=request_id,
                user=user,
                action="DESKTOP_CONNECTION_DENIED",
                resource_type="Desktop",
                resource_id=desktop.id,
                source_ip=source_ip,
                result="DENIED",
                details={"reason": "state", "observed_state": desktop.observed_state},
            )
            self.db.commit()
            raise ApiError(409, "DESKTOP_NOT_READY", "Desktop must be READY before a remote session can be created.")

        connection = (remote_access or RemoteAccessService(self.settings)).connection_for(desktop=desktop, user=user)
        desktop.last_connected_at = _now()
        desktop.updated_at = _now()
        self._operation(desktop, "DESKTOP_CONNECTION_REQUESTED", "SUCCESS", request_id, None)
        record_audit_event(
            self.db,
            request_id=request_id,
            user=user,
            action="DESKTOP_CONNECTION_REQUESTED",
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=source_ip,
            result="SUCCESS",
            details={
                "protocol": connection.protocol,
                "expires_at": connection.expires_at.isoformat(),
                "kubevirt_service": desktop.kubevirt_service_name,
            },
        )
        self.db.commit()
        return connection

    def start_desktop(
        self,
        *,
        desktop_id: str,
        user: AuthenticatedUser,
        request_id: str,
        source_ip: str | None,
    ) -> Desktop:
        desktop = self.get_desktop(desktop_id=desktop_id, user=user)
        if desktop.observed_state == "TERMINATED":
            raise ApiError(409, "DESKTOP_TERMINATED", "A terminated desktop cannot be started.")
        desktop.desired_state = "RUNNING"
        if desktop.observed_state in {"STOPPED", "STOPPING", "FAILED"}:
            desktop.observed_state = "PROVISIONING"
            desktop.failure_code = None
            desktop.failure_message = None
        desktop.updated_at = _now()
        self._operation(desktop, "DESKTOP_START_REQUESTED", "PENDING", request_id, None)
        record_audit_event(
            self.db,
            request_id=request_id,
            user=user,
            action="DESKTOP_STARTED",
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=source_ip,
            result="SUCCESS",
            details={},
        )
        self.db.commit()
        self.db.refresh(desktop)
        return desktop

    def stop_desktop(
        self,
        *,
        desktop_id: str,
        user: AuthenticatedUser,
        request_id: str,
        source_ip: str | None,
    ) -> Desktop:
        desktop = self.get_desktop(desktop_id=desktop_id, user=user)
        if desktop.observed_state == "TERMINATED":
            return desktop
        desktop.desired_state = "STOPPED"
        if desktop.observed_state not in {"STOPPED", "REQUESTED"}:
            desktop.observed_state = "STOPPING"
        desktop.updated_at = _now()
        self._operation(desktop, "DESKTOP_STOP_REQUESTED", "PENDING", request_id, None)
        record_audit_event(
            self.db,
            request_id=request_id,
            user=user,
            action="DESKTOP_STOPPED",
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=source_ip,
            result="SUCCESS",
            details={},
        )
        self.db.commit()
        self.db.refresh(desktop)
        return desktop

    def delete_desktop(
        self,
        *,
        desktop_id: str,
        user: AuthenticatedUser,
        request_id: str,
        source_ip: str | None,
    ) -> Desktop:
        desktop = self.get_desktop(desktop_id=desktop_id, user=user)
        if desktop.observed_state != "TERMINATED":
            desktop.desired_state = "DELETED"
            desktop.observed_state = "TERMINATING"
            desktop.updated_at = _now()
            self._operation(desktop, "DESKTOP_DELETE_REQUESTED", "PENDING", request_id, None)
        record_audit_event(
            self.db,
            request_id=request_id,
            user=user,
            action="DESKTOP_DELETED",
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=source_ip,
            result="SUCCESS",
            details={},
        )
        self.db.commit()
        self.db.refresh(desktop)
        return desktop

    def audit_events(self, *, user: AuthenticatedUser, limit: int = 50):
        if not user.is_admin:
            raise ApiError(403, "ADMIN_REQUIRED", "Only admins can read audit events.")
        from app.models.entities import AuditEvent

        statement = select(AuditEvent).order_by(AuditEvent.timestamp.desc()).limit(limit)
        return list(self.db.scalars(statement))

    def _active_desktop_count(self, user: AuthenticatedUser) -> int:
        statement = (
            select(func.count())
            .select_from(Desktop)
            .where(Desktop.owner_subject == user.subject, Desktop.observed_state.not_in(TERMINAL_STATES))
        )
        return int(self.db.scalar(statement) or 0)

    def _operation(
        self,
        desktop: Desktop,
        operation: str,
        status: str,
        request_id: str,
        idempotency_key: str | None,
    ) -> ProvisioningOperation:
        item = ProvisioningOperation(
            desktop_id=desktop.id,
            operation=operation,
            status=status,
            request_id=request_id,
            idempotency_key=idempotency_key,
        )
        self.db.add(item)
        return item
