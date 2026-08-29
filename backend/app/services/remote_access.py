from __future__ import annotations

import base64
import hashlib
import hmac
import json
import urllib.parse
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from app.api.errors import ApiError
from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings
from app.models.entities import Desktop
from app.provisioning.kubevirt import KubeVirtClient
from app.schemas.api import DesktopConnectionResponse


@dataclass(frozen=True)
class RemoteCredentials:
    username: str
    password: str


class RemoteAccessService:
    def __init__(self, settings: Settings, kubevirt: KubeVirtClient | None = None) -> None:
        self.settings = settings
        self.kubevirt = kubevirt or KubeVirtClient(settings)

    def connection_for(self, *, desktop: Desktop, user: AuthenticatedUser) -> DesktopConnectionResponse:
        credentials = self.kubevirt.read_remote_credentials(desktop)
        expires_at = datetime.now(UTC) + timedelta(seconds=self.settings.remote_session_ttl_seconds)
        token = self._encrypt_json(self._payload(desktop, user, credentials, expires_at))
        query = urllib.parse.urlencode({"data": token})
        url = f"{self.settings.guacamole_base_url.rstrip('/')}/?{query}"
        return DesktopConnectionResponse(
            desktop_id=desktop.id,
            connection_url=url,
            expires_at=expires_at,
            protocol=self.settings.remote_desktop_protocol,
        )

    def _payload(
        self,
        desktop: Desktop,
        user: AuthenticatedUser,
        credentials: RemoteCredentials,
        expires_at: datetime,
    ) -> dict:
        connection_name = f"VDIForge {desktop.display_name} {desktop.id[:8]}"
        return {
            "username": user.username,
            "expires": int(expires_at.timestamp() * 1000),
            "connections": {
                connection_name: {
                    "id": f"desktop-{desktop.id}",
                    "protocol": self.settings.remote_desktop_protocol,
                    "parameters": {
                        "hostname": (
                            f"{desktop.kubevirt_service_name}."
                            f"{self.settings.desktops_namespace}.svc.cluster.local"
                        ),
                        "port": str(self.settings.remote_desktop_port),
                        "username": credentials.username,
                        "password": credentials.password,
                        "security": self.settings.guacamole_rdp_security,
                        "ignore-cert": "true",
                        "server-layout": self.settings.guacamole_rdp_server_layout,
                        "resize-method": "display-update",
                        "enable-drive": "false",
                        "disable-audio": "true",
                    },
                }
            },
        }

    def _encrypt_json(self, payload: dict) -> str:
        secret = self.settings.guacamole_json_secret_key
        if not secret:
            raise ApiError(503, "REMOTE_ACCESS_NOT_CONFIGURED", "Remote access is not configured.")
        try:
            key = bytes.fromhex(secret)
        except ValueError as exc:
            raise ApiError(503, "REMOTE_ACCESS_NOT_CONFIGURED", "Guacamole JSON key is not valid hex.") from exc
        if len(key) != 16:
            raise ApiError(503, "REMOTE_ACCESS_NOT_CONFIGURED", "Guacamole JSON key must be 128-bit hex.")

        plaintext = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        signed = hmac.new(key, plaintext, hashlib.sha256).digest() + plaintext
        padded = signed + bytes([16 - (len(signed) % 16)]) * (16 - (len(signed) % 16))
        cipher = Cipher(algorithms.AES(key), modes.CBC(b"\x00" * 16))
        encryptor = cipher.encryptor()
        encrypted = encryptor.update(padded) + encryptor.finalize()
        return base64.b64encode(encrypted).decode("ascii")
