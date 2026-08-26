# ADR 0004: Apache Guacamole for Remote Access

## Status

Accepted for MVP architecture.

## Context

VDIForge needs browser-based access to Ubuntu desktops without installing a special client on the thin client. The MVP must remain free and open-source. Apache Guacamole provides an HTML5 remote desktop gateway and supports protocols including RDP and VNC.

The selected protocol must be reliable and automatable for Ubuntu desktop VMs.

## Decision

Use Apache Guacamole as the browser-based remote desktop gateway.

Use RDP through `xrdp` as the MVP protocol. Keep VNC as a documented fallback if RDP session behavior or image configuration blocks the demo.

## Alternatives Considered

- Direct browser VNC client: simpler in some cases, but Guacamole provides a stronger gateway architecture and supports multiple protocols.
- NoMachine/NX: not selected because Guacamole documentation notes modern proprietary NX variants are not an open protocol target for Guacamole.
- PCoIP: rejected because the MVP should remain free and PCoIP licensing is out of scope.
- SSH-only browser terminal: insufficient because VDIForge needs a graphical Ubuntu desktop.

## Consequences

- The thin client needs only a modern browser.
- The remote desktop service runs inside the Ubuntu VM.
- Guacamole connection handling must be secured so users cannot guess another user's connection.
- The design must not claim RDP/VNC is equivalent to PCoIP.
- Remote desktop credentials must not be exposed to frontend JavaScript.
