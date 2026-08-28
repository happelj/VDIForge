from __future__ import annotations

from typing import Any

from kubernetes import client, config
from kubernetes.client import ApiException

from app.config.settings import Settings
from app.models.entities import Desktop
from app.services.resource_profiles import ResourceProfile


class KubeVirtClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        self.custom = client.CustomObjectsApi()
        self.core = client.CoreV1Api()

    def source_pvc_exists(self, name: str) -> bool:
        try:
            self.core.read_namespaced_persistent_volume_claim(name, self.settings.desktops_namespace)
            return True
        except ApiException as exc:
            if exc.status == 404:
                return False
            raise

    def ensure_data_volume(self, desktop: Desktop, profile: ResourceProfile) -> None:
        if self._object_exists("cdi.kubevirt.io", "v1beta1", "datavolumes", desktop.kubevirt_data_volume_name):
            return
        body = {
            "apiVersion": "cdi.kubevirt.io/v1beta1",
            "kind": "DataVolume",
            "metadata": {
                "name": desktop.kubevirt_data_volume_name,
                "namespace": self.settings.desktops_namespace,
                "labels": self._labels(desktop),
            },
            "spec": {
                "source": {
                    "pvc": {
                        "namespace": self.settings.desktops_namespace,
                        "name": desktop.source_pvc_name,
                    }
                },
                "storage": {
                    "accessModes": ["ReadWriteOnce"],
                    "resources": {"requests": {"storage": profile.disk}},
                    "storageClassName": self.settings.storage_class,
                },
            },
        }
        self.custom.create_namespaced_custom_object(
            group="cdi.kubevirt.io",
            version="v1beta1",
            namespace=self.settings.desktops_namespace,
            plural="datavolumes",
            body=body,
        )

    def data_volume_ready(self, name: str) -> bool:
        item = self._get_object("cdi.kubevirt.io", "v1beta1", "datavolumes", name)
        if item is None:
            return False
        conditions = item.get("status", {}).get("conditions", [])
        return any(condition.get("type") == "Ready" and condition.get("status") == "True" for condition in conditions)

    def ensure_vm(self, desktop: Desktop, profile: ResourceProfile) -> None:
        if self._object_exists("kubevirt.io", "v1", "virtualmachines", desktop.kubevirt_vm_name):
            return
        self.custom.create_namespaced_custom_object(
            group="kubevirt.io",
            version="v1",
            namespace=self.settings.desktops_namespace,
            plural="virtualmachines",
            body=self._vm_body(desktop, profile),
        )

    def ensure_vm_running(self, name: str) -> None:
        self._patch_vm_run_strategy(name, "Always")

    def ensure_vm_stopped(self, name: str) -> None:
        self._patch_vm_run_strategy(name, "Halted")

    def ensure_service(self, desktop: Desktop) -> None:
        try:
            self.core.read_namespaced_service(desktop.kubevirt_service_name, self.settings.desktops_namespace)
            return
        except ApiException as exc:
            if exc.status != 404:
                raise

        body = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=desktop.kubevirt_service_name,
                namespace=self.settings.desktops_namespace,
                labels=self._labels(desktop),
            ),
            spec=client.V1ServiceSpec(
                type="ClusterIP",
                selector={"vdiforge.io/desktop-id": desktop.id},
                ports=[
                    client.V1ServicePort(name="ssh", port=22, target_port=22, protocol="TCP"),
                    client.V1ServicePort(name="rdp", port=3389, target_port=3389, protocol="TCP"),
                ],
            ),
        )
        self.core.create_namespaced_service(self.settings.desktops_namespace, body)

    def vmi_running_and_ready(self, name: str) -> bool:
        vmi = self._get_object("kubevirt.io", "v1", "virtualmachineinstances", name)
        if not vmi:
            return False
        if vmi.get("status", {}).get("phase") != "Running":
            return False
        conditions = vmi.get("status", {}).get("conditions", [])
        return any(condition.get("type") == "Ready" and condition.get("status") == "True" for condition in conditions)

    def vmi_exists(self, name: str) -> bool:
        return self._object_exists("kubevirt.io", "v1", "virtualmachineinstances", name)

    def delete_desktop_resources(self, desktop: Desktop) -> None:
        self._delete_service(desktop.kubevirt_service_name)
        self._delete_custom_object("kubevirt.io", "v1", "virtualmachines", desktop.kubevirt_vm_name)
        self._delete_custom_object("cdi.kubevirt.io", "v1beta1", "datavolumes", desktop.kubevirt_data_volume_name)
        self._delete_pvc(desktop.kubevirt_data_volume_name)

    def desktop_resources_deleted(self, desktop: Desktop) -> bool:
        return (
            not self._object_exists("kubevirt.io", "v1", "virtualmachines", desktop.kubevirt_vm_name)
            and not self._object_exists("cdi.kubevirt.io", "v1beta1", "datavolumes", desktop.kubevirt_data_volume_name)
            and not self._pvc_exists(desktop.kubevirt_data_volume_name)
        )

    def _vm_body(self, desktop: Desktop, profile: ResourceProfile) -> dict[str, Any]:
        return {
            "apiVersion": "kubevirt.io/v1",
            "kind": "VirtualMachine",
            "metadata": {
                "name": desktop.kubevirt_vm_name,
                "namespace": self.settings.desktops_namespace,
                "labels": self._labels(desktop),
            },
            "spec": {
                "runStrategy": "Always",
                "template": {
                    "metadata": {"labels": self._labels(desktop)},
                    "spec": {
                        "nodeSelector": {
                            self.settings.desktop_node_selector_key: self.settings.desktop_node_selector_value,
                        },
                        "domain": {
                            "cpu": {"cores": profile.cpu_cores},
                            "resources": {"requests": {"memory": profile.memory}},
                            "devices": {
                                "disks": [
                                    {"name": "rootdisk", "disk": {"bus": "virtio"}},
                                    {"name": "cloudinitdisk", "disk": {"bus": "virtio"}},
                                ],
                                "interfaces": [{"name": "default", "masquerade": {}}],
                            },
                        },
                        "networks": [{"name": "default", "pod": {}}],
                        "volumes": [
                            {
                                "name": "rootdisk",
                                "persistentVolumeClaim": {"claimName": desktop.kubevirt_data_volume_name},
                            },
                            {
                                "name": "cloudinitdisk",
                                "cloudInitNoCloud": {"userData": self._cloud_init()},
                            },
                        ],
                    },
                },
            },
        }

    def _cloud_init(self) -> str:
        return f"""#cloud-config
users:
  - name: {self.settings.default_vm_user}
    groups:
      - sudo
    shell: /bin/bash
    lock_passwd: true
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - {self.settings.default_ssh_public_key}
ssh_pwauth: false
disable_root: true
"""

    def _labels(self, desktop: Desktop) -> dict[str, str]:
        return {
            "app.kubernetes.io/name": "vdiforge-desktop",
            "app.kubernetes.io/component": "desktop-vm",
            "app.kubernetes.io/part-of": "vdiforge",
            "vdiforge.io/managed-by": "provisioner",
            "vdiforge.io/desktop-id": desktop.id,
            "vdiforge.io/image-id": desktop.image_id,
        }

    def _get_object(self, group: str, version: str, plural: str, name: str) -> dict[str, Any] | None:
        try:
            return self.custom.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=self.settings.desktops_namespace,
                plural=plural,
                name=name,
            )
        except ApiException as exc:
            if exc.status == 404:
                return None
            raise

    def _object_exists(self, group: str, version: str, plural: str, name: str) -> bool:
        return self._get_object(group, version, plural, name) is not None

    def _patch_vm_run_strategy(self, name: str, run_strategy: str) -> None:
        if not self._object_exists("kubevirt.io", "v1", "virtualmachines", name):
            return
        self.custom.patch_namespaced_custom_object(
            group="kubevirt.io",
            version="v1",
            namespace=self.settings.desktops_namespace,
            plural="virtualmachines",
            name=name,
            body={"spec": {"runStrategy": run_strategy}},
        )

    def _delete_custom_object(self, group: str, version: str, plural: str, name: str) -> None:
        try:
            self.custom.delete_namespaced_custom_object(
                group=group,
                version=version,
                namespace=self.settings.desktops_namespace,
                plural=plural,
                name=name,
            )
        except ApiException as exc:
            if exc.status != 404:
                raise

    def _pvc_exists(self, name: str) -> bool:
        try:
            self.core.read_namespaced_persistent_volume_claim(name, self.settings.desktops_namespace)
            return True
        except ApiException as exc:
            if exc.status == 404:
                return False
            raise

    def _delete_pvc(self, name: str) -> None:
        try:
            self.core.delete_namespaced_persistent_volume_claim(name, self.settings.desktops_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise

    def _delete_service(self, name: str) -> None:
        try:
            self.core.delete_namespaced_service(name, self.settings.desktops_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise
