param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase11-validation"
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
    $matches = $Paths |
        Select-String -Pattern $Pattern -ErrorAction SilentlyContinue

    if ($matches) {
        Fail "$Description found"
        $matches | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $($_.Path):$($_.LineNumber)"
        }
    } else {
        Pass "$Description not found"
    }
}

Write-Host "VDIForge Phase 11 static validation"

$requiredFiles = @(
    "backend/app/observability/metrics.py",
    "backend/tests/test_metrics.py",
    "helm/vdiforge/templates/servicemonitors.yaml",
    "helm/vdiforge/templates/prometheusrules.yaml",
    "helm/vdiforge/templates/grafana-dashboard.yaml",
    "helm/vdiforge/values-phase11-local.yaml",
    "monitoring/kube-prometheus-stack-values-local.yaml",
    "monitoring/grafana/vdiforge-overview.json",
    "helm/vdiforge/files/grafana/vdiforge-overview.json",
    "scripts/phase11-create-local-secrets.sh",
    "scripts/phase11-install-monitoring.sh",
    "scripts/validate-phase11.ps1",
    "scripts/validate-phase11-live.sh",
    "docs/PROMETHEUS-GRAFANA.md",
    "docs/ADR/0021-kube-prometheus-stack-observability.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"
Check-ContentAbsent $repoFiles "(?im)^\s*(admin-password|GRAFANA_ADMIN_PASSWORD|grafana_admin_password)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "Grafana credential"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$|phase[0-9]+\.env|\.key$|browser-connection\.json" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$metrics = Get-Content "backend/app/observability/metrics.py" -Raw
$requiredMetrics = @(
    "vdiforge_api_requests_total",
    "vdiforge_api_request_duration_seconds",
    "vdiforge_desktop_provision_requests_total",
    "vdiforge_desktop_provision_failures_total",
    "vdiforge_desktop_provision_duration_seconds",
    "vdiforge_desktops_active",
    "vdiforge_desktops_by_state",
    "vdiforge_remote_sessions_active",
    "vdiforge_provisioner_reconcile_total",
    "vdiforge_provisioner_reconcile_failures_total",
    "vdiforge_provisioner_reconcile_duration_seconds",
    "vdiforge_provisioner_pending_operations"
)
foreach ($metric in $requiredMetrics) {
    if ($metrics -match [regex]::Escape($metric)) {
        Pass "metric defined: $metric"
    } else {
        Fail "metric missing: $metric"
    }
}

if ($metrics -notmatch '"request_id"|"user_id"|"username"|"desktop_id"|"subject"|"token"|"connection_id"') {
    Pass "application metrics avoid forbidden high-cardinality labels"
} else {
    Fail "application metrics include forbidden high-cardinality labels"
}

$chart = Get-Content "helm/vdiforge/Chart.yaml" -Raw
if ($chart -match "version:\s+0\.11\.0" -and $chart -match "appVersion:\s+`"0\.11\.0`"") {
    Pass "Helm chart version advanced to 0.11.0"
} else {
    Fail "Helm chart version/appVersion is not 0.11.0"
}

$pyproject = Get-Content "backend/pyproject.toml" -Raw
if ($pyproject -match 'prometheus-client==0\.23\.1' -and $pyproject -match 'version = "0\.11\.0"') {
    Pass "backend package includes prometheus-client and version 0.11.0"
} else {
    Fail "backend package version or prometheus-client dependency missing"
}

$dash = Get-Content "monitoring/grafana/vdiforge-overview.json" -Raw | ConvertFrom-Json
if ($dash.title -eq "VDIForge Overview" -and $dash.panels.Count -ge 12) {
    Pass "Grafana dashboard JSON is valid and has expected panels"
} else {
    Fail "Grafana dashboard JSON is incomplete"
}

$dashboardSource = Get-Content "monitoring/grafana/vdiforge-overview.json" -Raw
$dashboardChart = Get-Content "helm/vdiforge/files/grafana/vdiforge-overview.json" -Raw
if ($dashboardSource -eq $dashboardChart) {
    Pass "chart-packaged dashboard matches monitoring/grafana source"
} else {
    Fail "chart-packaged dashboard differs from monitoring/grafana source"
}

$phase11Values = Get-Content "helm/vdiforge/values-phase11-local.yaml" -Raw
$monitoringValues = Get-Content "monitoring/kube-prometheus-stack-values-local.yaml" -Raw
if ($phase11Values -match "serviceMonitor:\s+[\s\S]*enabled:\s+true" -and $phase11Values -match "prometheusRule:\s+[\s\S]*enabled:\s+true" -and $phase11Values -match "grafanaDashboard:\s+[\s\S]*enabled:\s+true") {
    Pass "Phase 11 values enable ServiceMonitor, PrometheusRule, and dashboard"
} else {
    Fail "Phase 11 values do not enable required monitoring resources"
}
if ($monitoringValues -match 'storageClassName:\s+vdiforge-local-path' -and $monitoringValues -match 'grafana.vdiforge.local' -and $monitoringValues -match 'existingSecret:\s+vdiforge-grafana-admin') {
    Pass "kube-prometheus-stack local values configure storage, ingress, and external Grafana admin Secret"
} else {
    Fail "kube-prometheus-stack local values are incomplete"
}
if ($monitoringValues -notmatch "(?im)^\s*(adminPassword|password|admin-password):\s+[A-Za-z0-9_./+=-]{8,}\s*$") {
    Pass "monitoring values contain no plaintext Grafana password"
} else {
    Fail "monitoring values contain a plaintext Grafana password"
}

$rendered = ""
if (Get-Command helm -ErrorAction SilentlyContinue) {
    $valueArgs = @(
        "--values", "./helm/vdiforge/values-local.yaml",
        "--values", "./helm/vdiforge/values-phase5-local.yaml",
        "--values", "./helm/vdiforge/values-phase7-local.yaml",
        "--values", "./helm/vdiforge/values-phase8-local.yaml",
        "--values", "./helm/vdiforge/values-phase9-local.yaml",
        "--values", "./helm/vdiforge/values-phase10-local.yaml",
        "--values", "./helm/vdiforge/values-phase11-local.yaml"
    )

    helm lint ./helm/vdiforge @valueArgs
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 11 values" } else { Fail "helm lint with Phase 11 values" }

    New-Item -ItemType Directory -Force -Path ".local/phase11" | Out-Null
    $renderedPath = ".local/phase11/rendered-phase11.yaml"
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system @valueArgs --kube-version 1.36.4 > $renderedPath
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 11 values" } else { Fail "helm template with Phase 11 values" }

    $rendered = Get-Content $renderedPath -Raw
    if ($rendered -match "kind:\s+ServiceMonitor" -and $rendered -match "kind:\s+PrometheusRule" -and $rendered -match "VDIForge Overview") {
        Pass "rendered monitoring resources exist"
    } else {
        Fail "rendered monitoring resources missing"
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
    if ($rendered -match "(?im)^\s*(admin-password|GRAFANA_ADMIN_PASSWORD|password):\s+[A-Za-z0-9_./+=-]{8,}\s*$") {
        Fail "rendered manifests contain plaintext secrets"
    } else {
        Pass "rendered manifests contain no plaintext secrets"
    }
} else {
    Warn "helm is not installed on this Windows host; Helm render should run on vdi-control-01."
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/load-test-api.py scripts/phase7-api-e2e-test.py scripts/phase8-remote-desktop-e2e-test.py
    if ($LASTEXITCODE -eq 0) { Pass "validation helper Python scripts compile" } else { Fail "validation helper Python scripts compile" }

    $venv = ".local/phase11/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase11/tmp-$PID")).Path
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

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB|HPA|MON)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

if ($requirements -match "## Phase 11 Traceability" -and ($definitionIds | Where-Object { $_ -like "MON-*" }).Count -ge 14) {
    Pass "Phase 11 monitoring requirements and traceability are defined"
} else {
    Fail "Phase 11 monitoring requirements or traceability are incomplete"
}

foreach ($doc in @("docs/PROMETHEUS-GRAFANA.md", "docs/OBSERVABILITY.md", "docs/HELM-PLATFORM.md", "docs/API-CONTROL-PLANE.md", "docs/RUNBOOK.md", "docs/ROADMAP.md")) {
    $content = Get-Content $doc -Raw
    if ($content -match "Phase 11" -and ($content -match "Prometheus" -or $content -match "Grafana")) {
        Pass "Phase 11 documentation present in $doc"
    } else {
        Fail "Phase 11 documentation missing in $doc"
    }
}

if ($Live) {
    Write-Host "Running Phase 11 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase11-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 11 live validation" } else { Fail "Phase 11 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 11 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 11 validation: PASS" -ForegroundColor Green
