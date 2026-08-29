from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from typing import Any


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        if value.tzinfo is not None:
            value = value.astimezone(UTC).replace(tzinfo=None)
        return value.isoformat(timespec="microseconds")
    return str(value)


def audit_hash_payload(
    *,
    event_id: str,
    timestamp: datetime,
    request_id: str,
    user_subject: str,
    username: str | None,
    action: str,
    resource_type: str,
    resource_id: str | None,
    source_ip: str | None,
    result: str,
    details: dict,
    previous_event_hash: str | None,
) -> dict[str, Any]:
    return {
        "event_id": event_id,
        "timestamp": timestamp,
        "request_id": request_id,
        "user_subject": user_subject,
        "username": username,
        "action": action,
        "resource_type": resource_type,
        "resource_id": resource_id,
        "source_ip": source_ip,
        "result": result,
        "details": details,
        "previous_event_hash": previous_event_hash,
    }


def compute_audit_event_hash(payload: dict[str, Any]) -> str:
    body = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=_json_default).encode("utf-8")
    return hashlib.sha256(body).hexdigest()
