# ADR 0013: Local Ingress and TLS for Browser-Facing Services

## Status

Accepted

## Context

Phase 5 is the first phase that exposes a browser-facing service. Keycloak must be reachable at a stable HTTPS URL so OIDC issuer metadata, redirect URIs, and future browser authentication behavior are realistic.

The local lab runs in VirtualBox on a Windows 10 Pro host. The Kubernetes nodes use a host-only management network at `192.168.56.0/24`, with `vdi-worker-01` as the platform worker at `192.168.56.11`.

The design must support:

- `https://auth.vdiforge.local`
- future `https://vdiforge.local`
- future `https://grafana.vdiforge.local`
- trusted local HTTPS without disabling TLS verification
- no committed TLS private keys
- no unnecessary production-grade complexity

References:

- [Traefik Helm chart releases](https://github.com/traefik/traefik-helm-chart/releases)
- [Keycloak reverse proxy configuration](https://www.keycloak.org/server/reverseproxy)

## Decision

Install Traefik with Helm chart `41.2.0` as a separate infrastructure release in namespace `ingress-traefik`.

Expose Traefik through host ports on the platform worker:

| Host port | Traefik entry point |
| ---: | --- |
| `80` | `web` |
| `443` | `websecure` |

Use local host resolution:

```text
192.168.56.11 auth.vdiforge.local vdiforge.local grafana.vdiforge.local
```

Use a generated VDIForge local development CA and a local `auth.vdiforge.local` certificate. Generated CA private keys, TLS private keys, and local secret values live under ignored `.local/phase5/` paths.

Do not install cert-manager in Phase 5. Do not use public ACME certificates for `.local` names.

## Alternatives Considered

- NGINX Ingress Controller: technically valid, but Traefik is lightweight, straightforward to install by Helm, and adequate for the local lab.
- NodePort-only access: simpler, but less realistic for OIDC issuer URLs and browser callbacks because it requires port-bearing URLs.
- `kubectl port-forward`: useful for troubleshooting, but not a stable browser or thin-client access path.
- cert-manager with a local CA issuer: good for larger labs, but unnecessary moving parts for a single local identity endpoint.
- Self-signed leaf certificate without a local CA: easier to generate, but harder to trust cleanly across a Windows host and future thin client.

## Consequences

- OIDC tests can validate the real HTTPS issuer `https://auth.vdiforge.local/realms/vdiforge`.
- Browser clients need a hosts-file entry or equivalent DNS and must trust the generated local CA.
- The ingress endpoint depends on `vdi-worker-01`; this is not a high-availability ingress design.
- Later phases can add `vdiforge.local` and `grafana.vdiforge.local` without reworking the hostname convention.
- Operators should not globally disable TLS verification. Test clients may use explicit local resolver mapping while still validating the certificate chain and hostname.
