param(
  [switch]$Live,
  [string]$VmRoot = "F:\VirtualBox VMs",
  [string]$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Add-Warning {
  param([string]$Message)
  $warnings.Add($Message)
}

function Invoke-Checked {
  param(
    [string]$Label,
    [string]$Command
  )

  Write-Host "==> $Label"
  Invoke-Expression $Command
}

$requiredFiles = @(
  "terraform/environments/local/main.tf",
  "terraform/environments/local/variables.tf",
  "terraform/environments/local/outputs.tf",
  "terraform/environments/local/versions.tf",
  "terraform/modules/virtualbox-lab-node/main.tf",
  "terraform/modules/virtualbox-lab-node/variables.tf",
  "terraform/modules/virtualbox-lab-node/outputs.tf",
  "ansible/ansible.cfg",
  "ansible/inventory/local/hosts.yml",
  "ansible/inventory/local/group_vars/all.yml",
  "ansible/playbooks/baseline.yml",
  "ansible/roles/common/tasks/main.yml",
  "ansible/roles/security-baseline/tasks/main.yml",
  "docs/LOCAL-INFRASTRUCTURE.md",
  "docs/ADR/0009-virtualbox-local-lab-on-windows.md"
)

foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Add-Failure "Missing required Phase 2 file: $file"
  }
}

$expectedNodes = @{
  "vdi-control-01" = @{
    Cpu = 2; Memory = 4096; DiskMb = 40960; Ip = "192.168.56.10"; Nested = $false
  }
  "vdi-worker-01" = @{
    Cpu = 2; Memory = 6144; DiskMb = 51200; Ip = "192.168.56.11"; Nested = $false
  }
  "vdi-worker-02" = @{
    Cpu = 4; Memory = 8192; DiskMb = 61440; Ip = "192.168.56.12"; Nested = $true
  }
}

$terraform = Get-Command terraform -ErrorAction SilentlyContinue
if ($terraform) {
  try {
    Invoke-Checked "terraform fmt" "terraform -chdir=terraform/environments/local fmt -check -recursive"
    Invoke-Checked "terraform init" "terraform -chdir=terraform/environments/local init -backend=false -input=false"
    Invoke-Checked "terraform validate" "terraform -chdir=terraform/environments/local validate"
  }
  catch {
    Add-Failure "Terraform validation failed: $($_.Exception.Message)"
  }
}
else {
  Add-Failure "Terraform is not installed or not on PATH."
}

$ansiblePlaybook = Get-Command ansible-playbook -ErrorAction SilentlyContinue
if ($ansiblePlaybook) {
  try {
    Invoke-Checked "ansible syntax check" "ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --syntax-check"
  }
  catch {
    Add-Failure "Ansible syntax validation failed: $($_.Exception.Message)"
  }
}
else {
  Add-Warning "ansible-playbook is not installed on this Windows host; run syntax/idempotency checks from a Linux/WSL Ansible controller before changing host policy."
}

$ansibleLint = Get-Command ansible-lint -ErrorAction SilentlyContinue
if ($ansibleLint) {
  try {
    Invoke-Checked "ansible lint" "ansible-lint ansible/playbooks/baseline.yml"
  }
  catch {
    Add-Failure "ansible-lint failed: $($_.Exception.Message)"
  }
}
else {
  Add-Warning "ansible-lint is not installed on this Windows host."
}

if (Test-Path -LiteralPath $VBoxManage -PathType Leaf) {
  $hostOnlyInfo = (& $VBoxManage list hostonlyifs) -join "`n"
  if ($hostOnlyInfo -notmatch "VirtualBox Host-Only Ethernet Adapter") {
    Add-Failure "Expected VirtualBox Host-Only Ethernet Adapter was not found."
  }
  if ($hostOnlyInfo -notmatch "IPAddress:\s+192\.168\.56\.1") {
    Add-Failure "Expected host-only adapter IP 192.168.56.1 was not found."
  }
}
else {
  Add-Failure "VBoxManage not found at $VBoxManage."
}

foreach ($nodeName in $expectedNodes.Keys) {
  $expected = $expectedNodes[$nodeName]
  $nodeDir = Join-Path -Path $VmRoot -ChildPath $nodeName
  $vboxPath = Join-Path -Path $nodeDir -ChildPath "$nodeName.vbox"
  $diskPath = Join-Path -Path $nodeDir -ChildPath "$nodeName.vdi"

  if (-not (Test-Path -LiteralPath $vboxPath -PathType Leaf)) {
    Add-Failure "Missing VirtualBox metadata file: $vboxPath"
    continue
  }

  if (-not (Test-Path -LiteralPath $diskPath -PathType Leaf)) {
    Add-Failure "Missing VirtualBox disk file: $diskPath"
    continue
  }

  $vbox = Get-Content -LiteralPath $vboxPath -Raw
  if ($vbox -notmatch "RAMSize=`"$($expected.Memory)`"") {
    Add-Failure "$nodeName memory does not match expected $($expected.Memory) MiB."
  }
  if ($vbox -notmatch "<CPU count=`"$($expected.Cpu)`"") {
    Add-Failure "$nodeName CPU count does not match expected $($expected.Cpu)."
  }
  if ($vbox -notmatch "<NAT") {
    Add-Failure "$nodeName does not have NAT on Adapter 1."
  }
  if ($vbox -notmatch "HostOnlyInterface name=`"VirtualBox Host-Only Ethernet Adapter`"") {
    Add-Failure "$nodeName does not use the expected host-only adapter."
  }
  if ($expected.Nested -and $vbox -notmatch "NestedHWVirt enabled=`"true`"") {
    Add-Failure "$nodeName requires nested virtualization but it is not enabled in VirtualBox metadata."
  }

  if (Test-Path -LiteralPath $VBoxManage -PathType Leaf) {
    $mediumInfo = (& $VBoxManage showmediuminfo disk $diskPath) -join "`n"
    if ($mediumInfo -notmatch "Capacity:\s+$($expected.DiskMb)\s+MBytes") {
      Add-Failure "$nodeName disk capacity does not match expected $($expected.DiskMb) MBytes."
    }
  }
}

