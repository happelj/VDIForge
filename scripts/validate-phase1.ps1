$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$requiredFiles = @(
  "README.md",
  "LICENSE",
  ".gitignore",
  ".editorconfig",
  "docs/DESIGN.md",
  "docs/REQUIREMENTS.md",
  "docs/ARCHITECTURE.md",
  "docs/SECURITY.md",
  "docs/IMAGE-PIPELINE.md",
  "docs/SSO-RBAC.md",
  "docs/AUTOSCALING.md",
  "docs/OBSERVABILITY.md",
  "docs/TESTING.md",
  "docs/RUNBOOK.md",
  "docs/DEMO.md",
  "docs/ROADMAP.md",
  "docs/ADR/0001-kubernetes-orchestration.md",
  "docs/ADR/0002-kubevirt-for-vm-workloads.md",
  "docs/ADR/0003-keycloak-for-identity.md",
  "docs/ADR/0004-guacamole-for-remote-access.md",
  "docs/ADR/0005-terraform-infrastructure-boundary.md",
  "docs/ADR/0006-helm-application-deployment.md",
  "docs/ADR/0007-packer-ansible-image-pipeline.md",
  "docs/ADR/0008-local-three-node-development-cluster.md",
  "terraform/README.md",
  "ansible/README.md",
  "packer/README.md",
  "kubernetes/README.md",
  "helm/vdiforge/README.md",
  "backend/README.md",
  "frontend/README.md",
  "keycloak/README.md",
  "monitoring/README.md"
)

$requiredDirs = @(
  "terraform/modules",
  "terraform/environments/local",
  "ansible/inventory",
  "ansible/roles",
  "ansible/playbooks",
  "packer/ubuntu-base",
  "packer/ubuntu-developer",
  "packer/ubuntu-devops",
  "kubernetes/namespaces",
  "kubernetes/kubevirt",
  "kubernetes/policies",
  "backend/app",
  "backend/tests",
  "frontend/src",
  "frontend/tests",
  "keycloak/realm",
  "monitoring/prometheus",
  "monitoring/grafana",
  ".github/workflows"
)

$missingFiles = $requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
$missingDirs = $requiredDirs | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) }

if ($missingFiles.Count -gt 0) {
  throw "Missing required files: $($missingFiles -join ', ')"
}

if ($missingDirs.Count -gt 0) {
  throw "Missing required directories: $($missingDirs -join ', ')"
}

$markdownFiles = Get-ChildItem -Recurse -File -Include *.md
$allMarkdown = ($markdownFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

$bannedClaims = @(
  "Kubernetes is a hypervisor",
  "HPA adds physical worker nodes",
  "Guacamole is PCoIP",
  "client downloads the remote OS",
  "three local VMs provide physical HA",
  "reproduces CoreWeave's proprietary architecture"
)

foreach ($claim in $bannedClaims) {
  if ($allMarkdown -match [regex]::Escape($claim)) {
    throw "Banned or misleading claim found: $claim"
  }
}

$requirementText = Get-Content -LiteralPath "docs/REQUIREMENTS.md" -Raw
$ids = [regex]::Matches($requirementText, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }

if ($ids.Count -lt 40) {
  throw "Expected at least 40 formal requirements, found $($ids.Count)."
}

$duplicates = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -gt 0) {
  throw "Duplicate requirement IDs: $($duplicates.Name -join ', ')"
}

$requiredPrefixes = @("FR", "NFR", "SEC", "OBS", "OPS")
foreach ($prefix in $requiredPrefixes) {
  if (-not ($ids | Where-Object { $_ -like "$prefix-*" })) {
    throw "No requirements found for prefix $prefix."
  }
}

$missingLinks = New-Object System.Collections.Generic.List[string]

foreach ($file in $markdownFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw
  $linkMatches = [regex]::Matches($content, "\[[^\]]+\]\(([^)]+)\)")

  foreach ($match in $linkMatches) {
    $target = $match.Groups[1].Value
    if ($target -match "^(https?://|mailto:|#)") {
      continue
    }
    $pathOnly = ($target -split "#")[0]
    if ([string]::IsNullOrWhiteSpace($pathOnly)) {
      continue
    }
    $normalized = $pathOnly -replace "/", [System.IO.Path]::DirectorySeparatorChar
    $resolved = Join-Path -Path $file.DirectoryName -ChildPath $normalized
    if (-not (Test-Path -LiteralPath $resolved)) {
      $missingLinks.Add("$($file.FullName): $target")
    }
  }
}

if ($missingLinks.Count -gt 0) {
  throw "Broken local markdown links: $($missingLinks -join ', ')"
}

$fenceCount = ([regex]::Matches($allMarkdown, '```')).Count
if (($fenceCount % 2) -ne 0) {
  throw "Unbalanced markdown code fences detected."
}

Write-Host "Phase 1 repository validation passed."
