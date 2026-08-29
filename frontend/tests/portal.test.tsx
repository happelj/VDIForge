import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError, type VDIForgeApi } from "../src/api/client";
import { PortalApp } from "../src/components/PortalApp";
import type { Desktop, Image } from "../src/types";

const images: Image[] = [
  {
    allowed_roles: ["vdi-devops", "vdi-admin"],
    default_version: "1.2.0",
    description: "Ubuntu desktop with platform tooling.",
    display_name: "Ubuntu DevOps",
    id: "ubuntu-devops",
    versions: [
      {
        architecture: "amd64",
        artifact_format: "qcow2",
        lifecycle: "available",
        ubuntu_release: "26.04 LTS",
        version: "1.2.0",
      },
    ],
  },
];

const readyDesktop: Desktop = {
  created_at: "2026-08-29T00:00:00Z",
  desired_state: "RUNNING",
  display_name: "Ubuntu DevOps",
  failure_code: null,
  failure_message: null,
  id: "desktop-1",
  image_id: "ubuntu-devops",
  image_version: "1.2.0",
  kubevirt_data_volume_name: "desktop-1-root",
  kubevirt_service_name: "desktop-1",
  kubevirt_vm_name: "desktop-1",
  observed_state: "READY",
  owner_username: "demo-devops",
  resource_profile: "small",
  updated_at: "2026-08-29T00:05:00Z",
};

function createApi(overrides: Partial<VDIForgeApi> = {}): VDIForgeApi {
  return {
    connectDesktop: vi.fn().mockResolvedValue({
      connection_url: "https://remote.vdiforge.local/?data=exact-token",
      desktop_id: "desktop-1",
      expires_at: "2026-08-29T00:10:00Z",
      protocol: "rdp",
    }),
    deleteDesktop: vi.fn().mockResolvedValue({ ...readyDesktop, observed_state: "TERMINATING" }),
    launchDesktop: vi.fn().mockResolvedValue(readyDesktop),
    listDesktops: vi.fn().mockResolvedValue([readyDesktop]),
    listImages: vi.fn().mockResolvedValue(images),
    startDesktop: vi.fn().mockResolvedValue(readyDesktop),
    stopDesktop: vi.fn().mockResolvedValue({ ...readyDesktop, observed_state: "STOPPING" }),
    ...overrides,
  };
}

function renderPortal(api = createApi(), openExternal = vi.fn()) {
  render(
    <PortalApp
      api={api}
      onLogout={vi.fn()}
      openExternal={openExternal}
      user={{ roles: ["vdi-devops"], username: "demo-devops" }}
    />,
  );
  return { api, openExternal };
}

describe("VDIForge portal", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders authorized images and owned desktops from the API", async () => {
    const user = userEvent.setup();
    renderPortal();

    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
    expect(screen.getByText("Ubuntu DevOps")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "My Desktops" }));
    expect(screen.getByText("desktop-1")).toBeInTheDocument();
  });

  it("submits launches with an idempotency key and selected resource profile", async () => {
    const user = userEvent.setup();
    const api = createApi({ listDesktops: vi.fn().mockResolvedValue([]) });
    renderPortal(api);

    await user.click(await screen.findByRole("button", { name: "Launch Ubuntu DevOps" }));
    await user.clear(screen.getByLabelText("Desktop name"));
    await user.type(screen.getByLabelText("Desktop name"), "Interview desktop");
    await user.click(screen.getByLabelText(/Standard/));
    await user.click(screen.getByRole("button", { name: "Launch Desktop" }));

    await waitFor(() => expect(api.launchDesktop).toHaveBeenCalledTimes(1));
    expect(api.launchDesktop).toHaveBeenCalledWith(
      {
        display_name: "Interview desktop",
        image_id: "ubuntu-devops",
        image_version: "1.2.0",
        resource_profile: "standard",
      },
      expect.stringMatching(/[a-z0-9-]+/),
    );
  });

  it("opens the Guacamole URL returned by the API without rewriting it", async () => {
    const user = userEvent.setup();
    const openExternal = vi.fn();
    const { api } = renderPortal(undefined, openExternal);

    await user.click(await screen.findByRole("button", { name: "My Desktops" }));
    await user.click(screen.getByRole("button", { name: "Connect" }));

    await waitFor(() => expect(api.connectDesktop).toHaveBeenCalledWith("desktop-1"));
    expect(openExternal).toHaveBeenCalledWith("https://remote.vdiforge.local/?data=exact-token");
  });

  it("shows loading and empty states without inventing data", async () => {
    const api = createApi({
      listDesktops: vi.fn().mockResolvedValue([]),
      listImages: vi.fn().mockResolvedValue([]),
    });
    renderPortal(api);

    expect(screen.getByText("Loading VDIForge data")).toBeInTheDocument();
    expect(await screen.findByText("No launchable images")).toBeInTheDocument();
  });

  it("maps API errors to safe user-facing messages with request IDs", async () => {
    const api = createApi({
      listDesktops: vi.fn().mockResolvedValue([]),
      listImages: vi.fn().mockRejectedValue(
        new ApiError(
          409,
          "DESKTOP_QUOTA_EXCEEDED",
          "backend detail",
          "req-phase9",
        ),
      ),
    });
    renderPortal(api);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "You already have the maximum number of active desktops.",
    );
    expect(screen.getByText("Request ID req-phase9")).toBeInTheDocument();
  });

  it("keeps Connect disabled until the backend reports READY", async () => {
    const api = createApi({
      listDesktops: vi.fn().mockResolvedValue([{ ...readyDesktop, observed_state: "BOOTING" }]),
    });
    const user = userEvent.setup();
    renderPortal(api);

    await user.click(await screen.findByRole("button", { name: "My Desktops" }));

    expect(screen.getByText("Starting Ubuntu")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Connect" })).toBeDisabled();
  });

  it("calls the supplied logout handler", async () => {
    const user = userEvent.setup();
    const onLogout = vi.fn();
    render(
      <PortalApp
        api={createApi()}
        onLogout={onLogout}
        openExternal={vi.fn()}
        user={{ roles: ["vdi-devops"], username: "demo-devops" }}
      />,
    );

    await user.click(screen.getByRole("button", { name: "Logout" }));
    expect(onLogout).toHaveBeenCalledOnce();
  });

  it("supports stop, start, and delete actions for visible desktops", async () => {
    const user = userEvent.setup();
    const stoppedDesktop = {
      ...readyDesktop,
      id: "desktop-2",
      kubevirt_data_volume_name: "desktop-2-root",
      kubevirt_service_name: "desktop-2",
      kubevirt_vm_name: "desktop-2",
      observed_state: "STOPPED" as const,
    };
    const api = createApi({
      listDesktops: vi.fn().mockResolvedValue([readyDesktop, stoppedDesktop]),
    });
    vi.spyOn(window, "confirm").mockReturnValue(true);
    renderPortal(api);

    await user.click(await screen.findByRole("button", { name: "My Desktops" }));
    await user.click(screen.getAllByRole("button", { name: "Stop" })[0]);
    await waitFor(() => expect(api.stopDesktop).toHaveBeenCalledWith("desktop-1"));

    await user.click(screen.getAllByRole("button", { name: "Start" })[0]);
    await waitFor(() => expect(api.startDesktop).toHaveBeenCalledWith("desktop-2"));

    await user.click(screen.getAllByRole("button", { name: "Delete" })[0]);
    await waitFor(() => expect(api.deleteDesktop).toHaveBeenCalledWith("desktop-1"));
  });
});
