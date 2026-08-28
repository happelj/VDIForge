from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "service": getattr(record, "service", "vdiforge"),
            "request_id": getattr(record, "request_id", None),
            "user_id": getattr(record, "user_id", None),
            "operation": getattr(record, "operation", None),
            "resource_id": getattr(record, "resource_id", None),
            "message": record.getMessage(),
        }
        return json.dumps({key: value for key, value in payload.items() if value is not None}, separators=(",", ":"))


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())
