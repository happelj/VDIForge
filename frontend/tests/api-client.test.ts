import { afterEach, describe, expect, it, vi } from "vitest";

import { createVDIForgeApiClient } from "../src/api/client";

describe("VDIForge API client", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("attaches bearer tokens and idempotency keys to launch requests", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
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
          observed_state: "REQUESTED",
          owner_username: "demo-devops",
          resource_profile: "small",
          updated_at: "2026-08-29T00:00:00Z",
        }),
        { headers: { "Content-Type": "application/json" }, status: 202 },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const client = createVDIForgeApiClient({
      baseUrl: "https://api.vdiforge.local",
      getAccessToken: async () => "token-value",
    });

    await client.launchDesktop(
      { image_id: "ubuntu-devops", image_version: "1.2.0", resource_profile: "small" },
      "launch-key",
    );

    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.vdiforge.local/api/v1/desktops",
      expect.objectContaining({
        body: JSON.stringify({ image_id: "ubuntu-devops", image_version: "1.2.0", resource_profile: "small" }),
        method: "POST",
      }),
    );
    const headers = fetchMock.mock.calls[0][1]?.headers as Headers;
    expect(headers.get("Authorization")).toBe("Bearer token-value");
    expect(headers.get("Idempotency-Key")).toBe("launch-key");
  });

  it("maps structured backend errors without exposing token contents", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            error: {
              code: "DESKTOP_ACCESS_DENIED",
              message: "You are not authorized to access this desktop.",
              request_id: "req-123",
            },
          }),
          { headers: { "Content-Type": "application/json" }, status: 403 },
        ),
      ),
    );

    const client = createVDIForgeApiClient({
      baseUrl: "https://api.vdiforge.local",
      getAccessToken: async () => "secret-token-value",
    });

    await expect(client.connectDesktop("desktop-1")).rejects.toMatchObject({
      code: "DESKTOP_ACCESS_DENIED",
      message: "You are not authorized to access this desktop.",
      requestId: "req-123",
      status: 403,
    });
  });
});
