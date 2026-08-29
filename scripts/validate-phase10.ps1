param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase10-validation"
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

Write-Host "VDIForge Phase 10 static validation"

$requiredFiles = @(
    "backend/app/api/routes.py",
    "backend/app/config/settings.py",
    "backend/tests/test_api_authorization.py",
    "helm/vdiforge/templates/hpa.yaml",
    "helm/vdiforge/values-phase10-local.yaml",
    "scripts/load-test-api.py",
    "scripts/validate-phase10.ps1",
    "scripts/validate-phase10-live.sh",
    "docs/AUTOSCALING.md",
    "docs/API-CONTROL-PLANE.md",
    "docs/HELM-PLATFORM.md",
    "docs/ADR/0020-api-hpa-and-provisioner-scaling-boundary.md"
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

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-|terraform\.tfstate|\.kubeconfig$|phase[0-9]+\.env|\.key$|browser-connection\.json" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated artifacts or credentials are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated artifacts or credentials are tracked"
}

$chart = Get-Content "helm/vdiforge/Chart.yaml" -Raw
$chartVersion = if ($chart -match "(?m)^version:\s+([0-9]+\.[0-9]+\.[0-9]+)") { [version]$Matches[1] } else { $null }
$appVersion = if ($chart -match "(?m)^appVersion:\s+`"?([0-9]+\.[0-9]+\.[0-9]+)`"?") { [version]$Matches[1] } else { $null }
$phase10Baseline = [version]"0.10.0"
if ($chartVersion -and $appVersion -and $chartVersion -ge $phase10Baseline -and $appVersion -ge $phase10Baseline) {
    Pass "Helm chart version remains at or above the Phase 10 baseline"
} else {
    Fail "Helm chart version/appVersion is below the Phase 10 baseline"
}

$values = Get-Content "helm/vdiforge/values.yaml" -Raw
$phase10Values = Get-Content "helm/vdiforge/values-phase10-local.yaml" -Raw
$hpaTemplate = Get-Content "helm/vdiforge/templates/hpa.yaml" -Raw
$apiTemplate = Get-Content "helm/vdiforge/templates/api.yaml" -Raw
$routes = Get-Content "backend/app/api/routes.py" -Raw
$loadScript = Get-Content "scripts/load-test-api.py" -Raw

if ($values -match "api:\s+[\s\S]*loadTest:\s+[\s\S]*enabled:\s+false" -and $phase10Values -match "loadTest:\s+[\s\S]*enabled:\s+true" -and $phase10Values -match 'maxIterations:\s+"1500000"') {
    Pass "load-test endpoint is disabled by default and enabled only by Phase 10 values"
} else {
    Fail "load-test endpoint values are not safely gated"
}

if ($hpaTemplate -match "apiVersion:\s+autoscaling/v2" -and $hpaTemplate -match "kind:\s+HorizontalPodAutoscaler" -and $hpaTemplate -match "scaleTargetRef:" -and $hpaTemplate -match "averageUtilization") {
    Pass "API HPA template uses autoscaling/v2 and CPU utilization"
} else {
    Fail "API HPA template is incomplete"
}

if ($apiTemplate -match "if not \.Values\.api\.autoscaling\.enabled" -and $apiTemplate -match "VDIFORGE_LOAD_TEST_ENABLED") {
    Pass "API deployment supports HPA ownership and load-test settings"
} else {
    Fail "API deployment does not support HPA ownership or load-test settings"
}

if ($routes -match "/health/load-test" -and $routes -match "Depends\(get_current_user\)" -and $routes -match "LOAD_TEST_DISABLED") {
    Pass "safe authenticated load-test endpoint is implemented"
} else {
    Fail "safe authenticated load-test endpoint is missing"
}

if ($loadScript -match "method=`"GET`"" -and $loadScript -notmatch "POST.*/api/v1/desktops") {
    Pass "load generator uses safe GET requests and does not create desktops"
} else {
    Fail "load generator appears to use an unsafe desktop-creation path"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/load-test-api.py
    if ($LASTEXITCODE -eq 0) { Pass "Phase 10 load-test Python script compiles" } else { Fail "Phase 10 load-test Python script compiles" }

    $venv = ".local/phase10/static-venv"
    if (-not (Test-Path $venv)) {
        python -m venv $venv
    }
    $python = (Resolve-Path (Join-Path $venv "Scripts/python.exe")).Path
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail "pip upgrade" }
    & $python -m pip install -r backend/requirements-dev.txt
    if ($LASTEXITCODE -ne 0) { Fail "backend dependency installation" }
    $tmpRoot = (Resolve-Path (New-Item -ItemType Directory -Force -Path ".local/phase10/tmp-$PID")).Path
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

