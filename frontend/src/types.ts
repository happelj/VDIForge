export type DesktopObservedState =
  | "REQUESTED"
  | "PROVISIONING"
  | "BOOTING"
  | "READY"
  | "CONNECTED"
  | "STOPPING"
  | "STOPPED"
  | "TERMINATING"
  | "TERMINATED"
  | "FAILED";

export type DesktopDesiredState = "RUNNING" | "STOPPED" | "DELETED";

export type ImageVersion = {
  version: string;
  ubuntu_release: string;
  architecture: string;
  artifact_format: string;
  lifecycle: string;
};

export type Image = {
  id: string;
  display_name: string;
  description: string;
  default_version: string;
  allowed_roles: string[];
  versions: ImageVersion[];
};

export type Desktop = {
  id: string;
  display_name: string;
  owner_username: string;
  image_id: string;
  image_version: string;
  resource_profile: string;
  desired_state: DesktopDesiredState;
  observed_state: DesktopObservedState;
  kubevirt_vm_name: string;
  kubevirt_data_volume_name: string;
  kubevirt_service_name: string;
  failure_code: string | null;
  failure_message: string | null;
  created_at: string;
  updated_at: string;
};

export type DesktopListResponse = {
  desktops: Desktop[];
};

export type DesktopCreateRequest = {
  image_id: string;
  image_version?: string;
  resource_profile: string;
  display_name?: string;
};

export type DesktopConnectionResponse = {
  desktop_id: string;
  connection_url: string;
  expires_at: string;
  protocol: string;
};

export type ApiErrorResponse = {
  error?: {
    code?: string;
    message?: string;
    request_id?: string;
  };
};

export type PortalUser = {
  username: string;
  roles: string[];
};
