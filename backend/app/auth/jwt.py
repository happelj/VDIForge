from __future__ import annotations

import json
import ssl
import time
import urllib.request
from urllib.parse import urlparse

import jwt
from jwt import InvalidTokenError

from app.auth.claims import AuthenticatedUser
from app.config.settings import Settings


class JwtValidationError(Exception):
    pass


class JwtVerifier:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._jwks: dict | None = None
        self._jwks_expires_at = 0.0

    def verify(self, token: str) -> AuthenticatedUser:
        try:
            header = jwt.get_unverified_header(token)
        except InvalidTokenError as exc:
            raise JwtValidationError("Invalid JWT header.") from exc

        if header.get("alg") != "RS256":
            raise JwtValidationError("Only RS256 access tokens are accepted.")
        kid = header.get("kid")
        if not kid:
            raise JwtValidationError("JWT header is missing kid.")

        jwk = self._key_for_kid(kid)
        try:
            key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(jwk))
            payload = jwt.decode(
                token,
                key=key,
                algorithms=["RS256"],
                issuer=self.settings.keycloak_issuer.rstrip("/"),
                audience=self.settings.jwt_audience,
                options={"require": ["exp", "sub"]},
            )
        except InvalidTokenError as exc:
            raise JwtValidationError("JWT validation failed.") from exc

        subject = payload.get("sub")
        username = payload.get("preferred_username") or payload.get("email") or subject
        if not subject or not username:
            raise JwtValidationError("JWT missing required identity claims.")

        roles = self._extract_roles(payload)
        return AuthenticatedUser(subject=subject, username=username, roles=frozenset(roles))

    def _key_for_kid(self, kid: str) -> dict:
        jwks = self._fetch_jwks()
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                return key
        self._jwks = None
        jwks = self._fetch_jwks()
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                return key
        raise JwtValidationError("JWT signing key was not found in JWKS.")

    def _fetch_jwks(self) -> dict:
        now = time.monotonic()
        if self._jwks is not None and now < self._jwks_expires_at:
            return self._jwks

        context = ssl.create_default_context(cafile=self.settings.keycloak_ca_file)
        scheme = urlparse(self.settings.jwks_url).scheme
        if scheme not in {"http", "https"}:
            raise JwtValidationError("JWKS URL must use http or https.")
        with urllib.request.urlopen(self.settings.jwks_url, timeout=10, context=context) as response:  # noqa: S310
            jwks = json.loads(response.read().decode("utf-8"))
        if not jwks.get("keys"):
            raise JwtValidationError("JWKS did not contain signing keys.")
        self._jwks = jwks
        self._jwks_expires_at = now + self.settings.jwks_cache_seconds
        return jwks

    def _extract_roles(self, payload: dict) -> set[str]:
        roles = set(payload.get(self.settings.jwt_roles_claim, []))
        realm_access = payload.get("realm_access", {})
        if isinstance(realm_access, dict):
            roles.update(realm_access.get("roles", []))
        return {role for role in roles if isinstance(role, str)}
