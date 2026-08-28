from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import JSON, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


def now_utc() -> datetime:
    return datetime.now(UTC)


def new_uuid() -> str:
    return str(uuid4())


class Desktop(Base):
    __tablename__ = "desktops"
    __table_args__ = (UniqueConstraint("owner_subject", "idempotency_key", name="uq_desktops_owner_idempotency"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    display_name: Mapped[str] = mapped_column(String(128))
    owner_subject: Mapped[str] = mapped_column(String(255), index=True)
    owner_username: Mapped[str] = mapped_column(String(255))
    image_id: Mapped[str] = mapped_column(String(64))
    image_version: Mapped[str] = mapped_column(String(32))
    resource_profile: Mapped[str] = mapped_column(String(32))
    desired_state: Mapped[str] = mapped_column(String(32))
    observed_state: Mapped[str] = mapped_column(String(32), index=True)
    kubevirt_vm_name: Mapped[str] = mapped_column(String(63), unique=True)
    kubevirt_data_volume_name: Mapped[str] = mapped_column(String(63), unique=True)
    kubevirt_service_name: Mapped[str] = mapped_column(String(63), unique=True)
    source_pvc_name: Mapped[str] = mapped_column(String(253))
    idempotency_key: Mapped[str] = mapped_column(String(128))
    request_id: Mapped[str] = mapped_column(String(64))
    provisioning_attempts: Mapped[int] = mapped_column(default=0)
    next_reconcile_at: Mapped[datetime | None] = mapped_column(nullable=True)
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    failure_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_observed_at: Mapped[datetime | None] = mapped_column(nullable=True)
    last_connected_at: Mapped[datetime | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(default=now_utc)
    updated_at: Mapped[datetime] = mapped_column(default=now_utc, onupdate=now_utc)

    operations: Mapped[list[ProvisioningOperation]] = relationship(
        "ProvisioningOperation",
        back_populates="desktop",
        cascade="all, delete-orphan",
    )


class ProvisioningOperation(Base):
    __tablename__ = "provisioning_operations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    desktop_id: Mapped[str] = mapped_column(ForeignKey("desktops.id", ondelete="CASCADE"), index=True)
    operation: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32))
    request_id: Mapped[str] = mapped_column(String(64))
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    attempts: Mapped[int] = mapped_column(default=0)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(default=now_utc)
    updated_at: Mapped[datetime] = mapped_column(default=now_utc, onupdate=now_utc)

    desktop: Mapped[Desktop] = relationship("Desktop", back_populates="operations")


class AuditEvent(Base):
    __tablename__ = "audit_events"

    event_id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    timestamp: Mapped[datetime] = mapped_column(default=now_utc, index=True)
    request_id: Mapped[str] = mapped_column(String(64), index=True)
    user_subject: Mapped[str] = mapped_column(String(255), index=True)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    resource_type: Mapped[str] = mapped_column(String(64))
    resource_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    source_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    result: Mapped[str] = mapped_column(String(32))
    details: Mapped[dict] = mapped_column(JSON, default=dict)
