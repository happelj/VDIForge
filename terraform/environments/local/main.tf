locals {
  nodes = {
    vdi-control-01 = {
      role                  = "control-plane"
      cpu_count             = 4
      memory_mb             = 6144
      disk_gb               = 40
      host_only_ipv4        = "192.168.56.10"
      nested_virtualization = false
      pae_nx                = false
    }
    vdi-worker-01 = {
      role                  = "platform-worker"
      cpu_count             = 2
      memory_mb             = 6144
      disk_gb               = 50
      host_only_ipv4        = "192.168.56.11"
      nested_virtualization = false
      pae_nx                = false
    }
    vdi-worker-02 = {
      role                  = "vdi-worker"
      cpu_count             = 4
      memory_mb             = 8192
      disk_gb               = 60
      host_only_ipv4        = "192.168.56.12"
      nested_virtualization = true
      pae_nx                = true
    }
  }
}

module "nodes" {
  source = "../../modules/virtualbox-lab-node"

  for_each = local.nodes

  name                   = each.key
  role                   = each.value.role
  cpu_count              = each.value.cpu_count
  memory_mb              = each.value.memory_mb
  disk_gb                = each.value.disk_gb
  host_only_ipv4         = each.value.host_only_ipv4
  ssh_user               = var.ssh_user
  vm_folder              = var.vm_folder
  host_only_adapter_name = var.host_only_adapter_name
  nested_virtualization  = each.value.nested_virtualization
  pae_nx                 = each.value.pae_nx
  ubuntu_release         = var.ubuntu_release
}
