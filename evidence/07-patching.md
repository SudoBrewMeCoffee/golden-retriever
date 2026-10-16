# Patching - rebuild the image, replace the instance

Lab evidence, 16 Oct 2026. Rocky Linux 9.8 (RHEL 9 rebuild) on Proxmox, scanned by Wazuh 4.14.8
vulnerability detection. Raw outputs: `07-patching-raw/`.

## The approach

Servers are never patched in place. Nobody logs in and runs `dnf update` on a running server.

1. **Rebuild.** Packer clones the upstream base, runs `dnf -y update` (`packer/rocky9.pkr.hcl`), applies
   the CIS role, and runs the real-VM verify gate (`ansible/verify-vm.yml`). If the gate fails, no
   image is published.
2. **Version it.** Each build is a new template, `ch-rocky9-base-<semver>`, with its own template ID.
   Package updates only = patch bump (1.0.0 -> 1.0.1). Hardening or control changes = minor bump.
   A base OS or disk-layout change = major bump. The previous template is kept for rollback.
3. **Replace.** A PR changes `template_id` in `terraform/variables.tf`. `terraform plan` shows the
   change for review. Nothing is applied until someone approves the `kronos-prod` environment
   (`ci.yml`). Rolling back means pointing `template_id` at the previous template.
4. **Verify.** The new instance enrols in Wazuh. The vulnerability index and `dnf updateinfo` show
   what is still outstanding. That is what this document measures.

On AWS the steps are the same, with AMIs in place of templates and a launch template / ASG
instance refresh in place of the Terraform clone.

## Before / after

Same base. **Before** = VM 302, cloned from template 9200 (the upstream Rocky 9 GenericCloud image,
May 2026). It was not updated and was scanned as shipped. **After** = VM 301 `ch-app-01`, deployed
from `ch-rocky9-base-1.0.0`. That image was built today with all updates applied.

### Wazuh vulnerability detection (wazuh-states-vulnerabilities index)

| | Upstream image (VM 302) | ch-rocky9-base-1.0.0 (VM 301) |
|---|---|---|
| Unique CVEs | **542** | **336** (see note) |
| Critical | 3 | 0 |
| High | 397 | 299 |
| Medium | 133 | 36 |
| Low | 9 | 1 |
| Findings (package x CVE rows) | 2,401 (C 4 / H 1,956 / M 420 / L 21) | 1,344 (H 1,196 / M 144 / L 4) |
| Packages with findings | 94 | 4 |
| CVEs outside the kernel | **206** (C 3 / H 98 / M 97 / L 8) | **0** |
| Running kernel | 5.14.0-687.10.1 | 5.14.0-687.58.1 |

Severity uses the highest rating Wazuh gave each CVE, from its vendor-enriched CVSS.

**Note: all 336 CVEs left on 301 are on the old kernel RPM, which is not running.** 301 is running
the patched kernel, 687.58.1. `dnf update` installs a new kernel next to the old one. The old one,
687.10.1, comes from the upstream image and stays installed: dnf keeps installonly kernels, and it
cannot remove the kernel that is running during the build. Wazuh scans installed packages, so it
reports the old kernel's 336 CVEs. These are not running code, but they are still a real hygiene
problem. The old kernel is still a boot entry, and the scanner noise hides real findings.
**Fix for 1.0.1:** reboot the build VM into the new kernel, then run `dnf -y remove --oldinstallonly`
before the verify gate. Add a gate check that `rpm -q kernel` returns exactly one kernel. This is
not yet built or tested.

### dnf security advisories (read-only `dnf updateinfo`; no packages installed)

| | Upstream image (VM 302) | ch-rocky9-base-1.0.0 (VM 301) |
|---|---|---|
| Security advisories pending | **100** | **0** |
| Critical | 1 | 0 |
| Important | 60 | 0 |
| Moderate | 34 | 0 |
| Low | 5 | 0 |
| Unique CVEs in those advisories | 559 | 0 |
| Package updates pending | 318 | 0 |

The two tools agree: 301 has nothing outstanding. dnf compares against the newest installed kernel,
so the leftover kernel does not show up here. Wazuh does show it, which is why both views are worth
having.

### Top 5 on the upstream image, all fixed in 1.0.0

Ranked by Wazuh severity and CVSS. Kernel CVEs are left out of this list because they are covered
by the KEV item below.

