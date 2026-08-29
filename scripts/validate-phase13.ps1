param(
    [switch]$RunOptionalTools
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failures = 0

function Pass($Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Fail($Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:failures++
}

function Warn($Message) {
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Check-File($Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Pass "required file exists: $Path"
    } else {
        Fail "required file missing: $Path"
    }
}

function Check-ContentPresent($Path, $Pattern, $Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Description; missing file $Path"
        return
    }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
        Pass $Description
    } else {
        Fail $Description
    }
}

function Get-RepositoryFiles {
    Get-ChildItem -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "[\\/]\.git([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]\.codex-remote-attachments([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]\.local([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]artifacts([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]reports([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]packer_cache([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]node_modules([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]dist([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]\.terraform([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]\.pytest_cache([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]__pycache__([\\/]|$)" } |
        Where-Object { $_.FullName -notmatch "[\\/]\.venv([\\/]|$)" }
}

function Check-ContentAbsent($Paths, $Pattern, $Description) {
    $matches = $Paths | Select-String -Pattern $Pattern -ErrorAction SilentlyContinue
    if ($matches) {
        Fail "$Description found"
        $matches | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $($_.Path):$($_.LineNumber)"
        }
    } else {
        Pass "$Description not found"
    }
}

Write-Host "VDIForge Phase 13 static validation"

