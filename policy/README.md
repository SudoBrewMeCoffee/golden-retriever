# Policy as code - Terraform guardrails

Open Policy Agent policies, run with [conftest](https://www.conftest.dev/), that check the
**Terraform plan** before anyone can approve an apply. A `deny` fails the CI `plan` job, so an
unsafe change never reaches the `kronos-prod` approval gate. A `warn` is shown to the reviewer
but does not block.

Static scanners (tflint, Trivy in pre-commit) read the HCL. These policies read the *plan*, so
they see the real values after variables, `-var` overrides and `*.auto.tfvars` are applied, and
they encode rules that are specific to this estate.

## Rules (`terraform/proxmox_vm.rego`)

Applies to every `proxmox_virtual_environment_vm` the plan creates, updates or keeps.

| Rule | Result | What it prevents | Came from |
|---|---|---|---|
| `cpu.type` must be `host` (missing = provider default `qemu64`) | deny | A RHEL 9 VM that never boots - RHEL 9 needs x86-64-v2, which `kvm64`/`qemu64` don't provide | what-broke #11, #15 |
| Tags `ch-mirror`, `cis-l1`, `kronos-managed` all present | deny | Untracked guests: tags are how the estate knows a VM is hardened, CIS-scanned and Terraform-owned | Estate convention |
| Static IPv4 address set, never `dhcp` | deny | A duplicate IP: the DHCP pool overlaps live containers with static addresses | what-broke #4 |
| `vm_id` in 300-309 | deny | Colliding with, or replacing, another guest's VM ID | ch-mirror ID allocation |
| Cloned from a template in 9200-9299 | deny | A VM built from anything other than a CIS-hardened ch-mirror image | Pipeline design |
| Any resource being destroyed or replaced | warn | A destructive change slipping through review unnoticed | what-broke #15 was caught by reading the plan |

## Run locally

```bash
brew install conftest                      # 0.71.x (OPA 1.x, Rego v1 syntax)

conftest verify -p policy/terraform        # unit tests, no credentials (also a pre-commit hook)

terraform/tf.sh plan                       # writes terraform/tfplan
scripts/policy-check.sh                    # terraform show -json + conftest test
```

`policy-check.sh` writes the plan JSON to a temp file outside the repo and deletes it on exit:
plan JSON contains input variables, including sensitive ones, so it must never be committed.

Evidence: `evidence/08-policy-blocked.log` (a deliberately unsafe plan, denied) and
`evidence/08-policy-pass.log` (the real configuration, passing).
