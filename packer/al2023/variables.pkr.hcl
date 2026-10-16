variable "proxmox_url" { type = string }
variable "proxmox_username" { type = string }
variable "proxmox_token" {
  type      = string
  sensitive = true
}
variable "proxmox_insecure" {
  type    = bool
  default = true
}
variable "node" { type = string }
variable "bridge" {
  type    = string
  default = "vmbr0"
}
variable "storage_pool" {
  type    = string
  default = "local-zfs"
}
variable "source_template_id" {
  type        = number
  default     = 9210
  description = "al2023-kvm-base: AWS AL2023 KVM qcow2, SHA256-verified (README, Amazon Linux 2023)."
}
variable "target_template_id" {
  type    = number
  default = 9211
}
variable "name_prefix" {
  type    = string
  default = "al2023-cis-base"
}
variable "version" {
  type        = string
  description = "Semantic version appended to the template name (CH convention)."
}
variable "ssh_username" {
  type    = string
  default = "ec2-user"
}
variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/packer-builder"
}
variable "build_ip" {
  type        = string
  default     = "10.69.1.74"
  description = "Fixed IP for the temporary build VM - outside the UniFi DHCP pool (10.69.1.100-254)."
}
variable "gateway" {
  type    = string
  default = "10.69.1.1"
}
