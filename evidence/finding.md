# The finding

- **Source:** Wazuh 4.14.8 SCA on VM 300 `ch-before` (unhardened clone of base template 9200, Rocky Linux 9.8 GenericCloud). Wazuh auto-selected policy **CIS Rocky Linux 9 Benchmark v1.0.0** (Rocky is the RHEL 9 rebuild; control content matches the RHEL 9 benchmark).
- **Baseline score:** 53% - 87 pass, 77 fail, 2 not applicable (scan ended 2026-10-16 14:04 UTC). Full list: `01-sca-before-checks.jsonl`.
- **Control:** CIS 5.2.4 *Ensure SSH access is limited* (Wazuh check 31621). Same control is 5.1.7 in the CIS RHEL 9 v2.0 numbering the Ansible role uses.
- **Result before:** FAIL - `sshd -T` shows no `AllowUsers`, `AllowGroups`, `DenyUsers` or `DenyGroups`, so any local account with a valid key or password can attempt SSH.
- **Risk in plain English:** every account on the box is a remote-login target. If a service or test account is ever created with a weak password, it's reachable over SSH. Limiting SSH to named admin accounts shrinks the attack surface to the accounts you actually manage.
- **Why this one:** it's the control the first draft of the pipeline would have *silently skipped* - the guardrail was written with variable names the CIS role doesn't read (what-broke #1). The scan, not the code review, is what proves it's really applied.
- **Fix location:** `ansible/group_vars/all/cis.yml` (`rhel9cis_sshd_allowusers: rocky`) baked into the image by Packer - not a manual change on a server.
- **Test:** `ansible/verify-vm.yml` asserts `allowusers rocky` in `sshd -T` on the real VM inside every Packer build (Molecule can't - the role disables SSH controls in containers, what-broke #12).
- **Result after (VM 301 `ch-app-01`, image ch-rocky9-base-1.0.0):** **PASS** - Wazuh SCA 2026-10-16 15:18 UTC. `sshd -T` shows `allowusers rocky`; also asserted by `ansible/verify-vm.yml` inside the Packer build and again on 301 (`06-verify-vm-301.log`, 11/11).
- **Overall:** 53% -> **73%** (87 -> 122 pass, 77 -> 43 fail). Every remaining failure is classified in `06-sca-after-analysis.md`: 11 real gaps (next image version), 22 disk-layout, 9 benchmark-version mismatch, 1 accepted deviation.

## Known gaps the image will NOT close (be upfront about these)
- `/tmp`, `/var/tmp`, `/var/log/audit` separate partitions (1.1.2.x, 1.1.4.x, 1.1.6.x): the upstream cloud image is a single partition. Closing these needs a custom disk layout (kickstart build or LVM in the image) - next iteration.
- 5.3.4 *users must provide password for escalation*: deliberately not applied to the `rocky` automation account - deviation D2 in `deviations.md`.
