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
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    if ([regex]::IsMatch($content, $Pattern, $options)) {
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

function Get-Json($Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-VersionAtLeast($Value, $Minimum) {
    try {
        return ([version]$Value) -ge ([version]$Minimum)
    } catch {
        return $false
    }
}

Write-Host "VDIForge Phase 14 static validation"

$requiredFiles = @(
    "scripts/validate-phase14.ps1",
    "scripts/validate-phase14-live.sh",
    "scripts/phase14-prepare-demo-images.sh",
    "scripts/phase14-role-image-test.py",
    "helm/vdiforge/values-phase14-local.yaml",
    "docs/DEMO.md",
    "docs/PORTFOLIO-SUMMARY.md",
    "docs/INTERVIEW-TALKING-POINTS.md",
    "docs/LIMITATIONS.md",
    "docs/ADR/0024-final-demo-image-promotion.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

try {
    $catalog = Get-Json "images/catalog.json"
    $images = @($catalog.images)
    $expected = @{
        "ubuntu-base" = @{
            default = "1.0.0"
            source = "vdiforge-golden-ubuntu-base-1-0-0"
            roles = @("vdi-user", "vdi-developer", "vdi-devops", "vdi-admin")
        }
        "ubuntu-developer" = @{
            default = "1.0.0"
            source = "vdiforge-golden-ubuntu-developer-1-0-0"
            roles = @("vdi-developer", "vdi-devops", "vdi-admin")
        }
        "ubuntu-devops" = @{
            default = "1.2.0"
            source = "vdiforge-golden-ubuntu-devops-1-2-0"
            roles = @("vdi-devops", "vdi-admin")
        }
    }

    foreach ($imageId in $expected.Keys) {
        $image = $images | Where-Object { $_.id -eq $imageId } | Select-Object -First 1
        if (-not $image) {
            Fail "catalog includes $imageId"
            continue
        }
        Pass "catalog includes $imageId"

        if ($image.defaultVersion -eq $expected[$imageId].default) {
            Pass "$imageId default version is $($expected[$imageId].default)"
        } else {
            Fail "$imageId default version is $($expected[$imageId].default)"
        }

        $version = @($image.versions) | Where-Object { $_.version -eq $expected[$imageId].default } | Select-Object -First 1
        if ($version -and $version.lifecycle -eq "available" -and $version.sourcePvcName -eq $expected[$imageId].source) {
            Pass "$imageId launchable source PVC is configured"
        } else {
            Fail "$imageId launchable source PVC is configured"
        }

        $actualRoles = @($image.allowedRoles) | Sort-Object
        $expectedRoles = @($expected[$imageId].roles) | Sort-Object
        if (($actualRoles -join ",") -eq ($expectedRoles -join ",")) {
            Pass "$imageId allowed roles match the final demo RBAC model"
        } else {
            Fail "$imageId allowed roles match the final demo RBAC model"
        }
    }

    $devops = $images | Where-Object { $_.id -eq "ubuntu-devops" } | Select-Object -First 1
    $supersededLaunchable = @($devops.versions) | Where-Object {
        $_.version -in @("1.0.0", "1.1.0") -and $_.lifecycle -eq "available" -and $_.sourcePvcName
    }
    if ($supersededLaunchable.Count -eq 0) {
        Pass "superseded DevOps versions are not advertised as launchable sources"
    } else {
        Fail "superseded DevOps versions are not advertised as launchable sources"
    }
} catch {
    Fail "image catalog could not be parsed: $($_.Exception.Message)"
}

try {
    $chart = Get-Content -LiteralPath "helm/vdiforge/Chart.yaml" -Raw
    if ($chart -match "(?m)^version:\s*0\.14\.0\s*$" -and $chart -match "(?m)^appVersion:\s*`"0\.14\.0`"\s*$") {
        Pass "Helm chart version is 0.14.0"
    } else {
        Fail "Helm chart version is 0.14.0"
    }
} catch {
    Fail "Helm chart version check failed: $($_.Exception.Message)"
}

try {
    $init = Get-Content -LiteralPath "backend/app/__init__.py" -Raw
    $pyproject = Get-Content -LiteralPath "backend/pyproject.toml" -Raw
    if ($init -match '__version__\s*=\s*"0\.14\.0"' -and $pyproject -match '(?m)^version\s*=\s*"0\.14\.0"\s*$') {
        Pass "backend package version is 0.14.0"
    } else {
        Fail "backend package version is 0.14.0"
    }
} catch {
    Fail "backend package version check failed: $($_.Exception.Message)"
}

Check-ContentPresent "README.md" "AI-assisted tools|AI-assisted" "README discloses AI-assisted project creation"
Check-ContentPresent "README.md" "Phase 14" "README reflects Phase 14"
Check-ContentPresent "README.md" "ubuntu-base.*ubuntu-developer.*ubuntu-devops|ubuntu-devops.*ubuntu-developer.*ubuntu-base" "README mentions the three final demo images"
Check-ContentPresent "docs/DEMO.md" "demo-user.*ubuntu[- ]base" "Demo plan includes demo-user image visibility"
Check-ContentPresent "docs/DEMO.md" "demo-developer.*ubuntu[- ]base.*ubuntu[- ]developer" "Demo plan includes demo-developer image visibility"
Check-ContentPresent "docs/DEMO.md" "demo-admin.*ubuntu[- ]base.*ubuntu[- ]developer.*ubuntu[- ]devops" "Demo plan includes admin image visibility"
Check-ContentPresent "docs/PORTFOLIO-SUMMARY.md" "AI-assisted tools|AI-assisted" "Portfolio summary discloses AI-assisted tooling"
Check-ContentPresent "docs/LIMITATIONS.md" "VirtualBox|local lab|not production" "Limitations document covers local-lab boundaries"
Check-ContentPresent "docs/ADR/0024-final-demo-image-promotion.md" "Status|Context|Decision|Alternatives considered|Consequences" "Phase 14 ADR has required sections"
Check-ContentPresent "docs/REQUIREMENTS.md" "## Final Demo Requirements" "Phase 14 final-demo requirements are defined"
Check-ContentPresent "docs/REQUIREMENTS.md" "## Phase 14 Traceability" "Phase 14 traceability is defined"

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG|APP|RDP|WEB|HPA|MON|CI|DEMO)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$demoRequirements = $definitionIds | Where-Object { $_ -like "DEMO-*" }
if ($demoRequirements.Count -ge 10) {
    Pass "Phase 14 demo requirements are complete enough for traceability"
} else {
    Fail "Phase 14 demo requirements are complete enough for traceability"
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

if (Get-Command python -ErrorAction SilentlyContinue) {
    python -m py_compile scripts/phase14-role-image-test.py
    if ($LASTEXITCODE -eq 0) { Pass "Phase 14 role/image test compiles" } else { Fail "Phase 14 role/image test compiles" }
    python scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog schema validation" } else { Fail "image catalog schema validation" }
} else {
    Warn "python is not installed; Python validation skipped"
}

if ($RunOptionalTools) {
    if (Get-Command helm -ErrorAction SilentlyContinue) {
        helm lint ./helm/vdiforge --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase14-local.yaml
        if ($LASTEXITCODE -eq 0) { Pass "helm lint with Phase 14 values" } else { Fail "helm lint with Phase 14 values" }

        New-Item -ItemType Directory -Force -Path ".local/phase14" | Out-Null
        helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase14-local.yaml --kube-version 1.36.4 > ".local/phase14/rendered.yaml"
        if ($LASTEXITCODE -eq 0) { Pass "helm template with Phase 14 values" } else { Fail "helm template with Phase 14 values" }
    } else {
        Warn "helm is not installed; Helm validation will run on the control node and in CI"
    }

    if (Get-Command bash -ErrorAction SilentlyContinue) {
        bash -n scripts/phase14-prepare-demo-images.sh
        if ($LASTEXITCODE -eq 0) { Pass "phase14 image preparation script syntax" } else { Fail "phase14 image preparation script syntax" }
        bash -n scripts/validate-phase14-live.sh
        if ($LASTEXITCODE -eq 0) { Pass "phase14 live validator syntax" } else { Fail "phase14 live validator syntax" }
    } else {
        Warn "bash is not installed; shell syntax validation skipped"
    }
}

if ($failures -ne 0) {
    Write-Host "Phase 14 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 14 validation: PASS" -ForegroundColor Green
