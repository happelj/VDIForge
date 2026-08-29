from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VDIFORGE_", env_file=".env", extra="ignore")

    environment: str = "local"
    service_name: str = "vdiforge-api"
    run_mode: Literal["api", "provisioner"] = "api"
    log_level: str = "INFO"
    cors_allowed_origins: list[str] = Field(default_factory=lambda: ["https://vdiforge.local"])

    database_url: str = "sqlite:///./vdiforge.db"

    keycloak_issuer: str = "https://auth.vdiforge.local/realms/vdiforge"
    keycloak_jwks_url: str | None = None
    keycloak_ca_file: str | None = None
    jwt_audience: str = "vdiforge-api"
    jwt_roles_claim: str = "roles"
    jwks_cache_seconds: int = 300

    image_catalog_path: Path = Path("images/catalog.json")

    desktops_namespace: str = "vdiforge-desktops"
    storage_class: str = "vdiforge-local-path"
    desktop_node_selector_key: str = "vdiforge.io/node-role"
    desktop_node_selector_value: str = "vdi"
    provisioner_poll_seconds: int = 10
    provisioner_max_attempts: int = 12
    provisioner_max_backoff_seconds: int = 300
    desktop_boot_timeout_seconds: int = 900
    max_desktops_per_user: int = 1
    max_desktops_per_admin: int = 3

    default_vm_user: str = "vdiforge"
    remote_desktop_protocol: str = "rdp"
    remote_desktop_port: int = 3389
    remote_session_ttl_seconds: int = 300
    guacamole_base_url: str = "https://remote.vdiforge.local"
    guacamole_json_secret_key: str | None = None
    guacamole_rdp_security: str = "any"
    guacamole_rdp_server_layout: str = "en-us-qwerty"
    load_test_enabled: bool = False
    load_test_default_iterations: int = 125_000
    load_test_max_iterations: int = 1_500_000
    metrics_enabled: bool = True
    metrics_port: int = 9102
    default_ssh_public_key: str = Field(
        default=(
            "ssh-ed25519 "
            "AAAAC3NzaC1lZDI1NTE5AAAAIFZESUZvcmdlUGhhc2U3UGxhY2Vob2xkZXJLZXkK "
            "vdiforge-phase7-placeholder"
        )
    )

    @property
    def jwks_url(self) -> str:
        if self.keycloak_jwks_url:
            return self.keycloak_jwks_url
        issuer = self.keycloak_issuer.rstrip("/")
        return f"{issuer}/protocol/openid-connect/certs"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
