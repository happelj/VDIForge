from __future__ import annotations

import base64
import hashlib
import hmac
import json
import urllib.parse

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings
from app.models.entities import Desktop
from app.provisioning.kubevirt import KubeVirtClient
from app.services.remote_access import RemoteAccessService


def remote_access_test_credential() -> str:
    return "not-returned-to-browser"


class FakeKubeVirt:
    def read_remote_credentials(self, desktop: Desktop):
        from app.services.remote_access import RemoteCredentials

        return RemoteCredentials(username="vdiforge", password=remote_access_test_credential())


def desktop() -> Desktop:
    return Desktop(
        id="desktop-id",
        display_name="Ubuntu DevOps",
        owner_subject="sub-devops",
        owner_username="demo-devops",
        image_id="ubuntu-devops",
        image_version="1.1.0",
        resource_profile="small",
        desired_state="RUNNING",
        observed_state="READY",
        kubevirt_vm_name="desktop-test",
        kubevirt_data_volume_name="desktop-test-root",
        kubevirt_service_name="desktop-test",
        source_pvc_name="vdiforge-golden-ubuntu-devops-1-1-0",
        idempotency_key="key",
        request_id="request",
    )


def decrypt_guacamole_json(token: str, hex_key: str) -> dict:
    key = bytes.fromhex(hex_key)
    encrypted = base64.b64decode(token)
    cipher = Cipher(algorithms.AES(key), modes.CBC(b"\x00" * 16))
    decryptor = cipher.decryptor()
    padded = decryptor.update(encrypted) + decryptor.finalize()
    padding = padded[-1]
    signed = padded[:-padding]
    signature = signed[:32]
    payload = signed[32:]
    expected = hmac.new(key, payload, hashlib.sha256).digest()
    assert hmac.compare_digest(signature, expected)
    return json.loads(payload.decode("utf-8"))


def test_guacamole_json_token_contains_scoped_rdp_connection() -> None:
    key = "0123456789abcdeffedcba9876543210"
    settings = Settings(guacamole_json_secret_key=key)
    user = AuthenticatedUser("sub-devops", "demo-devops", frozenset({"vdi-devops"}))

    response = RemoteAccessService(settings, FakeKubeVirt()).connection_for(desktop=desktop(), user=user)
    parsed = urllib.parse.urlparse(response.connection_url)
    token = urllib.parse.parse_qs(parsed.query)["data"][0]
    payload = decrypt_guacamole_json(token, key)

    assert response.protocol == "rdp"
    assert response.desktop_id == "desktop-id"
    assert remote_access_test_credential() not in response.model_dump_json()
    assert payload["username"] == "demo-devops"
    connection = payload["connections"]["VDIForge Ubuntu DevOps desktop-"]
    assert connection["protocol"] == "rdp"
    assert connection["parameters"]["hostname"] == "desktop-test.vdiforge-desktops.svc.cluster.local"
    assert connection["parameters"]["username"] == "vdiforge"
    assert connection["parameters"]["password"] == remote_access_test_credential()


def test_desktop_cloud_init_configures_xfce_xorg_session() -> None:
    client = object.__new__(KubeVirtClient)
    client.settings = Settings(default_ssh_public_key="ssh-ed25519 test-key")

    user_data = client._cloud_init("vdiforge", "test-password")

    assert "homedir: /home/vdiforge" in user_data
    assert "create_home: true" in user_data
    assert "allowed_users=anybody" in user_data
    assert "needs_root_rights=yes" in user_data
    assert "startxfce4" in user_data
    assert "restart, xrdp-sesman" in user_data
