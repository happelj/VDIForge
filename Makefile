.PHONY: validate-phase1 validate-phase2 infra-init infra-plan infra-apply infra-output infra-destroy-spec configure terraform-init terraform-plan terraform-output ansible-syntax

validate-phase1:
	pwsh -NoProfile -File ./scripts/validate-phase1.ps1

validate-phase2:
	pwsh -NoProfile -File ./scripts/validate-phase2.ps1

infra-init: terraform-init

infra-plan: terraform-plan

infra-apply:
	terraform -chdir=terraform/environments/local apply

infra-output: terraform-output

infra-destroy-spec:
	terraform -chdir=terraform/environments/local destroy

configure:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --ask-become-pass

terraform-init:
	terraform -chdir=terraform/environments/local init

terraform-plan:
	terraform -chdir=terraform/environments/local plan

terraform-output:
	terraform -chdir=terraform/environments/local output

ansible-syntax:
	ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --syntax-check
