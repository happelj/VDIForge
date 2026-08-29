from __future__ import annotations

import json
from collections.abc import Generator
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.dependencies import current_settings, get_current_user, get_remote_access_service
from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings, get_settings
from app.db.base import Base
from app.db.session import get_db
from app.main import create_app
from app.schemas.api import DesktopConnectionResponse
from app.security.rate_limit import api_rate_limiter


@pytest.fixture(autouse=True)
def reset_api_rate_limiter() -> Generator[None]:
    api_rate_limiter.reset()
    yield
    api_rate_limiter.reset()


class FakeRemoteAccessService:
    def connection_for(self, *, desktop, user) -> DesktopConnectionResponse:
        return DesktopConnectionResponse(
            desktop_id=desktop.id,
            connection_url=f"https://remote.vdiforge.local/?data=fake-{desktop.id}",
            expires_at=datetime.now(UTC) + timedelta(minutes=5),
            protocol="rdp",
        )


@pytest.fixture()
def catalog_path(tmp_path: Path) -> Path:
    path = tmp_path / "catalog.json"
    path.write_text(
        json.dumps(
            {
                "schemaVersion": "vdiforge.io/image-catalog/v1alpha1",
                "images": [
                    {
                        "id": "ubuntu-base",
                        "displayName": "Ubuntu Base",
                        "defaultVersion": "1.0.0",
                        "description": "Base desktop",
                        "allowedRoles": ["vdi-user", "vdi-developer", "vdi-devops", "vdi-admin"],
                        "versions": [
                            {
                                "version": "1.0.0",
                                "ubuntuRelease": "26.04 LTS",
                                "architecture": "amd64",
                                "artifactFormat": "qcow2",
                                "lifecycle": "candidate",
                                "manifestPath": "artifacts/images/ubuntu-base/1.0.0/ubuntu-base-1.0.0.manifest.json",
                            }
                        ],
                    },
                    {
                        "id": "ubuntu-devops",
                        "displayName": "Ubuntu DevOps",
                        "defaultVersion": "1.0.0",
                        "description": "DevOps desktop",
                        "allowedRoles": ["vdi-devops", "vdi-admin"],
                        "versions": [
                            {
                                "version": "1.0.0",
                                "ubuntuRelease": "26.04 LTS",
                                "architecture": "amd64",
                                "artifactFormat": "qcow2",
                                "lifecycle": "available",
                                "manifestPath": (
                                    "artifacts/images/ubuntu-devops/1.0.0/"
                                    "ubuntu-devops-1.0.0.manifest.json"
                                ),
                                "sourcePvcName": "vdiforge-golden-ubuntu-devops-1-0-0",
                            }
                        ],
                    },
                ],
            }
        ),
        encoding="utf-8",
    )
    return path


@pytest.fixture()
def settings(catalog_path: Path) -> Settings:
    return Settings(
        database_url="sqlite:///:memory:",
        image_catalog_path=catalog_path,
        max_desktops_per_user=1,
        max_desktops_per_admin=3,
    )


@pytest.fixture()
def db_session() -> Generator[Session]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False, future=True)
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as session:
        yield session


@pytest.fixture()
def users() -> dict[str, AuthenticatedUser]:
    return {
        "user": AuthenticatedUser("sub-user", "demo-user", frozenset({"vdi-user"})),
        "devops": AuthenticatedUser(
            "sub-devops",
            "demo-devops",
            frozenset({"vdi-user", "vdi-developer", "vdi-devops"}),
        ),
        "admin": AuthenticatedUser(
            "sub-admin",
            "demo-admin",
            frozenset({"vdi-user", "vdi-developer", "vdi-devops", "vdi-admin"}),
        ),
    }


@pytest.fixture()
def client(
    settings: Settings,
    db_session: Session,
    users: dict[str, AuthenticatedUser],
) -> Generator[TestClient]:
    get_settings.cache_clear()
    app = create_app()
    app.dependency_overrides[get_db] = lambda: db_session
    app.dependency_overrides[current_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: users["devops"]
    app.dependency_overrides[get_remote_access_service] = lambda: FakeRemoteAccessService()
    with TestClient(app) as test_client:
        yield test_client
