# ADR 0016: XFCE for VDIForge Ubuntu Images

## Status

Accepted for the MVP image pipeline.

## Context

The Ubuntu desktop images must boot reliably in a small VirtualBox/KubeVirt lab and later support browser-based remote desktop access through Apache Guacamole. The lab has constrained CPU, memory, and local storage, so the desktop environment should be modest and stable rather than visually heavy.

## Decision

Use XFCE as the default graphical desktop environment for the initial Ubuntu images.

The base image installs:

- `xfce4`
- `xfce4-terminal`
- `xfce4-goodies`
- `xrdp`
- `xorgxrdp`
- `qemu-guest-agent`
- common CLI and system utilities

Phase 6 configures remote desktop prerequisites only. It does not deploy Guacamole or implement the final xrdp/Guacamole integration.

## Alternatives Considered

- GNOME desktop: rejected for the MVP because it consumes more RAM and CPU than needed for a small lab.
- KDE Plasma: viable, but adds more package surface than the project needs at this phase.
- No graphical desktop until Phase 8: rejected because Phase 6 must prove a desktop-capable golden-image pipeline.
- Minimal window manager only: lightweight, but less representative of a normal Ubuntu desktop experience.

## Consequences

- The images remain smaller and more responsive than a full GNOME desktop image.
- Future remote desktop work can build on `xrdp` and XFCE session defaults.
- Later phases may revisit the desktop choice if Guacamole integration exposes compatibility problems.
