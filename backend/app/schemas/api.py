from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

DesktopObservedState = Literal[
    "REQUESTED",
    "PROVISIONING",
    "BOOTING",
    "READY",
    "CONNECTED",
    "STOPPING",
    "STOPPED",
    "TERMINATING",
    "TERMINATED",
    "FAILED",
]
DesktopDesiredState = Literal["RUNNING", "STOPPED", "DELETED"]


class ErrorBody(BaseModel):
    code: str
    message: str
    request_id: str


class ErrorResponse(BaseModel):
    error: ErrorBody


class ImageVersionResponse(BaseModel):
    version: str
    ubuntu_release: str
    architecture: str
    artifact_format: str
    lifecycle: str


class ImageResponse(BaseModel):
    id: str
    display_name: str
    description: str
    default_version: str
    allowed_roles: list[str]
    versions: list[ImageVersionResponse]


class DesktopCreateRequest(BaseModel):
    image_id: str = Field(min_length=1, max_length=64)
    image_version: str | None = Field(default=None, max_length=32)
    resource_profile: str = Field(default="small", max_length=32)
    display_name: str | None = Field(default=None, max_length=128)


class DesktopResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    display_name: str
    owner_username: str
    image_id: str
    image_version: str
    resource_profile: str
    desired_state: DesktopDesiredState
    observed_state: DesktopObservedState
    kubevirt_vm_name: str
    kubevirt_data_volume_name: str
    kubevirt_service_name: str
    failure_code: str | None
    failure_message: str | None
    created_at: datetime
    updated_at: datetime


class DesktopListResponse(BaseModel):
    desktops: list[DesktopResponse]


class AuditEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    event_id: str
    timestamp: datetime
    request_id: str
    user_subject: str
    username: str | None
    action: str
    resource_type: str
    resource_id: str | None
    source_ip: str | None
    result: str
    details: dict


class AuditEventListResponse(BaseModel):
    audit_events: list[AuditEventResponse]


class HealthResponse(BaseModel):
    status: str
    version: str


class ReadyResponse(BaseModel):
    status: str
    database: str
    image_catalog: str
