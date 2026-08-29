"""Add Phase 12 audit integrity metadata.

Revision ID: 0002_phase12_audit_integrity
Revises: 0001_phase7_initial
Create Date: 2026-08-29
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0002_phase12_audit_integrity"
down_revision = "0001_phase7_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("audit_events", sa.Column("previous_event_hash", sa.String(length=64), nullable=True))
    op.add_column("audit_events", sa.Column("event_hash", sa.String(length=64), nullable=True))
    op.create_unique_constraint("uq_audit_events_event_hash", "audit_events", ["event_hash"])


def downgrade() -> None:
    op.drop_constraint("uq_audit_events_event_hash", "audit_events", type_="unique")
    op.drop_column("audit_events", "event_hash")
    op.drop_column("audit_events", "previous_event_hash")
