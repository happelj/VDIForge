# CI/CD Pipeline

Phase 13 establishes the GitHub Actions pipeline for VDIForge. The pipeline is designed for fast pull-request feedback, branch-protection-ready status checks, and supply-chain visibility without depending on the local VirtualBox/Kubernetes lab.

## Goals

- Run CI-safe checks on pull requests, pushes to `main`, and feature-branch pushes used for pre-merge validation.
- Validate backend, frontend, infrastructure definitions, Helm charts, Kubernetes manifests, security scans, and custom container images.
- Keep live-lab validation separate from normal pull-request validation.
- Avoid exposing local-lab credentials, kubeconfigs, TLS private keys, or generated image artifacts to GitHub Actions.
- Provide an optional release path for publishing custom container images to GitHub Container Registry.

## Non-Goals

- GitHub Actions does not create the three VirtualBox VMs.
- GitHub Actions does not connect to the home lab.
- GitHub Actions does not run the full KubeVirt, Guacamole, xrdp, or browser VDI lifecycle on every pull request.
- GitHub Actions does not build the full QCOW2 Ubuntu golden images by default.
- Phase 13 does not implement Phase 14 demo polish.

## Workflow Summary

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `phase1-validation.yml` | pull request, push to `main`, push to `feature/**`, manual | Lightweight repository/documentation regression validation. |
| `ci.yml` | pull request, push to `main`, push to `feature/**`, manual | Repository policy checks, backend lint/tests/migrations, frontend lint/tests/build. |
| `infra-validation.yml` | pull request, push to `main`, push to `feature/**`, manual | Terraform, Ansible, Packer, Helm, and Kubernetes manifest validation. |
| `security.yml` | pull request, push to `main`, push to `feature/**`, manual | Secret scan, backend dependency scan, frontend dependency scan, and repository configuration scan. |
| `containers.yml` | pull request, push to `main`, push to `feature/**`, manual | Build VDIForge-owned API/frontend images, run Trivy image scans, and upload SBOMs. |
| `release.yml` | semantic version tag `v*`, manual | Build and publish API/frontend images to GHCR with SBOM/provenance metadata. |
| `golden-image-validation.yml` | manual only | Validate Packer image definitions without building QCOW2 artifacts. |

All pull-request, feature-branch, and `main` validation workflows use concurrency cancellation so obsolete commits do not waste runner time.

## Tool Versions

| Tool | Version | Use |
| --- | --- | --- |
| Python | `3.13` | Backend CI and validation scripts. |
| Node.js | `22.15.0` | Frontend CI. |
| Terraform | `1.15.9` | Static infrastructure validation. |
| Packer | `1.16.0` | Static image-template validation. |
| Helm | `v4.2.4` | Chart lint/render validation. |
| kubeconform | `v0.7.0` | Kubernetes schema validation. |
| ansible-core | `2.21.3` | Playbook syntax validation. |
| ansible-lint | `26.8.0` | Ansible style and safety validation. |
| pip-audit | `2.10.1` | Backend dependency advisory scan. |
| Gitleaks | `v8.30.1` | Git secret scan. |
| Trivy action | `v0.36.0` | Filesystem, image, and SBOM scanning. |
| actionlint | `v1.7.7` | GitHub Actions syntax validation. |

GitHub Actions are pinned to maintained major versions or explicit tool versions. The project currently uses major-version pins for official and well-known actions so Dependabot can safely propose updates without hardcoding stale commit SHAs.

## Backend CI

The backend job uses Python `3.13`, installs `backend/requirements-dev.txt`, and runs:

```bash
python -m ruff check .
python -m pytest
python -m alembic upgrade head
```

Alembic migration validation uses a disposable PostgreSQL service container. It never connects to the local lab database.

## Frontend CI

The frontend job uses Node.js `22.15.0` and the checked-in `package-lock.json`:

```bash
npm ci
npm run lint
npm run test:run
npm run build
```

Frontend tests do not require a live Keycloak, API, KubeVirt, or Guacamole deployment.

## Browser Testing Boundary

CI validates the React code through unit/component tests and production build. The full browser workflow that logs into Keycloak, launches a KubeVirt VM, brokers a Guacamole session, and connects to xrdp remains a live-lab validation path:

```bash
bash scripts/validate-phase9-live.sh
bash scripts/validate-phase12-live.sh
```

This distinction is intentional. A GitHub-hosted runner does not have access to the local VirtualBox lab and should not receive local kubeconfigs or secrets.

## Infrastructure Validation

