"""Run the real Ansible acceptance assertions against service evidence regressions."""

from pathlib import Path
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def evidence():
    return {
        "aide_service_run": {"rc": 0},
        "aide_previous": {"status": {"InvocationID": "old-invocation"}},
        "aidecheck": {"status": {
            "Result": "success", "ExecMainStatus": "0",
            "InvocationID": "1234567890abcdef1234567890abcdef",
            "UnitFileState": "enabled", "ActiveState": "inactive",
            "ConditionResult": "yes",
        }},
        "aide_service_log": {
            "stdout": "AIDE found NO differences between database and filesystem.\nNumber of entries: 36786",
            "stderr": "", "rc": 0,
        },
        "aide_db_before": {"stat": {"exists": True, "checksum": "baseline"}},
        "aide_db_after": {"stat": {"exists": True, "checksum": "baseline"}},
        "aide_enforcement": {"stdout": "Enforcing"},
        "aide_permissive_before": {"rc": 0, "stdout": "Builtin Permissive Types\nqgs_t\n"},
        "aide_permissive_after": {"rc": 0, "stdout": "Builtin Permissive Types\nqgs_t\n"},
    }


@pytest.mark.parametrize("regression", [
    None, "warning", "stderr_warning", "failed_service", "empty_log",
    "baseline_changed", "permissive", "skipped_service", "stale_invocation",
    "domain_permissive_before", "domain_permissive_after", "policy_query_failed",
])
def test_scheduled_service_evidence(tmp_path, regression):
    data = evidence()
    if regression == "warning":
        data["aide_service_log"]["stdout"] += "\nWARNING: fstatfs() failed for /boot/efi: Permission denied"
    elif regression == "stderr_warning":
        data["aide_service_log"]["stderr"] = "WARNING: fstatfs() failed for /efi"
    elif regression == "failed_service":
        data["aidecheck"]["status"]["ExecMainStatus"] = "4"
    elif regression == "empty_log":
        data["aide_service_log"]["stdout"] = ""
    elif regression == "baseline_changed":
        data["aide_db_after"]["stat"]["checksum"] = "replacement"
    elif regression == "permissive":
        data["aide_enforcement"]["stdout"] = "Permissive"
    elif regression == "skipped_service":
        data["aidecheck"]["status"]["ConditionResult"] = "no"
    elif regression == "stale_invocation":
        data["aide_previous"]["status"]["InvocationID"] = data["aidecheck"]["status"]["InvocationID"]

    if regression == "domain_permissive_before":
        data["aide_permissive_before"]["stdout"] += "aide_t\n"
    elif regression == "domain_permissive_after":
        data["aide_permissive_after"]["stdout"] += "aide_t\n"
    elif regression == "policy_query_failed":
        data["aide_permissive_after"]["rc"] = 1

    gate = ROOT / "ansible/tasks/assert-aide-service.yml"
    tasks = [{"ansible.builtin.import_tasks": str(gate)}]
    playbook = tmp_path / "gate.yml"
    playbook.write_text(yaml.safe_dump([{
        "name": "Exercise AIDE service acceptance", "hosts": "localhost",
        "gather_facts": False, "vars": data, "tasks": tasks,
    }]))
    result = subprocess.run([
        "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
    ], capture_output=True, text=True, check=False)
    assert (result.returncode == 0) == (regression is None), result.stdout + result.stderr


@pytest.mark.parametrize("modules,accepted", [
    ("400 aide_efi_metadata pp\n", True),
    ("400 aide_efi_metadata pp disabled\n", False),
    ("400 aide_efi_metadata pp\n500 aide_efi_metadata cil\n", False),
    ("100 other_module pp\n", False),
])
def test_image_requires_enabled_unshadowed_policy(tmp_path, modules, accepted):
    play = yaml.safe_load((ROOT / "ansible/verify-vm.yml").read_text())[0]
    rocky = next(task for task in play["tasks"] if task["name"] == "Rocky image remediation checks")
    gate = next(task for task in rocky["block"] if task["name"] == "Image includes persistent AIDE EFI metadata policy")
    playbook = tmp_path / "policy-gate.yml"
    playbook.write_text(yaml.safe_dump([{
        "name": "Exercise policy installation gate", "hosts": "localhost",
        "gather_facts": False, "vars": {"aide_efi_modules": {"stdout": modules}},
        "tasks": [gate],
    }]))
    result = subprocess.run([
        "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
    ], capture_output=True, text=True, check=False)
    assert (result.returncode == 0) == accepted, result.stdout + result.stderr
