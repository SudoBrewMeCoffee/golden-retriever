terraform {
  # One state for local runs and the CI runner (fresh checkout each job).
  # Lives outside the repo; backed up with the KRONOS backups.
  backend "local" {
    path = "/Users/graham/ch-mirror-state/terraform.tfstate"
  }

  required_version = ">= 1.6" # works with OpenTofu >= 1.6 too
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token # "terraform@pve!tf=<secret>" — from TF_VAR_proxmox_api_token
  insecure  = var.proxmox_insecure
}
