# How this lab pattern maps to AWS at scale

**Scope, said plainly:** ch-mirror is lab work on Rocky Linux 9 (the binary-compatible rebuild of RHEL 9)
on a Proxmox homelab. It is not production RHEL administration and it is not AWS. This page explains how
the same pattern - image pipeline, CIS hardening, scan, ticket, fix in code, rebuild, re-scan - would map
onto AWS, and why I'd pick each service. Every AWS and Terraform claim below was checked against the
primary documentation listed at the bottom (checked October 2026). Where I am describing what I *would*
do rather than what I have done, it says so.

The shape is the same at any size: **fix the image, not the server; prove it with a scan; never let a
human change production by hand.** What changes at scale is that the evidence, the tickets and the
rollout have to be automatic, because there are too many instances to look at one by one.

---

## 1. Image pipeline

**The lab does:** `packer/rocky9.pkr.hcl` clones a base template, runs the CIS role
(ansible-lockdown RHEL9-CIS 2.4.2), runs a real-VM verify gate (`ansible/verify-vm.yml`), clears SSH keys
and machine-id, then publishes a semver-named template (`ch-rocky9-base-1.0.0`).

**On AWS I would use** the Packer `amazon-ebs` builder - the same builder Companies House use in their
public `rhel9-base-ami` repo. Reading that repo, the pattern is:

| Concern | Companies House `rhel9-base-ami` (public) | Why it matters |
|---|---|---|
| Source image | `source_ami_filter` with an owner ID and `most_recent = true` | Every build starts from the newest vendor image, so the rebuild picks up the vendor's latest patches. |
| Versioning | `ami_name = "<prefix>-<version>"`, version kept in a `version` file; tags for `Name`, `BuildDate`, Packer version | AMI names must be unique, so a semver name doubles as an audit trail: any instance can be traced back to the build that made it. |
| Encryption | `launch_block_device_mappings` with `encrypted = true` and a customer-managed KMS key (`alias/packer-builders-kms`) | The resulting AMI snapshot is encrypted with a key the organisation controls. |
| Key hygiene | `ssh_clear_authorized_keys = true`, plus a shell step deleting every `authorized_keys` and shell history file | No build-time credentials or history ship inside the image. (HashiCorp describe the Packer flag as mostly cosmetic, because Packer deletes its temporary key anyway - which is why the explicit `find ... -delete` step is the real control.) |
| Sharing | `ami_regions` and `ami_users` (account IDs) | Build once in a central account, share to workload accounts. |
| Build network | Dedicated build subnet, security group, key pair and instance profile, all named `packer-builders-<region>` | The build instance has its own narrow permissions and network, separate from workloads. |

Two things I would add that the lab already does and that I could not see in the public repo:

