from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AuthenticatedUser:
    subject: str
    username: str
    roles: frozenset[str]

    @property
    def is_admin(self) -> bool:
        return "vdi-admin" in self.roles
