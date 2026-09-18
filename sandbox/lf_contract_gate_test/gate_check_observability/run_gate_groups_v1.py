#!/usr/bin/env python3
"""Run deterministic LF gate checks as stable, reusable subprocess groups.

This is an orchestration layer over LF_GATE_CHECK_OBSERVABILITY_V1. It adds
stable group identity, complete-manifest coverage checks, targeted repair reruns,
and a claim/Excel-readiness ceiling. It does not persist EKB or mutate LF state.
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

SCHEMA_VERSION = "lf-gate-group-summary/v1"
PRODUCER = "LF_GATE_GROUP_ORCHESTRATOR_V1"
DEFAULT_CHILD_RUNNER = Path(__file__).with_name("run_gate_checks_v1.py")


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--artifact-dir", required=True)
    p.add_argument("--group", action="append", default=[])
    p.add_argument("--runner", default=str(DEFAULT_CHILD_RUNNER))
    p.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID") or "LOCAL")
    p.add_argument("--job-id", default=os.environ.get("GITHUB_JOB") or "LOCAL")
    return p


def _require_str(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label}_required")
    return value.strip()


def load_manifest(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("manifest_must_be_object")
    if value.get("schema_version") != "lf-gate-group-manifest/v1":
        raise ValueError("manifest_schema_version_invalid")
    _require_str(value.get("consumer_code"), "consumer_code")
    _require_str(value.get("gate_id"), "gate_id")
    _require_str(value.get("owner"), "owner")
    _require_str(value.get("discover_glob"), "discover_glob")
    expected = value.get("expected_total_checks")
    if not isinstance(expected, int) or expected < 1:
        raise ValueError("expected_total_checks_invalid")
    groups = value.get("groups")
    if not isinstance(groups, list) or not groups:
        raise ValueError("groups_required")

    seen_groups: set[str] = set()
    assigned: list[str] = []
    for group in groups:
        if not isinstance(group, dict):
            raise ValueError("group_must_be_object")
        gid = _require_str(group.get("group_id"), "group_id")
        if gid in seen_groups:
            raise ValueError(f"duplicate_group_id:{gid}")
        seen_groups.add(gid)
        if group.get("execution_class") != "DETERMINISTIC":
            raise ValueError(f"execution_class_not_deterministic:{gid}")
        tests = group.get("tests")
        commands = group.get("commands")
        if (tests is None) == (commands is None):
            raise ValueError(f"exactly_one_of_tests_or_commands_required:{gid}")
        if tests is not None:
            if not isinstance(tests, list) or not tests or any(not isinstance(x, str) or not x for x in tests):
                raise ValueError(f"tests_invalid:{gid}")
            assigned.extend(tests)
        else:
            if not isinstance(commands, list) or not commands:
                raise ValueError(f"commands_invalid:{gid}")
            for command in commands:
                if not isinstance(command, dict):
                    raise ValueError(f"command_must_be_object:{gid}")
                unknown = set(command) - {"argv", "source_path", "critical"}
                if unknown:
                    raise ValueError(f"command_unknown_keys:{gid}:{','.join(sorted(unknown))}")
                argv = command.get("argv")
                source_path = command.get("source_path")
                critical = command.get("critical", False)
                if not isinstance(argv, list) or len(argv) < 2 or any(not isinstance(x, str) or not x for x in argv):
                    raise ValueError(f"command_argv_invalid:{gid}")
                if not isinstance(source_path, str) or not source_path:
                    raise ValueError(f"command_source_path_invalid:{gid}")
                if not isinstance(critical, bool):
                    raise ValueError(f"command_critical_invalid:{gid}")
                assigned.append(source_path)

    duplicates = sorted({x for x in assigned if assigned.count(x) > 1})
    if duplicates:
        raise ValueError("duplicate_test_assignment:" + ",".join(duplicates))

    discovered = sorted(p for p in glob.glob(value["discover_glob"], recursive=True) if Path(p).is_file())
    assigned_sorted = sorted(assigned)
    if len(discovered) != expected:
        raise ValueError(f"discovered_count_mismatch:expected={expected}:actual={len(discovered)}")
    if len(assigned_sorted) != expected:
        raise ValueError(f"assigned_count_mismatch:expected={expected}:actual={len(assigned_sorted)}")
    if set(discovered) != set(assigned_sorted):
        missing = sorted(set(discovered) - set(assigned_sorted))
        stale = sorted(set(assigned_sorted) - set(discovered))
        raise ValueError("manifest_coverage_mismatch:missing=" + ",".join(missing) + ":stale=" + ",".join(stale))
    return value


def blocked_summary(manifest_path: Path, artifact_dir: Path, error: Exception) -> int:
    summary = {
        "schema_version": SCHEMA_VERSION,
        "producer": PRODUCER,
        "gate_result": "BLOCKED",
        "diagnostic_complete": False,
        "condition": "group manifest is complete, deterministic and executable",
        "error_class": error.__class__.__name__,
        "error_summary": str(error),
        "manifest_ref": str(manifest_path.as_posix()),
        "manifest_sha256": sha256_bytes(manifest_path.read_bytes()) if manifest_path.is_file() else None,
        "full_selection": False,
        "full_coverage": False,
        "claim_ready": False,
        "excel_ready": False,
        "groups": [],
        "timestamp": now(),
    }
    write_json(artifact_dir / "lf_gate_group_summary_v1.json", summary)
    print(json.dumps({"gate_result": "BLOCKED", "reason": str(error)}, sort_keys=True))
    return 2


def main() -> int:
    args = parser().parse_args()
    manifest_path = Path(args.manifest)
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    try:
        manifest = load_manifest(manifest_path)
        runner = Path(args.runner)
        if not runner.is_file():
            raise ValueError(f"child_runner_missing:{runner.as_posix()}")
        group_map = {g["group_id"]: g for g in manifest["groups"]}
        selected_ids = args.group or [g["group_id"] for g in manifest["groups"]]
        if len(selected_ids) != len(set(selected_ids)):
            raise ValueError("duplicate_group_selector")
        unknown = sorted(set(selected_ids) - set(group_map))
        if unknown:
            raise ValueError("unknown_group_selector:" + ",".join(unknown))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        return blocked_summary(manifest_path, artifact_dir, exc)

    full_selection = selected_ids == [g["group_id"] for g in manifest["groups"]]
    started_at = now()
    rows: list[dict] = []
    executed_test_count = 0
    stopped = False

    for gid in selected_ids:
        group = group_map[gid]
        group_dir = artifact_dir / "groups" / gid
        report_path = group_dir / "lf_gate_error_v1.json"
        command = [
            sys.executable,
            str(runner),
            "--gate-id", f"{manifest['gate_id']}::{gid}",
            "--step-id", gid.lower(),
            "--mode", "COLLECT_ALL",
            "--artifact-dir", str(group_dir),
            "--artifact-name", "lf_gate_error_v1.json",
            "--check-prefix", gid,
            "--owner", manifest["owner"],
            "--next-action", "FIX_FAILED_GROUP_AND_RERUN_TARGETED_THEN_FULL_GATE",
            "--run-id", str(args.run_id),
            "--job-id", str(args.job_id),
        ]
        for impact in group.get("downstream_impact") or manifest.get("downstream_impact") or []:
            command += ["--downstream-impact", str(impact)]
        if group.get("tests") is not None:
            check_specs = [
                {"argv": [sys.executable, test_path], "source_path": test_path, "critical": False}
                for test_path in group["tests"]
            ]
        else:
            check_specs = [dict(spec) for spec in group["commands"]]
        for spec in check_specs:
            command += ["--command-json", canonical(spec)]

        rc = subprocess.run(command).returncode
        if not report_path.is_file():
            result = "BLOCKED"
            report = {}
        else:
            try:
                report = json.loads(report_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                report = {}
            result = str(report.get("gate_result") or ("PASS" if rc == 0 else "FAIL" if rc == 1 else "BLOCKED"))
        executed = int(report.get("executed_check_count") or 0)
        executed_test_count += executed
        row = {
            "group_id": gid,
            "group_name": group.get("name") or gid,
            "execution_class": "DETERMINISTIC",
            "result": result,
            "expected_check_count": len(check_specs),
            "executed_check_count": executed,
            "diagnostic_complete": report.get("diagnostic_complete") is True,
            "report_ref": str(report_path.as_posix()),
            "matrix_tag": group.get("matrix_tag"),
            "claim_surface": group.get("claim_surface", "CONTROL_EVIDENCE_ONLY"),
        }
        rows.append(row)
        print(f"LF_GATE_GROUP group_id={gid} result={result} expected={len(check_specs)} executed={executed}")
        if result != "PASS":
            stopped = True
            break

    executed_ids = [row["group_id"] for row in rows]
    remaining = [gid for gid in selected_ids if gid not in executed_ids]
    blocked = any(row["result"] == "BLOCKED" for row in rows)
    failed = any(row["result"] == "FAIL" for row in rows)
    gate_result = "BLOCKED" if blocked else "FAIL" if failed else "PASS"

    expected_total = int(manifest["expected_total_checks"])
    full_coverage = bool(full_selection and not remaining and executed_test_count == expected_total)
    all_groups_pass = gate_result == "PASS" and len(rows) == len(manifest["groups"])
    claim_ready = bool(full_coverage and all_groups_pass)
    summary = {
        "schema_version": SCHEMA_VERSION,
        "producer": PRODUCER,
        "consumer_code": manifest["consumer_code"],
        "gate_id": manifest["gate_id"],
        "owner": manifest["owner"],
        "gate_result": gate_result,
        "diagnostic_complete": bool(all(row["diagnostic_complete"] for row in rows) and not blocked),
        "group_failure_policy": "STOP_AFTER_FAILED_GROUP",
        "manifest_ref": str(manifest_path.as_posix()),
        "manifest_sha256": sha256_bytes(manifest_path.read_bytes()),
        "run_id": str(args.run_id),
        "job_id": str(args.job_id),
        "started_at": started_at,
        "timestamp": now(),
        "selected_group_ids": selected_ids,
        "executed_group_ids": executed_ids,
        "remaining_group_ids": remaining,
        "full_selection": full_selection,
        "full_coverage": full_coverage,
        "targeted_repair_only": not full_selection,
        "claim_ready": claim_ready,
        "excel_ready": claim_ready,
        "prueba_a_nivel_general": {
            "result": gate_result,
            "expected_group_count": len(manifest["groups"]),
            "executed_group_count": len(rows),
            "expected_check_count": expected_total,
            "executed_check_count": executed_test_count,
            "full_coverage": full_coverage,
        },
        "prueba_paso_a_paso": rows,
        "groups": rows,
        "stopped_after_failed_group": stopped,
    }
    write_json(artifact_dir / "lf_gate_group_summary_v1.json", summary)
    print(json.dumps({
        "schema_version": SCHEMA_VERSION,
        "gate_result": gate_result,
        "full_coverage": full_coverage,
        "claim_ready": claim_ready,
        "excel_ready": claim_ready,
        "executed_groups": len(rows),
        "executed_checks": executed_test_count,
        "artifact": str((artifact_dir / "lf_gate_group_summary_v1.json").as_posix()),
    }, sort_keys=True))
    return 0 if gate_result == "PASS" else 1 if gate_result == "FAIL" else 2


if __name__ == "__main__":
    raise SystemExit(main())
