from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from app.api.errors import ApiError
from app.auth.claims import AuthenticatedUser
from app.auth.policy import can_launch_image
from app.config.settings import Settings


@dataclass(frozen=True)
class CatalogVersion:
    version: str
    ubuntu_release: str
    architecture: str
    artifact_format: str
    lifecycle: str
    manifest_path: str
    source_pvc_name: str | None


@dataclass(frozen=True)
class CatalogImage:
    id: str
    display_name: str
    default_version: str
    description: str
    allowed_roles: list[str]
    versions: list[CatalogVersion]

    def selected_version(self, version: str | None = None) -> CatalogVersion | None:
        target = version or self.default_version
        return next((item for item in self.versions if item.version == target), None)


class ImageCatalogService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def list_authorized_images(self, user: AuthenticatedUser) -> list[CatalogImage]:
        return [
            image
            for image in self._load_images()
            if can_launch_image(user, image.allowed_roles)
            and any(version.lifecycle == "available" for version in image.versions)
        ]

    def require_launchable_image(
        self,
        *,
        image_id: str,
        version: str | None,
        user: AuthenticatedUser,
    ) -> tuple[CatalogImage, CatalogVersion]:
        image = next((item for item in self._load_images() if item.id == image_id), None)
        if image is None:
            raise ApiError(404, "IMAGE_NOT_FOUND", "The requested image was not found.")
        if not can_launch_image(user, image.allowed_roles):
            raise ApiError(403, "IMAGE_NOT_AUTHORIZED", "You are not authorized to launch this image.")
        selected = image.selected_version(version)
        if selected is None:
            raise ApiError(404, "IMAGE_VERSION_NOT_FOUND", "The requested image version was not found.")
        if selected.lifecycle != "available" or not selected.source_pvc_name:
            raise ApiError(409, "IMAGE_NOT_AVAILABLE", "The requested image version is not available for launch.")
        return image, selected

    def validate_catalog(self) -> None:
        self._load_images()

    def _load_images(self) -> list[CatalogImage]:
        path = Path(self.settings.image_catalog_path)
        with path.open("r", encoding="utf-8") as handle:
            raw = json.load(handle)

        images = []
        for image in raw.get("images", []):
            versions = [
                CatalogVersion(
                    version=version["version"],
                    ubuntu_release=version["ubuntuRelease"],
                    architecture=version["architecture"],
                    artifact_format=version["artifactFormat"],
                    lifecycle=version["lifecycle"],
                    manifest_path=version["manifestPath"],
                    source_pvc_name=version.get("sourcePvcName"),
                )
                for version in image.get("versions", [])
            ]
            images.append(
                CatalogImage(
                    id=image["id"],
                    display_name=image["displayName"],
                    default_version=image["defaultVersion"],
                    description=image.get("description", ""),
                    allowed_roles=list(image["allowedRoles"]),
                    versions=versions,
                )
            )
        return images
