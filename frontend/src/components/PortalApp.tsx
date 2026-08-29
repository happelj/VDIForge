import {
  AlertCircle,
  Boxes,
  CheckCircle2,
  Clock3,
  ExternalLink,
  Images,
  LayoutDashboard,
  LoaderCircle,
  LogOut,
  Monitor,
  Play,
  Power,
  RefreshCw,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";

import { ApiError, type VDIForgeApi } from "../api/client";
import type { Desktop, DesktopCreateRequest, DesktopObservedState, Image, PortalUser } from "../types";
import { isConnectable, isTransitional, stateLabel, stateTone } from "../utils/status";

type View = "dashboard" | "images" | "desktops";

type PortalAppProps = {
  api: VDIForgeApi;
  onLogout: () => Promise<void> | void;
  openExternal?: (url: string) => void;
  pollIntervalMs?: number;
  user: PortalUser;
};

type LoadState = {
  desktops: Desktop[];
  images: Image[];
};

type Notice = {
  title: string;
  detail?: string;
  type: "success" | "error";
};

const EMPTY_STATE: LoadState = {
  desktops: [],
  images: [],
};

const RESOURCE_PROFILES = [
  { id: "small", label: "Small", detail: "1 vCPU / 2 GiB RAM" },
  { id: "standard", label: "Standard", detail: "2 vCPU / 4 GiB RAM" },
];

function createIdempotencyKey(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `launch-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function friendlyError(error: unknown): Notice {
  if (error instanceof ApiError) {
    const messages: Record<string, string> = {
      DESKTOP_ACCESS_DENIED: "You are not authorized to access that desktop.",
      DESKTOP_NOT_FOUND: "That desktop could not be found.",
      DESKTOP_NOT_OWNED: "You can only manage your own desktops.",
      DESKTOP_NOT_READY: "The desktop is not ready for connection yet.",
      DESKTOP_QUOTA_EXCEEDED: "You already have the maximum number of active desktops.",
      QUOTA_EXCEEDED: "You already have the maximum number of active desktops.",
      IMAGE_NOT_AUTHORIZED: "That image is not available to your account.",
      IMAGE_VERSION_NOT_FOUND: "The selected image version was not found.",
      INSUFFICIENT_CAPACITY: "The VDI cluster does not currently have enough resources to create this desktop.",
      INVALID_RESOURCE_PROFILE: "The selected resource profile is not supported.",
      INVALID_STATE_TRANSITION: "That action is not valid for the current desktop state.",
      PROVISIONING_FAILED: "The desktop could not be provisioned.",
    };
    return {
      title: messages[error.code] ?? error.message,
      detail: error.requestId ? `Request ID ${error.requestId}` : error.code,
      type: "error",
    };
  }
  return {
    title: error instanceof Error ? error.message : "Request failed.",
    type: "error",
  };
}

function ImageName({ id, images }: { id: string; images: Image[] }) {
  const image = images.find((item) => item.id === id);
  return <>{image?.display_name ?? id}</>;
}

function StatusBadge({ state }: { state: DesktopObservedState }) {
  return <span className={`status-badge status-badge--${stateTone(state)}`}>{stateLabel(state)}</span>;
}

function IconButton({
  children,
  disabled,
  icon,
  label,
  onClick,
}: {
  children: string;
  disabled?: boolean;
  icon: ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className="button button--secondary button--compact"
      disabled={disabled}
      onClick={onClick}
      title={label}
      type="button"
    >
      {icon}
      <span>{children}</span>
    </button>
  );
}

export function PortalApp({
  api,
  onLogout,
  openExternal = (url) => window.open(url, "_blank", "noopener,noreferrer"),
  pollIntervalMs = 5000,
  user,
}: PortalAppProps) {
  const [view, setView] = useState<View>("dashboard");
  const [state, setState] = useState<LoadState>(EMPTY_STATE);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [selectedImage, setSelectedImage] = useState<Image | null>(null);
  const [pendingAction, setPendingAction] = useState<string | null>(null);

  const refresh = useCallback(
    async (quiet = false) => {
      if (quiet) {
        setIsRefreshing(true);
      } else {
        setIsLoading(true);
      }
      try {
        const [images, desktops] = await Promise.all([api.listImages(), api.listDesktops()]);
        setState({ images, desktops });
        if (!quiet) {
          setNotice(null);
        }
      } catch (error) {
        setNotice(friendlyError(error));
      } finally {
        setIsLoading(false);
        setIsRefreshing(false);
      }
    },
    [api],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const hasTransitionalDesktop = state.desktops.some((desktop) => isTransitional(desktop.observed_state));
  useEffect(() => {
    if (!hasTransitionalDesktop) {
      return undefined;
    }
    const interval = window.setInterval(() => {
      void refresh(true);
    }, pollIntervalMs);
    return () => window.clearInterval(interval);
  }, [hasTransitionalDesktop, pollIntervalMs, refresh]);

  const stats = useMemo(() => {
    const active = state.desktops.filter((desktop) => desktop.observed_state !== "TERMINATED").length;
    const provisioning = state.desktops.filter((desktop) =>
      ["REQUESTED", "PROVISIONING", "BOOTING"].includes(desktop.observed_state),
    ).length;
    const ready = state.desktops.filter((desktop) => isConnectable(desktop.observed_state)).length;
    const failed = state.desktops.filter((desktop) => desktop.observed_state === "FAILED").length;
    return { active, failed, provisioning, ready };
  }, [state.desktops]);

  const runAction = useCallback(
    async (key: string, action: () => Promise<unknown>, success: string) => {
      setPendingAction(key);
      try {
        await action();
        await refresh(true);
        setNotice({ title: success, type: "success" });
      } catch (error) {
        setNotice(friendlyError(error));
      } finally {
        setPendingAction(null);
      }
    },
    [refresh],
  );

  const launchDesktop = useCallback(
    async (request: DesktopCreateRequest) => {
      await runAction(
        "launch",
        () => api.launchDesktop(request, createIdempotencyKey()),
        "Desktop launch accepted.",
      );
      setSelectedImage(null);
      setView("desktops");
    },
    [api, runAction],
  );

  const connectDesktop = useCallback(
    async (desktop: Desktop) => {
      await runAction(
        `connect-${desktop.id}`,
        async () => {
          const connection = await api.connectDesktop(desktop.id);
          openExternal(connection.connection_url);
        },
        "Remote connection opened.",
      );
    },
    [api, openExternal, runAction],
  );

  const nav = [
    { id: "dashboard" as const, icon: LayoutDashboard, label: "Dashboard" },
    { id: "images" as const, icon: Images, label: "Images" },
    { id: "desktops" as const, icon: Monitor, label: "My Desktops" },
  ];

  return (
    <div className="portal-shell">
      <aside className="sidebar" aria-label="Primary">
        <div className="brand">
          <span className="brand__mark">V</span>
          <div>
            <p className="brand__name">VDIForge</p>
            <p className="brand__scope">Self-service VDI</p>
          </div>
        </div>
        <nav className="nav">
          {nav.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.id}
                aria-current={view === item.id ? "page" : undefined}
                className="nav__item"
                onClick={() => setView(item.id)}
                type="button"
              >
                <Icon aria-hidden="true" size={18} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="sidebar__footer">
          <div className="identity" title={user.roles.join(", ") || "No VDI roles"}>
            <ShieldCheck aria-hidden="true" size={18} />
            <div>
              <p>{user.username}</p>
              <span>{user.roles.filter((role) => role.startsWith("vdi-")).join(", ") || "no VDI role"}</span>
            </div>
          </div>
          <button className="button button--ghost" onClick={() => void onLogout()} type="button">
            <LogOut aria-hidden="true" size={17} />
            <span>Logout</span>
          </button>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <h1>
              {view === "dashboard" && "Dashboard"}
              {view === "images" && "Image Catalog"}
              {view === "desktops" && "My Desktops"}
            </h1>
            <p className="topbar__meta">
              {state.images.length} authorized image{state.images.length === 1 ? "" : "s"} / {state.desktops.length}{" "}
              desktop{state.desktops.length === 1 ? "" : "s"}
            </p>
          </div>
          <button className="button button--secondary" disabled={isRefreshing} onClick={() => void refresh(true)}>
            <RefreshCw aria-hidden="true" className={isRefreshing ? "spin" : undefined} size={18} />
            <span>Refresh</span>
          </button>
        </header>

        {notice && (
          <div className={`notice notice--${notice.type}`} role={notice.type === "error" ? "alert" : "status"}>
            {notice.type === "error" ? (
              <AlertCircle aria-hidden="true" size={18} />
            ) : (
              <CheckCircle2 aria-hidden="true" size={18} />
            )}
            <div>
              <p>{notice.title}</p>
              {notice.detail && <span>{notice.detail}</span>}
            </div>
            <button aria-label="Dismiss message" onClick={() => setNotice(null)} type="button">
              x
            </button>
          </div>
        )}

        {isLoading ? (
          <section className="loading-state" aria-live="polite">
            <LoaderCircle aria-hidden="true" className="spin" size={28} />
            <span>Loading VDIForge data</span>
          </section>
        ) : (
          <>
            {view === "dashboard" && (
              <DashboardView
                images={state.images}
                onLaunch={setSelectedImage}
                onViewDesktops={() => setView("desktops")}
                stats={stats}
              />
            )}
            {view === "images" && <ImagesView images={state.images} onLaunch={setSelectedImage} />}
            {view === "desktops" && (
              <DesktopsView
                desktops={state.desktops}
                images={state.images}
                onConnect={connectDesktop}
                onDelete={(desktop) =>
                  void runAction(
                    `delete-${desktop.id}`,
                    () => api.deleteDesktop(desktop.id),
                    "Desktop deletion requested.",
                  )
                }
                onStart={(desktop) =>
                  void runAction(`start-${desktop.id}`, () => api.startDesktop(desktop.id), "Desktop start requested.")
                }
                onStop={(desktop) =>
                  void runAction(`stop-${desktop.id}`, () => api.stopDesktop(desktop.id), "Desktop stop requested.")
                }
                pendingAction={pendingAction}
              />
            )}
          </>
        )}
      </main>

      {selectedImage && (
        <LaunchDesktopDialog
          image={selectedImage}
          isSubmitting={pendingAction === "launch"}
          onCancel={() => setSelectedImage(null)}
          onLaunch={launchDesktop}
        />
      )}
    </div>
  );
}

function DashboardView({
  images,
  onLaunch,
  onViewDesktops,
  stats,
}: {
  images: Image[];
  onLaunch: (image: Image) => void;
  onViewDesktops: () => void;
  stats: { active: number; failed: number; provisioning: number; ready: number };
}) {
  const primaryImage = images[0];

  return (
    <section className="content-stack">
      <div className="stat-grid" aria-label="Desktop summary">
        <StatCard icon={<Monitor size={20} />} label="Active" value={stats.active} />
        <StatCard icon={<Clock3 size={20} />} label="Provisioning" value={stats.provisioning} />
        <StatCard icon={<CheckCircle2 size={20} />} label="Ready" value={stats.ready} />
        <StatCard icon={<AlertCircle size={20} />} label="Failed" tone="danger" value={stats.failed} />
      </div>

      <section className="panel">
        <div className="panel__header">
          <div>
            <h2>Authorized Images</h2>
            <p>{images.length} available from the backend catalog</p>
          </div>
          {primaryImage && (
            <button className="button button--primary" onClick={() => onLaunch(primaryImage)} type="button">
              <Play aria-hidden="true" size={18} />
              <span>Launch</span>
            </button>
          )}
        </div>
        {images.length === 0 ? (
          <EmptyState title="No launchable images" />
        ) : (
          <div className="image-strip">
            {images.slice(0, 3).map((image) => (
              <ImageCard image={image} key={image.id} onLaunch={onLaunch} />
            ))}
          </div>
        )}
      </section>

      <section className="panel panel--compact">
        <div className="panel__header">
          <div>
            <h2>Desktop Lifecycle</h2>
            <p>Current desktops refresh while they are changing state</p>
          </div>
          <button className="button button--secondary" onClick={onViewDesktops} type="button">
            <Monitor aria-hidden="true" size={18} />
            <span>Open</span>
          </button>
        </div>
      </section>
    </section>
  );
}

function StatCard({
  icon,
  label,
  tone = "default",
  value,
}: {
  icon: ReactNode;
  label: string;
  tone?: "default" | "danger";
  value: number;
}) {
  return (
    <div className={`stat-card stat-card--${tone}`}>
      <div className="stat-card__icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
      </div>
    </div>
  );
}

function ImagesView({ images, onLaunch }: { images: Image[]; onLaunch: (image: Image) => void }) {
  return (
    <section className="content-stack">
      {images.length === 0 ? (
        <EmptyState title="No authorized images returned" />
      ) : (
        <div className="image-grid">
          {images.map((image) => (
            <ImageCard image={image} key={image.id} onLaunch={onLaunch} />
          ))}
        </div>
      )}
    </section>
  );
}

function ImageCard({ image, onLaunch }: { image: Image; onLaunch: (image: Image) => void }) {
  const hasVersion = image.versions.length > 0;

  return (
    <article className="image-card">
      <div className="image-card__icon">
        <Boxes aria-hidden="true" size={22} />
      </div>
      <div className="image-card__body">
        <h3>{image.display_name}</h3>
        <p>{image.description}</p>
        <dl>
          <div>
            <dt>Default</dt>
            <dd>{image.default_version}</dd>
          </div>
          <div>
            <dt>Release</dt>
            <dd>{image.versions[0]?.ubuntu_release ?? "unavailable"}</dd>
          </div>
          <div>
            <dt>Access</dt>
            <dd>{image.allowed_roles.join(", ")}</dd>
          </div>
        </dl>
      </div>
      <button
        aria-label={`Launch ${image.display_name}`}
        className="button button--primary"
        disabled={!hasVersion}
        onClick={() => onLaunch(image)}
        type="button"
      >
        <Play aria-hidden="true" size={18} />
        <span>{hasVersion ? "Launch" : "Unavailable"}</span>
      </button>
    </article>
  );
}

function DesktopsView({
  desktops,
  images,
  onConnect,
  onDelete,
  onStart,
  onStop,
  pendingAction,
}: {
  desktops: Desktop[];
  images: Image[];
  onConnect: (desktop: Desktop) => void;
  onDelete: (desktop: Desktop) => void;
  onStart: (desktop: Desktop) => void;
  onStop: (desktop: Desktop) => void;
  pendingAction: string | null;
}) {
  if (desktops.length === 0) {
    return <EmptyState title="No desktops" />;
  }

  return (
    <section className="desktop-table" aria-label="My desktops">
      <div className="desktop-table__head">
        <span>Name</span>
        <span>Image</span>
        <span>State</span>
        <span>Profile</span>
        <span>Created</span>
        <span>Actions</span>
      </div>
      {desktops.map((desktop) => {
        const disabled = pendingAction?.endsWith(desktop.id);
        const canStop = ["READY", "CONNECTED", "BOOTING"].includes(desktop.observed_state);
        const canStart = desktop.observed_state === "STOPPED";
        const canDelete = !["TERMINATED", "TERMINATING"].includes(desktop.observed_state);
        return (
          <article className="desktop-row" key={desktop.id}>
            <div>
              <strong>{desktop.display_name}</strong>
              <span>{desktop.kubevirt_vm_name}</span>
            </div>
            <div>
              <ImageName id={desktop.image_id} images={images} />
              <span>{desktop.image_version}</span>
            </div>
            <div>
              <StatusBadge state={desktop.observed_state} />
              {desktop.failure_message && <span className="error-text">{desktop.failure_message}</span>}
            </div>
            <div>{desktop.resource_profile}</div>
            <div>{formatDate(desktop.created_at)}</div>
            <div className="desktop-actions">
              <IconButton
                disabled={!isConnectable(desktop.observed_state) || disabled}
                icon={<ExternalLink aria-hidden="true" size={16} />}
                label={`Connect to ${desktop.display_name}`}
                onClick={() => onConnect(desktop)}
              >
                Connect
              </IconButton>
              {canStart ? (
                <IconButton
                  disabled={disabled}
                  icon={<Play aria-hidden="true" size={16} />}
                  label={`Start ${desktop.display_name}`}
                  onClick={() => onStart(desktop)}
                >
                  Start
                </IconButton>
              ) : (
                <IconButton
                  disabled={!canStop || disabled}
                  icon={<Power aria-hidden="true" size={16} />}
                  label={`Stop ${desktop.display_name}`}
                  onClick={() => onStop(desktop)}
                >
                  Stop
                </IconButton>
              )}
              <IconButton
                disabled={!canDelete || disabled}
                icon={<Trash2 aria-hidden="true" size={16} />}
                label={`Delete ${desktop.display_name}`}
                onClick={() => {
                  if (window.confirm(`Delete ${desktop.display_name}?`)) {
                    onDelete(desktop);
                  }
                }}
              >
                Delete
              </IconButton>
            </div>
          </article>
        );
      })}
    </section>
  );
}

function LaunchDesktopDialog({
  image,
  isSubmitting,
  onCancel,
  onLaunch,
}: {
  image: Image;
  isSubmitting: boolean;
  onCancel: () => void;
  onLaunch: (request: DesktopCreateRequest) => Promise<void>;
}) {
  const [displayName, setDisplayName] = useState(image.display_name);
  const [profile, setProfile] = useState("small");
  const [version, setVersion] = useState(image.default_version);

  return (
    <div className="modal-backdrop">
      <section aria-labelledby="launch-title" aria-modal="true" className="modal" role="dialog">
        <header className="modal__header">
          <h2 id="launch-title">Launch {image.display_name}</h2>
          <button aria-label="Close launch dialog" onClick={onCancel} type="button">
            x
          </button>
        </header>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void onLaunch({
              display_name: displayName.trim() || image.display_name,
              image_id: image.id,
              image_version: version,
              resource_profile: profile,
            });
          }}
        >
          <label className="field">
            <span>Desktop name</span>
            <input maxLength={128} onChange={(event) => setDisplayName(event.target.value)} value={displayName} />
          </label>

          <label className="field">
            <span>Image version</span>
            <select onChange={(event) => setVersion(event.target.value)} value={version}>
              {image.versions.map((item) => (
                <option key={item.version} value={item.version}>
                  {item.version} / {item.ubuntu_release}
                </option>
              ))}
            </select>
          </label>

          <fieldset className="profile-options">
            <legend>Resource profile</legend>
            {RESOURCE_PROFILES.map((item) => (
              <label className="profile-option" key={item.id}>
                <input
                  checked={profile === item.id}
                  name="resource-profile"
                  onChange={() => setProfile(item.id)}
                  type="radio"
                  value={item.id}
                />
                <span>
                  <strong>{item.label}</strong>
                  <small>{item.detail}</small>
                </span>
              </label>
            ))}
          </fieldset>

          <footer className="modal__actions">
            <button className="button button--secondary" disabled={isSubmitting} onClick={onCancel} type="button">
              Cancel
            </button>
            <button className="button button--primary" disabled={isSubmitting} type="submit">
              {isSubmitting ? (
                <LoaderCircle aria-hidden="true" className="spin" size={18} />
              ) : (
                <Play aria-hidden="true" size={18} />
              )}
              <span>Launch Desktop</span>
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}

function EmptyState({ title }: { title: string }) {
  return (
    <div className="empty-state">
      <Monitor aria-hidden="true" size={26} />
      <span>{title}</span>
    </div>
  );
}
