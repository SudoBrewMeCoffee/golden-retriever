# Copy to kronos.pkrvars.hcl (git-ignored) and fill in. Token via env is preferred.
proxmox_url      = "https://10.69.1.139:8006/api2/json"
proxmox_username = "terraform@pve!tf"
proxmox_token    = "REPLACE_ME"
node             = "pve"
bridge           = "vmbr0"
storage_pool     = "local-zfs"