if (Get-Command helm -ErrorAction SilentlyContinue) {
    $valueArgs = @(
        "--values", "./helm/vdiforge/values-local.yaml",
        "--values", "./helm/vdiforge/values-phase5-local.yaml",
        "--values", "./helm/vdiforge/values-phase7-local.yaml",
        "--values", "./helm/vdiforge/values-phase8-local.yaml",
        "--values", "./helm/vdiforge/values-phase9-local.yaml",
        "--values", "./helm/vdiforge/values-phase10-local.yaml"
    )

    helm lint ./helm/vdiforge @valueArgs
    if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 10 values" } else { Fail "helm lint with Phase 10 values" }

    New-Item -ItemType Directory -Force -Path ".local/phase10" | Out-Null
    $renderedPhase9 = ".local/phase10/rendered-phase9.yaml"
    $renderedPhase10 = ".local/phase10/rendered-phase10.yaml"
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --values ./helm/vdiforge/values-phase8-local.yaml --values ./helm/vdiforge/values-phase9-local.yaml --kube-version 1.36.4 > $renderedPhase9
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 9 values" } else { Fail "helm template with Phase 9 values" }
    helm template vdiforge ./helm/vdiforge --namespace vdiforge-system @valueArgs --kube-version 1.36.4 > $renderedPhase10
    if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 10 values" } else { Fail "helm template with Phase 10 values" }

    $phase9Text = Get-Content $renderedPhase9 -Raw
    $phase10Text = Get-Content $renderedPhase10 -Raw
    if ($phase9Text -notmatch "kind:\s+HorizontalPodAutoscaler" -and $phase10Text -match "apiVersion:\s+autoscaling/v2[\s\S]*kind:\s+HorizontalPodAutoscaler[\s\S]*name:\s+vdiforge-api") {
        Pass "HPA renders only when Phase 10 values are enabled"
    } else {
        Fail "HPA disabled/enabled rendering is incorrect"
    }
    if ($phase10Text -match "maxReplicas:\s+3" -and $phase10Text -match "minReplicas:\s+1" -and $phase10Text -match "averageUtilization:\s+50") {
        Pass "rendered API HPA has expected local-lab min/max/CPU target"
    } else {
        Fail "rendered API HPA does not have expected local-lab settings"
    }
    if ($phase10Text -match "kind:\s+HorizontalPodAutoscaler[\s\S]{0,400}name:\s+vdiforge-provisioner") {
        Fail "provisioner HPA rendered despite deferred scaling decision"
    } else {
        Pass "provisioner HPA is omitted"
    }
    if ($phase10Text -match "requests:\s+[\s\S]*cpu:\s+100m" -and $phase10Text -match "VDIFORGE_LOAD_TEST_ENABLED") {
        Pass "rendered API resources include CPU requests and load-test environment"
    } else {
        Fail "rendered API resource requests/load-test environment missing"
    }
    if ($phase10Text -match "cluster-admin|ClusterRoleBinding") {
        Fail "rendered unsafe RBAC"
    } else {
        Pass "rendered RBAC has no cluster-admin"
    }
    if ($phase10Text -match "vdi-control-01|vdi-worker-01|vdi-worker-02") {
        Fail "rendered manifests hardcode node names"
    } else {
        Pass "rendered manifests avoid hardcoded node names"
    }
    if ($phase10Text -match "(?im)^\s*(password|JSON_SECRET_KEY|client_secret):\s+[A-Za-z0-9_./+=-]{16,}\s*$") {
        Fail "rendered manifests contain a plaintext credential value"
    } else {
        Pass "rendered manifests contain no plaintext credential values"
    }
} else {
    Warn "helm is not installed on this Windows host; live validation renders with Helm on vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB|HPA)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$hpaIds = $definitionIds | Where-Object { $_ -like "HPA-*" }
if ($hpaIds.Count -ge 12 -and $requirements -match "## Phase 10 Traceability") {
    Pass "Phase 10 autoscaling requirements and traceability are defined"
} else {
    Fail "Phase 10 autoscaling requirements or traceability are incomplete"
}

foreach ($doc in @("docs/AUTOSCALING.md", "docs/HELM-PLATFORM.md", "docs/API-CONTROL-PLANE.md", "docs/RUNBOOK.md", "docs/ROADMAP.md")) {
    $content = Get-Content $doc -Raw
    if ($content -match "Phase 10" -and $content -match "HPA") {
        Pass "Phase 10 documentation present in $doc"
    } else {
        Fail "Phase 10 documentation missing in $doc"
    }
}

if ($Live) {
    Write-Host "Running Phase 10 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase10-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 10 live validation" } else { Fail "Phase 10 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 10 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 10 validation: PASS" -ForegroundColor Green
