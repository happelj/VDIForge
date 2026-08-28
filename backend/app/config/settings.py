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
