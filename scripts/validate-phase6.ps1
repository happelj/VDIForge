param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin",
    [string]$RemotePath = "~/vdiforge-phase6-validation"
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
    Get-ChildItem -File -Recurse |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
        Where-Object { $_.FullName -notmatch "\\artifacts\\" } |
        Where-Object { $_.FullName -notmatch "\\packer_cache\\" } |
        Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
        Where-Object { $_.FullName -notmatch "\\.terraform\\" } |
        Where-Object { $_.FullName -notmatch "\\__pycache__\\" }
}

function Check-ContentAbsent($Paths, $Pattern, $Description) {
    $items = foreach ($path in $Paths) {
        if (Test-Path $path -PathType Leaf) {
            Get-Item $path
        } elseif (Test-Path $path -PathType Container) {
            Get-ChildItem $path -File -Recurse
        } else {
            $path
        }
    }

    $matches = $items |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
        Where-Object { $_.FullName -notmatch "\\artifacts\\" } |
        Where-Object { $_.FullName -notmatch "\\scripts\\validate-phase\d+\.ps1$" } |
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

Write-Host "VDIForge Phase 6 static validation"

$requiredFiles = @(
    "packer/shared/cloud-init/user-data.pkrtpl",
    "packer/shared/scripts/generalize-artifact.sh",
    "packer/shared/scripts/validate-image.sh",
    "packer/shared/scripts/write-manifest.sh",
    "packer/ubuntu-base/ubuntu-base.pkr.hcl",
    "packer/ubuntu-base/variables.pkr.hcl",
    "packer/ubuntu-developer/ubuntu-developer.pkr.hcl",
    "packer/ubuntu-developer/variables.pkr.hcl",
    "packer/ubuntu-devops/ubuntu-devops.pkr.hcl",
    "packer/ubuntu-devops/variables.pkr.hcl",
    "ansible/roles/image-common/tasks/main.yml",
    "ansible/roles/image-desktop/tasks/main.yml",
    "ansible/roles/image-developer/tasks/main.yml",
    "ansible/roles/image-devops/tasks/main.yml",
    "ansible/roles/image-cleanup/tasks/main.yml",
    "ansible/playbooks/image-ubuntu-base.yml",
    "ansible/playbooks/image-ubuntu-developer.yml",
    "ansible/playbooks/image-ubuntu-devops.yml",
    "images/catalog.json",
    "images/catalog.schema.json",
    "scripts/validate-image-catalog.py",
    "scripts/phase6-install-build-tools.sh",
    "scripts/phase6-build-image.sh",
    "scripts/phase6-build-all.sh",
    "scripts/phase6-cdi-kubevirt-test.sh",
    "scripts/validate-phase6.ps1",
    "scripts/validate-phase6-live.sh",
    "kubernetes/kubevirt/phase6-ubuntu-devops-vm.template.yaml",
    "docs/IMAGE-PIPELINE.md",
    "docs/GOLDEN-IMAGES.md",
    "docs/REQUIREMENTS.md",
    "docs/ROADMAP.md",
    "docs/RUNBOOK.md",
    "docs/SECURITY.md",
    "docs/TESTING.md",
    "docs/ADR/0014-phase6-image-build-environment.md",
    "docs/ADR/0015-qcow2-cdi-golden-image-import.md",
    "docs/ADR/0016-xfce-for-vdiforge-ubuntu-images.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY" "private key material"
Check-ContentAbsent $repoFiles "-----BEGIN PRIVATE KEY-----" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent $repoFiles "(?im)^\s*(aws_access_key_id|aws_secret_access_key|client_secret|refresh_token|access_token)\s*[:=]\s*['""]?[A-Za-z0-9_./+=-]{16,}['""]?\s*(#.*)?$" "cloud or OAuth credential"

$trackedArtifacts = git ls-files | Select-String -Pattern "\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-" -ErrorAction SilentlyContinue
if ($trackedArtifacts) {
    Fail "generated image artifacts are tracked"
    $trackedArtifacts | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Pass "no generated image artifacts are tracked"
}

foreach ($dir in @("packer/ubuntu-base", "packer/ubuntu-developer", "packer/ubuntu-devops")) {
    $template = Get-Content (Join-Path $dir ("$(Split-Path $dir -Leaf).pkr.hcl")) -Raw
    $vars = Get-Content (Join-Path $dir "variables.pkr.hcl") -Raw
    if ($template -match 'required_version\s*=\s*">= 1\.16\.0, < 1\.17\.0"' -and $template -match 'source\s*=\s*"github\.com/hashicorp/qemu"' -and $template -match 'source\s*=\s*"github\.com/hashicorp/ansible"' -and ([regex]::Matches($template, 'version\s*=\s*"1\.1\.6"').Count -ge 2)) {
        Pass "$dir pins Packer, QEMU, and Ansible plugin versions"
    } else {
        Fail "$dir does not pin Packer/QEMU/Ansible plugin versions correctly"
    }
    if ($vars -match 'ubuntu-26\.04-server-cloudimg-amd64\.img' -and $vars -match '8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035') {
        Pass "$dir pins trusted Ubuntu source and checksum"
    } else {
        Fail "$dir missing Ubuntu source checksum pin"
    }
}

try {
    Get-Content "images/catalog.json" -Raw | ConvertFrom-Json | Out-Null
    Pass "image catalog JSON parses"
} catch {
    Fail "image catalog JSON is invalid: $($_.Exception.Message)"
}

if (Get-Command python3 -ErrorAction SilentlyContinue) {
    python3 scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog policy validation" } else { Fail "image catalog policy validation" }
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    python scripts/validate-image-catalog.py
    if ($LASTEXITCODE -eq 0) { Pass "image catalog policy validation" } else { Fail "image catalog policy validation" }
} else {
    Warn "python is not installed on this Windows host; live validation also validates the catalog."
}

if (Get-Command packer -ErrorAction SilentlyContinue) {
    $validationDir = ".local/phase6/static-validation"
    New-Item -ItemType Directory -Force -Path $validationDir | Out-Null
    $validationKey = Join-Path $validationDir "packer_ed25519"
    if (-not (Test-Path $validationKey)) {
        New-Item -ItemType File -Force -Path $validationKey | Out-Null
    }
    $validationKeyForHcl = (Resolve-Path $validationKey).Path.Replace("\", "/")
    foreach ($dir in @("packer/ubuntu-base", "packer/ubuntu-developer", "packer/ubuntu-devops")) {
        $imageName = Split-Path $dir -Leaf
        $artifactRootForHcl = (Resolve-Path ".").Path.Replace("\", "/") + "/.local/phase6/static-validation-artifacts-$imageName-$PID"
        $varFile = Join-Path $validationDir "static-validation-$imageName.pkrvars.hcl"
        @(
            'image_version = "1.0.0"'
            "artifact_root = `"$artifactRootForHcl`""
            "ssh_private_key_file = `"$validationKeyForHcl`""
            'ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZESUZvcmdlUGFja2VyUGxhY2Vob2xkZXJLZXkK vdiforge-packer-placeholder"'
            'build_username = "packer"'
        ) | Set-Content -Path $varFile -Encoding ascii
        packer fmt -check $dir
        if ($LASTEXITCODE -eq 0) { Pass "packer fmt -check $dir" } else { Fail "packer fmt -check $dir" }
        packer validate -var-file=$varFile $dir
        if ($LASTEXITCODE -eq 0) { Pass "packer validate $dir" } else { Fail "packer validate $dir" }
    }
} else {
    Warn "packer is not installed on this Windows host; live validation runs Packer from the Linux build host."
}

if (Get-Command ansible-playbook -ErrorAction SilentlyContinue) {
    Push-Location ansible
    foreach ($playbook in @("image-ubuntu-base.yml", "image-ubuntu-developer.yml", "image-ubuntu-devops.yml")) {
        ansible-playbook -i localhost, "playbooks/$playbook" --syntax-check
        if ($LASTEXITCODE -eq 0) { Pass "Ansible syntax check $playbook" } else { Fail "Ansible syntax check $playbook" }
    }
    Pop-Location
} else {
    Warn "ansible-playbook is not installed on this Windows host; live validation runs Ansible from Linux."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP|IMG)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$imageIds = $definitionIds | Where-Object { $_ -like "IMG-*" }
if ($imageIds.Count -ge 12) {
    Pass "Phase 6 IMG requirements are defined"
} else {
    Fail "Expected at least 12 IMG-* requirements, found $($imageIds.Count)"
}

$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$roadmap = Get-Content "docs/ROADMAP.md" -Raw
if ($roadmap -match "\|\s*6\s*\|\s*Ubuntu/Packer image pipeline\s*\|\s*Complete\s*\|") {
    Pass "roadmap marks Phase 6 complete"
} else {
    Fail "roadmap does not mark Phase 6 complete"
}

if ($Live) {
    Write-Host "Running Phase 6 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd $RemotePath && bash scripts/validate-phase6-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 6 live validation" } else { Fail "Phase 6 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 6 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 6 validation: PASS" -ForegroundColor Green
