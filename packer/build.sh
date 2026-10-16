#!/bin/bash
# ch-mirror: build the CIS-hardened template.
# Usage: build.sh <semver> [template-id] [extra packer args...]
#   e.g. build.sh 1.0.2 9203     or     build.sh 1.0.2 9203 -var build_ip=10.69.1.71/24
# Patching = run this with a new version and a new template id, then point Terraform at it.
# Builds from the checkout this script lives in (works from a git worktree).
# Token: taken from PKR_VAR_proxmox_username/PKR_VAR_proxmox_token if already set (CI secrets),
# otherwise read from ~/.config/ch-mirror/pve-token into the environment only - never printed or written elsewhere.
set -eo pipefail
VER="${1:?version required, e.g. 1.0.0}"
shift
TID=9201
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then TID="$1"; shift; fi
export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH
if [ -z "$PKR_VAR_proxmox_token" ]; then
  T="$(cat ~/.config/ch-mirror/pve-token)"
  export PKR_VAR_proxmox_username="${T%%=*}"
  export PKR_VAR_proxmox_token="${T#*=}"
  unset T
fi
cd "$(dirname "$0")"
cat > kronos.pkrvars.hcl <<EOF
proxmox_url  = "https://10.69.1.139:8006/api2/json"
node         = "pve"
bridge       = "vmbr0"
storage_pool = "local-zfs"
EOF
packer init . >/dev/null
packer validate -var-file=kronos.pkrvars.hcl -var version="$VER" -var target_template_id="$TID" "$@" .
PACKER_LOG=0 packer build -color=false -var-file=kronos.pkrvars.hcl -var version="$VER" -var target_template_id="$TID" "$@" . \
  2>&1 | tee ../evidence/03-packer-build-$VER.log
