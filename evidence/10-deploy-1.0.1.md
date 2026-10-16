# Deploying image 1.0.1 - the remediation loop, closed

**When:** 16 Oct 2026, 18:40 UTC. **Approved by:** Graham Hathway (owner), in writing, before apply - the GitHub `kronos-prod` approval gate was not yet live because the self-hosted runner is still being set up, so the reviewed plan was applied from the runner host (Magnus) instead. Nothing other than the reviewed plan was applied.

## The loop
1. **Finding** - Wazuh SCA on VM 301 (image 1.0.0): 73%, 11 real gaps (`06-sca-after-analysis.md`).
2. **Tickets** - one GitHub issue per gap, written as security remediation tickets (#1-#4, #6, #7, #9, #10).
3. **Fix in code** - Ansible variables and two small systemd units, never on the server (this PR).
4. **Test** - Molecule (converge, idempotence, verify) and pre-commit 9/9.
5. **Build** - Packer image `ch-rocky9-base-1.0.1` (template 9202); CIS role 457 ok / 0 failed; real-VM verify gate 28/28.
6. **Plan + policy** - `terraform plan`: 1 to add, 0 to change, 1 to destroy (VM 301 replaced, template 9201 -> 9202, same name/IP/tags). Policy-as-code (PR #5): 8 passed, 0 failures, 1 warning ("plan will REPLACE this resource") - the warning is exactly what the owner reviewed and approved. `05-plan-1.0.1-apply.log`
7. **Apply** - `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.` `05-apply-1.0.1.log`
8. **Re-scan** - Wazuh SCA on the new VM 301 (agent 044).

## Result

| | upstream | 1.0.0 | **1.0.1** |
|---|---|---|---|
| CIS Rocky 9 v1.0.0 score | 53% | 73% | **76%** |
| pass / fail | 87 / 77 | 122 / 43 | **127 / 38** |

Fixed 1.0.0 -> 1.0.1 (5), regressed (0):
- 1.3.2 Ensure filesystem integrity is regularly checked (#3)
- 2.2.16 nfs-utils not installed (#1)
- 2.2.17 rpcbind not installed (#1)
- 5.4.1 custom authselect profile used (#2)
- 5.4.2 authselect includes with-faillock (#2)

Raw: `10-sca-1.0.1-summary.json`, `10-sca-1.0.1-checks.jsonl`.

## What the deploy found (post-deploy verify: 18 ok, 1 failed)
**What the verifier observed:** `06-verify-vm-301-1.0.1.log` fails one assertion on the *deployed* VM: `aidecheck.service` is not in an enabled/OK state. The same check passed 28/28 inside the build. The verifier only checks unit state; it does not run `aide --check` itself.

**What the diagnosis found:** this comes from a separate read-only check, not from the verifier log. The unit's journal (`10-aide-301-first-check.txt`) shows the first scheduled check exited **7**, meaning differences were found: 68 added, 1 removed and 62 changed of 40,041 entries. The entry list points to two causes:
1. **The baseline is taken part-way through the build.** Most entries are changes the CIS role made *after* it initialised AIDE: journal-remote/upload packages and units, sysctl.d and audit rules, crypto-policy back-ends, passwd/group/shadow, the new kernel's boot entries, `/etc/ch-mirror-release` and the aidecheck units themselves.
2. **Per-instance first-boot changes** made by cloud-init and the clone: hostname, hosts, machine-id, ifcfg-eth0 and persistent-net rules.

Either cause alone means every new VM raises a false integrity alert, which trains people to ignore AIDE. Raised as **#17**. The fix in image 1.0.2 removes the database from the image and creates a per-instance baseline on first boot, after cloud-init. 1.0.2 also adds a post-deploy check that actually runs `aide --check`. **#14** (old kernel RPM retained) is fixed in the same image.

This is why there are two verify points: a build gate that proves the image, and a post-deploy check that proves the instance.
