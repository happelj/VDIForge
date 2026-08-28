from __future__ import annotations

from app.auth.claims import AuthenticatedUser

ROLE_ORDER = ("vdi-user", "vdi-developer", "vdi-devops", "vdi-admin")
TERMINAL_STATES = {"TERMINATED", "FAILED"}


def has_any_role(user: AuthenticatedUser, allowed_roles: set[str]) -> bool:
    return bool(user.roles.intersection(allowed_roles))


def can_access_owned_resource(user: AuthenticatedUser, owner_subject: str) -> bool:
    return user.is_admin or user.subject == owner_subject


def can_launch_image(user: AuthenticatedUser, allowed_roles: list[str]) -> bool:
    return has_any_role(user, set(allowed_roles))


def can_view_all_desktops(user: AuthenticatedUser) -> bool:
    return user.is_admin


def max_desktops_for_user(user: AuthenticatedUser, user_limit: int, admin_limit: int) -> int:
    return admin_limit if user.is_admin else user_limit
