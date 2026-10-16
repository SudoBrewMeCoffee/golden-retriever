# Mirrors companieshouse/rhel9-base-ami: clone a source image, provision with
# Ansible (CIS hardening), clear SSH keys, publish a semver-tagged template.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

source "proxmox-clone" "rocky9" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure

  node        = var.node
  clone_vm_id = var.source_template_id
  full_clone  = true

  vm_id                = var.target_template_id
  template_name        = "${var.name_prefix}-${var.version}"
  tags                 = "ch-mirror;kronos-managed;cis-l1;golden-image"
  template_description = "CIS-hardened Rocky 9 base, v${var.version}, built by Packer ${formatdate("YYYY-MM-DD hh:mm", timestamp())}"

  cores           = 2
  memory          = 2048
  cpu_type        = "host" # RHEL 9 needs x86-64-v2; plugin default kvm64 cannot boot it (what-broke #11)
  os              = "l26"
  scsi_controller = "virtio-scsi-single"

  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool
  ipconfig {
    ip      = "${var.build_ip}/24"
    gateway = var.gateway
  }

  ssh_host             = var.build_ip
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "15m"
  qemu_agent           = true
  task_timeout         = "10m" # hardened guest takes ~90s to shut down; plugin default is 60s (what-broke #14)
}

build {
  name    = "ch-rocky9-base"
  sources = ["source.proxmox-clone.rocky9"]

  provisioner "shell" {
    inline = ["sudo dnf -y install python3 && sudo dnf -y update"]
  }

  provisioner "ansible" {
    playbook_file    = var.playbook_file_path
    user             = var.ssh_username
    use_proxy        = false
    extra_arguments  = ["--extra-vars", "build_version=${var.version}"]
    ansible_env_vars = ["ANSIBLE_ROLES_PATH=../ansible/roles", "ANSIBLE_HOST_KEY_CHECKING=False"]
  }

  # Gate: prove the controls are actually in effect on the real VM before the
  # image is published. Molecule can't (containers skip 78 controls) - what-broke #12.
  provisioner "ansible" {
    playbook_file    = "../ansible/verify-vm.yml"
    user             = var.ssh_username
    use_proxy        = false
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
  }

  # CH: ssh_clear_authorized_keys = true
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "rm -f ~/.ssh/authorized_keys",
      "sudo rm -f /root/.ssh/authorized_keys"
    ]
  }

  post-processor "manifest" {
    output     = "../evidence/packer-manifest.json"
    strip_path = true
  }
}
