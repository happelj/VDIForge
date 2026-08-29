/// <reference types="vite/client" />

export type VDIForgeRuntimeConfig = {
  apiBaseUrl: string;
  oidcAuthority: string;
  oidcClientId: string;
  oidcRedirectUri: string;
  oidcPostLogoutRedirectUri: string;
  sessionPollIntervalMs: number;
};

declare global {
  interface Window {
    __VDIFORGE_CONFIG__?: Partial<VDIForgeRuntimeConfig>;
  }
}
