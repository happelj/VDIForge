from __future__ import annotations

from sqlalchemy.orm import Session

from app.auth.claims import AuthenticatedUser
from app.models.entities import AuditEvent, new_uuid, now_utc
from app.security.audit_integrity import audit_hash_payload, compute_audit_event_hash
from app.security.redaction import redact_sensitive


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
    event_id = new_uuid()
    timestamp = now_utc()
    sanitized_details = redact_sensitive(details or {})
    previous_event_hash = (
        db.query(AuditEvent.event_hash)
        .filter(AuditEvent.event_hash.isnot(None))
        .order_by(AuditEvent.timestamp.desc(), AuditEvent.event_id.desc())
        .limit(1)
        .scalar()
    )
    event_hash = compute_audit_event_hash(
        audit_hash_payload(
            event_id=event_id,
            timestamp=timestamp,
            request_id=request_id,
            user_subject=user.subject,
            username=user.username,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            source_ip=source_ip,
            result=result,
            details=sanitized_details,
            previous_event_hash=previous_event_hash,
        )
    )
    event = AuditEvent(
        event_id=event_id,
        timestamp=timestamp,
        request_id=request_id,
        user_subject=user.subject,
        username=user.username,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        source_ip=source_ip,
        result=result,
        details=sanitized_details,
        previous_event_hash=previous_event_hash,
        event_hash=event_hash,
    )
    db.add(event)
    return event
