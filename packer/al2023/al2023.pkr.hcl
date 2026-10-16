# Amazon Linux 2023 counterpart of ../rocky9.pkr.hcl - mirrors companieshouse/amzn2023-base-ami.
# Separate directory so `packer build .` in packer/ (RHEL) never picks this up.
# Source: AWS's official AL2023 KVM image (cdn.amazonlinux.com), template 9210.

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

locals {
  ansible_dir = "${path.root}/../../ansible"
}

source "proxmox-clone" "al2023" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure

  node        = var.node
  clone_vm_id = var.source_template_id
  full_clone  = true

  vm_id                = var.target_template_id
  template_name        = "${var.name_prefix}-${var.version}"
  tags                 = "ch-mirror;kronos-managed;cis-l1;golden-image;al2023"
  template_description = "CIS-hardened Amazon Linux 2023 base, v${var.version}, built by Packer ${formatdate("YYYY-MM-DD hh:mm", timestamp())}"

  cores           = 2
  memory          = 2048
  cpu_type        = "host" # never inherit the plugin default kvm64 (what-broke #11)
  os              = "l26"
  scsi_controller = "virtio-scsi-single"

  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  # Proxmox's cloud-init drive is a NoCloud (cidata) seed - what AWS document for AL2023 on KVM
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
  task_timeout         = "10m" # hardened guest shutdown can exceed the 60s default (what-broke #14)
}

build {
  name    = "al2023-cis-base"
  sources = ["source.proxmox-clone.al2023"]

  # AL2023 KVM image has no guest agent by default; Proxmox shutdown/IP reporting want it.
  # dnf update stays within the image's locked AL2023 release (deterministic upgrades).
  provisioner "shell" {
    inline = [
      "sudo dnf -y install python3 qemu-guest-agent",
      "sudo systemctl enable --now qemu-guest-agent",
      "sudo dnf -y update"
    ]
  }

  # Level 1 is chosen by tag in AMAZON2023-CIS - its level vars are not read (what-broke #16).
  # Plus the host firewall controls 3.4.1.2 + 3.4.2.1, which CIS AL2023 puts in Level 2
  # (AWS has security groups; Proxmox doesn't) - what-broke #18.
  provisioner "ansible" {
    playbook_file    = "${local.ansible_dir}/playbook-al2023.yml"
    user             = var.ssh_username
    use_proxy        = false
    extra_arguments  = ["--tags", "level1-server,rule_3.4.1.2,rule_3.4.2.1", "--extra-vars", "build_version=${var.version}"]
    ansible_env_vars = ["ANSIBLE_ROLES_PATH=${local.ansible_dir}/roles", "ANSIBLE_HOST_KEY_CHECKING=False"]
  }

  # Same real-VM gate as the RHEL image, run as ec2-user
  provisioner "ansible" {
    playbook_file    = "${local.ansible_dir}/verify-vm.yml"
    user             = var.ssh_username
    use_proxy        = false
    extra_arguments  = ["--extra-vars", "admin_user=${var.ssh_username}"]
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
  }

  # CH: ssh_clear_authorized_keys = true
  # Packer uploads inline scripts to /tmp, which CIS 1.1.2.4 has just made noexec
  # (AL2023 mounts /tmp as tmpfs, so the role remounts it live) - what-broke #19.
  provisioner "shell" {
    remote_folder = "/home/${var.ssh_username}"
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "rm -f ~/.ssh/authorized_keys",
      "sudo rm -f /root/.ssh/authorized_keys"
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/../../evidence/packer-manifest-al2023.json"
    strip_path = true
  }
}
