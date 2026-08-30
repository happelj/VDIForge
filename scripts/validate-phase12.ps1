param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase12-validation"
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
    if (Test-Path $Path) {
        Pass "required file exists: $Path"
    } else {
        Fail "required file missing: $Path"
    }
}

function Get-RepositoryFiles {
    Get-ChildItem -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\.codex-remote-attachments\\" } |
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
        Where-Object { $_.FullName -notmatch "\\artifacts\\" } |
        Where-Object { $_.FullName -notmatch "\\packer_cache\\" } |
        Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
        Where-Object { $_.FullName -notmatch "\\dist\\" } |
        Where-Object { $_.FullName -notmatch "\\.terraform\\" } |
        Where-Object { $_.FullName -notmatch "\\.pytest_cache\\" } |
        Where-Object { $_.FullName -notmatch "\\__pycache__\\" } |
        Where-Object { $_.FullName -notmatch "\\.venv\\" }
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

function Check-ContentPresent($Path, $Pattern, $Description) {
    $content = Get-Content $Path -Raw
    if ($content -match $Pattern) {
        Pass $Description
    } else {
        Fail $Description
    }
}

function Rendered-DocHasIngressMiddleware($Rendered, $ResourceName) {
    foreach ($doc in ($Rendered -split "(?m)^---\s*$")) {
        if ($doc -match "(?m)^kind:\s+Ingress\s*$" -and
            $doc -match "(?m)^\s+name:\s+$([regex]::Escape($ResourceName))\s*$" -and
            $doc -match "traefik\.ingress\.kubernetes\.io/router\.middlewares") {
            return $true
        }
    }
    return $false
}

function Rendered-ServiceHasMiddleware($Rendered) {
    foreach ($doc in ($Rendered -split "(?m)^---\s*$")) {
        if ($doc -match "(?m)^kind:\s+Service\s*$" -and
            $doc -match "traefik\.ingress\.kubernetes\.io/router\.middlewares") {
            return $true
        }
    }
    return $false
}

Write-Host "VDIForge Phase 12 static validation"

$requiredFiles = @(
    "backend/app/security/headers.py",
    "backend/app/security/rate_limit.py",
    "backend/app/security/redaction.py",
    "backend/app/security/audit_integrity.py",
    "backend/alembic/versions/0002_phase12_audit_integrity.py",
    "helm/vdiforge/templates/securityheaders.yaml",
    "helm/vdiforge/values-phase12-local.yaml",
    "scripts/phase12-api-security-test.py",
    "scripts/phase12-dependency-scan.sh",
    "scripts/phase12-inventory.sh",
    "scripts/phase12-keycloak-hardening.sh",
    "scripts/phase12-networkpolicy-test.sh",
    "scripts/phase12-rbac-test.sh",
    "scripts/phase12-security-headers-test.sh",
    "scripts/validate-phase12.ps1",
    "scripts/validate-phase12-live.sh",
    "docs/SECURITY-HARDENING.md",
    "docs/ADR/0022-security-and-audit-hardening.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"
Check-ContentAbsent $repoFiles "(?im)^\s*(password|admin-password|GRAFANA_ADMIN_PASSWORD|KEYCLOAK_ADMIN_PASSWORD|KEYCLOAK_DB_PASSWORD|VDIFORGE_APP_DB_PASSWORD|JSON_SECRET_KEY)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{12,}['""]?\s*(#.*)?$" "plaintext runtime password"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$|phase[0-9]+\.env|\.key$|browser-connection\.json|audit-export\.jsonl" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$chart = Get-Content "helm/vdiforge/Chart.yaml" -Raw
$chartVersion = if ($chart -match "(?m)^version:\s+([0-9]+\.[0-9]+\.[0-9]+)") { [version]$Matches[1] } else { $null }
$appVersion = if ($chart -match "(?m)^appVersion:\s+`"?([0-9]+\.[0-9]+\.[0-9]+)`"?") { [version]$Matches[1] } else { $null }
$phase12Baseline = [version]"0.12.0"
if ($chartVersion -and $appVersion -and $chartVersion -ge $phase12Baseline -and $appVersion -ge $phase12Baseline) {
    Pass "Helm chart version remains at or above the Phase 12 baseline"
} else {
    Fail "Helm chart version/appVersion is below the Phase 12 baseline"
}

$pyproject = Get-Content "backend/pyproject.toml" -Raw
$backendVersion = if ($pyproject -match '(?m)^version = "([0-9]+\.[0-9]+\.[0-9]+)"') { [version]$Matches[1] } else { $null }
if ($backendVersion -and $backendVersion -ge $phase12Baseline) {
    Pass "backend package version remains at or above the Phase 12 baseline"
} else {
    Fail "backend package version is below the Phase 12 baseline"
}

Check-ContentPresent "backend/app/api/routes.py" "RATE_LIMIT_EXCEEDED" "API implements high-impact operation rate limiting"
Check-ContentPresent "backend/app/api/routes.py" "/audit-events/export" "API exposes admin audit JSON Lines export"
Check-ContentPresent "backend/app/audit/service.py" "compute_audit_event_hash" "audit service computes tamper-evident hashes"
Check-ContentPresent "backend/app/observability/logging.py" "redact_text" "application logging uses centralized redaction"
Check-ContentPresent "backend/app/schemas/api.py" "display_name_must_be_safe_text" "desktop request model rejects unsafe display-name text"
Check-ContentPresent "frontend/src/auth/oidc.ts" "sessionStorage" "portal uses sessionStorage for OIDC state"

$frontendAuth = Get-Content "frontend/src/auth/oidc.ts" -Raw
if ($frontendAuth -notmatch "localStorage" -and $frontendAuth -notmatch "client_secret") {
    Pass "frontend OIDC configuration avoids localStorage and client secrets"
} else {
    Fail "frontend OIDC configuration uses localStorage or a client secret"
}

$realm = Get-Content "helm/vdiforge/files/keycloak/vdiforge-realm.json" -Raw
if ($realm -match '"bruteForceProtected": true' -and
    $realm -match '"implicitFlowEnabled": false' -and
    $realm -match '"pkce\.code\.challenge\.method": "S256"' -and
    $realm -notmatch '"redirectUris":\s*\[[^\]]*"\*"') {
    Pass "Keycloak realm keeps PKCE, disables implicit flow, and enables brute-force protection"
} else {
    Fail "Keycloak realm hardening is incomplete"
}

$rbac = Get-Content "helm/vdiforge/templates/rbac.yaml" -Raw
if ($rbac -match "cluster-admin|resources:\s*\[\s*`"\*`"\s*\]|verbs:\s*\[\s*`"\*`"\s*\]") {
    Fail "Helm RBAC contains broad wildcard or cluster-admin permissions"
} else {
    Pass "Helm RBAC avoids cluster-admin and wildcard permissions"
}

$values = Get-Content "helm/vdiforge/values.yaml" -Raw
if ($values -match "securityHeaders:" -and $values -match "desktopMutation:" -and $values -match "desktopConnect:") {
    Pass "Helm values define security headers and rate-limit configuration"
} else {
    Fail "Helm values are missing security header or rate-limit configuration"
}

$monitoringValues = Get-Content "monitoring/kube-prometheus-stack-values-local.yaml" -Raw
if ($monitoringValues -match "vdiforge-grafana-security-headers" -and $monitoringValues -match "strict_transport_security:\s+true" -and $monitoringValues -match "allow_embedding:\s+false") {
    Pass "Grafana local values include security-header middleware and security settings"
} else {
    Fail "Grafana local values are missing Phase 12 security settings"
}

if (Get-Command helm -ErrorAction SilentlyContinue) {
    $valueArgs = @(
        "--values", "./helm/vdiforge/values-local.yaml",
        "--values", "./helm/vdiforge/values-phase5-local.yaml",
        "--values", "./helm/vdiforge/values-phase7-local.yaml",
        "--values", "./helm/vdiforge/values-phase8-local.yaml",
        "--values", "./helm/vdiforge/values-phase9-local.yaml",
        "--values", "./helm/vdiforge/values-phase10-local.yaml",
        "--values", "./helm/vdiforge/values-phase11-local.yaml",
        "--values", "./helm/vdiforge/values-phase12-local.yaml"
    )

    helm lint ./helm/vdiforge @valueArgs
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 12 values" } else { Fail "helm lint with Phase 12 values" }

    New-Item -ItemType Directory -Force -Path ".local/phase12" | Out-Null
    $renderedPath = ".local/phase12/rendered-phase12.yaml"
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system @valueArgs --kube-version 1.36.4 > $renderedPath
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 12 values" } else { Fail "helm template with Phase 12 values" }

    $rendered = Get-Content $renderedPath -Raw
    if ($rendered -match "kind:\s+Middleware" -and $rendered -match "contentSecurityPolicy" -and $rendered -match "VDIFORGE_API_RATE_LIMIT_ENABLED") {
        Pass "rendered Phase 12 middleware and API rate-limit resources exist"
    } else {
        Fail "rendered Phase 12 middleware or API rate-limit configuration missing"
    }
    foreach ($ingressName in @("vdiforge-frontend", "vdiforge-api", "vdiforge-keycloak", "vdiforge-guacamole")) {
        if (Rendered-DocHasIngressMiddleware $rendered $ingressName) {
            Pass "rendered Ingress $ingressName has security middleware"
        } else {
            Fail "rendered Ingress $ingressName is missing security middleware"
        }
    }
    if (Rendered-ServiceHasMiddleware $rendered) {
        Fail "rendered Service resources contain Ingress-only middleware annotations"
    } else {
        Pass "middleware annotations are limited to Ingress resources"
    }
    if ($rendered -match "cluster-admin|ClusterRoleBinding") {
        Fail "rendered unsafe RBAC"
    } else {
        Pass "rendered RBAC has no cluster-admin"
    }
    if ($rendered -match "nodeName:") {
        Fail "rendered manifests hardcode direct nodeName scheduling"
    } else {
        Pass "rendered manifests avoid direct nodeName scheduling"
    }
    if ($rendered -match "(?im)^\s*(admin-password|GRAFANA_ADMIN_PASSWORD|KEYCLOAK_ADMIN_PASSWORD|KEYCLOAK_DB_PASSWORD|VDIFORGE_APP_DB_PASSWORD|JSON_SECRET_KEY|password):\s+[A-Za-z0-9_./+=-]{8,}\s*$") {
        Fail "rendered manifests contain plaintext secrets"
    } else {
        Pass "rendered manifests contain no plaintext secrets"
    }
} else {
    Warn "helm is not installed on this Windows host; Helm render should run on vdi-control-01."
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/phase12-api-security-test.py
    if ($LASTEXITCODE -eq 0) { Pass "Phase 12 Python helper compiles" } else { Fail "Phase 12 Python helper compiles" }

    $venv = ".local/phase12/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase12/tmp-$PID")).Path
    $env:TMP = $tmpRoot
    $env:TEMP = $tmpRoot
    $env:PYTEST_DEBUG_TEMPROOT = $tmpRoot
    Push-Location backend
    & $python -m ruff check app tests
    if ($LASTEXITCODE -eq 0) { Pass "ruff check backend" } else { Fail "ruff check backend" }
    & $python -m pytest --basetemp (Join-Path $tmpRoot "pytest")
    if ($LASTEXITCODE -eq 0) { Pass "backend pytest" } else { Fail "backend pytest" }
    Pop-Location
} else {
    Warn "python is not installed on this Windows host; Python checks skipped."
}

