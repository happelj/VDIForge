output "lab_network" {
  description = "VirtualBox host-only network design."
  value = {
    subnet          = var.host_only_subnet
    host_ip         = var.host_only_host_ip
    adapter         = var.host_only_adapter_name
    internet        = "Adapter 1 NAT per VM"
    management      = "Adapter 2 host-only per VM"
    dns             = "Provided by NAT for outbound access"
    public_exposure = "No direct public VM exposure"
  }
}

output "nodes" {
  description = "Validated VDIForge local lab node specifications."
  value       = { for name, node in module.nodes : name => node.spec }
}

output "ssh_targets" {
  description = "SSH targets for host administration."
  value       = { for name, node in module.nodes : name => node.spec.ssh_target }
}

output "ansible_inventory" {
  description = "Expected Ansible inventory addresses."
  value = {
    all = {
      vars = {
        ansible_user = var.ssh_user
      }
      hosts = { for name, node in module.nodes : name => {
        ansible_host = node.spec.host_only_ipv4
        role         = node.spec.role
      } }
    }
  }
}
