import { User, UserManager, WebStorageStateStore } from "oidc-client-ts";

import type { VDIForgeRuntimeConfig } from "../env";

type RoleClaims = {
  roles?: unknown;
  realm_access?: {
    roles?: unknown;
  };
  resource_access?: Record<string, { roles?: unknown }>;
  preferred_username?: unknown;
  name?: unknown;
};

export function createUserManager(config: VDIForgeRuntimeConfig): UserManager {
  return new UserManager({
    authority: config.oidcAuthority,
    client_id: config.oidcClientId,
    redirect_uri: config.oidcRedirectUri,
    post_logout_redirect_uri: config.oidcPostLogoutRedirectUri,
    response_type: "code",
    scope: "openid profile email",
    automaticSilentRenew: true,
    monitorSession: true,
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),
  });
}

function toRoleList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((role): role is string => typeof role === "string") : [];
}

export function rolesFromUser(user: User | null, clientId: string): string[] {
  if (!user) {
    return [];
  }

  const claims = user.profile as RoleClaims;
  return Array.from(
    new Set([
      ...toRoleList(claims.roles),
      ...toRoleList(claims.realm_access?.roles),
      ...toRoleList(claims.resource_access?.[clientId]?.roles),
    ]),
  ).sort();
}

export function usernameFromUser(user: User | null): string {
  if (!user) {
    return "unknown";
  }

  const claims = user.profile as RoleClaims;
  if (typeof claims.preferred_username === "string") {
    return claims.preferred_username;
  }
  if (typeof claims.name === "string") {
    return claims.name;
  }
  return user.profile.sub ?? "unknown";
}
