#!/bin/bash
# ch-mirror Terraform wrapper (local and CI). Usage: tf.sh plan|apply|output [args]
# The Proxmox token goes into the environment only; never printed or committed.
set -eo pipefail
export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH
cd "$(dirname "$0")"
if [ -z "${TF_VAR_proxmox_api_token:-}" ]; then
  export TF_VAR_proxmox_api_token="$(cat ~/.config/ch-mirror/pve-token)"
fi
if [ -z "${TF_VAR_ssh_public_key:-}" ]; then
  export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
fi
terraform init -input=false >/dev/null
case "$1" in
  plan)   terraform plan -input=false -out=tfplan "${@:2}" ;;
  apply)  terraform apply -input=false tfplan ;;   # only ever the reviewed plan
  *)      terraform "$@" ;;
esac
