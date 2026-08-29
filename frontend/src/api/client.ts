import type {
  ApiErrorResponse,
  Desktop,
  DesktopConnectionResponse,
  DesktopCreateRequest,
  DesktopListResponse,
  Image,
} from "../types";

export class ApiError extends Error {
  readonly code: string;
  readonly requestId?: string;
  readonly status: number;

  constructor(status: number, code: string, message: string, requestId?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }
}

export type VDIForgeApi = {
  listImages(): Promise<Image[]>;
  listDesktops(): Promise<Desktop[]>;
  launchDesktop(request: DesktopCreateRequest, idempotencyKey: string): Promise<Desktop>;
  connectDesktop(id: string): Promise<DesktopConnectionResponse>;
  startDesktop(id: string): Promise<Desktop>;
  stopDesktop(id: string): Promise<Desktop>;
  deleteDesktop(id: string): Promise<Desktop>;
};

type ApiClientOptions = {
  baseUrl: string;
  getAccessToken: () => Promise<string | null>;
};

async function parseError(response: Response): Promise<ApiError> {
  const payload = await response.json().catch(() => ({} as ApiErrorResponse));

  const requestId = payload.error?.request_id ?? response.headers.get("x-request-id") ?? undefined;
  const code = payload.error?.code ?? `HTTP_${response.status}`;
  const message = payload.error?.message ?? response.statusText ?? "Request failed.";
  return new ApiError(response.status, code, message, requestId);
}

export function createVDIForgeApiClient(options: ApiClientOptions): VDIForgeApi {
  const request = async <T>(path: string, init: RequestInit = {}): Promise<T> => {
    const token = await options.getAccessToken();
    const headers = new Headers(init.headers);
    headers.set("Accept", "application/json");
    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }
    if (init.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }

    const response = await fetch(`${options.baseUrl}${path}`, {
      ...init,
      headers,
    });

    if (!response.ok) {
      throw await parseError(response);
    }

    if (response.status === 204) {
      return undefined as T;
    }

    return (await response.json()) as T;
  };

  return {
    async listImages() {
      return request<Image[]>("/api/v1/images");
    },
    async listDesktops() {
      const response = await request<DesktopListResponse>("/api/v1/desktops");
      return response.desktops;
    },
    async launchDesktop(body, idempotencyKey) {
      return request<Desktop>("/api/v1/desktops", {
        method: "POST",
        headers: {
          "Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(body),
      });
    },
    async connectDesktop(id) {
      return request<DesktopConnectionResponse>(`/api/v1/desktops/${encodeURIComponent(id)}/connect`, {
        method: "POST",
      });
    },
    async startDesktop(id) {
      return request<Desktop>(`/api/v1/desktops/${encodeURIComponent(id)}/start`, {
        method: "POST",
      });
    },
    async stopDesktop(id) {
      return request<Desktop>(`/api/v1/desktops/${encodeURIComponent(id)}/stop`, {
        method: "POST",
      });
    },
    async deleteDesktop(id) {
      return request<Desktop>(`/api/v1/desktops/${encodeURIComponent(id)}`, {
        method: "DELETE",
      });
    },
  };
}
