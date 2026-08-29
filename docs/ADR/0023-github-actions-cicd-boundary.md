# ADR 0023: GitHub Actions CI/CD Boundary

## Status

Accepted

## Context

VDIForge now includes infrastructure definitions, Kubernetes/KubeVirt, Helm, Keycloak, FastAPI, PostgreSQL, golden-image definitions, Guacamole, a React portal, HPA, Prometheus/Grafana, and security hardening. Phase 13 needs a real CI/CD pipeline that gives useful feedback on pull requests without depending on the developer's Windows/VirtualBox home lab.

GitHub-hosted runners are suitable for static validation, unit tests, dependency scanning, container builds, and manifest rendering. They are not a reliable replacement for the local KVM-backed VDIForge lab because the full system depends on nested virtualization, KubeVirt, CDI storage, local TLS/DNS, Keycloak, Guacamole, xrdp, and generated lab credentials.

The project also needs a defensible approach to Phase 12 vulnerability findings. Blocking CI on already accepted findings would keep the pipeline permanently red, while ignoring all future findings would remove value from the scan.

## Decision

Use GitHub Actions for CI-safe validation on pull requests and pushes to `main`.

The normal pipeline will run:

- repository and workflow validation;
- backend Ruff, pytest, and Alembic migration checks against disposable PostgreSQL;
- frontend `npm ci`, lint, tests, and production build;
- Terraform format and validation without provisioning infrastructure;
- Ansible syntax validation and linting without configuring live nodes;
- Packer static validation without building QCOW2 images;
- Helm lint/template and kubeconform manifest validation without a live API server;
- Gitleaks, pip-audit, npm audit, Trivy filesystem scan, Trivy image scan;
- custom API/frontend container builds;
- SBOM generation for VDIForge-owned container images.

Keep live-lab validation local/manual. The default CI pipeline will not connect to the home lab, use kubeconfigs, use local CA/private keys, run KubeVirt VM lifecycle tests, run Guacamole browser sessions, deploy to the cluster, or build full golden images.

Use GHCR as the documented container registry path for release/tag/manual publishing. Pull requests and ordinary `main` validation build and scan images but do not push images.

Store the Phase 12 accepted Trivy high/critical counts in a versioned baseline file with an expiration date. CI fails when new scan results exceed that baseline.

## Alternatives Considered

1. Run the complete local lab in GitHub Actions.
   - Rejected because the platform depends on VirtualBox/KVM/nested virtualization, large image artifacts, local DNS/TLS, and live state that hosted runners should not receive.

2. Deploy automatically to the home lab from GitHub Actions.
   - Rejected for Phase 13 because it would require exposing local network access and sensitive credentials. Developer-controlled local deployment remains safer and easier to reason about.

3. Build all QCOW2 golden images on every pull request.
   - Rejected because this is slow, storage-heavy, KVM-dependent, and unnecessary for normal code review.

4. Fail CI on every existing Trivy high/critical finding.
   - Rejected because Phase 12 already documented accepted findings. The selected baseline gates regressions while leaving a visible remediation target.

5. Ignore all Trivy high/critical findings.
   - Rejected because it would silently allow new vulnerabilities.

## Consequences

- Pull requests get fast, useful feedback without requiring the local lab.
- Branch protection can require consistent checks across code, infrastructure, charts, manifests, dependencies, and containers.
- The repository does not expose lab credentials or kubeconfigs to GitHub Actions.
- Full end-to-end VDI behavior still requires local/manual validation.
- The Trivy baseline must be reviewed before it expires and should be reduced as dependencies are patched.
- Release publishing can use GitHub-native `GITHUB_TOKEN` permissions and GHCR without personal access tokens.
