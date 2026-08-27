.PHONY: validate-phase1 validate-phase2 validate-phase3 validate-phase3-live validate-phase4 validate-phase4-live install-helm-client infra-init infra-plan infra-apply infra-output infra-destroy-spec configure configure-phase3 remove-temp-sudo terraform-init terraform-plan terraform-output ansible-syntax ansible-syntax-phase3 helm-lint helm-template

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

install-helm-client:
	bash scripts/install-helm-client.sh

helm-lint:
	helm lint ./helm/vdiforge

helm-template:
	helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --kube-version 1.36.4

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
