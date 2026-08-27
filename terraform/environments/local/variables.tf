variable "vm_folder" {
  description = "VirtualBox VM folder on the Windows host."
  type        = string
  default     = "F:\\VirtualBox VMs"

  validation {
    condition     = length(var.vm_folder) > 0
    error_message = "vm_folder cannot be empty."
  }
}

variable "ssh_user" {
  description = "Administrative SSH user for all lab nodes."
  type        = string
  default     = "vdiadmin"
}

variable "host_only_adapter_name" {
  description = "VirtualBox host-only adapter used for node and host management traffic."
  type        = string
  default     = "VirtualBox Host-Only Ethernet Adapter"
}

variable "host_only_subnet" {
  description = "Host-only subnet used by the Phase 2 lab."
  type        = string
  default     = "192.168.56.0/24"

  validation {
    condition     = can(cidrnetmask(var.host_only_subnet))
    error_message = "host_only_subnet must be a valid CIDR."
  }
}

variable "host_only_host_ip" {
  description = "Windows host IP on the VirtualBox host-only network."
  type        = string
  default     = "192.168.56.1"
}

variable "ubuntu_release" {
  description = "Installed Ubuntu Server release on the Phase 2 lab nodes."
  type        = string
  default     = "26.04 LTS"
}
