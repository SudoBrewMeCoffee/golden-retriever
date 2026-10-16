# Unit tests for proxmox_vm.rego - run with: conftest verify -p policy/terraform
# Fixtures mirror the shape of `terraform show -json tfplan` for bpg/proxmox.
package main

# A VM that matches terraform/main.tf defaults - must pass cleanly.
good_vm := {
	"vm_id": 301,
	"name": "ch-app-01",
	"tags": ["ch-mirror", "cis-l1", "kronos-managed"],
	"cpu": [{"cores": 2, "type": "host"}],
	"clone": [{"vm_id": 9201, "full": true}],
	"initialization": [{"ip_config": [{"ipv4": [{"address": "10.69.1.72/24", "gateway": "10.69.1.1"}]}]}],
}

plan_with(after, actions) := {"resource_changes": [{
	"address": "proxmox_virtual_environment_vm.app",
	"type": "proxmox_virtual_environment_vm",
	"change": {"actions": actions, "after": after},
}]}

create(after) := plan_with(after, ["create"])

with_ip(addr) := object.union(good_vm, {"initialization": [{"ip_config": [{"ipv4": [{"address": addr}]}]}]})

denied_with(after, text) if {
	some msg in deny with input as create(after)
	contains(msg, text)
}

# --- good fixtures ---------------------------------------------------------

test_good_vm_has_no_denies if {
	count(deny) == 0 with input as create(good_vm)
}

test_good_vm_has_no_warnings if {
	count(warn) == 0 with input as create(good_vm)
}

test_unchanged_vm_passes if {
	count(deny) == 0 with input as plan_with(good_vm, ["no-op"])
}

test_other_resource_types_ignored if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "null_resource.x",
		"type": "null_resource",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

test_range_edges_allowed if {
	count(deny) == 0 with input as create(object.union(good_vm, {"vm_id": 309, "clone": [{"vm_id": 9299}]}))
}

# --- bad fixtures: cpu (what-broke #11, #15) -------------------------------

test_cpu_qemu64_denied if {
	denied_with(object.union(good_vm, {"cpu": [{"type": "qemu64"}]}), "cpu.type is \"qemu64\"")
}

test_cpu_kvm64_denied if {
	denied_with(object.union(good_vm, {"cpu": [{"type": "kvm64"}]}), "use \"host\"")
}

test_cpu_missing_denied if {
	denied_with(object.remove(good_vm, ["cpu"]), "no cpu.type set")
}

# --- bad fixtures: tags ----------------------------------------------------

test_wrong_tags_denied if {
	denied_with(object.union(good_vm, {"tags": ["oops"]}), "missing required tags")
}

test_one_tag_missing_named if {
	denied_with(object.union(good_vm, {"tags": ["ch-mirror", "kronos-managed"]}), "cis-l1")
}

test_no_tags_denied if {
	denied_with(object.remove(good_vm, ["tags"]), "missing required tags")
}

# --- bad fixtures: DHCP (what-broke #4) ------------------------------------

test_dhcp_denied if {
	denied_with(with_ip("dhcp"), "static IPs only")
}

test_no_ip_config_denied if {
	denied_with(object.remove(good_vm, ["initialization"]), "no static ipv4 address")
}

# --- bad fixtures: vm_id and template ranges -------------------------------

test_vm_id_above_range_denied if {
	denied_with(object.union(good_vm, {"vm_id": 310}), "outside the ch-mirror range")
}

test_vm_id_below_range_denied if {
	denied_with(object.union(good_vm, {"vm_id": 130}), "outside the ch-mirror range")
}

test_vm_id_unset_denied if {
	denied_with(object.remove(good_vm, ["vm_id"]), "outside the ch-mirror range")
}

test_template_outside_range_denied if {
	denied_with(object.union(good_vm, {"clone": [{"vm_id": 9000}]}), "only hardened ch-mirror templates")
}

test_no_clone_denied if {
	denied_with(object.remove(good_vm, ["clone"]), "not cloned from a template")
}

# --- delete / replace: warn, never deny ------------------------------------

test_replace_warns_not_denies if {
	some msg in warn with input as plan_with(good_vm, ["delete", "create"])
	contains(msg, "REPLACE")
	count(deny) == 0 with input as plan_with(good_vm, ["delete", "create"])
}

test_destroy_warns if {
	some msg in warn with input as plan_with(null, ["delete"])
	contains(msg, "DESTROY")
}

test_destroy_not_checked_as_vm if {
	count(deny) == 0 with input as plan_with(null, ["delete"])
}
