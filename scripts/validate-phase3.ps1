param(
    [switch]$Live,
    [string]$ControlHost = "192.168.56.10",
    [string]$SshUser = "vdiadmin"
)

$ErrorActionPreference = "Stop"
$failures = 0

function Pass($Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Fail($Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:failures++
}

function Check-File($Path) {
    if (Test-Path $Path) {
        Pass "required file exists: $Path"
    } else {
        Fail "required file missing: $Path"
    }
}

function Check-ContentAbsent($Pattern, $Description) {
    $matches = Get-ChildItem -File -Recurse |
        Where-Object { $_.FullName -notmatch "\\.git\\" } |
        Where-Object { $_.FullName -notmatch "\\scripts\\validate-phase3\.ps1$" } |
        Select-String -Pattern $Pattern -ErrorAction SilentlyContinue

    if ($matches) {
        Fail "$Description found in repository content"
        $matches | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $($_.Path):$($_.LineNumber)"
        }
    } else {
        Pass "$Description not found"
    }
}

Write-Host "VDIForge Phase 3 static validation"

$requiredFiles = @(
    "ansible/playbooks/phase3.yml",
    "ansible/playbooks/kubernetes.yml",
    "ansible/playbooks/cluster-addons.yml",
    "ansible/roles/containerd/tasks/main.yml",
    "ansible/roles/kubernetes-common/tasks/main.yml",
    "ansible/roles/kubernetes-control-plane/tasks/main.yml",
    "ansible/roles/kubernetes-worker/tasks/main.yml",
    "kubernetes/calico/custom-resources.yaml",
    "kubernetes/namespaces/vdiforge-namespaces.yaml",
    "kubernetes/rbac/vdiforge-provisioner-foundation.yaml",
    "kubernetes/storage/local-path-provisioner.yaml",
    "kubernetes/metrics-server/metrics-server-local-patch.yaml",
    "kubernetes/kubevirt/phase3-test-vm.yaml",
    "scripts/phase3-networkpolicy-test.sh",
    "scripts/phase3-kubevirt-test-vm.sh",
    "scripts/validate-phase3-live.sh",
    "scripts/validate-phase3.ps1",
    "docs/KUBERNETES-KUBEVIRT.md",
    "docs/ADR/0010-local-path-storage-for-phase3.md"
)

foreach ($file in $requiredFiles) {
    Check-File $file
}

Check-ContentAbsent "BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY" "private key material"
Check-ContentAbsent "kubeadm join .+--token" "committed kubeadm join token"
Check-ContentAbsent "client-secret|refresh_token|id_token|access_token" "committed OAuth/token secret"
Check-ContentAbsent "kind:\s*Config\s*$" "committed kubeconfig"
function Check-NoClusterAdminBinding {
    $manifestFiles = Get-ChildItem kubernetes -Recurse -File | Where-Object { $_.Extension -in ".yml", ".yaml" }
    $matches = $manifestFiles | Select-String -Pattern "name:\s*cluster-admin|clusterRole:\s*cluster-admin" -ErrorAction SilentlyContinue
    if ($matches) {
        Fail "cluster-admin binding found in Kubernetes manifests"
        $matches | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
    } else {
        Pass "no cluster-admin bindings in Kubernetes manifests"
    }
}

Check-NoClusterAdminBinding

$floatingMatches = Get-ChildItem kubernetes, ansible -Recurse -File |
    Select-String -Pattern ":[Ll]atest|/latest/" -ErrorAction SilentlyContinue

if ($floatingMatches) {
    Fail "floating latest references found in Phase 3 manifests"
    $floatingMatches | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
} else {
    Pass "no floating latest references in Phase 3 manifests"
}

$requirementMatches = Select-String -Path "docs/REQUIREMENTS.md" -Pattern "^\| (FR|NFR|INFRA|K8S|KV|STOR|SEC|OBS|OPS)-\d{3} \|" -AllMatches
$ids = @()
foreach ($match in $requirementMatches) {
    foreach ($capture in $match.Matches) {
        if ($capture.Value -match "(FR|NFR|INFRA|K8S|KV|STOR|SEC|OBS|OPS)-\d{3}") {
            $ids += $Matches[0]
        }
    }
}
$duplicates = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    Fail "duplicate requirement IDs found"
    $duplicates | ForEach-Object { Write-Host "  $($_.Name)" }
} else {
    Pass "requirement IDs are unique"
}

if (Get-Command ansible-playbook -ErrorAction SilentlyContinue) {
    Push-Location ansible
    ansible-playbook -i inventory/local/hosts.yml playbooks/phase3.yml --syntax-check
    $syntaxExit = $LASTEXITCODE
    Pop-Location
    if ($syntaxExit -eq 0) { Pass "local Ansible syntax check" } else { Fail "local Ansible syntax check" }
} else {
    Write-Host "WARN: ansible-playbook not installed on this host; run live validation from vdi-control-01."
}

if (Get-Command ansible-lint -ErrorAction SilentlyContinue) {
    ansible-lint ansible
    if ($LASTEXITCODE -eq 0) { Pass "local ansible-lint" } else { Fail "local ansible-lint" }
} else {
    Write-Host "WARN: ansible-lint not installed on this host; run live validation from vdi-control-01."
}

if ($Live) {
    Write-Host "Running Phase 3 live validation over SSH on $ControlHost"
    ssh "$SshUser@$ControlHost" "cd ~/vdiforge-phase3-validation && bash scripts/validate-phase3-live.sh"
    if ($LASTEXITCODE -eq 0) { Pass "Phase 3 live validation" } else { Fail "Phase 3 live validation" }
}

if ($failures -ne 0) {
    Write-Host "Phase 3 validation: FAIL ($failures failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "Phase 3 validation: PASS" -ForegroundColor Green
