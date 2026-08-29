from __future__ import annotations

import base64
import secrets
import socket
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

    def remote_secret_name(self, desktop: Desktop) -> str:
        return f"{desktop.kubevirt_vm_name}-remote"

    def source_pvc_exists(self, name: str) -> bool:
        try:
            self.core.read_namespaced_persistent_volume_claim(name, self.settings.desktops_namespace)
            return True
        except ApiException as exc:
            if exc.status == 404:
                return False
            raise

    def ensure_remote_access_secret(self, desktop: Desktop) -> None:
        name = self.remote_secret_name(desktop)
        try:
            self.core.read_namespaced_secret(name, self.settings.desktops_namespace)
            return
        except ApiException as exc:
            if exc.status != 404:
                raise

        username = self.settings.default_vm_user
        password = secrets.token_urlsafe(32)
        secret = client.V1Secret(
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=self.settings.desktops_namespace,
                labels={**self._labels(desktop), "app.kubernetes.io/component": "desktop-credential"},
            ),
            type="Opaque",
            string_data={
                "username": username,
                "password": password,
                "userdata": self._cloud_init(username, password),
            },
        )
        self.core.create_namespaced_secret(self.settings.desktops_namespace, secret)

    def read_remote_credentials(self, desktop: Desktop):
        from app.services.remote_access import RemoteCredentials

        secret = self.core.read_namespaced_secret(self.remote_secret_name(desktop), self.settings.desktops_namespace)
        data = secret.data or {}
        try:
            username = base64.b64decode(data["username"]).decode("utf-8")
            password = base64.b64decode(data["password"]).decode("utf-8")
        except KeyError as exc:
            raise RuntimeError("remote access secret is missing required data") from exc
        return RemoteCredentials(username=username, password=password)

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
        self.ensure_remote_access_secret(desktop)
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

    def remote_desktop_reachable(self, desktop: Desktop) -> bool:
        host = f"{desktop.kubevirt_service_name}.{self.settings.desktops_namespace}.svc.cluster.local"
        try:
            with socket.create_connection((host, self.settings.remote_desktop_port), timeout=2):
                return True
        except OSError:
            return False

    def vmi_exists(self, name: str) -> bool:
        return self._object_exists("kubevirt.io", "v1", "virtualmachineinstances", name)

    def delete_desktop_resources(self, desktop: Desktop) -> None:
        self._delete_service(desktop.kubevirt_service_name)
        self._delete_custom_object("kubevirt.io", "v1", "virtualmachines", desktop.kubevirt_vm_name)
        self._delete_custom_object("cdi.kubevirt.io", "v1beta1", "datavolumes", desktop.kubevirt_data_volume_name)
        self._delete_pvc(desktop.kubevirt_data_volume_name)
        self._delete_secret(self.remote_secret_name(desktop))

    def desktop_resources_deleted(self, desktop: Desktop) -> bool:
        return (
            not self._object_exists("kubevirt.io", "v1", "virtualmachines", desktop.kubevirt_vm_name)
            and not self._object_exists("cdi.kubevirt.io", "v1beta1", "datavolumes", desktop.kubevirt_data_volume_name)
            and not self._pvc_exists(desktop.kubevirt_data_volume_name)
            and not self._secret_exists(self.remote_secret_name(desktop))
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
                                "cloudInitNoCloud": {"secretRef": {"name": self.remote_secret_name(desktop)}},
                            },
                        ],
                    },
                },
            },
        }

    def _cloud_init(self, username: str, password: str) -> str:
        return f"""#cloud-config
users:
  - name: {username}
    gecos: VDIForge Desktop User
    homedir: /home/{username}
    create_home: true
    groups:
      - sudo
    shell: /bin/bash
    lock_passwd: false
    sudo:
      - ALL=(ALL) ALL
    ssh_authorized_keys:
      - {self.settings.default_ssh_public_key}
chpasswd:
  expire: false
  list: |
    {username}:{password}
ssh_pwauth: false
disable_root: true
write_files:
  - path: /etc/X11/Xwrapper.config
    owner: root:root
    permissions: '0644'
    content: |
      allowed_users=anybody
      needs_root_rights=yes
runcmd:
  - [mkdir, -p, /home/{username}]
  - [sh, -c, "printf 'startxfce4\n' > /home/{username}/.xsession"]
  - [chown, -R, {username}:{username}, /home/{username}]
  - [chmod, '0755', /home/{username}]
  - [chmod, '0644', /home/{username}/.xsession]
  - [systemctl, enable, --now, xrdp]
  - [systemctl, restart, xrdp-sesman]
  - [systemctl, restart, xrdp]
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

    def _secret_exists(self, name: str) -> bool:
        try:
            self.core.read_namespaced_secret(name, self.settings.desktops_namespace)
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

    def _delete_secret(self, name: str) -> None:
        try:
            self.core.delete_namespaced_secret(name, self.settings.desktops_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise

    def _delete_service(self, name: str) -> None:
        try:
            self.core.delete_namespaced_service(name, self.settings.desktops_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise
