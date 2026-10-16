#!/bin/bash
# Policy-as-code gate: run the conftest policies in policy/terraform against a saved plan.
# Usage: scripts/policy-check.sh [terraform-dir]   (default: terraform/, which must contain tfplan)
# Exit code is non-zero if any policy denies the plan - CI fails the job on that.
#
# Plan JSON can contain sensitive input values (e.g. the API token), so it is written to a
# temp file outside the repo and deleted on exit. Only conftest's messages are printed.
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH

repo="$(cd "$(dirname "$0")/.." && pwd)"
tfdir="${1:-$repo/terraform}"

plan_json="$(mktemp "${TMPDIR:-/tmp}/ch-mirror-plan.XXXXXX")"
trap 'rm -f "$plan_json"' EXIT

terraform -chdir="$tfdir" show -json tfplan > "$plan_json"
conftest test --no-color --parser json -p "$repo/policy/terraform" "$plan_json"
