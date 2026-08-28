"""Create Phase 7 control-plane tables.

Revision ID: 0001_phase7_initial
Revises:
Create Date: 2026-08-28
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0001_phase7_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "desktops",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("display_name", sa.String(length=128), nullable=False),
        sa.Column("owner_subject", sa.String(length=255), nullable=False),
        sa.Column("owner_username", sa.String(length=255), nullable=False),
        sa.Column("image_id", sa.String(length=64), nullable=False),
        sa.Column("image_version", sa.String(length=32), nullable=False),
        sa.Column("resource_profile", sa.String(length=32), nullable=False),
        sa.Column("desired_state", sa.String(length=32), nullable=False),
        sa.Column("observed_state", sa.String(length=32), nullable=False),
        sa.Column("kubevirt_vm_name", sa.String(length=63), nullable=False, unique=True),
        sa.Column("kubevirt_data_volume_name", sa.String(length=63), nullable=False, unique=True),
        sa.Column("kubevirt_service_name", sa.String(length=63), nullable=False, unique=True),
        sa.Column("source_pvc_name", sa.String(length=253), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("request_id", sa.String(length=64), nullable=False),
        sa.Column("provisioning_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("next_reconcile_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_code", sa.String(length=64), nullable=True),
        sa.Column("failure_message", sa.Text(), nullable=True),
        sa.Column("last_observed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_connected_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("owner_subject", "idempotency_key", name="uq_desktops_owner_idempotency"),
    )
    op.create_index("ix_desktops_owner_subject", "desktops", ["owner_subject"])
    op.create_index("ix_desktops_observed_state", "desktops", ["observed_state"])

    op.create_table(
        "provisioning_operations",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("desktop_id", sa.String(length=36), sa.ForeignKey("desktops.id", ondelete="CASCADE"), nullable=False),
        sa.Column("operation", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("request_id", sa.String(length=64), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_provisioning_operations_desktop_id", "provisioning_operations", ["desktop_id"])

    op.create_table(
        "audit_events",
        sa.Column("event_id", sa.String(length=36), primary_key=True),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("request_id", sa.String(length=64), nullable=False),
        sa.Column("user_subject", sa.String(length=255), nullable=False),
        sa.Column("username", sa.String(length=255), nullable=True),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("resource_type", sa.String(length=64), nullable=False),
        sa.Column("resource_id", sa.String(length=128), nullable=True),
        sa.Column("source_ip", sa.String(length=64), nullable=True),
        sa.Column("result", sa.String(length=32), nullable=False),
        sa.Column("details", sa.JSON(), nullable=False, server_default=sa.text("'{}'")),
    )
    op.create_index("ix_audit_events_timestamp", "audit_events", ["timestamp"])
    op.create_index("ix_audit_events_request_id", "audit_events", ["request_id"])
    op.create_index("ix_audit_events_user_subject", "audit_events", ["user_subject"])
    op.create_index("ix_audit_events_action", "audit_events", ["action"])


def downgrade() -> None:
    op.drop_index("ix_audit_events_action", table_name="audit_events")
    op.drop_index("ix_audit_events_user_subject", table_name="audit_events")
    op.drop_index("ix_audit_events_request_id", table_name="audit_events")
    op.drop_index("ix_audit_events_timestamp", table_name="audit_events")
    op.drop_table("audit_events")
    op.drop_index("ix_provisioning_operations_desktop_id", table_name="provisioning_operations")
    op.drop_table("provisioning_operations")
    op.drop_index("ix_desktops_observed_state", table_name="desktops")
    op.drop_index("ix_desktops_owner_subject", table_name="desktops")
    op.drop_table("desktops")