$requiredFiles = @(
    ".github/workflows/ci.yml",
    ".github/workflows/infra-validation.yml",
    ".github/workflows/security.yml",
    ".github/workflows/containers.yml",
    ".github/workflows/release.yml",
    ".github/workflows/golden-image-validation.yml",
    ".github/workflows/phase1-validation.yml",
    ".github/dependabot.yml",
    ".github/security/trivy-baseline.json",
    ".gitleaks.toml",
    "scripts/ci/check-trivy-baseline.py",
    "scripts/ci-local.ps1",
    "scripts/validate-phase13.ps1",
    "docs/CI-CD.md",
    "docs/ADR/0023-github-actions-cicd-boundary.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$workflowFiles = @(Get-ChildItem ".github/workflows" -File -Include *.yml, *.yaml -Recurse)
$workflowContent = ($workflowFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

foreach ($workflow in @("ci.yml", "infra-validation.yml", "security.yml", "containers.yml")) {
    $path = ".github/workflows/$workflow"
    Check-ContentPresent $path "(?m)^\s*pull_request:\s*$" "$workflow runs on pull_request"
    Check-ContentPresent $path "(?s)push:\s*.*branches:\s*.*main" "$workflow runs on push to main"
    Check-ContentPresent $path "(?m)^\s*workflow_dispatch:\s*$" "$workflow supports manual dispatch"
    Check-ContentPresent $path "(?m)^permissions:\s*\r?\n\s+contents:\s+read\s*$" "$workflow uses read-only contents permission"
    Check-ContentPresent $path "(?m)^concurrency:\s*$" "$workflow defines concurrency"
}

Check-ContentPresent ".github/workflows/release.yml" "(?m)^\s+packages:\s+write\s*$" "release workflow grants package write only where needed"
Check-ContentPresent ".github/workflows/release.yml" "(?m)^\s+id-token:\s+write\s*$" "release workflow can emit provenance attestations"
Check-ContentPresent ".github/workflows/release.yml" "ghcr\.io" "release workflow targets GHCR"
Check-ContentPresent ".github/workflows/release.yml" "(?m)^\s+tags:\s*\r?\n\s+- `"v\*`"" "release workflow uses semantic version tag trigger"
Check-ContentPresent ".github/workflows/golden-image-validation.yml" "workflow_dispatch" "golden-image workflow is manual only"

$floatingActions = $workflowFiles | Select-String -Pattern "uses:\s+[^@\s]+@(main|master|latest)\b" -ErrorAction SilentlyContinue
if ($floatingActions) {
    Fail "floating GitHub Action references"
    $floatingActions | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
} else {
    Pass "GitHub Action references avoid main/master/latest"
}

$missingActionPins = $workflowFiles | Select-String -Pattern "uses:\s+[^@\s]+(?=\s*$)" -ErrorAction SilentlyContinue
if ($missingActionPins) {
    Fail "GitHub Action references without explicit version"
    $missingActionPins | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
} else {
    Pass "GitHub Action references include explicit versions"
}

if ($workflowContent -match "pull_request_target") {
    Fail "workflows use pull_request_target"
} else {
    Pass "workflows avoid pull_request_target"
}

if ($workflowContent -match "terraform\s+(apply|destroy)|helm\s+upgrade\s+--install|kubectl\s+apply|ssh\s+vdiadmin@|192\.168\.56\.") {
    Fail "normal workflows include live-lab or deployment operations"
} else {
    Pass "normal workflows avoid live-lab deployment operations"
}

Check-ContentPresent ".github/workflows/ci.yml" "python -m ruff check" "backend CI runs Ruff"
Check-ContentPresent ".github/workflows/ci.yml" "python -m pytest" "backend CI runs pytest"
Check-ContentPresent ".github/workflows/ci.yml" "alembic upgrade head" "backend CI validates Alembic migrations"
Check-ContentPresent ".github/workflows/ci.yml" "npm run lint" "frontend CI runs lint"
Check-ContentPresent ".github/workflows/ci.yml" "npm run test:run" "frontend CI runs tests"
Check-ContentPresent ".github/workflows/ci.yml" "npm run build" "frontend CI runs production build"
Check-ContentPresent ".github/workflows/infra-validation.yml" "terraform fmt -check -recursive" "Terraform fmt validation is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "terraform -chdir=terraform/environments/local validate" "Terraform validate is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "ansible-playbook .*--syntax-check" "Ansible syntax validation is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "ansible-lint ansible" "Ansible lint is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "packer validate" "Packer validation is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "helm lint" "Helm lint is configured"
Check-ContentPresent ".github/workflows/infra-validation.yml" "kubeconform" "Kubernetes schema validation is configured"
Check-ContentPresent ".github/workflows/security.yml" "gitleaks" "Gitleaks secret scanning is configured"
Check-ContentPresent ".github/workflows/security.yml" "pip-audit" "Python dependency scanning is configured"
Check-ContentPresent ".github/workflows/security.yml" "npm audit" "Node dependency scanning is configured"
Check-ContentPresent ".github/workflows/containers.yml" "docker/build-push-action@v7" "container image builds are configured"
Check-ContentPresent ".github/workflows/containers.yml" "push:\s+false" "PR/main container workflow does not push images"
Check-ContentPresent ".github/workflows/containers.yml" "format:\s+cyclonedx" "SBOM generation is configured"
Check-ContentPresent ".github/workflows/containers.yml" "check-trivy-baseline.py" "container vulnerability baseline checks are configured"

$dependabot = Get-Content ".github/dependabot.yml" -Raw
foreach ($ecosystem in @("github-actions", "pip", "npm", "docker")) {
    if ($dependabot -match "package-ecosystem:\s+$ecosystem") {
        Pass "Dependabot covers $ecosystem"
    } else {
        Fail "Dependabot missing $ecosystem"
    }
}

try {
    $baseline = Get-Content ".github/security/trivy-baseline.json" -Raw | ConvertFrom-Json
    if ([datetime]$baseline.expires -gt (Get-Date)) {
        Pass "Trivy baseline has a future review date"
    } else {
        Fail "Trivy baseline has expired"
    }
    if ($baseline.components.api.critical -eq 7 -and $baseline.components.api.high -eq 37 -and $baseline.components.frontend.critical -eq 0 -and $baseline.components.frontend.high -eq 12) {
        Pass "Trivy baseline matches Phase 12 accepted findings"
    } else {
        Fail "Trivy baseline does not match Phase 12 accepted findings"
    }
} catch {
    Fail "Trivy baseline JSON is invalid: $($_.Exception.Message)"
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"

$trackedArtifacts = git ls-files --cached --others --exclude-standard | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|terraform\.tfstate|\.kubeconfig$|phase[0-9]+\.env|browser-connection\.json|audit-export\.jsonl|reports/" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked or unignored"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked or unignored"
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB|HPA|MON|CI)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$ciRequirements = $definitionIds | Where-Object { $_ -like "CI-*" }
if ($ciRequirements.Count -ge 20 -and $requirements -match "## Phase 13 Traceability") {
    Pass "Phase 13 CI requirements and traceability are defined"
} else {
    Fail "Phase 13 CI requirements or traceability are incomplete"
}

foreach ($doc in @(
    "docs/CI-CD.md",
    "docs/TESTING.md",
    "docs/SECURITY.md",
    "docs/SECURITY-HARDENING.md",
    "docs/IMAGE-PIPELINE.md",
    "docs/HELM-PLATFORM.md",
    "docs/RUNBOOK.md",
    "docs/ROADMAP.md",
    "docs/DESIGN.md",
    "docs/ARCHITECTURE.md"
)) {
    if (Test-Path -LiteralPath $doc -PathType Leaf) {
        $content = Get-Content -LiteralPath $doc -Raw
        if ($content -match "Phase 13|CI/CD|GitHub Actions") {
            Pass "Phase 13 documentation present in $doc"
        } else {
            Fail "Phase 13 documentation missing in $doc"
        }
    } else {
        Fail "missing documentation file: $doc"
    }
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/ci/check-trivy-baseline.py
    if ($LASTEXITCODE -eq 0) { Pass "Trivy baseline checker compiles" } else { Fail "Trivy baseline checker compiles" }
    python scripts/ci/check-trivy-baseline.py --self-test
    if ($LASTEXITCODE -eq 0) { Pass "Trivy baseline checker self-test" } else { Fail "Trivy baseline checker self-test" }
} else {
    Warn "python is not installed; Trivy baseline checker compile/self-test skipped"
}

if ($RunOptionalTools) {
    if (Get-Command actionlint -ErrorAction SilentlyContinue) {
        actionlint
        if ($LASTEXITCODE -eq 0) { Pass "actionlint" } else { Fail "actionlint" }
    } else {
        Warn "actionlint is not installed; GitHub Actions workflow syntax will be checked in CI"
    }

    if (Get-Command helm -ErrorAction SilentlyContinue) {
        helm lint ./helm/vdiforge -f ./helm/vdiforge/values-phase12-local.yaml
        if ($LASTEXITCODE -eq 0) { Pass "helm lint" } else { Fail "helm lint" }
        New-Item -ItemType Directory -Force -Path ".local/phase13" | Out-Null
        helm template vdiforge ./helm/vdiforge --namespace vdiforge-system -f ./helm/vdiforge/values-phase12-local.yaml --kube-version 1.36.4 > ".local/phase13/rendered.yaml"
        if ($LASTEXITCODE -eq 0) { Pass "helm template" } else { Fail "helm template" }
    } else {
        Warn "helm is not installed; Helm validation will be checked in CI"
    }
}

if ($failures -ne 0) {
    Write-Host "Phase 13 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 13 validation: PASS" -ForegroundColor Green
