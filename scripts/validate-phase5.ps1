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

function Get-RepositoryFiles {
    Get-ChildItem -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
        Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
        Where-Object { $_.FullName -notmatch "\\.terraform\\" } |
        Where-Object { $_.FullName -notmatch "\\.pytest_cache\\" } |
        Where-Object { $_.FullName -notmatch "\\.venv\\" } |
        Where-Object { $_.FullName -notmatch "\\__pycache__\\" }
}

function Check-ContentAbsent($Paths, $Pattern, $Description) {
    $items = foreach ($path in $Paths) {
        if (Test-Path $path -PathType Leaf) {
            Get-Item $path
        } elseif (Test-Path $path -PathType Container) {
            Get-ChildItem $path -File -Recurse
        }
    }

    $matches = $items |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\.local\\" } |
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

Write-Host "VDIForge Phase 5 static validation"

$requiredFiles = @(
    "helm/vdiforge/Chart.yaml",
    "helm/vdiforge/values.yaml",
    "helm/vdiforge/values-local.yaml",
    "helm/vdiforge/values-phase5-local.yaml",
    "helm/vdiforge/templates/keycloak.yaml",
    "helm/vdiforge/templates/keycloak-postgres.yaml",
    "helm/vdiforge/templates/keycloak-networkpolicies.yaml",
    "helm/vdiforge/files/keycloak/vdiforge-realm.json",
    "helm/traefik/values-local.yaml",
    "keycloak/realm/vdiforge-realm.json",
    "keycloak/local-secrets.env.example",
    "scripts/phase5-create-local-secrets.sh",
    "scripts/phase5-configure-keycloak.sh",
    "scripts/phase5-networkpolicy-test.sh",
    "scripts/phase5-oidc-pkce-test.py",
    "scripts/phase5-windows-hosts-and-trust.ps1",
    "scripts/validate-phase5.ps1",
    "scripts/validate-phase5-live.sh",
    "docs/KEYCLOAK-OIDC.md",
    "docs/SSO-RBAC.md",
    "docs/REQUIREMENTS.md",
    "docs/ROADMAP.md",
    "docs/RUNBOOK.md",
    "docs/SECURITY.md",
    "docs/ADR/0012-keycloak-oidc-platform.md",
    "docs/ADR/0013-local-ingress-and-tls.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

$repoFiles = @(Get-RepositoryFiles)
Check-ContentAbsent $repoFiles "BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY" "private key material"
Check-ContentAbsent $repoFiles "-----BEGIN PRIVATE KEY-----" "TLS private key material"
Check-ContentAbsent $repoFiles "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "literal JWT token"
Check-ContentAbsent @("helm/vdiforge/values.yaml", "helm/vdiforge/values-local.yaml", "helm/vdiforge/values-phase5-local.yaml") "(?m)^\s*(password|clientSecret|client_secret|secret):\s*[^<{\s#].+$" "plaintext secret value in Helm values"
Check-ContentAbsent @("helm/vdiforge", "keycloak") ":[Ll]atest\b" "floating latest image tag"

$chartYaml = Get-Content "helm/vdiforge/Chart.yaml" -Raw
if ($chartYaml -match '(?m)^version:\s*\d+\.\d+\.\d+\s*$' -and $chartYaml -match 'kubeVersion:\s*">=1\.36\.0-0 <1\.37\.0-0"') {
    Pass "chart version and Kubernetes compatibility are pinned"
} else {
    Fail "chart version or Kubernetes compatibility pin missing"
}

$values = Get-Content "helm/vdiforge/values.yaml" -Raw
if ($values -match 'quay\.io/keycloak/keycloak' -and $values -match 'tag:\s*"26\.7\.2"' -and $values -match 'postgres' -and $values -match 'tag:\s*"18\.0-alpine"') {
    Pass "Keycloak and PostgreSQL image versions are pinned"
} else {
    Fail "Keycloak or PostgreSQL image version pin missing"
}

$realmPath = "keycloak/realm/vdiforge-realm.json"
$chartRealmPath = "helm/vdiforge/files/keycloak/vdiforge-realm.json"
try {
    $realm = Get-Content $realmPath -Raw | ConvertFrom-Json
    Pass "realm JSON parses"
} catch {
    Fail "realm JSON is invalid: $($_.Exception.Message)"
}

if ((Test-Path $realmPath) -and (Test-Path $chartRealmPath)) {
    $diff = Compare-Object (Get-Content $realmPath) (Get-Content $chartRealmPath)
    if ($diff) {
        Fail "chart realm import JSON differs from keycloak/realm source"
    } else {
        Pass "chart realm import JSON matches keycloak/realm source"
    }
}

if ($realm) {
    if ($realm.realm -eq "vdiforge" -and $realm.enabled -eq $true) {
        Pass "vdiforge realm is defined and enabled"
    } else {
        Fail "vdiforge realm is missing or disabled"
    }

    $requiredRoles = @("vdi-user", "vdi-developer", "vdi-devops", "vdi-admin")
    $roleNames = @($realm.roles.realm | ForEach-Object { $_.name })
    $missingRoles = $requiredRoles | Where-Object { $_ -notin $roleNames }
    if ($missingRoles.Count -eq 0) {
        Pass "all VDIForge roles are defined"
    } else {
        Fail "missing roles: $($missingRoles -join ', ')"
    }

    $clients = @($realm.clients)
    $frontend = $clients | Where-Object { $_.clientId -eq "vdiforge-frontend" } | Select-Object -First 1
    $api = $clients | Where-Object { $_.clientId -eq "vdiforge-api" } | Select-Object -First 1
    if ($frontend -and $frontend.publicClient -eq $true -and $frontend.standardFlowEnabled -eq $true -and $frontend.implicitFlowEnabled -eq $false -and $frontend.directAccessGrantsEnabled -eq $false) {
        Pass "browser client uses Authorization Code Flow and disables implicit/direct grants"
    } else {
        Fail "browser client OIDC flow settings are not correct"
    }
    if ($frontend -and $frontend.attributes.'pkce.code.challenge.method' -eq "S256") {
        Pass "browser client requires PKCE S256"
    } else {
        Fail "browser client PKCE S256 setting missing"
    }
    if ($frontend -and -not ($frontend.PSObject.Properties.Name -contains "secret")) {
        Pass "browser client has no committed client secret"
    } else {
        Fail "browser client contains a secret property"
    }
    if ($frontend -and (($frontend.redirectUris -contains "*") -or ($frontend.webOrigins -contains "*"))) {
        Fail "wildcard redirect URI or web origin found"
    } else {
        Pass "browser client redirect URIs and web origins are restricted"
    }
    if ($api) {
        Pass "future API audience client is defined"
    } else {
        Fail "future API audience client is missing"
    }

    $requiredUsers = @("demo-user", "demo-developer", "demo-devops", "demo-admin")
    $users = @($realm.users)
    $userNames = @($users | ForEach-Object { $_.username })
    $missingUsers = $requiredUsers | Where-Object { $_ -notin $userNames }
    if ($missingUsers.Count -eq 0) {
        Pass "all demo identities are defined"
    } else {
        Fail "missing demo identities: $($missingUsers -join ', ')"
    }
    $usersWithCredentials = $users | Where-Object { $_.PSObject.Properties.Name -contains "credentials" }
    if ($usersWithCredentials) {
        Fail "realm JSON includes user credentials"
    } else {
        Pass "realm JSON does not commit demo passwords"
    }
}

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm lint ./helm/vdiforge
    if ($LASTEXITCODE -eq 0) { Pass "helm lint" } else { Fail "helm lint" }

    $phase4Render = helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --kube-version 1.36.4
    if ($LASTEXITCODE -eq 0) {
        Pass "phase4/default helm template"
        $phase4Text = $phase4Render -join "`n"
        if ($phase4Text -match "(?m)^kind:\s*(Deployment|StatefulSet|DaemonSet|Ingress)\s*$") {
            Fail "Phase 4 default values render application workloads"
        } else {
            Pass "Phase 4 default values remain application-free"
        }
    } else {
        Fail "phase4/default helm template"
    }

    $phase5Render = helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --kube-version 1.36.4
    if ($LASTEXITCODE -eq 0) {
        Pass "phase5 helm template"
        $phase5Text = $phase5Render -join "`n"
        if ($phase5Text -match "kind:\s*Deployment" -and $phase5Text -match "kind:\s*StatefulSet" -and $phase5Text -match "kind:\s*Ingress") {
            Pass "Phase 5 render includes Keycloak, PostgreSQL, and Ingress resources"
        } else {
            Fail "Phase 5 render missing expected identity resources"
        }
        if ($phase5Text -match "cluster-admin|ClusterRoleBinding") {
            Fail "Phase 5 render contains cluster-admin or ClusterRoleBinding"
        } else {
            Pass "Phase 5 render contains no cluster-admin or ClusterRoleBinding"
        }
        if ($phase5Text -match "vdi-control-01|vdi-worker-01|vdi-worker-02") {
            Fail "Phase 5 render contains hardcoded node names"
        } else {
            Pass "Phase 5 render uses role labels instead of hardcoded node names"
        }
    } else {
        Fail "phase5 helm template"
    }

    if (Get-Command kubeconform -ErrorAction SilentlyContinue) {
        $manifest = New-TemporaryFile
        $phase5Render | Set-Content $manifest
        kubeconform -strict -summary -kubernetes-version 1.36.4 $manifest
        if ($LASTEXITCODE -eq 0) { Pass "kubeconform schema validation" } else { Fail "kubeconform schema validation" }
        Remove-Item $manifest -ErrorAction SilentlyContinue
    } else {
        Warn "kubeconform is not installed; live validation uses Kubernetes server-side dry-run."
    }
} else {
    Warn "helm is not installed on this Windows host; live validation runs Helm from vdi-control-01."
}

$requirements = Get-Content "docs/REQUIREMENTS.md" -Raw
$definitionIds = [regex]::Matches($requirements, "(?m)^\|\s*((?:FR|NFR|SEC|OBS|OPS|INFRA|K8S|KV|STOR|HELM|IDP)-\d{3})\s*\|") | ForEach-Object { $_.Groups[1].Value }
$idpIds = $definitionIds | Where-Object { $_ -like "IDP-*" }
if ($idpIds.Count -ge 12) {
    Pass "Phase 5 IDP requirements are defined"
} else {
    Fail "Expected at least 12 IDP-* requirements, found $($idpIds.Count)"
}

$duplicates = $definitionIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -eq 0) {
    Pass "requirement definition IDs are unique"
} else {
    Fail "duplicate requirement definition IDs found: $($duplicates.Name -join ', ')"
}

$roadmap = Get-Content "docs/ROADMAP.md" -Raw
if ($roadmap -match "\|\s*5\s*\|\s*Keycloak/OIDC/RBAC\s*\|\s*Complete\s*\|") {
    Pass "roadmap marks Phase 5 complete"
} else {
    Fail "roadmap does not mark Phase 5 complete"
}

if ($Live) {
    Write-Host "Running Phase 5 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd ~/vdiforge-phase5-validation && bash scripts/validate-phase5-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 5 live validation" } else { Fail "Phase 5 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 5 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 5 validation: PASS" -ForegroundColor Green
