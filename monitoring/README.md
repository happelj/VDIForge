# Monitoring

Phase 11 uses this directory for Prometheus and Grafana configuration.

```text
monitoring/
  kube-prometheus-stack-values-local.yaml
  grafana/
    vdiforge-overview.json
```

The monitoring stack is installed with the upstream `prometheus-community/kube-prometheus-stack` chart rather than embedding Prometheus and Grafana directly in the VDIForge chart.

| Item | Value |
| --- | --- |
| Helm release | `vdiforge-monitoring` |
| Namespace | `monitoring` |
| kube-prometheus-stack version | `88.6.1` |
| Prometheus Operator app version | `v0.93.1` |
| Grafana URL | `https://grafana.vdiforge.local` |
| Dashboard | `VDIForge Overview` |

The VDIForge chart owns the application-specific observability resources:

- `ServiceMonitor` for `vdiforge-api`;
- `ServiceMonitor` for `vdiforge-provisioner`;
- `PrometheusRule` `vdiforge-alerts`;
- Grafana dashboard ConfigMap;
- NetworkPolicy allowance for Prometheus scraping.

The dashboard source in this directory must match the chart-packaged copy at:

```text
helm/vdiforge/files/grafana/vdiforge-overview.json
```

Validate from the repository checkout:

```powershell
.\scripts\validate-phase11.ps1
```

Install or validate live from `vdi-control-01`:

```bash
bash scripts/phase11-install-monitoring.sh
bash scripts/validate-phase11-live.sh
```

Generated Grafana credentials and TLS material live under ignored `.local/phase11` paths and must not be committed.
