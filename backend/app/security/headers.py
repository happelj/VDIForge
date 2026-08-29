from __future__ import annotations

from fastapi import Request
from starlette.responses import Response

from app.config.settings import Settings

STRICT_API_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"


def apply_security_headers(request: Request, response: Response, settings: Settings) -> None:
    if not settings.security_headers_enabled:
        return

    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("Referrer-Policy", settings.referrer_policy)
    response.headers.setdefault("Permissions-Policy", settings.permissions_policy)
    if settings.hsts_enabled:
        response.headers.setdefault(
            "Strict-Transport-Security",
            f"max-age={settings.hsts_max_age_seconds}; includeSubDomains",
        )

    if request.url.path.startswith(("/api/", "/metrics")):
        response.headers.setdefault("Content-Security-Policy", settings.api_content_security_policy)
