# CIS deviations register - Amazon Linux 2023 image

Benchmark: CIS Amazon Linux 2023 v1.0.0, Level 1 - Server (applied via ansible-lockdown/AMAZON2023-CIS 1.5.0,
`--tags level1-server,rule_3.4.1.2,rule_3.4.2.1`). Template `al2023-cis-base-<ver>` (9211). The Rocky 9 register is `deviations.md`.

| ID | Control | Deviation | Reason | Compensating control | Owner / review |
|---|---|---|---|---|---|
| AL-D1 | Level 2 controls (incl. auditd rules 5.2.x, SELinux 1.6.1.5, nftables policy) | Not applied, except host firewall 3.4.1.2 + 3.4.2.1, which ARE applied (stricter than L1) | Level 1 server profile chosen for the base image; on-prem has no security groups, so the firewall is added back | SELinux still set to enforcing by L1 1.6.1.4; auditd installed and running (playbook post-task); Level 2 can be layered per workload | Graham |
| AL-D2 | 4.6.6 Ensure root password is set | Rule disabled (`amzn2023cis_rule_4_6_6: false`); root stays locked with no password | The AWS KVM image ships root locked. Setting one would put a shared root secret in every VM built from the template. The role's pre-flight stops the build otherwise | Root locked (no password login at all), root SSH login disabled, SSH limited to `ec2-user` with keys only; console access restricted to the Proxmox admin | Graham - review at each image version |
| AL-D3 | Users must provide password for escalation (Wazuh CIS AL2023 5.3.4) | Not applied: `ec2-user` keeps cloud-init NOPASSWD sudo. Wazuh SCA reports FAIL | Same as Rocky D2: key-only automation/admin account with no password. The AMAZON2023-CIS role has no task for this control, so nothing to switch off - found by the SCA scan, not the build | SSH limited to `ec2-user` (AllowUsers), key auth only, root locked and root SSH off, sudo logged | Graham - review at each image version |

Notes: CIS AL2023 v1.0.0 has no bootloader-password control (only config permissions). The role's
rule IDs don't match Wazuh's CIS AL2023 policy IDs (e.g. escalation is 5.3.4 in Wazuh), so map by title.
SCA after hardening (throwaway VM from 9211): 117 pass / 63 fail / 3 n/a = 65% - see `09-sca-al2023-summary.json`.
