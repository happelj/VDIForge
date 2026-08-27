variable "name" {
  description = "VirtualBox VM name."
  type        = string

  validation {
    condition     = can(regex("^vdi-(control|worker)-[0-9]{2}$", var.name))
    error_message = "Node name must follow vdi-control-NN or vdi-worker-NN."
  }
}

variable "role" {
  description = "Future Kubernetes role for the node."
  type        = string

  validation {
    condition     = contains(["control-plane", "platform-worker", "vdi-worker"], var.role)
    error_message = "Role must be control-plane, platform-worker, or vdi-worker."
  }
}

variable "cpu_count" {
  description = "Virtual CPU allocation."
  type        = number

  validation {
    condition     = var.cpu_count >= 1 && var.cpu_count <= 16
    error_message = "cpu_count must be between 1 and 16."
  }
}

variable "memory_mb" {
  description = "Memory allocation in MiB."
  type        = number

  validation {
    condition     = var.memory_mb >= 2048
    error_message = "memory_mb must be at least 2048."
  }
}

variable "disk_gb" {
  description = "Virtual disk capacity in GiB."
  type        = number

  validation {
    condition     = var.disk_gb >= 30
    error_message = "disk_gb must be at least 30."
  }
}

variable "host_only_ipv4" {
  description = "Static host-only IPv4 address for the node."
  type        = string

  validation {
    condition     = can(cidrhost("${var.host_only_ipv4}/24", 0))
    error_message = "host_only_ipv4 must be a valid IPv4 address."
  }
}

variable "ssh_user" {
  description = "Administrative SSH user."
  type        = string

  validation {
    condition     = length(var.ssh_user) > 0
    error_message = "ssh_user cannot be empty."
  }
}

variable "vm_folder" {
  description = "VirtualBox VM folder on the Windows host."
  type        = string
}

variable "disk_format" {
  description = "Virtual disk format."
  type        = string
  default     = "VDI"

  validation {
    condition     = contains(["VDI"], var.disk_format)
    error_message = "Only VDI is supported by the Phase 2 VirtualBox lab spec."
  }
}

variable "host_only_adapter_name" {
  description = "VirtualBox host-only adapter name."
  type        = string
}

variable "nested_virtualization" {
  description = "Whether nested VT-x/AMD-V is required and enabled for the VM."
  type        = bool
  default     = false
}

variable "pae_nx" {
  description = "Whether PAE/NX is enabled for the VM."
  type        = bool
  default     = false
}

variable "ubuntu_release" {
  description = "Installed Ubuntu Server release."
  type        = string
}
