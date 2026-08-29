# 0021 - kube-prometheus-stack Observability

## Status

Accepted

## Context

Phase 11 needs real observability for the VDIForge lab without changing the HPA design from Phase 10. Metrics Server is already installed and supports HPA resource metrics, but it is not a time-series store, dashboard system, or alerting platform.

VDIForge also needs KubeVirt visibility, API/provisioner application metrics, alert rules, and dashboard-as-code. The local lab has limited CPU, memory, and storage, so the monitoring stack must be widely used, maintainable, and configurable rather than unnecessarily complex.

## Decision

Deploy `prometheus-community/kube-prometheus-stack` version `88.6.1` into the existing `monitoring` namespace. Use its bundled Prometheus Operator, Prometheus, Alertmanager, Grafana, and kube-state-metrics components. Disable node-exporter in the local baseline because it requires host namespace and hostPath access that would force the whole `monitoring` namespace above baseline Pod Security.

Keep Metrics Server as the Kubernetes HPA metrics provider. Prometheus and Grafana are for observability, dashboards, PrometheusRule alerts, and validation evidence.

Use the VDIForge Helm chart to manage VDIForge-specific observability resources:

- ServiceMonitors for the FastAPI API and provisioner;
- PrometheusRule `vdiforge-alerts`;
- Grafana dashboard ConfigMap for `VDIForge Overview`;
- NetworkPolicy allowance for Prometheus scraping;
- values-based metric and dashboard configuration.

Generate Grafana local admin credentials and TLS material outside Git under `.local/phase11`, then apply them as Kubernetes Secrets. Do not commit real Grafana passwords, TLS private keys, kubeconfigs, tokens, or generated runtime artifacts.

Defer Grafana Keycloak OIDC integration until a later hardening phase because it requires a dedicated Grafana OIDC client, role mapping, session policy, and secret-management decision.

## Alternatives Considered

- Use Metrics Server only: rejected because it cannot provide Prometheus queries, dashboards, alert rules, or application metric retention.
- Install raw Prometheus and Grafana manifests manually: rejected because Helm lifecycle and Prometheus Operator CRDs are already a better fit for the platform foundation.
- Build a custom Prometheus/Grafana chart inside `helm/vdiforge`: rejected because upstream kube-prometheus-stack already maintains the core monitoring components.
- Use Grafana Cloud or another hosted monitoring service: rejected because the MVP lab should remain free and locally demonstrable.
- Add Elasticsearch, Loki, or a SIEM now: rejected as unnecessary for Phase 11. Logs and audit records remain separate, and SIEM forwarding is future work.

## Consequences

- The lab gains a real Prometheus/Grafana foundation with pinned chart values and reproducible validation.
- Metrics Server and Prometheus have distinct roles, which avoids breaking the Phase 10 HPA model.
- The monitoring namespace now contains persistent local-path volumes and must be included in storage troubleshooting.
- Grafana credentials are operational secrets and must be regenerated or read from `.local/phase11/phase11.env`, not stored in source control.
- Future phases can add dashboards, ServiceMonitors, alerts, and log forwarding without replacing the Phase 11 stack.
