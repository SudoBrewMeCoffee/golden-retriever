# AIDE EFI metadata policy

The Rocky image includes `aide_efi_metadata` at SELinux module priority 400.
The source is `ansible/files/aide_efi_metadata.te`. It grants exactly two
read-only permissions: `aide_t` may query filesystem attributes (`getattr`)
on `dosfs_t` (EFI vfat) and `autofs_t` (`/efi` automount). It grants no file
writes, mount operations, relabeling or unconfined execution. SELinux remains
enforcing. No AIDE exclusions or baseline changes are involved.

`ansible/playbook.yml` compiles and installs the policy on real SELinux-enabled
Rocky hosts before the image is published. An unchanged source with the module
already installed is skipped. Molecule containers skip the SELinux task; they
cannot prove host policy. `verify-vm.yml` requires enforcing SELinux and the
installed module before Packer publishes the image. Existing image versions and
Terraform template IDs are unchanged by this patch.

## Verify an instance

Run `ansible/verify-deployed.yml` immediately after first boot, before other
software is installed (or against an existing instance whose current baseline
is already valid). Override `expected_version` when verifying a newer image.

The verifier requires an idle service and existing database, starts the exact
`aidecheck.service` used by the daily timer, and reads only the fresh systemd
invocation's journal. It rejects skipped/failed checks, absent clean-result
evidence, warnings/errors on either output stream, a changed baseline hash or
non-enforcing SELinux. The daily timer must remain enabled and active. This is
an explicit service run; it does not wait for or alter the timer schedule.

The Packer build-time database is still removed by the existing cleanup step;
each replacement creates its baseline on first boot. The build gate therefore
checks policy installation, while the post-deploy gate proves the scheduled
service against the instance baseline. It never runs `aide --init` or
`aide --update` to make an acceptance check pass.

## Regression evidence

On VM 301 (Rocky 9.8, AIDE 0.19.2), the scheduled confined service warned about
`fstatfs(): Permission denied` for EFI paths, although its exit code was zero.
Effective policy denied the two filesystem metadata permissions. After adding
these exact rules on 20 October 2026, the service returned zero with no warnings
and no differences across 36,786 entries. The baseline SHA-256 stayed unchanged:
`26e244b8a9a648d4ade4b785bc45c1d9f9b267342f99f33cc5ad4dc22d29c561`.

Controller regression tests execute the actual Ansible assertions with clean
evidence and failing warning, error/status, empty-journal, changed-baseline,
permissive and skipped-service cases. They run in hosted validation without
infrastructure access. Real SELinux/image acceptance still requires a future
approved build and instance verification; this PR does not deploy anything.

PR preparation validation on 20 October 2026:
- All 19 Python tests passed (9 scheduled-service acceptance cases, 10 existing SCA tests).
- Ansible production-profile lint and playbook syntax checks passed.
- This policy source compiled and packaged with Rocky's `checkmodule` and
  `semodule_package` in a temporary directory, without installing it again.
- The updated `verify-deployed.yml` ran against VM 301 with its existing policy
  and baseline: **28 ok, 0 changed, 0 failed**, including the fresh scheduled
  service invocation and unchanged baseline checksum.

To remove the local policy on an instance, use
`sudo semodule -r aide_efi_metadata`. This restores the previous metadata denial
and warnings; it does not change the AIDE database.

## Security review follow-up

The grants apply to filesystems labelled `dosfs_t` and `autofs_t`, not just
two pathnames. They permit filesystem metadata queries only; no file-content
read, write, mount, relabel or unconfined-domain permission is added.

Global `Enforcing` alone does not prove that `aide_t` is enforcing. Instance
verification now reads the effective `semanage permissive -l` list before and
after the scheduled run, rejects `aide_t` in either list, and fails closed if
the query fails. The image installs the package providing `semanage`.

The image module gate now rejects disabled modules and duplicate priorities
that could shadow the intended module. Installation explicitly enables the
packaged module; it never removes a higher-priority override silently.
Regression tests reproduced both former false-pass cases before these fixes.
All 26 tests pass, including permissive-domain, failed-policy-query, disabled
module and shadowed-module cases. The two policy grants are unchanged.