if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
    npm.cmd --prefix frontend audit --audit-level=high --omit=optional
    if ($LASTEXITCODE -eq 0) {
        Pass "frontend npm audit high threshold"
    } else {
        Warn "frontend npm audit reported advisories; review Phase 12 scan output"
    }
} else {
    Warn "npm is not installed on this Windows host; dependency scan should run on vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB|HPA|MON)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

if ($requirements -match "SEC-017" -and $requirements -match "SEC-032" -and $requirements -match "## Phase 12 Traceability") {
    Pass "Phase 12 security requirements and traceability are defined"
} else {
    Fail "Phase 12 security requirements or traceability are incomplete"
}

foreach ($doc in @(
    "docs/SECURITY-HARDENING.md",
    "docs/SECURITY.md",
    "docs/API-CONTROL-PLANE.md",
    "docs/REMOTE-DESKTOP.md",
    "docs/WEB-PORTAL.md",
    "docs/OBSERVABILITY.md",
    "docs/RUNBOOK.md",
    "docs/ROADMAP.md"
)) {
    if (Test-Path $doc) {
        $content = Get-Content $doc -Raw
        if ($content -match "Phase 12" -or $content -match "security hardening") {
            Pass "Phase 12 documentation present in $doc"
        } else {
            Fail "Phase 12 documentation missing in $doc"
        }
    }
}

if ($Live) {
    Write-Host "Running Phase 12 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase12-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 12 live validation" } else { Fail "Phase 12 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 12 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 12 validation: PASS" -ForegroundColor Green
