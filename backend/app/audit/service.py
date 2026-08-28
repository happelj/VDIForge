from __future__ import annotations

from sqlalchemy.orm import Session

from app.auth.claims import AuthenticatedUser
from app.models.entities import AuditEvent


def record_audit_event(
    db: Session,
    *,
    request_id: str,
    user: AuthenticatedUser,
    action: str,
    resource_type: str,
    resource_id: str | None,
    source_ip: str | None,
    result: str,
    details: dict | None = None,
) -> AuditEvent:
    event = AuditEvent(
        request_id=request_id,
        user_subject=user.subject,
        username=user.username,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        source_ip=source_ip,
        result=result,
        details=details or {},
    )
    db.add(event)
    return event
