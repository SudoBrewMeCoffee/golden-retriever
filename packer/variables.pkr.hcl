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
  type    = number
  default = 9200
}
variable "target_template_id" {
  type    = number
  default = 9201
}
variable "name_prefix" {
  type    = string
  default = "ch-rocky9-base"
}
variable "version" {
  type        = string
  description = "Semantic version appended to the template name (reference-pipeline convention)."
}
variable "ssh_username" {
  type    = string
  default = "rocky"
}
variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/packer-builder"
}
variable "playbook_file_path" {
  type    = string
  default = "../ansible/playbook.yml"
}

variable "build_ip" {
  type        = string
  default     = "10.69.1.71"
  description = "Fixed IP for the temporary build VM - outside the UniFi DHCP pool (10.69.1.100-254)."
}
variable "gateway" {
  type    = string
  default = "10.69.1.1"
}
