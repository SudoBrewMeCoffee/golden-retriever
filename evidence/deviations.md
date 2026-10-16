# CIS deviations register

Benchmark: CIS Red Hat Enterprise Linux 9, Level 1 - Server (applied via ansible-lockdown/RHEL9-CIS 2.4.2).
Each deviation is deliberate, justified, and owned. Anything not listed here is applied as the benchmark says.

| ID | Control | Deviation | Reason | Compensating control | Owner / review |
|---|---|---|---|---|---|
| D1 | 1.4.1 Bootloader password | Not set | Lab template; a GRUB password blocks Proxmox console recovery | Proxmox console access restricted to the host admin; VM is rebuilt from image, not repaired | Graham - review at each image version |
| D2 | 5.2.4 Users must provide password for escalation | Rule 5.2.4 not applied (`rhel9cis_rule_5_2_4: false`); `rocky` keeps NOPASSWD sudo | Key-only automation/admin account with no password; needed by the Packer build and by admins | SSH limited to `rocky` via AllowUsers (5.1.7), key auth only, root login disabled, sudo logged to /var/log/sudo.log | Graham - review at each image version |
| D3 | Level 2 controls | Not applied | Level 1 server profile chosen for the base image | Level 2 can be layered per workload | Graham |
| D4 | 1.6.1.6 (Rocky v1) No unconfined services | Wazuh agent processes run as `unconfined_service_t` | Vendor ships no SELinux policy module; a home-made module is ongoing upkeep and a wrong one can silently break monitoring. The agent is the control that produces the CIS evidence. Issue #9 | Agent from the vendor's signed repo, authenticated/encrypted manager link, patched with the estate; SELinux enforcing for everything else; firewalld public zone limits inbound to the listed services | Graham - review at each image version |