- **A verify gate inside the build.** ch-mirror's `verify-vm.yml` fails the Packer build if `sshd -T`,
  SELinux, auditd, firewalld or admin access are wrong. Molecule cannot prove these, because the CIS role
  switches off 78 controls inside containers (`evidence/what-broke.md` #12). The same playbook runs
  unchanged against an EC2 build instance.
- **IMDSv2 required on the AMI.** The `amazon-ebs` builder has `imds_support = "v2.0"` to mark the AMI
  as IMDSv2-only, and `metadata_options { http_tokens = "required" }` for the build instance itself. Both
  default to the legacy/optional behaviour, so they have to be set deliberately.

**Encryption at account level as well.** EBS encryption by default is a per-Region account setting.
Once on, every new volume in that Region is encrypted (with `aws/ebs` or a customer-managed key you set
as the default). It does not touch existing volumes. I would turn it on in every account and Region as a
guardrail, so an unencrypted volume cannot be created even if a template forgets.

---

## 2. Patching at scale

There are two honest answers, and most estates need both.

### a. Immutable fleets: rebuild the image, roll the fleet

**The lab does:** a patch means a new image version. `packer/build.sh 1.0.1` runs `dnf -y update`, the
CIS role and the verify gate; Terraform then replaces the VM from the new template. VM 301 is
deliberately *not* backed up - it is rebuilt, not restored (`kronos/onboarding.md`).

**On AWS I would use** a scheduled image pipeline (weekly, plus on demand for a critical CVE) that
produces a new AMI, then an **Auto Scaling group instance refresh** to roll it out:

- Update the launch template to the new AMI ID (Terraform looks the AMI up by name/tag, never hard-codes
  it), then start an instance refresh.
- Instance refresh replaces instances in batches based on minimum and maximum healthy percentages. With
  a minimum of 90% and maximum of 100%, it replaces 10% of capacity at a time; at 100% minimum it
  launches new instances before terminating old ones.
- **Checkpoints** pause the refresh at set percentages so you can check the new instances (for example,
  re-run the CIS scan on the first 10%) before carrying on. You can cancel or roll back from there.
- Refresh preferences include `AutoRollback` (off by default) and an `AlarmSpecification`, so a failed
  refresh or a breached CloudWatch alarm returns the group to its previous configuration.

Why this way: every instance is identical and was verified at build time, so there is no drift and the
evidence for the auditor is the build log plus the scan of the image, not a per-server patch history.

### b. Long-lived instances: Systems Manager Patch Manager

Some servers can't be replaced on a schedule (stateful, licensed, or legacy). For those I would use
**AWS Systems Manager Patch Manager**:

- **Patch baselines** define what "compliant" means. The predefined RHEL baseline
  (`AWS-RedHatDefaultPatchBaseline`) and the AL2023 baseline approve Security patches of severity Critical
  or Important, plus Bugfix, **7 days after release**. A custom baseline can change the delay, add
  explicit approve/reject lists, or set a fixed cut-off date.
- **Scan** reports missing patches only; **Scan and install** installs them.
- **Patch policies** (Quick Setup) are AWS's recommended method: one policy can set the schedule and
  baseline across an AWS Organization, every account and Region, or selected OUs.
- **Maintenance windows** are the older, finer-grained option; each window task targets a single
  account/Region pair.
- Compliance data is a point-in-time snapshot from the last successful run, and AWS state plainly that
  patch-compliant does not mean secure - which is why vulnerability scanning (section 4) sits alongside it.
- Patch Manager does not do major-version upgrades (for example RHEL 8 to 9). That is an image rebuild.

The 7-day default delay is a choice, not a law: for a CVE on the CISA KEV list I would approve the patch
explicitly rather than wait.

---

## 3. CIS compliance at fleet scale

It is easy to blur two different things here, so to be precise:

- **Security Hub's CIS AWS Foundations Benchmark standard is account-level.** Its controls check AWS
  service configuration - IAM, CloudTrail, S3, EC2, KMS, Config, CloudWatch and so on. It does **not**
  check the operating system inside an instance. (In current AWS naming, standards and controls are run
  by *Security Hub CSPM*; the newer *Security Hub* correlates CSPM, Inspector, GuardDuty and Macie
  findings.) I would enable the latest supported version (v5.0.0 at the time of writing) alongside AWS
  Foundational Security Best Practices.
- **OS-level CIS on EC2 instances** is a different job. The lab uses Wazuh SCA for this. On AWS the
  options are:
  - **Amazon Inspector CIS scans.** These benchmark the instance OS against CIS Level 1 or Level 2,
    on demand or on a daily/weekly/monthly schedule. Targets are chosen by tag, and a delegated
    administrator can scan across multiple accounts. Supported OSes include RHEL 9 and Rocky Linux 9
    (CIS benchmark 2.0.0) and Amazon Linux 2023 (1.0.0). Instances must be SSM managed instances with the
    `AmazonSSMManagedInstanceCore` and `AmazonInspector2ManagedCisPolicy` policies; private instances
    need VPC endpoints for `inspector2`, `s3`, `ssm` and `ssmmessages`.
  - **Systems Manager State Manager** to *keep* instances compliant: an association using the
    `AWS-ApplyAnsiblePlaybooks` document can run the same Ansible playbook from S3 or GitHub on a
    schedule, with a `Check` parameter and compliance severity reporting. That is the same
    `ansible/playbook.yml` and `group_vars/all/cis.yml` the lab uses.
  - **Ansible directly** (from a pipeline with a dynamic `aws_ec2` inventory, which the CH repo's dev
    scripts already use) for ad hoc checks.

A useful detail from the lab that carries straight over: the CIS role in ch-mirror implements
**CIS RHEL 9 v2.0**, while Wazuh scored against the older **CIS Rocky Linux 9 v1.0.0**, which is why 9
of the remaining failures are benchmark-version mismatches, not real gaps
(`evidence/06-sca-after-analysis.md`, category C). Inspector's CIS scans use benchmark 2.0.0 for RHEL 9
and Rocky 9, so the scanner and the role would line up. Whatever the tools, the rule is the same: every
remaining failure is labelled real gap, structural, scanner mismatch or accepted deviation, and only real
gaps become work. Accepted deviations live in a register like `evidence/deviations.md`.

---

## 4. Vulnerability management

**The lab does:** Wazuh vulnerability detection watches 301's packages; there is no CISA KEV
cross-check yet (an acknowledged gap in `kronos/onboarding.md`).

**On AWS I would use Amazon Inspector (v2):**

- It discovers and scans **EC2 instances, ECR container images and Lambda functions**, and re-scans
  automatically when a package is installed, a patch is applied, or a new CVE affecting the resource is
  published - no scan schedule to maintain.
- EC2 scanning works through the SSM agent or agentlessly through EBS snapshots; hybrid mode is the
  default when EC2 scanning is activated. RHEL 9, Rocky Linux 9 and AL2023 are all supported.
- ECR enhanced scanning can be set to scan on push, which is where I would put the gate for container
  images.
- With AWS Organizations, a delegated administrator account activates Inspector for every account and
  sees all findings in one place.
- Findings flow to Security Hub CSPM automatically (in ASFF) once both are enabled.

**Prioritisation.** CVSS alone gives far too many "highs". Inspector's score adjusts the CVSS base score
using network reachability and exploitability data from the environment, and each finding's
vulnerability intelligence includes the **CISA KEV date added and due date** where the CVE is on the
Known Exploited Vulnerabilities catalogue. My order would be:

1. On CISA KEV and reachable - fix now, out of cycle (explicit patch approval, image rebuild, instance
   refresh).
2. On CISA KEV, not reachable - next scheduled image.
3. High Inspector score - next scheduled image.
4. Everything else - normal patch baseline.

---

## 5. Remediation ticket flow at scale

**The lab does:** one finding is followed end to end by hand - finding (`evidence/finding.md`), ticket
(GitHub issue labelled `remediation`), fix in code (`ansible/group_vars/all/cis.yml`), rebuilt image
(`evidence/03-packer-build-1.0.0.log`), re-scan (`evidence/06-sca-after-analysis.md`).

**On AWS the same loop is automated:**

```
Inspector / CSPM control / GuardDuty
        |
Security Hub (CSPM in ASFF, Security Hub in OCSF)
        |  automation rules: suppress accepted deviations,
        |  raise severity on tagged prod resources, open ticket
        v
EventBridge rule  ->  Lambda / SNS / SQS / Step Functions  ->  ticketing (Jira, ServiceNow, GitHub issues)
        |
Engineer fixes in code -> PR -> pipeline -> new AMI -> instance refresh
        |
Inspector re-scans automatically -> finding closes -> Security Hub archives it -> ticket closes
```

What the documentation confirms:

- Security Hub CSPM sends **all new findings and all updates** to EventBridge in near real time;
  EventBridge rules can target Lambda, SSM Run Command, Kinesis, Step Functions, SNS, SQS, or a
  third-party ticketing, chat, SIEM or incident tool.
- Security Hub **automation rules** run *before* EventBridge sees the finding, so suppression and
  severity changes are applied first. They can also create tickets directly in **Jira Cloud and
  ServiceNow**.
- When Inspector closes a finding (because the rescan no longer sees the vulnerable package), Security
  Hub CSPM archives it. That closing event is what I would use to close or comment on the ticket, so the
  ticket's evidence is the re-scan, not someone's word.

The important design choice is the same as in the lab: the ticket asks for a **code change** (Ansible
var, baseline, Terraform), never a hand-fix on an instance. Accepted risks become suppression rules
backed by a deviation register entry with an owner and a review date.

---

## 6. Terraform with security built in

**The lab does:** pre-commit gates (`terraform fmt`, `validate`, `terraform-docs`, `tflint`, Trivy
config scan at HIGH/CRITICAL, ansible-lint), CI that saves a plan and applies only that reviewed plan
behind a manual approval environment (`.github/workflows/ci.yml`), and a local state file outside the
repo. Policy-as-code checks are in `policy/`.

**On AWS I would use:**

- **Remote state in S3**, encrypted (`encrypt = true`, optionally `kms_key_id` for a customer-managed
  key - Terraform then needs `kms:Encrypt`, `kms:Decrypt` and `kms:GenerateDataKey` on it), with **bucket
  versioning** on, which HashiCorp strongly recommend so state can be recovered after mistakes.
- **S3 native state locking** with `use_lockfile = true`. S3 native locking arrived in Terraform 1.10
  and became generally available in 1.11; the DynamoDB locking arguments (`dynamodb_table`) are now
  deprecated and will be removed in a future minor version. Both can run together during migration. For
  a new setup I would not create a DynamoDB lock table at all.
- **tfsec is now part of Trivy.** Aqua Security consolidated tfsec into Trivy and point users there;
  ch-mirror's pre-commit already uses the `terraform_trivy` hook rather than `terraform_tfsec`.
- **OIDC from CI to AWS instead of long-lived keys.** GitHub Actions requests a short-lived token from
  `https://token.actions.githubusercontent.com` (job needs `permissions: id-token: write`), and
  `aws-actions/configure-aws-credentials` exchanges it for temporary role credentials. The IAM role's
  trust policy pins the audience (`sts.amazonaws.com`) and the `sub` claim to a specific repo and branch
  or environment, so only the approved workflow can assume the apply role. Nothing to rotate, nothing to
  leak. I would use a read-only role for `plan` on pull requests and a separate apply role restricted to
  the protected environment.
- **Policy as code** on the plan, not just the HCL. `terraform show -json tfplan` produces a JSON plan
  that Open Policy Agent (Rego, for example via conftest) or HCP Terraform's Sentinel/OPA policy sets
  can evaluate - for example: every EBS volume encrypted, IMDSv2 required, no `0.0.0.0/0` ingress on SSH,
  required tags present. OPA's docs warn that values computed at apply time are unknown in the plan, so
  policy should check intent (arguments set), with AWS-side guardrails (EBS encryption by default,
  Security Hub controls) catching the rest.
- **Plan as the review artefact.** In the lab, a Terraform plan review caught a CPU default that would
  have made the VM unbootable (`evidence/what-broke.md` #15). The same discipline - save the plan, review
  it, apply exactly that plan - is what stops drift on AWS.

---

## Lab component -> AWS equivalent

| Lab (ch-mirror on Proxmox) | AWS equivalent | Why |
|---|---|---|
| Base template 9200 (upstream Rocky 9 GenericCloud) | Vendor AMI via `source_ami_filter`, `most_recent = true` | Always build from the newest vendor image |
| Packer `proxmox-clone` builder | Packer `amazon-ebs` builder | Same HCL structure, same Ansible provisioner |
| Template `ch-rocky9-base-<semver>` | AMI `<prefix>-<version>` with build tags, shared via `ami_users` | Traceable, immutable image versions |
| ZFS storage | KMS-encrypted EBS (customer-managed key) plus EBS encryption by default | Encryption with a key you control, enforced at account level |
| Clearing `authorized_keys` and machine-id in Packer | `ssh_clear_authorized_keys` plus explicit key/history deletion | No build credentials in the image |
| `ansible/verify-vm.yml` gate in the Packer build | Same playbook against the EC2 build instance | Prove controls on a real instance before publishing |
| Molecule (Docker) | Molecule in CI (unchanged) | Role logic tests; not a substitute for the real-VM gate |
| Wazuh SCA (CIS Rocky 9 v1.0.0) | Amazon Inspector CIS scans (CIS RHEL/Rocky 9 2.0.0, AL2023 1.0.0) | OS-level CIS at fleet scale, tag-targeted, multi-account |
| (none) | Security Hub CSPM CIS AWS Foundations Benchmark | Account and service configuration - not the OS |
| Wazuh vulnerability detection | Amazon Inspector (EC2, ECR, Lambda), with CISA KEV intelligence | Continuous, event-driven rescans; KEV-based priority |
| Rebuild image + Terraform replace | New AMI + ASG instance refresh with checkpoints | Immutable patching with staged rollout and rollback |
| (not needed in lab) | SSM Patch Manager: baselines, patch policies, maintenance windows | Long-lived instances that can't be replaced |
| GitHub issues labelled `remediation` | Security Hub automation rules / EventBridge -> Jira, ServiceNow or GitHub | Findings become tickets automatically; closure on re-scan |
| `evidence/deviations.md` | Deviation register + Security Hub suppression rules | Accepted risk is owned, justified and visible |
| Local Terraform state outside the repo | S3 backend, encrypted, versioned, `use_lockfile = true` | Shared, recoverable, locked state without DynamoDB |
| Proxmox API token in GitHub secrets | GitHub OIDC -> IAM role (short-lived credentials) | No long-lived cloud keys anywhere |
| pre-commit: fmt, validate, docs, tflint, Trivy | Same gates in pre-commit and CI | Same checks CH publish in their Terraform repos |
| `policy/` checks | OPA/conftest or Sentinel on `terraform show -json` | Security rules enforced on the plan before apply |
| `kronos-prod` approval environment | Protected environment + OIDC-scoped apply role | Only the reviewed plan, only after approval |

---

## Sources (primary documentation, checked October 2026)

Packer and Terraform:
- Packer amazon-ebs builder - https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs
- Terraform S3 backend (`use_lockfile`, `dynamodb_table` deprecated, `encrypt`, `kms_key_id`, bucket versioning) - https://developer.hashicorp.com/terraform/language/backend/s3
- Upgrading to Terraform v1.11 (S3 native locking GA, DynamoDB arguments deprecated) - https://developer.hashicorp.com/terraform/language/v1.11.x/upgrade-guides
- Terraform v1.10.x changelog (S3 native state locking added) - https://github.com/hashicorp/terraform/blob/v1.10.1/CHANGELOG.md
- Terraform v1.11.0 changelog - https://github.com/hashicorp/terraform/blob/v1.11.0/CHANGELOG.md
- HashiCorp Well-Architected: enforce CIS benchmarks - https://developer.hashicorp.com/well-architected-framework/secure-systems/compliance-and-governance/enforce-cis-benchmarks
- tfsec is now part of Trivy - https://github.com/aquasecurity/tfsec
- OPA with Terraform plans - https://www.openpolicyagent.org/docs/terraform
- Companies House public base AMI repo - https://github.com/companieshouse/rhel9-base-ami

AWS:
- Inspector CIS scans for EC2 operating systems - https://docs.aws.amazon.com/inspector/latest/user/scanning-cis.html
- Inspector supported operating systems (CIS and package scanning) - https://docs.aws.amazon.com/inspector/latest/user/supported.html
- What is Amazon Inspector - https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html
- Inspector automated scan types (EC2 agent/agentless, ECR) - https://docs.aws.amazon.com/inspector/latest/user/scanning-resources.html
- Inspector score and vulnerability intelligence (CISA KEV) - https://docs.aws.amazon.com/inspector/latest/user/findings-understanding-score.html
- Inspector integration with Security Hub CSPM - https://docs.aws.amazon.com/inspector/latest/user/securityhub-integration.html
- CIS AWS Foundations Benchmark in Security Hub CSPM - https://docs.aws.amazon.com/securityhub/latest/userguide/cis-aws-foundations-benchmark.html
- What are Security Hub and Security Hub CSPM - https://docs.aws.amazon.com/securityhub/latest/userguide/what-are-securityhub-services.html
- Introduction to AWS Security Hub - https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub-v2.html
- Security Hub automations (automation rules, Jira Cloud / ServiceNow tickets) - https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-automations.html
- Security Hub CSPM and EventBridge - https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cloudwatch-events.html
- Systems Manager Patch Manager - https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html
- Predefined and custom patch baselines - https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-predefined-and-custom-patch-baselines.html
- State Manager associations that run Ansible playbooks - https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state-manager-ansible.html
- Auto Scaling instance refresh - https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html
- Instance refresh preferences (AutoRollback, AlarmSpecification) - https://docs.aws.amazon.com/autoscaling/ec2/APIReference/API_RefreshPreferences.html
- How an instance refresh works - https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-overview.html
- EBS encryption by default - https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html
- GitHub Actions OIDC with AWS - https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
