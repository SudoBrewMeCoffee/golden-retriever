variable "proxmox_endpoint" {
  type    = string
  default = "https://10.69.1.139:8006/"
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_id" {
  description = "Hardened template built by Packer (ch-rocky9-base-<version>). 9201 = 1.0.0, 9202 = 1.0.1, 9203 = 1.0.2."
  type        = number
  default     = 9203
}

variable "vm_id" {
  type    = number
  default = 301
}

variable "vm_name" {
  type    = string
  default = "ch-app-01"
}

variable "datastore_id" {
  type    = string
  default = "local-zfs"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "ssh_public_key" {
  description = "Admin public key injected by cloud-init."
  type        = string
}

variable "tags" {
  type    = list(string)
  default = ["ch-mirror", "cis-l1", "kronos-managed"]
}

variable "ipv4_address" {
  description = "Fixed address for the VM, outside the UniFi DHCP pool (10.69.1.100-254)."
  type        = string
  default     = "10.69.1.72/24"
}

variable "gateway" {
  type    = string
  default = "10.69.1.1"
}
