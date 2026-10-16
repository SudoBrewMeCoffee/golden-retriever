resource "proxmox_virtual_environment_vm" "app" {
  name        = var.vm_name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = "Deployed from CIS-hardened template ${var.template_id} via ch-mirror pipeline. Managed by Terraform — do not edit in the UI."
  tags        = var.tags

  clone {
    vm_id = var.template_id
    full  = true
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host" # RHEL 9 needs x86-64-v2; provider default qemu64 cannot boot it (what-broke #15)
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = var.bridge
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.gateway
      }
    }
    user_account {
      username = "rocky"
      keys     = [var.ssh_public_key]
    }
  }

  # Hardening lives in the image; protect against accidental replacement.
  lifecycle {
    prevent_destroy = false # set true once this becomes a long-lived KRONOS service
  }
}
