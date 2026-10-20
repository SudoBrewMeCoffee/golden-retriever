# ch-mirror in KRONOS - how the IT department looks after it

Written against the live estate on 16 Oct 2026 (the first draft assumed things that weren't there - corrections noted).

## What exists
| ID | Name | Kind | Address | Notes |
|---|---|---|---|---|
| 9200 | `rocky9-cloud-base` | template | - | Upstream Rocky 9 GenericCloud, unhardened. Source for Packer. |
| 9201+ | `ch-rocky9-base-<ver>` | template | - | CIS L1 image built by Packer (1.0.0 = 9201). Next version -> next free ID via `-var target_template_id=`. Bump version every rebuild. |
| 300 | `ch-before` | VM (destroyed 16 Oct) | 10.69.1.70 | Unhardened scan target. Evidence captured, VM + Wazuh agent 040 removed. Recreate with `qm clone 9200 300` if a fresh baseline is needed. |
| 301 | `ch-app-01` | VM | 10.69.1.72 | Deployed by Terraform from 9201. Wazuh agent **041**. Cattle: fix the image, not the server. |
| - | Packer build VM | VM (transient) | 10.69.1.71 | Exists only during `packer build`. |

Address block for ch-mirror: **10.69.1.70-79**, outside the UniFi Core LAN DHCP pool (10.69.1.100-254). Never use DHCP for ch-mirror guests (what-broke #4).

Code + toolchain: `~/ch-mirror` on **Magnus** (Mac Studio, 10.69.1.151). Logs: `~/ch-mirror-logs/`. Proxmox token: `~/.config/ch-mirror/pve-token` (0600, placed by Graham - agents never read or print it).

## 1. Health board - automatic
`kronos-estate-feed` (pve, every 5 min) already publishes every guest with its tags to Homebase, so ch-mirror guests appear without changes. Filter on tag `ch-mirror`.
Proof-live check for 301: `ssh rocky@10.69.1.72 cat /etc/ch-mirror-release` returns `ch-rocky9-base <version>` matching the template in use.

## 2. Security tooling
- **Wazuh (CT 130, 10.69.1.131, v4.14.8):** enrol with `kronos/wazuh-enrol.sh <name>`. It pins the agent to the manager's version and disables the repo afterwards so agents can't overtake the manager. SCA picks *CIS Rocky Linux 9 v1.0.0* automatically.
- **Read SCA results (read-only):** `pct exec 130 -- python3 /usr/local/bin/chm-sca.py <agent-id> summary|checks`.
- **Vulnerabilities:** there is no separate KEV watch on the estate (draft assumed one). Wazuh vulnerability detection is enabled (feed refresh 60 min) and covers 301's Rocky packages - that is the watch. Gap to raise: no CISA KEV cross-check yet.
- **Backups:** 301 is deliberately NOT in `t4-proxmox-backup.sh` - it is rebuilt from the image, not restored. What must be kept: the git repo and the Terraform state at `~/ch-mirror-state/terraform.tfstate` on Magnus (local backend, outside the repo - see `terraform/versions.tf`).

## 3. Automation that will NOT touch ch-mirror (checked)
container-orchestrator (containers in its config only), kronos-healer (containers with onboot only), self-healing-watchdog (named services only), nightly backup (VMs 101/200/246/248 only).

## 4. Changelog
One entry per change in `/root/.kronos-p2/changelog-<date>-ch-mirror.md` on pve, same style as existing logs: what changed, guest IDs, why, evidence path, undo.

## 5. Runbook for the AI IT department
| Symptom | First action (allowed unattended) | Needs Graham's approval |
|---|---|---|
| 301 down / agent not responding | `qm status 301`; `qm start 301` if stopped; check host RAM | Rebuild or replace the VM |
| Wazuh SCA control regresses on 301 | Ticket with control ID + diff vs last pass | Any config change (fix goes in Ansible -> new image version) |
| Wazuh vuln detection flags a Rocky package | Ticket with CVE, package, CVSS, affected guests | Image rebuild with bumped version + Terraform apply |
| Terraform drift (plan not empty, no PR) | Report drift; do **not** apply | Any apply / import |
| CI failing | Collect logs, summarise failing step | Changes to workflow, secrets or runner |
| Host RAM pressure | Report allocation vs physical | Stopping other guests |
| IP conflict on 10.69.1.70-79 | Stop the ch-mirror guest involved; report | Re-addressing |

**Hard rules for agents:** never `terraform destroy`; never edit 301 by hand; never touch guests outside 9200-9299 / 300-309; never read, print or commit the Proxmox token; never use DHCP for ch-mirror guests.

## 6. Kubernetes
Out of scope - the reference pipeline runs EC2/AMI. Not in the demo.

## 7. Running the tools on Magnus (lessons from the build)
- Run long jobs (Packer, Terraform, Molecule) in a **held-open session**, never `nohup ... &` over SSH - macOS Local Network privacy cuts detached jobs off the LAN (what-broke #13).
- Packer: `~/ch-mirror/packer/build.sh <semver>`. Terraform: `~/ch-mirror/terraform/tf.sh plan|apply`. Both read the token from `~/.config/ch-mirror/pve-token` into the environment only.
- If a Packer build fails, check for an orphaned `packer-*` VM at the target ID and remove it before retrying.
- SCA scores come from the older CIS Rocky 9 v1.0.0 policy; read `evidence/06-sca-after-analysis.md` before raising tickets on "failures" in category C.
