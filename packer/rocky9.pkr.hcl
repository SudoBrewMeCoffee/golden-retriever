# Mirrors the reference pipeline's public rhel9 base-AMI repo: clone a source image, provision with
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

  # Issue #14: dnf installs kernels side by side, so the old kernel RPM stays
  # installed and the vulnerability scanner reports its CVEs on a patched host.
  # Reboot into the newest kernel, then remove every older installonly package.
  provisioner "shell" {
    inline            = ["echo 'Rebooting into the updated kernel'", "sudo systemctl reboot"]
    expect_disconnect = true
  }

  # pause_before gives the VM time to go down before Packer reconnects.
  # `dnf remove --oldinstallonly` removes every installonly package except the
  # newest (and never the running kernel), but exits 1 when there is nothing
  # to remove, so it only runs when repoquery finds an old package.
  provisioner "shell" {
    pause_before = "45s"
    inline = [
      "set -eu",
      "RUNNING=$(uname -r)",
      "NEWEST=$(rpm -q kernel --qf '%%{VERSION}-%%{RELEASE}.%%{ARCH}\\n' | sort -V | tail -n 1)",
      "echo \"Running kernel: $RUNNING, newest installed: $NEWEST\"",
      "if [ \"$RUNNING\" != \"$NEWEST\" ]; then echo 'Not running the newest kernel - refusing to remove kernels'; exit 1; fi",
      "OLD=$(dnf repoquery --installonly --latest-limit=-1 -q)",
      "if [ -n \"$OLD\" ]; then echo \"Removing: $OLD\"; sudo dnf -y remove --oldinstallonly; else echo 'No old kernels to remove'; fi",
      "rpm -q kernel"
    ]
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

  # Reference pipeline: ssh_clear_authorized_keys = true
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      # Issue #17: never ship an AIDE baseline. aide-firstboot.service builds
      # one per instance after cloud-init finishes. This runs last, after the
      # kernel reboot and the verify gate, so nothing changes after it.
      "sudo rm -f /var/lib/aide/aide.db.gz /var/lib/aide/aide.db.new.gz",
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