GitHub Actions validates infrastructure definitions without provisioning VMs:

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/local init -backend=false
terraform -chdir=terraform/environments/local validate
```

The pipeline also runs Ansible syntax checks, `ansible-lint`, Packer `init`/`fmt`/`validate`, Helm `lint`/`template`, and kubeconform schema validation for rendered Helm output and raw Kubernetes manifests.

The `.ansible-lint` configuration preserves the hyphenated role directory names established by earlier phases while keeping the rest of the basic lint profile enabled.

Terraform state, VirtualBox VM files, kubeconfigs, and generated plans are not produced or committed by CI.

## Packer and Golden Image Boundary

CI validates Packer templates and image definitions only. Full QCOW2 golden-image builds remain local/manual because they require KVM, large disk artifacts, and the VDIForge image build environment.

The manual `golden-image-validation.yml` workflow exists to re-run static Packer validation from GitHub without implying that hosted runners validate the same path as the real local KVM build.

## Helm and Manifest Validation

The infrastructure workflow renders the VDIForge chart with Phase 12 local values and validates the result with kubeconform. Unknown CRD-backed resources are allowed through `-ignore-missing-schemas` because KubeVirt, CDI, Prometheus Operator, Traefik, and related CRDs are not available as built-in Kubernetes schemas.

Live Helm install, upgrade, rollback, and server-side dry-run remain local-lab validation tasks.

## Security Scanning

Security workflows include:

- Gitleaks repository history/current-content secret scan.
- `pip-audit` for backend dependencies.
- `npm audit` for frontend dependencies with critical severity gating.
- Trivy filesystem scan for advisory repository configuration findings.
- Trivy image scans for VDIForge-owned API and frontend images.

The repository contains `.gitleaks.toml` for narrow false-positive handling. It does not allow real secrets.

## Container Builds

The `containers.yml` workflow builds:

- `vdiforge-api:ci-<sha>`
- `vdiforge-frontend:ci-<sha>`

Pull-request, feature-branch, and `main` jobs build and scan images locally on the runner but do not push images to a registry.

## Trivy Baseline

Phase 12 documented accepted vulnerability counts for custom images:

| Image | Critical | High |
| --- | ---: | ---: |
| API | 7 | 37 |
| Frontend | 0 | 12 |

Phase 13 stores that baseline in `.github/security/trivy-baseline.json` with a review deadline of `2026-12-31`. CI fails if a custom image exceeds the accepted high or critical count. This prevents new high-impact findings from being silently introduced while avoiding permanently red CI from already documented Phase 12 findings.

The baseline is not a waiver forever. Phase 14 or future maintenance should reduce or refresh it.

## SBOM and Provenance

The container workflow generates CycloneDX SBOM artifacts for the API and frontend images with short retention. The release workflow enables Docker build SBOM/provenance metadata when pushing to GHCR.

Ordinary PR image builds use `load: true` and do not push, so registry-attached attestations are limited to release publishing.

## Registry and Tags

The release workflow targets GitHub Container Registry:

```text
ghcr.io/<owner>/vdiforge-api
ghcr.io/<owner>/vdiforge-frontend
```

Tag strategy:

- `sha-<commit>` for immutable commit references.
- `vX.Y.Z` for semantic release tags.
- optional manual `workflow_dispatch` tag when explicitly supplied.

The workflow uses `GITHUB_TOKEN`; no personal access token is required for normal repository-owned GHCR publishing.

## Permissions and Fork Safety

Normal CI workflows use:

```yaml
permissions:
  contents: read
```

Only the release workflow grants `packages: write` and `id-token: write`, and it is not triggered by pull requests.

The project does not use `pull_request_target`. Forked pull requests do not receive privileged credentials. No local-lab secrets are required by GitHub Actions.

## Artifacts

GitHub Actions may upload:

- rendered Helm manifests
- dependency scan reports
- Trivy scan reports
- SBOMs

Artifacts use short retention and must not include kubeconfigs, private keys, TLS CA material, database dumps, access tokens, or generated QCOW2 images.

## Local CI Parity

Run the CI-safe local checks from the repository root:

```powershell
.\scripts\ci-local.ps1
```

Optional local checks that depend on installed tools can be included with:

```powershell
.\scripts\ci-local.ps1 -RunOptionalTools
```

Live-lab validations remain separate and must be run from `vdi-control-01` where the local cluster credentials exist.

## Branch Protection Recommendations

Recommended `main` branch rules:

- require pull requests before merging;
- require status checks from `CI`, `Infrastructure validation`, `Security validation`, `Container images`, and `Phase 1 validation`;
- require the branch to be up to date before merge where practical;
- disable force pushes;
- restrict deletion of `main`;
- require conversation resolution before merge.

Phase 13 documents these settings but does not modify repository branch-protection settings.

## Dependabot

`.github/dependabot.yml` enables weekly grouped update PRs for:

- GitHub Actions
- Python dependencies
- npm dependencies
- backend Dockerfile
- frontend Dockerfile

Automatic merging is not enabled.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Backend migration job fails | Alembic migration does not apply to a clean PostgreSQL database | Reproduce locally against a disposable PostgreSQL database and fix the migration. |
| Frontend CI fails on `npm ci` | `package-lock.json` does not match `package.json` | Regenerate the lockfile intentionally and commit it. |
| Terraform validate fails | Provider/module schema or variable validation error | Run the same `terraform -chdir=terraform/environments/local init -backend=false validate` command locally. |
| Packer validate fails | Template formatting, plugin, or variable issue | Run the manual golden-image validation workflow or local Packer validation before building large artifacts. |
| kubeconform reports missing schema | A CRD resource lacks a public schema in CI | Confirm the resource is CRD-backed and covered by live-lab validation before adding a narrow exclusion. |
| Gitleaks fails | Possible committed secret or false positive | Treat as a real leak until reviewed; allowlist only safe placeholders. |
| Trivy baseline fails | New high/critical finding or changed scanner classification | Patch the dependency/image when practical; otherwise update the baseline with documented risk acceptance and expiry. |
| Release publish fails | GHCR permissions or tag metadata issue | Confirm package permissions and release trigger; do not use a personal token unless an ADR justifies it. |

## Validation Classification

| Validation | CI-safe | Live-lab only |
| --- | --- | --- |
| Phase 1 static repository validation | Yes | No |
| Backend unit tests | Yes | No |
| Frontend unit/component tests | Yes | No |
| Alembic clean database migration | Yes | No |
| Terraform fmt/validate | Yes | No |
| Ansible syntax/lint | Yes | No |
| Packer fmt/validate | Yes | No |
| Full QCOW2 image build | No | Yes |
| Helm lint/template | Yes | No |
| Helm live install/rollback | No | Yes |
| KubeVirt test VM lifecycle | No | Yes |
| Guacamole/xrdp browser connection | No | Yes |
| Prometheus/Grafana live dashboard validation | No | Yes |
| Security headers through live ingress | No | Yes |
| Secret and dependency scans | Yes | No |
| Container build, image scan, SBOM | Yes | No |
