# Guardrails for ch-mirror VMs, checked against `terraform show -json tfplan`.
# Each rule comes from something that went wrong in this lab (evidence/what-broke.md).
# Rego v1 syntax (OPA 1.x / conftest >= 0.56).
package main

required_tags := {"ch-mirror", "cis-l1", "kronos-managed"}

# Every proxmox VM the plan will create or keep (deletes have no "after").
vms contains rc if {
	some rc in input.resource_changes
	rc.type == "proxmox_virtual_environment_vm"
	rc.change.after != null
}

# what-broke #11 / #15: RHEL 9 needs x86-64-v2. The provider default (qemu64)
# and kvm64 don't provide it, so the kernel never boots.
deny contains msg if {
	some rc in vms
	not cpu_type(rc.change.after)
	msg := sprintf("%s: no cpu.type set - provider default qemu64 cannot boot RHEL 9; set cpu.type = \"host\" (what-broke #15)", [rc.address])
}

deny contains msg if {
	some rc in vms
	t := cpu_type(rc.change.after)
	t != "host"
	msg := sprintf("%s: cpu.type is %q - RHEL 9 needs x86-64-v2, use \"host\" (what-broke #11, #15)", [rc.address, t])
}

cpu_type(after) := t if {
	some c in after.cpu
	t := c.type
	t != null
}

# Tags are how the estate knows a guest is hardened, CIS-scanned and Terraform-owned.
deny contains msg if {
	some rc in vms
	present := {t | some t in object.get(rc.change.after, "tags", [])}
	missing := required_tags - present
	count(missing) > 0
	msg := sprintf("%s: missing required tags %v", [rc.address, sort(missing)])
}

# what-broke #4: a DHCP lease handed out the address of a live container (duplicate IP).
deny contains msg if {
	some rc in vms
	some addr in ipv4_addresses(rc.change.after)
	lower(addr) == "dhcp"
	msg := sprintf("%s: ipv4 address is \"dhcp\" - static IPs only, the DHCP pool overlaps live guests (what-broke #4)", [rc.address])
}

deny contains msg if {
	some rc in vms
	count(ipv4_addresses(rc.change.after)) == 0
	msg := sprintf("%s: no static ipv4 address in initialization.ip_config - static IPs only (what-broke #4)", [rc.address])
}

ipv4_addresses(after) := {a |
	some init in object.get(after, "initialization", [])
	some ipc in object.get(init, "ip_config", [])
	some v4 in object.get(ipc, "ipv4", [])
	a := v4.address
	a != null
}

# ch-mirror owns VM IDs 300-309 only; anything else could collide with another guest.
deny contains msg if {
	some rc in vms
	not in_range(object.get(rc.change.after, "vm_id", null), 300, 309)
	msg := sprintf("%s: vm_id %v is outside the ch-mirror range 300-309", [rc.address, object.get(rc.change.after, "vm_id", null)])
}

# VMs must come from a CIS-hardened template built by the Packer pipeline (9200-9299).
deny contains msg if {
	some rc in vms
	not clone_template(rc.change.after)
	msg := sprintf("%s: not cloned from a template - must clone a hardened ch-mirror template (9200-9299)", [rc.address])
}

deny contains msg if {
	some rc in vms
	id := clone_template(rc.change.after)
	not in_range(id, 9200, 9299)
	msg := sprintf("%s: clones template %v - only hardened ch-mirror templates 9200-9299 are allowed", [rc.address, id])
}

clone_template(after) := id if {
	some c in after.clone
	id := c.vm_id
	id != null
}

in_range(n, lo, hi) if {
	is_number(n)
	n >= lo
	n <= hi
}

# what-broke #15 was caught because a human read the plan. Make destructive
# changes impossible to miss: warn (not deny) so a reviewer can still approve.
warn contains msg if {
	some rc in input.resource_changes
	"delete" in rc.change.actions
	kind := action_kind(rc.change.actions)
	msg := sprintf("%s: plan will %s this resource - check the plan before approving apply", [rc.address, kind])
}

action_kind(actions) := "REPLACE (destroy and recreate)" if count(actions) > 1

action_kind(actions) := "DESTROY" if count(actions) == 1
