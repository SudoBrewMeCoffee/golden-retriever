# CIS deviations register

Benchmark: CIS Red Hat Enterprise Linux 9, Level 1 - Server (applied via ansible-lockdown/RHEL9-CIS 2.4.2).
Each deviation is deliberate, justified, and owned. Anything not listed here is applied as the benchmark says.

| ID | Control | Deviation | Reason | Compensating control | Owner / review |
|---|---|---|---|---|---|
| D1 | 1.4.1 Bootloader password | Not set | Lab template; a GRUB password blocks Proxmox console recovery | Proxmox console access restricted to the host admin; VM is rebuilt from image, not repaired | Graham - review at each image version |
| D2 | 5.2.4 Users must provide password for escalation | Rule 5.2.4 not applied (`rhel9cis_rule_5_2_4: false`); `rocky` keeps NOPASSWD sudo | Key-only automation/admin account with no password; needed by the Packer build and by admins | SSH limited to `rocky` via AllowUsers (5.1.7), key auth only, root login disabled, sudo logged to /var/log/sudo.log | Graham - review at each image version |
| D3 | Level 2 controls | Not applied | Level 1 server profile chosen for the base image | Level 2 can be layered per workload | Graham |
