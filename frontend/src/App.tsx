import { LoaderCircle, LogIn, TriangleAlert } from "lucide-react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { useMemo } from "react";

import { createVDIForgeApiClient } from "./api/client";
import { AuthProvider, useAuth } from "./auth/AuthProvider";
import { getRuntimeConfig } from "./config";
import { PortalApp } from "./components/PortalApp";

function AuthenticatedApp() {
  const auth = useAuth();
  const config = useMemo(() => getRuntimeConfig(), []);
  const api = useMemo(
    () =>
      createVDIForgeApiClient({
        baseUrl: config.apiBaseUrl,
        getAccessToken: auth.getAccessToken,
      }),
    [auth.getAccessToken, config.apiBaseUrl],
  );

  if (!auth.isReady) {
    return (
      <main className="auth-screen">
        <LoaderCircle aria-hidden="true" className="spin" size={30} />
        <span>Loading session</span>
      </main>
    );
  }

  if (auth.error) {
    return (
      <main className="auth-screen auth-screen--error">
        <TriangleAlert aria-hidden="true" size={30} />
        <h1>Authentication Error</h1>
        <p>{auth.error}</p>
        <button className="button button--primary" onClick={() => void auth.signIn()} type="button">
          <LogIn aria-hidden="true" size={18} />
          <span>Sign in</span>
        </button>
      </main>
    );
  }

  if (!auth.isAuthenticated) {
    return (
      <main className="auth-screen">
        <div className="auth-card">
          <span className="brand__mark">V</span>
          <h1>VDIForge</h1>
          <p>Self-service Ubuntu desktops</p>
          <button className="button button--primary" onClick={() => void auth.signIn()} type="button">
            <LogIn aria-hidden="true" size={18} />
            <span>Sign in</span>
          </button>
        </div>
      </main>
    );
  }

  return (
    <PortalApp
      api={api}
      onLogout={auth.signOut}
      pollIntervalMs={config.sessionPollIntervalMs}
      user={{ roles: auth.roles, username: auth.username }}
    />
  );
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<AuthenticatedApp />} path="*" />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
