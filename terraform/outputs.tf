output "vm_id" {
  value = proxmox_virtual_environment_vm.app.vm_id
}

output "ipv4" {
  value = var.ipv4_address
}
