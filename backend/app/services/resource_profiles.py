from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ResourceProfile:
    name: str
    cpu_cores: int
    memory: str
    disk: str


RESOURCE_PROFILES: dict[str, ResourceProfile] = {
    "small": ResourceProfile(name="small", cpu_cores=1, memory="2Gi", disk="32Gi"),
    "standard": ResourceProfile(name="standard", cpu_cores=2, memory="4Gi", disk="32Gi"),
}


def get_resource_profile(name: str) -> ResourceProfile | None:
    return RESOURCE_PROFILES.get(name)
