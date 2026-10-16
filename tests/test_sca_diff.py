"""Exercise the public CLI against the committed Wazuh exports and small edge cases."""

import json
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/sca_diff.py"


@pytest.fixture
def exports():
    return (
        ROOT / "evidence/01-sca-before-checks.jsonl",
        ROOT / "evidence/06-sca-after-checks.jsonl",
    )


def run_diff(before, after):
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(before), str(after)],
        capture_output=True, text=True, check=False,
    )


def write_export(path, rows):
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    return path


def control(identifier, result, cis="1.1.1", policy="rocky", title="A control"):
    return dict(policy_id=policy, id=identifier, result=result,
                compliance=f"cis:{cis}", title=title)


def test_real_exports_report_scores_and_transitions(exports):
    result = run_diff(*exports)
    assert result.returncode == 0, result.stderr
    assert "| Before | 87 | 77 | 2 | 53.05% |" in result.stdout
    assert "| After | 122 | 43 | 1 | 73.94% |" in result.stdout
    assert "## Fixed (35)" in result.stdout
    assert "## Regressed (1)" in result.stdout
    assert "## Still failing (42)" in result.stdout
    assert "## Other changes (1)" in result.stdout
    assert "not applicable → passed" in result.stdout
    assert "### CIS section 1" in result.stdout
    assert "### CIS section 5" in result.stdout


def test_identical_exports_have_no_fixed_or_regressed(exports):
    result = run_diff(exports[1], exports[1])
    assert result.returncode == 0
    assert "## Fixed (0)\n\nNone." in result.stdout
    assert "## Regressed (0)\n\nNone." in result.stdout
    assert "## Still failing (43)" in result.stdout


def test_added_removed_na_and_policy_ids_are_not_false_fixes(tmp_path):
    before = write_export(tmp_path / "before", [
        control(1, "failed"), control(2, "passed"),
        control(3, "not applicable"), control(1, "passed", policy="other"),
    ])
    after = write_export(tmp_path / "after", [
        control(1, "passed"), control(3, "passed"),
        control(4, "failed"), control(1, "failed", policy="other"),
    ])
    result = run_diff(before, after)
    assert result.returncode == 0, result.stderr
    assert "## Fixed (1)" in result.stdout
    assert "## Regressed (1)" in result.stdout
    assert "## Still failing (0)" in result.stdout
    assert "## Other changes (3)" in result.stdout
    assert "removed (was passed)" in result.stdout
    assert "added (failed)" in result.stdout
    assert "not applicable → passed" in result.stdout


@pytest.mark.parametrize("rows, message", [
    ([control(1, "unknown")], "unsupported result"),
    ([control(1, "failed"), control(1, "passed")], "duplicate control"),
    ([{"id": 1}], "missing required fields"),
    ([[]], "expected a JSON object"),
])
def test_invalid_records_fail_cleanly(tmp_path, rows, message):
    path = write_export(tmp_path / "invalid", rows)
    result = run_diff(path, path)
    assert result.returncode != 0
    assert message in result.stderr
    assert ":1:" in result.stderr or ":2:" in result.stderr
    assert not result.stdout
    assert "Traceback" not in result.stderr


def test_malformed_json_has_filename_and_line(tmp_path):
    path = tmp_path / "bad.jsonl"
    path.write_text('\n{"id":\n')
    result = run_diff(path, path)
    assert result.returncode != 0
    assert f"{path}:2:" in result.stderr
    assert "invalid JSON" in result.stderr


def test_no_applicable_controls_and_missing_cis(tmp_path):
    row = control(1, "not applicable")
    row["compliance"] = ""
    before = write_export(tmp_path / "before", [row])
    row = dict(row, result="failed", title="Title | with\nnewline")
    after = write_export(tmp_path / "after", [row])
    result = run_diff(before, after)
    assert result.returncode == 0
    assert "| Before | 0 | 0 | 1 | N/A |" in result.stdout
    assert "Title \\| with newline" in result.stdout
    assert "not applicable → failed" in result.stdout


def test_empty_export_and_missing_file_are_errors(tmp_path):
    path = tmp_path / "empty"
    path.write_text("\n")
    for candidate, message in [(path, "no controls"), (tmp_path / "absent", "No such file")]:
        result = run_diff(candidate, path)
        assert result.returncode != 0
        assert message in result.stderr
        assert "Traceback" not in result.stderr
