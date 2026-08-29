from __future__ import annotations

from sqlalchemy.orm import Session

from app.config.settings import Settings
from app.models.entities import Desktop
from app.provisioning.reconciler import Reconciler


class FakeKubeVirt:
    def __init__(self) -> None:
        self.source_exists = True
        self.dv_ready = False
        self.vm_ready = False
        self.remote_ready = False
        self.vmi_exists_value = True
        self.deleted = False
        self.created_data_volume = False
        self.created_vm = False
        self.created_service = False
        self.run_strategy = None

    def source_pvc_exists(self, name: str) -> bool:
        return self.source_exists

    def ensure_data_volume(self, desktop: Desktop, profile) -> None:
        self.created_data_volume = True

    def data_volume_ready(self, name: str) -> bool:
        return self.dv_ready

    def ensure_vm(self, desktop: Desktop, profile) -> None:
        self.created_vm = True

    def ensure_service(self, desktop: Desktop) -> None:
        self.created_service = True

    def ensure_vm_running(self, name: str) -> None:
        self.run_strategy = "Always"

    def vmi_running_and_ready(self, name: str) -> bool:
        return self.vm_ready

    def remote_desktop_reachable(self, desktop: Desktop) -> bool:
        return self.remote_ready

    def ensure_vm_stopped(self, name: str) -> None:
        self.run_strategy = "Halted"

    def vmi_exists(self, name: str) -> bool:
        return self.vmi_exists_value

    def delete_desktop_resources(self, desktop: Desktop) -> None:
        self.deleted = True

    def desktop_resources_deleted(self, desktop: Desktop) -> bool:
        return self.deleted


def desktop() -> Desktop:
    return Desktop(
        id="desktop-id",
        display_name="Ubuntu DevOps",
        owner_subject="sub-devops",
        owner_username="demo-devops",
        image_id="ubuntu-devops",
        image_version="1.0.0",
        resource_profile="small",
        desired_state="RUNNING",
        observed_state="REQUESTED",
        kubevirt_vm_name="desktop-test",
        kubevirt_data_volume_name="desktop-test-root",
        kubevirt_service_name="desktop-test",
        source_pvc_name="vdiforge-golden-ubuntu-devops-1-0-0",
        idempotency_key="key",
        request_id="request",
    )


def test_reconciler_moves_running_desktop_through_states(db_session: Session, settings: Settings) -> None:
    item = desktop()
    db_session.add(item)
    db_session.commit()

    fake = FakeKubeVirt()
    reconciler = Reconciler(settings, fake)
    reconciler.reconcile_once(db_session)
    assert item.observed_state == "PROVISIONING"
    assert fake.created_data_volume
    assert fake.created_vm
    assert fake.created_service
    assert fake.run_strategy == "Always"

    fake.dv_ready = True
    reconciler.reconcile_once(db_session)
    assert item.observed_state == "BOOTING"

    fake.vm_ready = True
    reconciler.reconcile_once(db_session)
    assert item.observed_state == "BOOTING"

    fake.remote_ready = True
    reconciler.reconcile_once(db_session)
    assert item.observed_state == "READY"


def test_reconciler_deletes_desktop_resources(db_session: Session, settings: Settings) -> None:
    item = desktop()
    item.desired_state = "DELETED"
    item.observed_state = "TERMINATING"
    db_session.add(item)
    db_session.commit()

    fake = FakeKubeVirt()
    Reconciler(settings, fake).reconcile_once(db_session)

    assert fake.deleted
    assert item.observed_state == "TERMINATED"
