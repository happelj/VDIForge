param(
    [string]$IngressIp = "192.168.56.11",
    [string[]]$Hostnames = @("auth.vdiforge.local", "api.vdiforge.local", "remote.vdiforge.local", "vdiforge.local", "grafana.vdiforge.local"),
    [string]$CaCertificatePath = ".local\phase5\tls\vdiforge-local-ca.crt"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (Test-Path $CaCertificatePath) {
    certutil.exe -user -addstore Root $CaCertificatePath | Out-Null
    Write-Host "Trusted local VDIForge CA for the current Windows user: $CaCertificatePath"
} else {
    Write-Host "CA certificate not found at $CaCertificatePath"
    Write-Host "Copy it from vdi-control-01 after running scripts/phase5-create-local-secrets.sh:"
    Write-Host "  scp vdiadmin@192.168.56.10:~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt .local\phase5\tls\"
}

if (-not (Test-Administrator)) {
    Write-Host "Run this script from an elevated PowerShell window to update C:\Windows\System32\drivers\etc\hosts."
    exit 0
}

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$existing = Get-Content $hostsPath -Raw
$line = "$IngressIp`t$($Hostnames -join ' ')"

foreach ($hostname in $Hostnames) {
    if ($existing -match "(?m)^\s*\S+\s+.*\b$([regex]::Escape($hostname))\b") {
        Write-Host "Hosts entry already contains $hostname"
    }
}

$missing = $Hostnames | Where-Object { $existing -notmatch "(?m)^\s*\S+\s+.*\b$([regex]::Escape($_))\b" }
if ($missing.Count -gt 0) {
    Add-Content -Path $hostsPath -Value ""
    Add-Content -Path $hostsPath -Value "# VDIForge local lab"
    Add-Content -Path $hostsPath -Value $line
    Write-Host "Added hosts entry: $line"
} else {
    Write-Host "All requested VDIForge hostnames are already present."
}

foreach ($hostname in $Hostnames) {
    Resolve-DnsName $hostname | Select-Object -First 1
}