$gitIgnore = Get-Content -LiteralPath ".gitignore" -Raw
foreach ($pattern in @("*.tfstate", ".terraform/", "*.vdi", "*.iso", "*.vbox", "*.vbox-prev")) {
  if ($gitIgnore -notmatch [regex]::Escape($pattern)) {
    Add-Failure ".gitignore does not include required pattern: $pattern"
  }
}

$secretPatterns = @(
  "BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY",
  "AKIA[0-9A-Z]{16}",
  "ghp_[A-Za-z0-9_]+",
  "github_pat_[A-Za-z0-9_]+",
  "sk-[A-Za-z0-9]{20,}"
)

$excludedFragments = @(
  "\.git\",
  "\.terraform\",
  "\node_modules\",
  "\.venv\",
  "\venv\",
  "\packer_cache\",
  "\VirtualBox VMs\"
)

$textExtensions = @(
  ".cfg",
  ".css",
  ".editorconfig",
  ".gitignore",
  ".hcl",
  ".html",
  ".ini",
  ".js",
  ".json",
  ".md",
  ".ps1",
  ".py",
  ".sh",
  ".tf",
  ".toml",
  ".ts",
  ".tsx",
  ".txt",
  ".yaml",
  ".yml"
)

$repoTextFiles = Get-ChildItem -Recurse -File -Force | Where-Object {
  $fullName = $_.FullName
  $isExcluded = $false
  foreach ($fragment in $excludedFragments) {
    if ($fullName.Contains($fragment)) {
      $isExcluded = $true
      break
    }
  }
  (-not $isExcluded) -and ($textExtensions -contains $_.Extension -or $textExtensions -contains $_.Name)
}

foreach ($file in $repoTextFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  foreach ($pattern in $secretPatterns) {
    if ($content -match $pattern) {
      Add-Failure "Potential secret pattern found in $($file.FullName)"
    }
  }
}

if ($Live) {
  foreach ($nodeName in $expectedNodes.Keys) {
    $ip = $expectedNodes[$nodeName].Ip
    if (-not (Test-Connection -ComputerName $ip -Count 2 -Quiet)) {
      Add-Failure "Live ping failed for $nodeName at $ip."
    }

    $sshCommand = "ssh -o BatchMode=yes -o ConnectTimeout=5 vdiadmin@$ip hostname"
    try {
      $sshOutput = Invoke-Expression "$sshCommand 2>`$null"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($sshOutput -join ""))) {
        Add-Warning "Live SSH check for $nodeName could not run non-interactively. Use manual SSH or key-based auth."
      }
      elseif (($sshOutput -join "").Trim() -ne $nodeName) {
        Add-Failure "SSH hostname check for $nodeName returned '$sshOutput'."
      }
    }
    catch {
      Add-Warning "Live SSH check for $nodeName could not run non-interactively. Use manual SSH or key-based auth."
    }
  }

  try {
    $kvmOutput = Invoke-Expression "ssh -o BatchMode=yes -o ConnectTimeout=5 vdiadmin@192.168.56.12 'test -e /dev/kvm && ls -l /dev/kvm' 2>`$null"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($kvmOutput -join ""))) {
      Add-Warning "Live /dev/kvm SSH check could not run non-interactively. Manual evidence is acceptable when recorded."
    }
    elseif (($kvmOutput -join "`n") -notmatch "/dev/kvm") {
      Add-Failure "Live /dev/kvm check did not report /dev/kvm on vdi-worker-02."
    }
  }
  catch {
    Add-Warning "Live /dev/kvm SSH check could not run non-interactively. Manual evidence is acceptable when recorded."
  }
}
else {
  Add-Warning "Live SSH, node-to-node ping, outbound Internet, and /dev/kvm checks were not run by this static validation. Run with -Live after key-based SSH is configured."
}

if ($warnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Warnings:"
  foreach ($warning in $warnings) {
    Write-Host " - $warning"
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Failures:"
  foreach ($failure in $failures) {
    Write-Host " - $failure"
  }
  throw "Phase 2 validation failed."
}

Write-Host ""
if ($Live) {
  Write-Host "Phase 2 live validation passed."
}
else {
  Write-Host "Phase 2 static validation passed."
}
