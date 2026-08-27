$ErrorActionPreference = "Stop"

Write-Host "Host operating system"
systeminfo | Select-String "OS Name|OS Version|System Type|Processor|Total Physical Memory|Available Physical Memory|Hyper-V Requirements"

Write-Host ""
Write-Host "VirtualBox"
$vboxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (Test-Path -LiteralPath $vboxManage -PathType Leaf) {
  & $vboxManage --version
  & $vboxManage list hostonlyifs
}
else {
  Write-Host "VBoxManage -> not found at $vboxManage"
}

Write-Host ""
Write-Host "Filesystem capacity"
Get-PSDrive -PSProvider FileSystem | Select-Object Name,Root,Used,Free | Format-Table -AutoSize

Write-Host ""
Write-Host "Tooling"
foreach ($tool in @("git", "terraform", "ssh", "ssh-keygen", "ansible", "ansible-playbook", "ansible-lint")) {
  $command = Get-Command $tool -ErrorAction SilentlyContinue
  if ($command) {
    Write-Host "$tool -> $($command.Source)"
  }
  else {
    Write-Host "$tool -> not found"
  }
}
