param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase9-validation"
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

function Invoke-Check($Description, $ScriptBlock) {
    & $ScriptBlock
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
        Pass $Description
    } else {
        Fail $Description
    }
}

Write-Host "VDIForge Phase 9 static validation"

$requiredFiles = @(
    "frontend/package.json",
    "frontend/package-lock.json",
    "frontend/index.html",
    "frontend/Dockerfile",
    "frontend/nginx.conf",
    "frontend/src/App.tsx",
    "frontend/src/auth/AuthProvider.tsx",
    "frontend/src/auth/oidc.ts",
    "frontend/src/api/client.ts",
    "frontend/src/components/PortalApp.tsx",
    "frontend/src/utils/status.ts",
    "frontend/tests/portal.test.tsx",
    "frontend/tests/api-client.test.ts",
    "frontend/e2e/portal-live.spec.ts",
    "helm/vdiforge/templates/frontend.yaml",
    "helm/vdiforge/values-phase9-local.yaml",
    "scripts/phase9-create-local-secrets.sh",
    "scripts/phase9-build-load-frontend-image.sh",
    "scripts/phase9-portal-e2e-test.py",
    "scripts/validate-phase9.ps1",
    "scripts/validate-phase9-live.sh",
    "docs/WEB-PORTAL.md",
    "docs/ADR/0019-react-portal-runtime-configuration.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----$" "private key material"
Check-ContentAbsent $repoFiles "(?m)^-----BEGIN PRIVATE KEY-----$" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"
Check-ContentAbsent $repoFiles "(?im)^\s*(xrdp_password|guacamole_admin_password|json_secret_key|rdp_password)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "remote desktop credential"
Check-ContentAbsent (Get-ChildItem frontend/src -File -Recurse) "console\.(log|debug|info|warn|error)\([^)]*(token|access_token|refresh_token)" "browser token logging"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$|phase[0-9]+\.env|\.key$|browser-connection\.json" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$frontendPackage = Get-Content "frontend/package.json" -Raw | ConvertFrom-Json
$deps = @{}
$frontendPackage.dependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value }
$frontendPackage.devDependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value }

$expectedPins = @{
    "react" = "19.2.8"
    "react-dom" = "19.2.8"
    "vite" = "8.2.2"
    "typescript" = "6.0.3"
    "oidc-client-ts" = "3.5.0"
    "@playwright/test" = "1.62.1"
}

foreach ($pin in $expectedPins.GetEnumerator()) {
    if ($deps[$pin.Key] -eq $pin.Value) {
        Pass "frontend dependency pin present: $($pin.Key)@$($pin.Value)"
    } else {
        Fail "frontend dependency pin missing: $($pin.Key)@$($pin.Value)"
    }
}

