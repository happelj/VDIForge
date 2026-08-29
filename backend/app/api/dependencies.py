from __future__ import annotations

from functools import lru_cache
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.api.errors import ApiError
from app.auth.claims import AuthenticatedUser
from app.auth.jwt import JwtValidationError, JwtVerifier
from app.config.settings import Settings, get_settings
from app.services.remote_access import RemoteAccessService

bearer_scheme = HTTPBearer(auto_error=False)
BearerCredentials = Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)]


@lru_cache(maxsize=1)
def get_jwt_verifier() -> JwtVerifier:
    return JwtVerifier(get_settings())


def current_settings() -> Settings:
    return get_settings()


def get_remote_access_service(settings: Annotated[Settings, Depends(current_settings)]) -> RemoteAccessService:
    return RemoteAccessService(settings)


def get_current_user(credentials: BearerCredentials) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiError(401, "AUTHENTICATION_REQUIRED", "A valid bearer access token is required.")
    try:
        return get_jwt_verifier().verify(credentials.credentials)
    except JwtValidationError as exc:
        raise ApiError(401, "INVALID_ACCESS_TOKEN", "The bearer access token is invalid.") from exc
