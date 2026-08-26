# Monitoring

This directory is reserved for Prometheus and Grafana configuration.

## Planned Areas

```text
monitoring/
  prometheus/
  grafana/
```

## Dashboard Targets

- active desktops
- provisioning desktops
- failed desktops
- provisioning success rate
- P50/P95 provisioning latency
- API request rate
- API error rate
- API latency
- API replica count
- HPA desired/current replicas
- pod CPU/memory
- worker-node CPU/memory
- Kubernetes node health
- active remote sessions

No monitoring implementation is present in Phase 1.
