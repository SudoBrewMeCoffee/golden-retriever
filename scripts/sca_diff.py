#!/usr/bin/env python3
"""Compare two Wazuh SCA JSONL exports and write Markdown to stdout.

Usage: python3 scripts/sca_diff.py before.jsonl after.jsonl > sca-report.md
Only Python's standard library is needed. Run tests with: python3 -m pytest tests/
"""

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re


RESULTS = {"passed", "failed", "not applicable"}


def read_export(path):
    """Index controls by policy AND check ID so different policies cannot collide."""
    controls = {}
    with path.open(encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            location = f"{path}:{number}:"
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{location} invalid JSON: {error.msg}") from error
            if not isinstance(row, dict):
                raise ValueError(f"{location} expected a JSON object")
            required = {"policy_id", "id", "title", "result"}
            if not required <= row.keys():
                raise ValueError(f"{location} missing required fields")
            if not isinstance(row["policy_id"], str) or not row["policy_id"].strip():
                raise ValueError(f"{location} policy_id must be a nonempty string")
            if type(row["id"]) is not int or not isinstance(row["title"], str):
                raise ValueError(f"{location} id must be an integer and title a string")
            if not isinstance(row["result"], str) or row["result"] not in RESULTS:
                raise ValueError(f"{location} unsupported result: {row['result']!r}")
            if not isinstance(row.get("compliance", ""), str):
                raise ValueError(f"{location} compliance must be a string")
            key = (row["policy_id"], row["id"])
            if key in controls:
                raise ValueError(f"{location} duplicate control {key}")
            controls[key] = row
    if not controls:
        raise ValueError(f"{path}: no controls found")
    return controls


def cell(value):
    """Keep titles and IDs on one Markdown line, without raw HTML or table pipes."""
    text = " ".join(str(value).split())
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return re.sub(r"([\\`*_\[\]|])", r"\\\1", text)


def control_line(row):
    cis = re.search(r"\bcis:(\d+(?:\.\d+)*)", row.get("compliance", ""))
    reference = f"CIS {cis.group(1)}" if cis else "CIS unclassified"
    return f"{cell(row['policy_id'])} / {row['id']} — {reference} — {cell(row['title'])}"


def report(before, after):
    lines = [
        "# Wazuh SCA comparison", "",
        "Scores are calculated from these exports as passed / (passed + failed).",
        "Not-applicable controls are excluded. Percentages are shown to two decimals;",
        "Wazuh's integer summary may truncate them. Counts below cover all exported policies.", "",
        "| Scan | Passed | Failed | Not applicable | Score |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for label, controls in [("Before", before), ("After", after)]:
        counts = Counter(row["result"] for row in controls.values())
        applicable = counts["passed"] + counts["failed"]
        score = f"{100 * counts['passed'] / applicable:.2f}%" if applicable else "N/A"
        lines.append(f"| {label} | {counts['passed']} | {counts['failed']} | "
                     f"{counts['not applicable']} | {score} |")

    common = before.keys() & after.keys()
    # Only comparable failed/passed transitions count as fixes or regressions.
    fixed = sorted(k for k in common if before[k]["result"] == "failed"
                   and after[k]["result"] == "passed")
    regressed = sorted(k for k in common if before[k]["result"] == "passed"
                       and after[k]["result"] == "failed")
    still = sorted(k for k in common if before[k]["result"] == after[k]["result"] == "failed")
    for heading, keys in [("Fixed", fixed), ("Regressed", regressed)]:
        lines.extend(["", f"## {heading} ({len(keys)})", ""])
        lines.extend([f"- {control_line(after[k])}" for k in keys] or ["None."])

    lines.extend(["", f"## Still failing ({len(still)})", ""])
    sections = defaultdict(list)
    for key in still:
        match = re.search(r"\bcis:(\d+)(?:\.|\b)", after[key].get("compliance", ""))
        sections[int(match.group(1)) if match else 0].append(after[key])
    if not still:
        lines.append("None.")
    for section, rows in sorted(sections.items()):
        heading = f"CIS section {section}" if section else "CIS unclassified"
        lines.extend([f"### {heading}", ""])
        lines.extend(f"- {control_line(row)}" for row in rows)
        lines.append("")

    # Missing checks and applicability changes can otherwise look like improvements.
    other = []
    for key in sorted(before.keys() | after.keys()):
        if key not in before:
            other.append(f"{control_line(after[key])} — added ({after[key]['result']})")
        elif key not in after:
            other.append(f"{control_line(before[key])} — removed (was {before[key]['result']})")
        elif before[key]["result"] != after[key]["result"] and key not in fixed + regressed:
            other.append(f"{control_line(after[key])} — "
                         f"{before[key]['result']} → {after[key]['result']}")
    lines.extend(["", f"## Other changes ({len(other)})", ""])
    lines.extend([f"- {change}" for change in other] or ["None."])
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path, help="Before SCA JSONL export")
    parser.add_argument("after", type=Path, help="After SCA JSONL export")
    args = parser.parse_args()
    try:
        before = read_export(args.before)
        after = read_export(args.after)
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))
    print(report(before, after), end="")


if __name__ == "__main__":
    main()
