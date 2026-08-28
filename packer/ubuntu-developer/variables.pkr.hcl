variable "image_version" {
  type    = string
  default = "1.0.0"
}

variable "ubuntu_release" {
  type    = string
  default = "26.04 LTS"
}

variable "architecture" {
  type    = string
  default = "amd64"
}

variable "source_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "source_checksum" {
  type    = string
  default = "8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035"
}

variable "artifact_root" {
  type    = string
  default = "../../artifacts/images"
}

variable "build_username" {
  type    = string
  default = "packer"
}

variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZESUZvcmdlUGFja2VyUGxhY2Vob2xkZXJLZXkK vdiforge-packer-placeholder"
}

variable "ssh_private_key_file" {
  type    = string
  default = "../../.local/phase6/packer_ed25519"
}

variable "ssh_timeout" {
  type    = string
  default = "20m"
}

variable "disk_size" {
  type    = string
  default = "28G"
}

variable "memory" {
  type    = number
  default = 3072
}

variable "cpus" {
  type    = number
  default = 2
}
