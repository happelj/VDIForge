from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

SENSITIVE_KEY_RE = re.compile(
    r"(authorization|access[_-]?token|refresh[_-]?token|id[_-]?token|password|passwd|secret|credential|private[_-]?key)",
    re.IGNORECASE,
)
BEARER_RE = re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]+", re.IGNORECASE)
JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")
SECRET_ASSIGNMENT_RE = re.compile(
    r"\b(password|passwd|secret|credential|access[_-]?token|refresh[_-]?token|private[_-]?key)\s*[:=]\s*[^,\s}]+",
    re.IGNORECASE,
)

REDACTED = "[REDACTED]"


def is_sensitive_key(key: str) -> bool:
    return bool(SENSITIVE_KEY_RE.search(key))


def redact_text(value: str) -> str:
    value = BEARER_RE.sub("Bearer [REDACTED]", value)
    value = JWT_RE.sub(REDACTED, value)
    return SECRET_ASSIGNMENT_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", value)


def redact_sensitive(value: Any) -> Any:
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, Mapping):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            text_key = str(key)
            redacted[text_key] = REDACTED if is_sensitive_key(text_key) else redact_sensitive(item)
        return redacted
    if isinstance(value, Sequence) and not isinstance(value, bytes | bytearray):
        return [redact_sensitive(item) for item in value]
    return value
