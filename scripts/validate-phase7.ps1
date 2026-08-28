param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase7-validation"
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

Write-Host "VDIForge Phase 7 static validation"

$requiredFiles = @(
    "backend/pyproject.toml",
    "backend/requirements-runtime.txt",
    "backend/requirements-dev.txt",
    "backend/Dockerfile",
    "backend/app/main.py",
    "backend/app/api/routes.py",
    "backend/app/auth/jwt.py",
    "backend/app/auth/policy.py",
    "backend/app/provisioning/reconciler.py",
    "backend/app/provisioning/kubevirt.py",
    "backend/alembic/versions/0001_phase7_initial.py",
    "helm/vdiforge/values-phase7-local.yaml",
    "helm/vdiforge/templates/api.yaml",
    "helm/vdiforge/templates/provisioner.yaml",
    "helm/vdiforge/templates/app-postgres.yaml",
    "helm/vdiforge/templates/migrations.yaml",
    "scripts/phase7-create-local-secrets.sh",
    "scripts/phase7-install-container-build-tools.sh",
    "scripts/phase7-build-load-image.sh",
    "scripts/phase7-prepare-golden-source.sh",
    "scripts/phase7-rbac-test.sh",
    "scripts/phase7-networkpolicy-test.sh",
    "scripts/phase7-api-e2e-test.py",
    "scripts/validate-phase7.ps1",
    "scripts/validate-phase7-live.sh",
    "docs/API-CONTROL-PLANE.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$runtime = Get-Content "backend/requirements-runtime.txt" -Raw
foreach ($pin in @(
    "fastapi==0.141.1",
    "SQLAlchemy==2.0.52",
    "PyJWT[crypto]==2.13.0",
    "kubernetes==36.0.2",
    "psycopg[binary]==3.3.4"
)) {
    if ($runtime.Contains($pin)) {
        Pass "dependency pin present: $pin"
    } else {
        Fail "dependency pin missing: $pin"
    }
}

$backendText = Get-ChildItem backend/app -File -Recurse | Select-String -Pattern "kubectl|virtctl|subprocess" -ErrorAction SilentlyContinue
if ($backendText) {
    Fail "backend app shell-out usage found"
    $backendText | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
} else {
    Pass "backend uses Kubernetes Python client rather than kubectl/virtctl shell-outs"
}

$rbacText = Get-Content "helm/vdiforge/templates/rbac.yaml" -Raw
if ($rbacText -match "cluster-admin|ClusterRoleBinding") {
    Fail "unsafe cluster-admin style RBAC found"
} else {
    Pass "no cluster-admin or ClusterRoleBinding in VDIForge RBAC"
}

$catalog = Get-Content "images/catalog.json" -Raw | ConvertFrom-Json
$availableDevops = $catalog.images |
    Where-Object { $_.id -eq "ubuntu-devops" } |
    ForEach-Object { $_.versions } |
    Where-Object { $_.version -eq "1.0.0" -and $_.lifecycle -eq "available" -and $_.sourcePvcName }
if ($availableDevops) {
    Pass "ubuntu-devops:1.0.0 is launchable and references a source PVC"
} else {
    Fail "ubuntu-devops:1.0.0 is not launchable or lacks sourcePvcName"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog policy validation" } else { Fail "image catalog policy validation" }

    $venv = ".local/phase7/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase7/tmp-$PID")).Path
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
    helm lint ./helm/vdiforge --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 7 values" } else { Fail "helm lint with Phase 7 values" }
    $rendered = ".local/phase7/rendered.yaml"
    New-Item -ItemType Directory -Force -Path ".local/phase7" | Out-Null
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --kube-version 1.36.4 > $rendered
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 7 values" } else { Fail "helm template with Phase 7 values" }
    $renderedText = Get-Content $rendered -Raw
    if ($renderedText -match "cluster-admin|ClusterRoleBinding") { Fail "rendered unsafe RBAC" } else { Pass "rendered RBAC has no cluster-admin" }
    if ($renderedText -match "vdi-control-01|vdi-worker-01|vdi-worker-02") { Fail "rendered manifests hardcode node names" } else { Pass "rendered manifests avoid hardcoded node names" }
} else {
    Warn "helm is not installed on this Windows host; live validation renders with Helm on vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$appIds = $definitionIds | Where-Object { $_ -like "APP-*" }
if ($appIds.Count -ge 12) {
    Pass "Phase 7 APP requirements are defined"
} else {
    Fail "Expected at least 12 APP-* requirements, found $($appIds.Count)"
}

if ($Live) {
    Write-Host "Running Phase 7 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase7-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 7 live validation" } else { Fail "Phase 7 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 7 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 7 validation: PASS" -ForegroundColor Green
