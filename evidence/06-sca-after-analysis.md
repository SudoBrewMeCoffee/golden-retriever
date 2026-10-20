# CIS before / after - what the scan says, and what it means

| | Before (VM 300, upstream image) | After (VM 301, ch-rocky9-base-1.0.0) |
|---|---|---|
| Policy | CIS Rocky Linux 9 v1.0.0 (Wazuh 4.14.8 SCA) | same |
| Score | **53%** - 87 pass / 77 fail | **73%** - 122 pass / 43 fail |
| Headline control 5.2.4 *Ensure SSH access is limited* | FAIL | **PASS** |

35 controls moved fail -> pass. 1 moved pass -> fail (rsyslog - explained below). Raw data: `01-sca-before-checks.jsonl`, `06-sca-after-checks.jsonl`. Every remaining failure was checked on the VM itself, not taken from the scanner at face value.

## The 43 that still fail, sorted honestly

### A. Real gaps - fix in the next image version (11)
| Control | What's actually on the VM | Fix |
|---|---|---|
| 5.4.1, 5.4.2 custom authselect profile / with-faillock | `authselect current`: *No existing configuration detected* - the role's authselect step didn't take on the cloud image | Investigate role 5.3.x tasks on GenericCloud; likely needs `authselect select sssd --force` first |
| 5.5.3 password reuse | depends on authselect/pwhistory above | same |
| 5.6.1.4 inactive lock | `useradd -D` INACTIVE=-1 | `rhel9cis_inactivelock` |
| 5.6.1.2 / 5.6.1.3 min days / warn age | login.defs is correct (7/7) but the existing `rocky` account wasn't updated | apply `chage` to existing accounts |
| 2.2.16 / 2.2.17 nfs-utils, rpcbind | both still installed from the cloud image | remove/mask in the image |
| 1.3.2 AIDE scheduled check | AIDE DB built, but no timer/cron | enable the role's AIDE cron |
| 1.3.3 audit tool integrity | AIDE rules for audit tools not present | role var for audit tools in AIDE |
| 1.6.1.6 no unconfined services | the only unconfined processes are **the Wazuh agent we added** (wazuh-agentd, -execd, -logcollector, -modulesd, -syscheckd) | vendor issue; document or confine with a custom SELinux module |

### B. Image disk layout - not fixable by Ansible (22)
1.1.2.x - 1.1.7.x: separate partitions + mount options for /tmp, /var, /var/tmp, /var/log, /var/log/audit, /home. The upstream cloud image is one partition. Fix = build from a kickstart / custom LVM layout (how the reference pipeline's AMIs get theirs) - next iteration.

### C. Benchmark version mismatch - the control is met, the older check can not see it (9)
Wazuh scores against **CIS Rocky Linux 9 v1.0.0**; the role implements **CIS RHEL 9 v2.0**.
- 4.2.1.2 / 4.2.1.3 / 4.2.1.4 / 4.2.2.3 / 4.2.2.4 logging, and the one "regression": v2.0 lets you pick journald *or* rsyslog; the role uses journald (`rhel9cis_syslog: journald`), so rsyslog is disabled. v1.0.0 assumes rsyslog.
- 4.2.1.6 remote log host: logs do leave the box via the Wazuh agent, but not via rsyslog as v1.0.0 expects.
- 3.4.2.7 nftables default deny: firewalld is the chosen single firewall utility (3.4.1.2 passes); the check looks for raw nftables rules.
- 5.3.3 sudo log file: `/var/log/sudo.log` exists and is configured in sudoers; the check's pattern doesn't match the role's formatting.
- 5.5.1 password creation: `minlen = 14`, `minclass = 4` are set (pwquality); the check looks in a different place.

### D. Deliberate deviation (1)
5.3.4 password for escalation - deviation D2 (`rocky` is a key-only automation account). See `deviations.md`.

## How to read a scanner score
A scanner score is a starting point, not the answer. Each failure gets one of four labels - real gap, structural, scanner/benchmark mismatch, or accepted risk - and only the real gaps become work. The real gaps above are the next image version, raised as a PR through the same gated pipeline.

## Remediation - image 1.0.1 (template 9202)
Each category A gap was raised as a GitHub issue, fixed in code (not on the server), proven by the Packer verify gate on the real build VM, and ships as a new image. VM 301 picks it up only when the Terraform plan (`05-plan-1.0.1.log`: replace VM 301) is approved and applied.

| Issue | Control (Rocky v1 / RHEL9 v2.0) | Root cause found | Fix | Proven by |
|---|---|---|---|---|
| #1 | 2.2.16, 2.2.17 / 2.1.9, 2.1.12 | Role defaults `rhel9cis_nfs_server` / `rhel9cis_rpc_server: true` (= "host needs NFS/RPC"), so both rules were skipped | Set to `false` (remove packages) | verify gate: packages absent |
| #2 | 5.4.1, 5.4.2, 5.5.3 / 5.3.2.x, 5.3.3.x | Not the cloud image: our own `rhel9cis_disruption_high: false` skips the whole PAM/authselect section | `rhel9cis_disruption_high: true` for image builds | verify gate: `custom/ch_mirror_cis` + with-faillock/pwquality/pwhistory/without-nullok; key login + sudo still work |
| #3 | 1.3.2 / 6.1.2 | Role ran AIDE from cron; benchmark audit looks for `aidecheck.timer`; EL9 aide ships no units | `rhel9cis_aide_scan: timer` + playbook installs the units | verify gate: timer enabled + active |
| #4 | 5.6.1.4 / 5.4.1.5 | **Triage evidence was wrong**: VM 301 already has `INACTIVE=30` | Made explicit in `cis.yml`; asserted | verify gate |
| #6 | 5.6.1.2, 5.6.1.3 / 5.4.1.2, 5.4.1.3 | Defaults set; existing accounts have no usable password (locked or key-only) | `rhel9cis_force_user_mindays/_warnage: true` for any future case; asserted | verify gate: no password account with weak ageing |
| #7 | 1.3.3 / 6.1.3 | Control **is** met in `/etc/aide.conf`; the Wazuh check reads `/etc/aide/aide.conf` (Debian path) | Asserted; reclassify as scanner mismatch | verify gate: 6 audit-tool rules |
| #9 | 1.6.1.6 | Only the Wazuh agent is unconfined | Accepted risk, deviation D4 | - |
| #10 | 1.1.2-1.1.7 (22 checks) | Single-partition cloud image | Structural: kickstart/LVM base image, separate work | - |

Expected after VM 301 is rebuilt (to confirm with a fresh SCA scan - not yet measured): 2.2.16, 2.2.17, 1.3.2, 5.4.1, 5.4.2 should move to pass. 5.5.3, 5.6.1.2, 5.6.1.3, 5.6.1.4 and 1.3.3 are likely to keep failing for scanner reasons, not configuration: the v1.0.0 Wazuh checks expect `remember=` inline on `pam_unix` (v2.0 forbids it), inspect every `/etc/shadow` line including locked system accounts, and in 1.3.3 look for the Debian AIDE path. Each is explained on its issue.
