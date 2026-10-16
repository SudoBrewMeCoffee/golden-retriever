#!/bin/bash
# ch-mirror: build the CIS-hardened template.
# Usage: build.sh <semver> [extra packer args...]
#   e.g. build.sh 1.0.1 -var target_template_id=9202
# Builds from the checkout this script lives in (works from a git worktree).
# Token is read from ~/.config/ch-mirror/pve-token into the environment only - never printed or written to disk elsewhere.
set -eo pipefail
VER="${1:?version required, e.g. 1.0.0}"
shift
export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH
T="$(cat ~/.config/ch-mirror/pve-token)"
export PKR_VAR_proxmox_username="${T%%=*}"
export PKR_VAR_proxmox_token="${T#*=}"
unset T
cd "$(dirname "$0")"
cat > kronos.pkrvars.hcl <<EOF
proxmox_url  = "https://10.69.1.139:8006/api2/json"
node         = "pve"
bridge       = "vmbr0"
storage_pool = "local-zfs"
EOF
packer init . >/dev/null
packer validate -var-file=kronos.pkrvars.hcl -var version="$VER" "$@" .
PACKER_LOG=0 packer build -color=false -var-file=kronos.pkrvars.hcl -var version="$VER" "$@" . \
  2>&1 | tee ../evidence/03-packer-build-$VER.log
