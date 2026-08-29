param(
    [switch]$RunOptionalTools
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failures = 0

function Invoke-Check($Name, $ScriptBlock, [switch]$Optional) {
    Write-Host "==> $Name"
    try {
        & $ScriptBlock
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "$Name exited with code $LASTEXITCODE"
        }
        Write-Host "PASS: $Name" -ForegroundColor Green
    } catch {
        if ($Optional) {
            Write-Host "WARN: $Name skipped or failed: $($_.Exception.Message)" -ForegroundColor Yellow
        } else {
            Write-Host "FAIL: $Name failed: $($_.Exception.Message)" -ForegroundColor Red
            $script:failures++
        }
    }
}

Write-Host "VDIForge local CI-safe validation"

Invoke-Check "Phase 1 repository validation" { powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-phase1.ps1 }
Invoke-Check "Phase 13 CI policy validation" { powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-phase13.ps1 }
Invoke-Check "Image catalog validation" { python .\scripts\validate-image-catalog.py }

if ($RunOptionalTools) {
    Invoke-Check "Phase 12 static regression validation" { powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-phase12.ps1 } -Optional
    Invoke-Check "Terraform fmt" { terraform fmt -check -recursive terraform } -Optional
    Invoke-Check "Terraform validate local environment" {
        terraform -chdir=terraform/environments/local init -backend=false
        terraform -chdir=terraform/environments/local validate
    } -Optional
    Invoke-Check "Helm lint" { helm lint .\helm\vdiforge -f .\helm\vdiforge\values-phase12-local.yaml } -Optional
    Invoke-Check "Frontend lint/test/build" {
        npm.cmd --prefix frontend ci
        npm.cmd --prefix frontend run lint
        npm.cmd --prefix frontend run test:run
        npm.cmd --prefix frontend run build
    } -Optional
}

if ($failures -ne 0) {
    Write-Host "Local CI-safe validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Local CI-safe validation: PASS" -ForegroundColor Green