| CVE | Package | Wazuh | Advisory (vendor severity) | Upstream (302) | 1.0.0 (301) |
|---|---|---|---|---|---|
| CVE-2026-45445 | openssl / openssl-libs | Critical 9.1 | RLSA-2026:25239 (Important) | 3.5.5-2 | 3.5.8-2 |
| CVE-2026-4480 | libldb | Critical 9.0 | RLSA-2026:25049 (Critical) | 4.23.5-6 | 4.23.5-12 |
| CVE-2026-4408 | libldb | Critical 9.0 | RLSA-2026:25049 (Critical) | 4.23.5-6 | 4.23.5-12 |
| CVE-2026-14474 | sssd libs (8 pkgs) | High 8.8 | RLSA-2026:42122 (Important) | 2.9.8-4 | 2.9.8-4.el9_8.1 |
| CVE-2026-73078 | vim-minimal | High 8.8 | RLSA-2026:66366 (Important) | 26.el9_8.4 | 26.el9_8.23 |

Other notable items fixed in 1.0.0: openssh-server (RLSA-2026:47756, :69130, Important), sudo
(RLSA-2026:69123, :75571, Important), curl, gnutls, and glibc (four Moderate advisories). Versions:
`07-patching-raw/rpm-versions.txt`.

## CISA KEV cross-check

Checked against the CISA Known Exploited Vulnerabilities catalogue, version 2026.10.16 (1,748
entries), using every CVE from both tools, not only the top 5 (`07-patching-raw/kev-check.txt`).

- None of the top 5 above is KEV-listed.
- **1 KEV hit: CVE-2025-39964** (Linux kernel race condition). It was added to KEV on 2026-09-18, with
  a federal remediation due date of 2026-09-21. It is fixed by RLSA-2026:70459 (kernel 687.50.1).
  - On the upstream image it is **exploitable**: it is in the running kernel, 687.10.1.
  - On 1.0.0 it is **fixed in the running kernel** (687.58.1). Wazuh still reports it for 301,
    because the old 687.10.1 RPM is still installed (see the note above).
- The lesson: the upstream image had a known-exploited kernel bug for weeks after the KEV due date.
  An image built in May and never rebuilt carries that bug to every server cloned from it. The
  scanner on its own also could not tell "fixed and running" from "still exposed" on 301. Checking
  `uname -r` against the fixed version settled it.

## Rebuild cadence

- **Monthly scheduled build.** `.github/workflows/image-rebuild.yml` runs on the 1st of each month.
  It works out the next patch version from the last `image-*` tag and picks the next free template
  ID (9202-9299). It then runs the same Packer build and verify gate. Publishing still waits for
  approval on the `kronos-prod` environment.
- **Out-of-band build when a KEV entry matches a package in the image**, or when there is a Critical
  advisory. Use `workflow_dispatch` with an explicit version. The target is a published image within
  days, not weeks: the KEV hit above had a 3-day federal due date.
- **Replacement** follows each build, through the Terraform PR, plan, and approved apply. A patched
  image does nothing until the instances running on it are replaced.
- **Not built yet:** automatic KEV matching. That would be a small daily job that intersects the KEV
  feed with the Wazuh vulnerability index for agents built from the image, and opens an issue or
  triggers the dispatch. Today the KEV check is the manual one recorded here.

## Caveat: 1.0.0 is only current as of its build time

1.0.0 was built today, so these "after" numbers are the best they will ever be. Drift starts at once.
Every advisory published after the build applies to the image and to every instance cloned from it.
The upstream image shows the scale: it was built in May, and five months later it had 100 pending
advisories. The patching control is the rebuild cadence and the replacement. A single clean scan is
not the control. Re-run this comparison against the next build to show the cycle working.

## Method (reproducible)

- VM 302 was cloned from 9200 with a static IP (10.69.1.73), then enrolled in Wazuh with
  `kronos/wazuh-enrol.sh` (agent 042). It was **not** updated. It was destroyed afterwards, and
  agent 042 was removed.
- Vulnerability state was read from the Wazuh indexer (`wazuh-states-vulnerabilities-*`) inside the
  manager container. The queries were read-only and used the indexer's client certificate, so no
  password was handled. The 302 scan finished within about 3 minutes of enrolment, and the counts
  were stable on several later polls.
- `dnf updateinfo` was run read-only on both VMs after `dnf makecache`.
- Files in `07-patching-raw/`: `wazuh-summary.json` (counts), `wazuh-04{1,2}-findings.tsv` (every
  finding: package, version, CVE, severity, CVSS), `updateinfo.txt`, `302-updateinfo-list.txt`
  (advisory list, with a CVE section after `===CVE`), `kev-check.txt`, `rpm-versions.txt`.
