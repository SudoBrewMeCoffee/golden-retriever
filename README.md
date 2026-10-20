# ch-mirror — public-sector-style golden-image pipeline on KRONOS

**Purpose:** a working, demonstrable copy of a UK public-sector reference pipeline's published infrastructure
pattern (Packer + Ansible CIS images, Molecule, Terraform, pre-commit gates) running on my
KRONOS homelab (Proxmox), kept as a managed KRONOS service.

**Scope, honestly:** lab work on Rocky Linux 9, the binary-compatible rebuild of RHEL 9, on a Proxmox
homelab - not production RHEL administration or AWS. [`docs/aws-at-scale.md`](docs/aws-at-scale.md)
describes how the same pattern maps to AWS.

## For reviewers - a 5-minute tour

**1. Security remediation - finding -> ticket -> fix in code -> rebuilt image -> re-scan.**
Start at [`evidence/finding.md`](evidence/finding.md) (CIS 5.2.4 *SSH access limited*, FAIL on the stock image).
Remediation tickets are tracked as [GitHub issues labelled `remediation`](../../issues?q=label%3Aremediation).
The fix is a variable in [`ansible/group_vars/all/cis.yml`](ansible/group_vars/all/cis.yml), baked into a new image
([`evidence/03-packer-build-1.0.0.log`](evidence/03-packer-build-1.0.0.log)) and proved by re-scan:
[`evidence/06-sca-after-analysis.md`](evidence/06-sca-after-analysis.md) (53% -> 73%, every remaining failure classified).

**2. Security at scale.** [`docs/aws-at-scale.md`](docs/aws-at-scale.md) - how the lab pattern maps to AWS:
Packer `amazon-ebs` AMIs, Inspector (vulnerabilities and OS-level CIS scans), Security Hub -> EventBridge -> tickets,
instance refresh vs Patch Manager. Every AWS/Terraform claim is sourced to primary documentation.

**3. CIS hardening and patching.** Guardrails and their reasons: [`ansible/group_vars/all/cis.yml`](ansible/group_vars/all/cis.yml).
Real-VM verify gate that fails the build if controls aren't in effect: [`ansible/verify-vm.yml`](ansible/verify-vm.yml).
Post-deploy check that proves each instance (runs `aide --check`, one kernel installed): [`ansible/verify-deployed.yml`](ansible/verify-deployed.yml).
Owned, justified deviations: [`evidence/deviations.md`](evidence/deviations.md). Patching: [`evidence/07-patching.md`](evidence/07-patching.md).

