# VDIForge Helm Chart

This directory is reserved for the VDIForge application Helm chart.

The eventual deployment experience should approximate:

```bash
helm upgrade --install vdiforge ./helm/vdiforge
```

## Planned Resources

- frontend Deployment, Service, Ingress
- FastAPI Deployment, Service, Ingress
- provisioning worker Deployment
- ConfigMaps
- ServiceAccounts
- Roles and RoleBindings
- NetworkPolicies
- HPA definitions

No Helm chart templates are present in Phase 1 because the application is not implemented yet.
