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
    }


@pytest.mark.parametrize("regression", [
    None, "warning", "stderr_warning", "failed_service", "empty_log",
    "baseline_changed", "permissive", "skipped_service", "stale_invocation",
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
