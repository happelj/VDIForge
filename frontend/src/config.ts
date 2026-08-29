import type { VDIForgeRuntimeConfig } from "./env";

const DEFAULT_POLL_INTERVAL_MS = 5000;

function withoutTrailingSlash(value: string): string {
  return value.replace(/\/+$/, "");
}

function numberFrom(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function getRuntimeConfig(): VDIForgeRuntimeConfig {
  const runtime = window.__VDIFORGE_CONFIG__ ?? {};
  const env = import.meta.env;

  return {
    apiBaseUrl: withoutTrailingSlash(
      runtime.apiBaseUrl ?? env.VITE_VDIFORGE_API_BASE_URL ?? "https://api.vdiforge.local",
    ),
    oidcAuthority: withoutTrailingSlash(
      runtime.oidcAuthority ??
        env.VITE_VDIFORGE_OIDC_AUTHORITY ??
        "https://auth.vdiforge.local/realms/vdiforge",
    ),
    oidcClientId: runtime.oidcClientId ?? env.VITE_VDIFORGE_OIDC_CLIENT_ID ?? "vdiforge-frontend",
    oidcRedirectUri:
      runtime.oidcRedirectUri ?? env.VITE_VDIFORGE_OIDC_REDIRECT_URI ?? "https://vdiforge.local/oidc/callback",
    oidcPostLogoutRedirectUri:
      runtime.oidcPostLogoutRedirectUri ??
      env.VITE_VDIFORGE_OIDC_POST_LOGOUT_REDIRECT_URI ??
      "https://vdiforge.local/",
    sessionPollIntervalMs: numberFrom(
      runtime.sessionPollIntervalMs ?? env.VITE_VDIFORGE_SESSION_POLL_INTERVAL_MS,
      DEFAULT_POLL_INTERVAL_MS,
    ),
  };
}
