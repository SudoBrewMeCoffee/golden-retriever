# Deploying image 1.0.2 through the pipeline

**When:** 17 Oct 2026, 07:48 UTC. **How:** the first deploy that went entirely through GitHub Actions. Merging #21 to `main` triggered `ci.yml` on the self-hosted runner. It ran three jobs in order:
1. checks;
2. `terraform plan` (on the runner host, with the plan kept there);
3. conftest policy.

It then stopped at the `kronos-prod` environment. The owner reviewed the plan and approved it in GitHub. Admin bypass is off, so not even the repo owner can skip that step. Only then did `apply` run, and it applied that exact saved plan.

Run: https://github.com/grahamhat/ch-mirror/actions/runs/38998590074

## The change
| | |
|---|---|
| Tickets | #14 (old kernel RPM kept after patching), #17 (AIDE baseline baked into the image) |
| Code | PR #20, image 1.0.2 (template 9203) |
| Plan | VM 301 `ch-app-01` replaced, template 9202 -> 9203: **1 to add, 0 to change, 1 to destroy**. Same name, IP and tags (`05-plan-1.0.2-pipeline.log`) |
| Policy | conftest: 10 tests, **9 passed, 1 warning, 0 failures**. The warning ("plan will REPLACE this resource") is the change being approved |
| Approval | `kronos-prod`, required reviewer = owner, admin bypass off |
| Apply | `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.` (`05-apply-1.0.2-pipeline.log`) |
| Rollback | Set `template_id` back to 9202 and run the same pipeline |

## Proving the instance, not just the image
`ansible/verify-deployed.yml` was run against the new VM 301 **before anything else was installed on it**: **16 ok, 0 failed** (`06-verify-deployed-301-1.0.2.log`).
- **#17:** the first-boot AIDE baseline unit ran and succeeded, and the per-instance database exists. `aide --check` is **run** and returns **rc 0**: no differences. Under 1.0.1, the first check on a new VM found 131.
- **#14:** exactly **one** kernel is installed (`kernel-5.14.0-687.58.1.el9_8`), and it is the running kernel.
- **Version:** the release stamp reads `ch-rocky9-base 1.0.2`.

## Wazuh after deploy (agent 046)
The Wazuh agent was enrolled after verification. Installing it is a real, approved change, so the AIDE baseline was then updated (`aide --update`) as normal AIDE operations. After the update, `aide --check` returned rc 0.

| | 1.0.0 | 1.0.1 | **1.0.2** |
|---|---|---|---|
| CIS Rocky 9 v1.0.0 score | 73% | 76% | **76%** (127 pass / 38 fail) |
| Changes vs 1.0.1 | | | 0 fixed, **0 regressed** (same control results) |
| Wazuh vulnerability findings on VM 301 | 336 (all on the old, non-running kernel) | not measured | **0** |

**Vulnerability count, how it was measured:** the indexer had 438 inventoried packages for agent 046 and **0** documents in `wazuh-states-vulnerabilities-*`. This was read about 7 minutes after enrolment. The same detector reports findings for other agents in the estate, so it is working. Under 1.0.0, the 336 findings appeared within about 3 minutes. The query was read-only and used the indexer's client certificate. Raw SCA data: `12-sca-301-1.0.2-summary.json`, `12-sca-301-1.0.2-checks.jsonl`.

The CIS score did not move; 1.0.2 was not a CIS change. It fixed two operational problems the scanner could not see: patched hosts still reporting hundreds of CVEs, and every new VM raising a false integrity alert. Both are now gone on the deployed instance.

## Noticed during the deploy (follow-ups)
- **Apply warning:** `error retrieving VM network interfaces from agent: 403 ... VM.GuestAgent.Audit`. The Terraform API token has no guest-agent read permission, so Terraform cannot read the VM's IP back. It is harmless here because the IP is static. Adding the permission is a change to the token's privileges, so the owner makes it, not the pipeline. Least privilege is a reasonable reason to leave it as it is.
- **SELinux denial:** aide (run by systemd) cannot read file-system details on `/boot/efi`. It is a warning only, the checks pass, and it gets its own ticket.
