from __future__ import annotations

import argparse
import sys
import time

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.db.session import SessionLocal


def wait_for_db(timeout_seconds: int) -> None:
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with SessionLocal() as session:
                session.execute(text("select 1"))
            return
        except SQLAlchemyError as exc:
            last_error = exc
            time.sleep(2)
    raise RuntimeError(f"database did not become ready within {timeout_seconds}s: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Wait for the VDIForge database to accept connections.")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    wait_for_db(args.timeout)
    print("database ready")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"database wait failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