$chart = Get-Content "helm/vdiforge/Chart.yaml" -Raw
if ($chart -match "version:\s+0\.(9|10)\.0" -and $chart -match "appVersion:\s+`"0\.(9|10)\.0`"") {
    Pass "Helm chart version remains at or above the Phase 9 baseline"
} else {
    Fail "Helm chart version/appVersion is below the Phase 9 baseline"
}

$phase9Values = Get-Content "helm/vdiforge/values-phase9-local.yaml" -Raw
$values = Get-Content "helm/vdiforge/values.yaml" -Raw
$frontendTemplate = Get-Content "helm/vdiforge/templates/frontend.yaml" -Raw
if ($phase9Values -match "frontend:\s+[\s\S]*enabled:\s+true" -and $phase9Values -match "vdiforge\.local") {
    Pass "Phase 9 local values enable the portal endpoint"
} else {
    Fail "Phase 9 local values do not enable the portal endpoint"
}
if ($values -match "allowIngressToFrontend" -and $frontendTemplate -match "automountServiceAccountToken" -and $frontendTemplate -match "readOnlyRootFilesystem") {
    Pass "frontend Helm template includes network/RBAC/security foundations"
} else {
    Fail "frontend Helm security foundation is incomplete"
}
if ($frontendTemplate -match "vdi-control-01|vdi-worker-01|vdi-worker-02") {
    Fail "frontend template hardcodes node names"
} else {
    Pass "frontend template uses placement labels instead of node names"
}

$catalog = Get-Content "images/catalog.json" -Raw | ConvertFrom-Json
$phase9Devops = $catalog.images |
    Where-Object { $_.id -eq "ubuntu-devops" } |
    ForEach-Object { $_.versions } |
    Where-Object { $_.version -eq "1.2.0" -and $_.lifecycle -eq "available" -and $_.sourcePvcName -eq "vdiforge-golden-ubuntu-devops-1-2-0" }
if ($phase9Devops) {
    Pass "ubuntu-devops:1.2.0 is launchable and references the Phase 9 source PVC"
} else {
    Fail "ubuntu-devops:1.2.0 is not launchable or lacks the Phase 9 sourcePvcName"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/phase9-portal-e2e-test.py
    if ($LASTEXITCODE -eq 0) { Pass "Phase 9 Python E2E script compiles" } else { Fail "Phase 9 Python E2E script compiles" }

    python scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog policy validation" } else { Fail "image catalog policy validation" }

    $venv = ".local/phase9/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase9/tmp-$PID")).Path
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
    Warn "python is not installed on this Windows host; backend/static Python checks skipped."
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    Push-Location frontend
    npm.cmd run lint
    if ($LASTEXITCODE -eq 0) { Pass "frontend lint" } else { Fail "frontend lint" }
    npm.cmd run test:run
    if ($LASTEXITCODE -eq 0) { Pass "frontend unit/component tests" } else { Fail "frontend unit/component tests" }
    npm.cmd run build
    if ($LASTEXITCODE -eq 0) { Pass "frontend production build" } else { Fail "frontend production build" }
    Pop-Location
} else {
    Warn "npm is not installed on this Windows host; frontend checks skipped."
}

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm lint ./helm/vdiforge --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --values ./helm/vdiforge/values-phase8-local.yaml --values ./helm/vdiforge/values-phase9-local.yaml
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 9 values" } else { Fail "helm lint with Phase 9 values" }
    $rendered = ".local/phase9/rendered.yaml"
    New-Item -ItemType Directory -Force -Path ".local/phase9" | Out-Null
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --values ./helm/vdiforge/values-phase8-local.yaml --values ./helm/vdiforge/values-phase9-local.yaml --kube-version 1.36.4 > $rendered
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 9 values" } else { Fail "helm template with Phase 9 values" }
    $renderedText = Get-Content $rendered -Raw
    if ($renderedText -match "cluster-admin|ClusterRoleBinding") { Fail "rendered unsafe RBAC" } else { Pass "rendered RBAC has no cluster-admin" }
    if ($renderedText -match "vdi-control-01|vdi-worker-01|vdi-worker-02") { Fail "rendered manifests hardcode node names" } else { Pass "rendered manifests avoid hardcoded node names" }
    if ($renderedText -match "kind:\s+Deployment[\s\S]*name:\s+vdiforge-frontend" -and $renderedText -match "host:\s+vdiforge\.local") {
        Pass "rendered manifests include the frontend deployment and ingress"
    } else {
        Fail "rendered manifests do not include the frontend deployment and ingress"
    }
    if ($renderedText -match "(?im)^\s*(password|JSON_SECRET_KEY|client_secret):\s+[A-Za-z0-9_./+=-]{16,}\s*$") {
        Fail "rendered manifests contain a plaintext credential value"
    } else {
        Pass "rendered manifests contain no plaintext credential values"
    }
} else {
    Warn "helm is not installed on this Windows host; live validation renders with Helm on vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$webIds = $definitionIds | Where-Object { $_ -like "WEB-*" }
if ($webIds.Count -ge 16) {
    Pass "Phase 9 web portal requirements are defined"
} else {
    Fail "Expected at least 16 WEB-* requirements, found $($webIds.Count)"
}

if ($Live) {
    Write-Host "Running Phase 9 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase9-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 9 live validation" } else { Fail "Phase 9 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 9 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 9 validation: PASS" -ForegroundColor Green