**4. Terraform with security built in.** Gates: [`.pre-commit-config.yaml`](.pre-commit-config.yaml) (fmt, validate, docs,
tflint, Trivy - tfsec's successor). Code: [`terraform/`](terraform/). Pipeline that applies only the reviewed plan behind
an approval: [`.github/workflows/ci.yml`](.github/workflows/ci.yml). Policy as code: [`policy/`](policy/).

**What went wrong:** [`evidence/what-broke.md`](evidence/what-broke.md) - 15 real incidents, each with root cause,
fix and the control added so it can't recur.

**Mirrors what the reference pipeline publishes in its open-source repos:**

| Reference pipeline (AWS) | ch-mirror (Proxmox) |
|---|---|
| `rhel9-base-ami`, `amzn2023-base-ami` — Packer + Ansible | `packer/rocky9.pkr.hcl` — Packer + Ansible, RHEL 9 rebuild |
| Source AMI filter → provision → versioned AMI | Base template 9200 → clone → CIS → versioned template `ch-rocky9-base-<semver>` |
| KMS-encrypted EBS, `ssh_clear_authorized_keys` | authorized_keys, machine-id and cloud-init state cleared post-build (no storage-encryption claim in the lab - see `docs/aws-at-scale.md`) |
| `ansible-collection-*` tested with **Molecule** | `ansible/molecule/default` (Docker driver on the Mac Studio) |
| `*-terraform` repos, pre-commit: fmt, docs, tfsec, tflint | `terraform/` + `.pre-commit-config.yaml` (tfsec → Trivy) |
| CI Packer container, Terraform runner | GitHub Actions workflow targeting a self-hosted runner on the Mac Studio, installed as a launchd daemon (`kronos/runner-daemon.sh`, what-broke #23) |

**Not in scope:** Kubernetes. The reference pipeline runs EC2/AMI, not K8s. Park the K8s cluster if it's using RAM.

## Current state (16 Oct 2026)

| Piece | State | Evidence |
|---|---|---|
| Base templates 9200 `rocky9-cloud-base`, 9210 `al2023-kvm-base` | Stock cloud images, checksum-verified; never deployed directly (policy denies it) | `/root/ch-mirror-logs/` on pve, `policy/terraform/` |
| Rocky image 1.0.0 (template 9201) | CIS RHEL 9 L1 (414 tasks, 0 failed) + real-VM verify gate 11/11 | `evidence/03-packer-build-1.0.0.log` |
| Rocky image 1.0.1 (template 9202) | Remediation of 8 scanner findings; verify gate 28/28 | PR #15 |
| Rocky image 1.0.2 (template 9203) | One kernel installed (#14); per-instance AIDE baseline built on first boot (#17); verify gate 32/32; throwaway VM: post-deploy verify 16/16 with `aide --check` rc 0, Wazuh 76% (127 pass / 38 fail), CIS 1.3.2 pass | `evidence/03-packer-build-1.0.2.log`, `06-verify-deployed-1.0.2.log`, `11-sca-1.0.2-summary.json` |
| AL2023 image 1.0.0 (template 9211) | AMAZON2023-CIS 1.5.0 + verify gate 11/11; Wazuh CIS Amazon Linux 2023: 65% (117 pass / 63 fail) | `packer/al2023/`, `evidence/03-packer-build-al2023-1.0.0.log`, `09-sca-al2023-summary.json` |
| VM 301 `ch-app-01` (10.69.1.72) | Running **1.0.2**, deployed through the GitHub pipeline after owner approval (1.0.1 was deployed from the runner host). Post-deploy verify 16/16; 1 kernel; `aide --check` rc 0; Wazuh vulnerability findings 336 -> **0** | `evidence/12-deploy-1.0.2.md`, `10-deploy-1.0.1.md` |
| CIS score (Wazuh, CIS Rocky 9 v1.0.0) | **53% upstream -> 73% (1.0.0) -> 76% (1.0.1, 1.0.2)**, 0 regressions | `evidence/finding.md`, `06-sca-after-analysis.md`, `10-deploy-1.0.1.md`, `12-deploy-1.0.2.md` |
| Patching | Upstream image: 100 security advisories, 542 CVEs -> patched image: 0 advisories; old-kernel finding fixed in image 1.0.2 (#14): deployed VM 301 went from 336 Wazuh findings to 0 | `evidence/07-patching.md`, `12-deploy-1.0.2.md` |
| Policy as code | conftest/OPA on every plan: ID range, hardened template (raw bases denied), static IP, replacement warning; 23 unit tests | `policy/terraform/` |
| Hosted checks (GitHub-hosted) | pre-commit, Terraform/Packer validate, Molecule on every push and PR | `.github/workflows/hosted-checks.yml` |
| Deploy pipeline (self-hosted) | Plan -> policy -> human approval (`kronos-prod`) -> apply saved plan; runner live as a launchd daemon on the Mac Studio. First end-to-end deploy: run 38998590074 (1.0.2) | `.github/workflows/ci.yml`, `evidence/12-deploy-1.0.2.md` |
| Scheduled image rebuild | Patch-bump rebuild, refuses to reuse a version | `.github/workflows/image-rebuild.yml` |
| What broke | Real incidents, each with root cause + control | `evidence/what-broke.md` |

Toolchain lives on **Magnus** (Mac Studio). Build: `packer/build.sh <semver>`. Deploy: `terraform/tf.sh plan` then `tf.sh apply` (applies only the saved, reviewed plan). Run both in a held-open session (what-broke #13).

---

## 0. Safety first (do before anything)

- Snapshot/backup: `vzdump 9000 9101 --storage unas-backups --mode snapshot`
- Check RAM headroom before building (the OOM lesson): total allocated vs physical.
- **Additive only.** New IDs 9200–9299 and 300–309. No existing guest is touched.
- Terraform state is a local backend outside the repo (`~/ch-mirror-state/` on Magnus, see `terraform/versions.tf`), backed up with KRONOS backups. Never `terraform destroy` outside this repo's resources.

## 1. One-time: base template 9200 (Rocky Linux 9 GenericCloud)

On the Proxmox host (adjust `STORAGE` and `BRIDGE`):

```bash
STORAGE=local-zfs; BRIDGE=vmbr0
cd /var/lib/vz/template/iso
wget https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
qm create 9200 --name rocky9-cloud-base --memory 2048 --cores 2 --net0 virtio,bridge=$BRIDGE \
  --scsihw virtio-scsi-single --ostype l26 --agent enabled=1 --serial0 socket --vga serial0
qm importdisk 9200 Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 $STORAGE
qm set 9200 --scsi0 $STORAGE:vm-9200-disk-0 --boot order=scsi0 --ide2 $STORAGE:cloudinit
qm template 9200
```

Optional second base: Amazon Linux 2023 KVM image (AWS publish `al2023-kvm-*.qcow2`) as 9210, same steps.

## 2. Proxmox API token (scoped)

Already created earlier as `terraform@pve!tf`. Packer and Terraform both read:

```bash
export PROXMOX_URL=https://10.69.1.139:8006/api2/json
export PROXMOX_USERNAME='terraform@pve!tf'
export PROXMOX_TOKEN='<secret>'           # never commit
export PM_API_TOKEN_ID="$PROXMOX_USERNAME" PM_API_TOKEN_SECRET="$PROXMOX_TOKEN"
```

## 3. Pick the finding (BEFORE evidence)

```bash
qm clone 9200 300 --name ch-before --full  &&  qm start 300
```
- Enrol in Wazuh (CT 130) and run SCA. Wazuh auto-selects **CIS Rocky Linux 9 v1.0.0** (same control content as RHEL 9; see `evidence/finding.md`).
- Pick **one** failing control (good candidates: SSH `PermitRootLogin`, `auditd` not installed/enabled,
  `/tmp` not a separate mount with `nosuid,noexec`, password complexity in `pwquality.conf`).
- Save the SCA report to `evidence/01-sca-before.*`. Record the control ID in `evidence/finding.md`.
- Destroy 300 when done.

## 4. Build the hardened image

```bash
cd ansible && ansible-galaxy install -r requirements.yml -p roles && cd ..
packer/build.sh 1.0.0      # reads the token from ~/.config/ch-mirror/pve-token; log -> evidence/03-packer-build-1.0.0.log
```
Produces template **9201 `ch-rocky9-base-1.0.0`**. Bump `version` on every rebuild (reference-pipeline style).

### Amazon Linux 2023 (the reference pipeline also builds `amzn2023-base-ami`)

Same pattern, second image. Source is AWS's official AL2023 KVM image
(`cdn.amazonlinux.com/al2023/os-images/latest/kvm/`, SHA256 checked against the published `SHA256SUMS`),
imported as base template **9210 `al2023-kvm-base`** exactly like 9200 but with `--ciuser ec2-user`
(the image's default user; the Proxmox cloud-init drive is the NoCloud seed AWS document) and a static `ipconfig0`.

```bash
packer/al2023/build.sh 1.0.0   # log -> evidence/03-packer-build-al2023-1.0.0.log
```
Produces **9211 `al2023-cis-base-1.0.0`**: ansible-lockdown AMAZON2023-CIS 1.5.0 (CIS AL2023 v1.0.0) via
`ansible/playbook-al2023.yml` + `ansible/vars/al2023-cis.yml`, then the same `verify-vm.yml` gate as `ec2-user`.
Level 1 is selected with `--tags level1-server` - that role ignores its level variables (what-broke #16) - plus
the host firewall controls, which CIS AL2023 puts in Level 2 (what-broke #18).
Deviations: `evidence/deviations-al2023.md`. Lives in its own directory, so `packer/build.sh` still builds RHEL only.
Result (1.0.0): hardening 316 ok / 0 failed, verify gate 11/11 (`evidence/03-packer-build-al2023-1.0.0.log`);
Wazuh SCA (CIS Amazon Linux 2023 v1.0.0) on a throwaway clone: **65%**, 117 pass / 63 fail
(`evidence/09-sca-al2023-summary.json`) - most fails are the single-partition image layout and Level 2 audit rules.

## 5. Test the role (Molecule, on the Mac Studio)

```bash
cd ansible && molecule test | tee ../evidence/04-molecule.log
```

## 6. Deploy via Terraform through the gated pipeline

PR → CI runs pre-commit + Molecule + `terraform plan` (saved plan uploaded as a build artefact for review) → **manual approval
environment `kronos-prod`** → `terraform apply` of that saved plan only. Creates VM **301 `ch-app-01`** from 9201.

## 7. Prove it (AFTER evidence)

- Wazuh SCA on 301 → `evidence/06-sca-after.*` — the chosen control now passes.
- Keep: pre-commit output, plan/apply logs, Packer log, Molecule log.
- Write `evidence/what-broke.md` — every failure hit during the build, cause, fix. (Often the most useful
  document in the repo. Don't skip it.)

## 8. Hand to the KRONOS IT department

See `kronos/onboarding.md`.

## 9. The 5-minute demo path

1. Repo tree — "this mirrors your base-AMI and Terraform repos."
2. `evidence/finding.md` + SCA before — "here's the CIS finding."
3. The PR — plan, pre-commit (fmt/tflint/Trivy), Molecule green, approval gate.
4. Packer log — hardening baked into a versioned image, keys cleared.
5. SCA after + VM in Wazuh — "and here's the proof for the auditor."
6. `what-broke.md` — "and here's what went wrong."

Rehearse it twice. No live builds on the call — show the evidence, offer to run it after.
