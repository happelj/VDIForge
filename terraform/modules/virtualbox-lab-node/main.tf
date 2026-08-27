resource "terraform_data" "node_spec" {
  input = {
    name                  = var.name
    role                  = var.role
    cpu_count             = var.cpu_count
    memory_mb             = var.memory_mb
    disk_gb               = var.disk_gb
    disk_format           = var.disk_format
    vm_folder             = var.vm_folder
    disk_path             = "${var.vm_folder}\\${var.name}\\${var.name}.vdi"
    host_only_ipv4        = var.host_only_ipv4
    ssh_target            = "${var.ssh_user}@${var.host_only_ipv4}"
    host_only_adapter     = var.host_only_adapter_name
    adapter_1             = "NAT"
    adapter_2             = "Host-only Adapter"
    nested_virtualization = var.nested_virtualization
    pae_nx                = var.pae_nx
    ubuntu_release        = var.ubuntu_release
  }
}
