param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase8-validation"
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
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
        Where-Object { $_.FullName -notmatch "\\artifacts\\" } |
        Where-Object { $_.FullName -notmatch "\\packer_cache\\" } |
        Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
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

Write-Host "VDIForge Phase 8 static validation"

$requiredFiles = @(
    "backend/app/services/remote_access.py",
    "backend/app/provisioning/kubevirt.py",
    "backend/app/api/routes.py",
    "backend/tests/test_remote_access.py",
    "helm/vdiforge/templates/guacamole.yaml",
    "helm/vdiforge/templates/guacamole-networkpolicies.yaml",
    "helm/vdiforge/values-phase8-local.yaml",
    "scripts/phase8-create-local-secrets.sh",
    "scripts/phase8-build-remote-image.sh",
    "scripts/phase8-prepare-remote-source.sh",
    "scripts/phase8-networkpolicy-test.sh",
    "scripts/phase8-remote-desktop-e2e-test.py",
    "scripts/validate-phase8.ps1",
    "scripts/validate-phase8-live.sh",
    "docs/REMOTE-DESKTOP.md",
    "docs/ADR/0018-guacamole-json-session-brokering.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"
Check-ContentAbsent $repoFiles "(?im)^\s*(xrdp_password|guacamole_admin_password|json_secret_key)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "remote desktop credential"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$|phase8\.env|\.key$" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$runtime = Get-Content "backend/requirements-runtime.txt" -Raw
foreach ($pin in @(
    "fastapi==0.141.1",
    "cryptography==50.0.1",
    "kubernetes==36.0.2",
    "psycopg[binary]==3.3.4"
)) {
    if ($runtime.Contains($pin)) {
        Pass "dependency pin present: $pin"
    } else {
        Fail "dependency pin missing: $pin"
    }
}

$chart = Get-Content "helm/vdiforge/Chart.yaml" -Raw
$chartVersion = if ($chart -match "(?m)^version:\s+([0-9]+\.[0-9]+\.[0-9]+)") { [version]$Matches[1] } else { $null }
$appVersion = if ($chart -match "(?m)^appVersion:\s+`"?([0-9]+\.[0-9]+\.[0-9]+)`"?") { [version]$Matches[1] } else { $null }
$phase8Baseline = [version]"0.8.0"
if ($chartVersion -and $appVersion -and $chartVersion -ge $phase8Baseline -and $appVersion -ge $phase8Baseline) {
    Pass "Helm chart version remains at or above the Phase 8 baseline"
} else {
    Fail "Helm chart version/appVersion is below the Phase 8 baseline"
}

$catalog = Get-Content "images/catalog.json" -Raw | ConvertFrom-Json
$remoteDevops = $catalog.images |
    Where-Object { $_.id -eq "ubuntu-devops" } |
    ForEach-Object { $_.versions } |
    Where-Object { $_.lifecycle -eq "available" -and $_.sourcePvcName }
if ($remoteDevops) {
    Pass "ubuntu-devops has a launchable remote-capable source PVC"
} else {
    Fail "ubuntu-devops has no launchable remote-capable source PVC"
}

$rbacText = Get-Content "helm/vdiforge/templates/rbac.yaml" -Raw
$valuesText = Get-Content "helm/vdiforge/values.yaml" -Raw
if ($rbacText -match "cluster-admin|ClusterRoleBinding") {
    Fail "unsafe cluster-admin style RBAC found"
} else {
    Pass "no cluster-admin or ClusterRoleBinding in VDIForge RBAC"
}
if (
    $rbacText -match "apiRemoteAccess\.enabled" -and
    $rbacText -match "resources:\s+[\s\S]*secrets[\s\S]*verbs:\s+[\s\S]*get" -and
    $rbacText -match "resources:\s+[\s\S]*services[\s\S]*verbs:\s+[\s\S]*get" -and
    $valuesText -match "roleName:\s+vdiforge-api-remote-session-reader"
) {
    Pass "API remote-session RBAC is present"
} else {
    Fail "API remote-session RBAC is missing"
}

$kubevirtText = Get-Content "backend/app/provisioning/kubevirt.py" -Raw
if ($kubevirtText -match "cloudInitNoCloud.*secretRef" -and $kubevirtText -match "token_urlsafe" -and $kubevirtText -match "delete_namespaced_secret") {
    Pass "per-desktop remote credential Secret lifecycle is implemented"
} else {
    Fail "remote credential Secret lifecycle implementation is incomplete"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog policy validation" } else { Fail "image catalog policy validation" }

    $venv = ".local/phase8/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase8/tmp-$PID")).Path
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
    Warn "python is not installed on this Windows host; live validation runs Python from Linux."
}

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm lint ./helm/vdiforge --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --values ./helm/vdiforge/values-phase8-local.yaml
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 8 values" } else { Fail "helm lint with Phase 8 values" }
    $rendered = ".local/phase8/rendered.yaml"
    New-Item -ItemType Directory -Force -Path ".local/phase8" | Out-Null
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --values ./helm/vdiforge/values-phase8-local.yaml --kube-version 1.36.4 > $rendered
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 8 values" } else { Fail "helm template with Phase 8 values" }
    $renderedText = Get-Content $rendered -Raw
    if ($renderedText -match "cluster-admin|ClusterRoleBinding") { Fail "rendered unsafe RBAC" } else { Pass "rendered RBAC has no cluster-admin" }
    if ($renderedText -match "vdi-control-01|vdi-worker-01|vdi-worker-02") { Fail "rendered manifests hardcode node names" } else { Pass "rendered manifests avoid hardcoded node names" }
    if ($renderedText -match "vdiforge-system-provisioner-to-desktop-rdp") {
        Pass "rendered manifests allow provisioner remote desktop readiness probes"
    } else {
        Fail "rendered manifests do not allow provisioner remote desktop readiness probes"
    }
    if ($renderedText -match "(?im)^\s*(password|JSON_SECRET_KEY):\s+[A-Za-z0-9_./+=-]{16,}\s*$") {
        Fail "rendered manifests contain a plaintext credential value"
    } else {
        Pass "rendered manifests contain no plaintext credential values"
    }
} else {
    Warn "helm is not installed on this Windows host; live validation renders with Helm on vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$rdpIds = $definitionIds | Where-Object { $_ -like "RDP-*" }
if ($rdpIds.Count -ge 10) {
    Pass "Phase 8 remote desktop requirements are defined"
} else {
    Fail "Expected at least 10 RDP-* requirements, found $($rdpIds.Count)"
}

if ($Live) {
    Write-Host "Running Phase 8 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase8-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 8 live validation" } else { Fail "Phase 8 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 8 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 8 validation: PASS" -ForegroundColor Green
