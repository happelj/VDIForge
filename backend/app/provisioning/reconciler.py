from __future__ import annotations

import logging
import time
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.audit.service import record_audit_event
from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings, get_settings
from app.db.session import SessionLocal
from app.models.entities import Desktop, ProvisioningOperation
from app.provisioning.kubevirt import KubeVirtClient
from app.services.resource_profiles import get_resource_profile

LOGGER = logging.getLogger(__name__)


def now_utc() -> datetime:
    return datetime.now(UTC)


class Reconciler:
    def __init__(self, settings: Settings, kubevirt: KubeVirtClient | None = None) -> None:
        self.settings = settings
        self.kubevirt = kubevirt or KubeVirtClient(settings)

    def run_forever(self) -> None:
        LOGGER.info("Starting VDIForge provisioner.", extra={"operation": "provisioner_start"})
        while True:
            with SessionLocal() as db:
                self.reconcile_once(db)
            time.sleep(self.settings.provisioner_poll_seconds)

    def reconcile_once(self, db: Session) -> int:
        statement = select(Desktop).where(Desktop.observed_state.not_in(["TERMINATED"]))
        desktops = list(db.scalars(statement))
        changed = 0
        for desktop in desktops:
            if desktop.next_reconcile_at and desktop.next_reconcile_at > now_utc():
                continue
            self._reconcile_desktop(db, desktop)
            changed += 1
        db.commit()
        return changed

    def _reconcile_desktop(self, db: Session, desktop: Desktop) -> None:
        try:
            profile = get_resource_profile(desktop.resource_profile)
            if profile is None:
                self._fail(db, desktop, "INVALID_RESOURCE_PROFILE", "Desktop references an unknown resource profile.")
                return

            if desktop.desired_state == "DELETED":
                self.kubevirt.delete_desktop_resources(desktop)
                if self.kubevirt.desktop_resources_deleted(desktop):
                    self._transition(db, desktop, "TERMINATED", "DESKTOP_DELETED")
                else:
                    desktop.observed_state = "TERMINATING"
                return

            if desktop.desired_state == "STOPPED":
                self.kubevirt.ensure_vm_stopped(desktop.kubevirt_vm_name)
                desktop.observed_state = "STOPPING" if self.kubevirt.vmi_exists(desktop.kubevirt_vm_name) else "STOPPED"
                desktop.last_observed_at = now_utc()
                return

            if not self.kubevirt.source_pvc_exists(desktop.source_pvc_name):
                self._fail(
                    db,
                    desktop,
                    "IMAGE_SOURCE_UNAVAILABLE",
                    f"Source PVC {desktop.source_pvc_name} is not available.",
                )
                return

            self.kubevirt.ensure_data_volume(desktop, profile)
            self.kubevirt.ensure_vm(desktop, profile)
            self.kubevirt.ensure_service(desktop)
            self.kubevirt.ensure_vm_running(desktop.kubevirt_vm_name)

            if not self.kubevirt.data_volume_ready(desktop.kubevirt_data_volume_name):
                desktop.observed_state = "PROVISIONING"
                desktop.last_observed_at = now_utc()
                return

            desktop.observed_state = (
                "READY"
                if self.kubevirt.vmi_running_and_ready(desktop.kubevirt_vm_name)
                and self.kubevirt.remote_desktop_reachable(desktop)
                else "BOOTING"
            )
            if desktop.observed_state == "READY":
                self._complete_latest_operation(db, desktop, "SUCCESS", "Desktop is ready.")
                self._audit_system(db, desktop, "DESKTOP_CREATED", "SUCCESS", {})
            desktop.last_observed_at = now_utc()
            desktop.failure_code = None
            desktop.failure_message = None
            desktop.next_reconcile_at = None
        except Exception as exc:
            self._retry_or_fail(db, desktop, exc)

    def _retry_or_fail(self, db: Session, desktop: Desktop, exc: Exception) -> None:
        desktop.provisioning_attempts += 1
        if desktop.provisioning_attempts >= self.settings.provisioner_max_attempts:
            self._fail(db, desktop, "PROVISIONING_FAILED", str(exc))
            return
        delay = min(self.settings.provisioner_max_backoff_seconds, 5 * (2 ** min(desktop.provisioning_attempts, 6)))
        desktop.next_reconcile_at = now_utc() + timedelta(seconds=delay)
        desktop.last_observed_at = now_utc()
        LOGGER.warning(
            "Provisioning attempt failed; retry scheduled.",
            extra={
                "request_id": desktop.request_id,
                "operation": "reconcile_desktop",
                "resource_id": desktop.id,
            },
        )

    def _fail(self, db: Session, desktop: Desktop, code: str, message: str) -> None:
        desktop.observed_state = "FAILED"
        desktop.failure_code = code
        desktop.failure_message = message[:2048]
        desktop.last_observed_at = now_utc()
        self._complete_latest_operation(db, desktop, "FAILED", message)
        self._audit_system(db, desktop, "DESKTOP_FAILED", "FAILURE", {"failure_code": code})

    def _transition(self, db: Session, desktop: Desktop, state: str, audit_action: str) -> None:
        previous = desktop.observed_state
        desktop.observed_state = state
        desktop.last_observed_at = now_utc()
        desktop.next_reconcile_at = None
        self._complete_latest_operation(db, desktop, "SUCCESS", f"{previous} -> {state}")
        self._audit_system(db, desktop, audit_action, "SUCCESS", {"previous_state": previous, "state": state})

    def _complete_latest_operation(self, db: Session, desktop: Desktop, status: str, message: str) -> None:
        statement = (
            select(ProvisioningOperation)
            .where(ProvisioningOperation.desktop_id == desktop.id, ProvisioningOperation.status == "PENDING")
            .order_by(ProvisioningOperation.created_at.desc())
            .limit(1)
        )
        operation = db.scalar(statement)
        if operation:
            operation.status = status
            operation.message = message[:2048]
            operation.updated_at = now_utc()

    def _audit_system(self, db: Session, desktop: Desktop, action: str, result: str, details: dict) -> None:
        user = AuthenticatedUser(subject=desktop.owner_subject, username=desktop.owner_username, roles=frozenset())
        record_audit_event(
            db,
            request_id=desktop.request_id,
            user=user,
            action=action,
            resource_type="Desktop",
            resource_id=desktop.id,
            source_ip=None,
            result=result,
            details=details,
        )


def main() -> int:
    from app.observability.logging import configure_logging

    settings = get_settings()
    configure_logging(settings.log_level)
    Reconciler(settings).run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
