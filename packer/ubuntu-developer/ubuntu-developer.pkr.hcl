packer {
  required_version = ">= 1.16.0, < 1.17.0"

  required_plugins {
    ansible = {
      version = "1.1.6"
      source  = "github.com/hashicorp/ansible"
    }

    qemu = {
      version = "1.1.6"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

locals {
  ansible_dir   = abspath("${path.root}/../../ansible")
  image_id      = "ubuntu-developer"
  shared_dir    = abspath("${path.root}/../shared")
  artifact_dir  = "${abspath(var.artifact_root)}/${local.image_id}/${var.image_version}"
  artifact_name = "${local.image_id}-${var.image_version}-${var.architecture}.qcow2"
  artifact_path = "${local.artifact_dir}/${local.artifact_name}"
}

source "qemu" "ubuntu_cloud" {
  accelerator = "kvm"
  boot_wait   = "5s"
  cd_content = {
    "meta-data" = "instance-id: ${local.image_id}-${var.image_version}\nlocal-hostname: ${local.image_id}\n"
    "user-data" = templatefile("${local.shared_dir}/cloud-init/user-data.pkrtpl", {
      build_username = var.build_username
      ssh_public_key = var.ssh_public_key
    })
  }
  cd_label             = "cidata"
  cpus                 = var.cpus
  disk_image           = true
  disk_interface       = "virtio"
  disk_size            = var.disk_size
  format               = "qcow2"
  headless             = true
  iso_checksum         = "sha256:${var.source_checksum}"
  iso_url              = var.source_url
  machine_type         = "q35"
  memory               = var.memory
  net_device           = "virtio-net"
  output_directory     = local.artifact_dir
  qemu_binary          = "qemu-system-x86_64"
  shutdown_command     = "sudo shutdown -P now"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  ssh_username         = var.build_username
  vm_name              = local.artifact_name
}

build {
  sources = ["source.qemu.ubuntu_cloud"]

  provisioner "ansible" {
    playbook_file = "${local.ansible_dir}/playbooks/image-ubuntu-developer.yml"
    user          = var.build_username

    ansible_env_vars = [
      "ANSIBLE_ROLES_PATH=${local.ansible_dir}/roles",
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=default"
    ]

    extra_arguments = [
      "--extra-vars",
      "vdiforge_image_name=${local.image_id} vdiforge_image_version=${var.image_version} vdiforge_image_ubuntu_release=${var.ubuntu_release} vdiforge_image_source_checksum=${var.source_checksum}"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "VDIFORGE_IMAGE_NAME=${local.image_id}"
    ]
    script = "${local.shared_dir}/scripts/validate-image.sh"
  }

  post-processor "shell-local" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -euo pipefail",
      "bash '${local.shared_dir}/scripts/generalize-artifact.sh' '${local.artifact_path}'",
      "bash '${local.shared_dir}/scripts/write-manifest.sh' '${local.image_id}' '${var.image_version}' '${local.artifact_path}' '${var.source_url}' '${var.source_checksum}' '${var.ubuntu_release}' '${var.architecture}'"
    ]
  }
}
