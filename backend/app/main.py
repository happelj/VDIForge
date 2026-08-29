from __future__ import annotations

import logging
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import __version__
from app.api.errors import ApiError, api_error_handler, generic_error_handler
from app.api.routes import metrics, router
from app.config.settings import get_settings
from app.observability.logging import configure_logging
from app.observability.metrics import elapsed_since, monotonic_time, normalized_route, observe_api_request

API_PREFIX = "/api/v1"


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(
        title="VDIForge API",
        version=__version__,
        description="FastAPI VDI control plane and Guacamole session broker for VDIForge.",
    )
    app.state.vdiforge_api_prefix = API_PREFIX

    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
            expose_headers=["X-Request-ID"],
            allow_credentials=False,
        )

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        started_at = monotonic_time()
        route = request.url.path
        try:
            response = await call_next(request)
            route = normalized_route(request)
            observe_api_request(request.method, route, response.status_code, elapsed_since(started_at))
        except Exception:
            route = normalized_route(request)
            observe_api_request(request.method, route, 500, elapsed_since(started_at))
            raise
        response.headers["X-Request-ID"] = request_id
        return response

    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, exc: ApiError) -> JSONResponse:
        return await api_error_handler(request, exc)

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": "Request validation failed.",
                    "request_id": getattr(request.state, "request_id", "unknown"),
                }
            },
        )

    @app.exception_handler(Exception)
    async def handle_exception(request: Request, exc: Exception) -> JSONResponse:
        logging.getLogger(__name__).exception(
            "Unhandled request error.",
            extra={"request_id": getattr(request.state, "request_id", None), "operation": "api_request"},
        )
        return await generic_error_handler(request, exc)

    app.include_router(router, prefix=API_PREFIX)
    app.add_api_route("/metrics", metrics, methods=["GET"], include_in_schema=False)
    return app


app = create_app()
