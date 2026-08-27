param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin"
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

function Check-ContentAbsent($Root, $Pattern, $Description) {
    $items = if (Test-Path $Root -PathType Leaf) {
        @(Get-Item $Root)
    } else {
        @(Get-ChildItem $Root -File -Recurse)
    }

    $matches = $items |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\scripts\\validate-phase4\.ps1$" } |
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

Write-Host "VDIForge Phase 4 static validation"

$requiredFiles = @(
    "helm/vdiforge/Chart.yaml",
    "helm/vdiforge/values.yaml",
    "helm/vdiforge/values-local.yaml",
    "helm/vdiforge/templates/_helpers.tpl",
    "helm/vdiforge/templates/configmap.yaml",
    "helm/vdiforge/templates/serviceaccounts.yaml",
    "helm/vdiforge/templates/rbac.yaml",
    "helm/vdiforge/templates/resourcequota.yaml",
    "helm/vdiforge/templates/limitrange.yaml",
    "helm/vdiforge/templates/networkpolicies.yaml",
    "helm/vdiforge/README.md",
    "scripts/install-helm-client.sh",
    "scripts/validate-phase4-live.sh",
    "scripts/validate-phase4.ps1",
    "README.md",
    "docs/HELM-PLATFORM.md",
    "docs/REQUIREMENTS.md",
    "docs/ROADMAP.md",
    "docs/RUNBOOK.md",
    "docs/SECURITY.md",
    "docs/TESTING.md",
    "docs/ADR/0006-helm-application-deployment.md",
    "docs/ADR/0011-helm-platform-ownership.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

Check-ContentAbsent "helm/vdiforge" "BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY" "private key material in Helm chart"
Check-ContentAbsent "helm/vdiforge" "client-secret|client_secret|refresh_token|id_token|access_token" "OAuth/token secret in Helm chart"
Check-ContentAbsent "helm/vdiforge" 'password:\s*[^"''<{#\s][^#\r\n]+' "plaintext password in Helm chart"
Check-ContentAbsent "helm/vdiforge/templates" "cluster-admin|ClusterRoleBinding" "cluster-admin or ClusterRoleBinding in Helm templates"
Check-ContentAbsent "helm/vdiforge/templates" "vdi-control-01|vdi-worker-01|vdi-worker-02" "hardcoded node name in Helm templates"

$templateFiles = Get-ChildItem "helm/vdiforge/templates" -File -Recurse
$labelMatches = $templateFiles | Select-String -Pattern "app\.kubernetes\.io/name|app\.kubernetes\.io/managed-by|helm\.sh/chart" -ErrorAction SilentlyContinue
if ($labelMatches) {
    Pass "Helm templates include recommended labels"
} else {
    Fail "Helm templates are missing recommended label helpers"
}

$chartYaml = Get-Content "helm/vdiforge/Chart.yaml" -Raw
if ($chartYaml -match '(?m)^version:\s*\d+\.\d+\.\d+\s*$' -and $chartYaml -match 'kubeVersion:\s*">=1\.36\.0-0 <1\.37\.0-0"') {
    Pass "Chart version and Kubernetes compatibility are pinned"
} else {
    Fail "Chart version or Kubernetes compatibility pin missing"
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$helmIds = $definitionIds | Where-Object { $_ -like "HELM-*" }
if ($helmIds.Count -ge 10) {
    Pass "Phase 4 Helm requirements are defined"
} else {
    Fail "Expected at least 10 HELM-* requirements, found $($helmIds.Count)"
}

$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$roadmap = Get-Content "docs/ROADMAP.md" -Raw
if ($roadmap -match "\|\s*4\s*\|\s*Helm/platform foundation\s*\|\s*Complete\s*\|") {
    Pass "roadmap marks Phase 4 complete"
} else {
    Fail "roadmap does not mark Phase 4 complete"
}

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm lint ./helm/vdiforge
    if ($LASTEXITCODE -eq 0) { Pass "local helm lint" } else { Fail "local helm lint" }

    $rendered = helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --kube-version 1.36.4
    if ($LASTEXITCODE -eq 0) {
        Pass "local helm template"
        $renderedText = $rendered -join "`n"
        if ($renderedText -match "(?m)^kind:\s*(Deployment|StatefulSet|DaemonSet|VirtualMachine)\s*$") {
            Fail "Phase 4 local values render out-of-scope workload kinds"
        } else {
            Pass "Phase 4 local values render no application workload kinds"
        }
    } else {
        Fail "local helm template"
    }
} else {
    Warn "helm is not installed on this Windows host; live validation runs Helm from vdi-control-01."
}

if ($Live) {
    Write-Host "Running Phase 4 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd ~/vdiforge-phase4-validation && bash scripts/validate-phase4-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 4 live validation" } else { Fail "Phase 4 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 4 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 4 validation: PASS" -ForegroundColor Green
