.PHONY: ci validate-phase1 validate-phase2 validate-phase3 validate-phase3-live validate-phase4 validate-phase4-live validate-phase5 validate-phase5-live validate-phase6 validate-phase6-live validate-phase7 validate-phase7-live validate-phase13 phase6-install-build-tools phase6-build-all phase6-build-devops phase6-kubevirt-test phase7-install-container-build-tools phase7-create-secrets phase7-prepare-golden-source phase7-build-load-image phase7-rbac-test phase7-networkpolicy-test phase7-api-e2e-test install-helm-client phase5-create-secrets phase5-configure-keycloak phase5-oidc-test phase5-networkpolicy-test infra-init infra-plan infra-apply infra-output infra-destroy-spec configure configure-phase3 remove-temp-sudo terraform-init terraform-plan terraform-output ansible-syntax ansible-syntax-phase3 ansible-syntax-phase6 helm-lint helm-template helm-template-phase5 helm-template-phase7

ci:
	pwsh -NoProfile -File ./scripts/ci-local.ps1

validate-phase1:
	pwsh -NoProfile -File ./scripts/validate-phase1.ps1

validate-phase2:
	pwsh -NoProfile -File ./scripts/validate-phase2.ps1

validate-phase3:
	pwsh -NoProfile -File ./scripts/validate-phase3.ps1

validate-phase3-live:
	bash scripts/validate-phase3-live.sh

validate-phase4:
	pwsh -NoProfile -File ./scripts/validate-phase4.ps1

validate-phase4-live:
	bash scripts/validate-phase4-live.sh

validate-phase5:
	pwsh -NoProfile -File ./scripts/validate-phase5.ps1

validate-phase5-live:
	bash scripts/validate-phase5-live.sh

validate-phase6:
	pwsh -NoProfile -File ./scripts/validate-phase6.ps1

validate-phase6-live:
	bash scripts/validate-phase6-live.sh

validate-phase7:
	pwsh -NoProfile -File ./scripts/validate-phase7.ps1

validate-phase7-live:
	bash scripts/validate-phase7-live.sh

validate-phase13:
	pwsh -NoProfile -File ./scripts/validate-phase13.ps1

phase6-install-build-tools:
	bash scripts/phase6-install-build-tools.sh

phase6-build-all:
	bash scripts/phase6-build-all.sh

phase6-build-devops:
	bash scripts/phase6-build-image.sh ubuntu-devops

phase6-kubevirt-test:
	bash scripts/phase6-cdi-kubevirt-test.sh

phase7-create-secrets:
	bash scripts/phase7-create-local-secrets.sh

phase7-install-container-build-tools:
	bash scripts/phase7-install-container-build-tools.sh

phase7-prepare-golden-source:
	bash scripts/phase7-prepare-golden-source.sh

phase7-build-load-image:
	bash scripts/phase7-build-load-image.sh

phase7-rbac-test:
	bash scripts/phase7-rbac-test.sh

phase7-networkpolicy-test:
	bash scripts/phase7-networkpolicy-test.sh

phase7-api-e2e-test:
	python3 scripts/phase7-api-e2e-test.py

install-helm-client:
	bash scripts/install-helm-client.sh

phase5-create-secrets:
	bash scripts/phase5-create-local-secrets.sh

phase5-configure-keycloak:
	bash scripts/phase5-configure-keycloak.sh

phase5-oidc-test:
	python3 scripts/phase5-oidc-pkce-test.py

phase5-networkpolicy-test:
	bash scripts/phase5-networkpolicy-test.sh

helm-lint:
	helm lint ./helm/vdiforge

helm-template:
	helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --kube-version 1.36.4

helm-template-phase5:
	helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --kube-version 1.36.4

helm-template-phase7:
	helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --values ./helm/vdiforge/values-phase5-local.yaml --values ./helm/vdiforge/values-phase7-local.yaml --kube-version 1.36.4

infra-init: terraform-init

infra-plan: terraform-plan

infra-apply:
	terraform -chdir=terraform/environments/local apply

infra-output: terraform-output

infra-destroy-spec:
	terraform -chdir=terraform/environments/local destroy

configure:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --ask-become-pass

configure-phase3:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible

remove-temp-sudo:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/remove-temporary-sudo.yml --private-key ~/.ssh/vdiforge_ansible

terraform-init:
	terraform -chdir=terraform/environments/local init

terraform-plan:
	terraform -chdir=terraform/environments/local plan

terraform-output:
	terraform -chdir=terraform/environments/local output

ansible-syntax:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --syntax-check

ansible-syntax-phase3:
	cd ansible && ansible-playbook -i inventory/local/hosts.yml playbooks/phase3.yml --syntax-check

ansible-syntax-phase6:
	cd ansible && ansible-playbook -i localhost, playbooks/image-ubuntu-base.yml --syntax-check
	cd ansible && ansible-playbook -i localhost, playbooks/image-ubuntu-developer.yml --syntax-check
	cd ansible && ansible-playbook -i localhost, playbooks/image-ubuntu-devops.yml --syntax-check
