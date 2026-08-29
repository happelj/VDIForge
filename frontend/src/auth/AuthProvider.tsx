import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { PropsWithChildren } from "react";
import type { User, UserManager } from "oidc-client-ts";

import { getRuntimeConfig } from "../config";
import { createUserManager, rolesFromUser, usernameFromUser } from "./oidc";

type AuthContextValue = {
  error: string | null;
  isAuthenticated: boolean;
  isReady: boolean;
  roles: string[];
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
  getAccessToken: () => Promise<string | null>;
  username: string;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Authentication failed.";
}

export function AuthProvider({ children }: PropsWithChildren) {
  const config = useMemo(() => getRuntimeConfig(), []);
  const [manager] = useState<UserManager>(() => createUserManager(config));
  const [user, setUser] = useState<User | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function loadSession() {
      try {
        const isCallback = window.location.pathname === new URL(config.oidcRedirectUri).pathname;
        if (isCallback && window.location.search.includes("code=")) {
          const callbackUser = await manager.signinRedirectCallback();
          if (!cancelled) {
            setUser(callbackUser);
          }
          window.history.replaceState({}, document.title, "/");
        } else {
          const currentUser = await manager.getUser();
          if (!cancelled) {
            setUser(currentUser && !currentUser.expired ? currentUser : null);
          }
        }
      } catch (sessionError) {
        if (!cancelled) {
          setError(safeErrorMessage(sessionError));
          setUser(null);
        }
      } finally {
        if (!cancelled) {
          setIsReady(true);
        }
      }
    }

    void loadSession();
    return () => {
      cancelled = true;
    };
  }, [config.oidcRedirectUri, manager]);

  useEffect(() => {
    const onUserLoaded = (loadedUser: User) => setUser(loadedUser);
    const onUserUnloaded = () => setUser(null);
    const onTokenExpired = () => setUser(null);

    manager.events.addUserLoaded(onUserLoaded);
    manager.events.addUserUnloaded(onUserUnloaded);
    manager.events.addAccessTokenExpired(onTokenExpired);

    return () => {
      manager.events.removeUserLoaded(onUserLoaded);
      manager.events.removeUserUnloaded(onUserUnloaded);
      manager.events.removeAccessTokenExpired(onTokenExpired);
    };
  }, [manager]);

  const signIn = useCallback(async () => {
    await manager.signinRedirect();
  }, [manager]);

  const signOut = useCallback(async () => {
    await manager.signoutRedirect();
  }, [manager]);

  const getAccessToken = useCallback(async () => {
    const currentUser = user && !user.expired ? user : await manager.getUser();
    return currentUser && !currentUser.expired ? currentUser.access_token : null;
  }, [manager, user]);

  const value = useMemo<AuthContextValue>(
    () => ({
      error,
      isAuthenticated: Boolean(user && !user.expired),
      isReady,
      roles: rolesFromUser(user, config.oidcClientId),
      signIn,
      signOut,
      getAccessToken,
      username: usernameFromUser(user),
    }),
    [config.oidcClientId, error, getAccessToken, isReady, signIn, signOut, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) {
    throw new Error("useAuth must be used inside AuthProvider");
  }
  return value;
}
