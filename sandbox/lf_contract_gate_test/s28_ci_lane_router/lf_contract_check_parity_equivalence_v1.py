#!/usr/bin/env python3
"""Fail-closed equivalence judge for legacy vs declarative MIGRATION_SOURCE_PARITY.

This is not an executor. It compares two executions of the same deterministic
control on one checkout and one frozen input snapshot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

CONTROL = "MIGRATION_SOURCE_PARITY"
SCHEMA_VERSION = "lf-contract-check-control-equivalence/v1"
_SHA40 = re.compile(r"^[0-9a-f]{40}$")


def sha256_bytes(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_bool(value: str) -> bool:
    lowered = value.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    raise ValueError(f"invalid_boolean:{value}")


def parse_controls(raw: str) -> list[str]:
    value = json.loads(raw)
    if not isinstance(value, list) or any(not isinstance(x, str) or not x for x in value):
        raise ValueError("required_controls_must_be_nonempty_string_array")
    if len(value) != len(set(value)):
        raise ValueError("required_controls_duplicate")
    return value


def parse_pair(raw: str) -> tuple[Path, Path]:
    if "=" not in raw:
        raise ValueError("input_pair_requires_legacy_equals_shadow")
    legacy, shadow = raw.split("=", 1)
    if not legacy or not shadow:
        raise ValueError("input_pair_path_missing")
    return Path(legacy), Path(shadow)


def require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise ValueError(f"{label}_missing:{path.as_posix()}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--required-controls-json", required=True)
    p.add_argument("--legacy-required", required=True)
    p.add_argument("--legacy-result", choices=["PASS", "FAIL", "BLOCKED"], required=True)
    p.add_argument("--legacy-stdout", required=True)
    p.add_argument("--legacy-stderr", required=True)
    p.add_argument("--shadow-summary", required=True)
    p.add_argument("--input-pair", action="append", default=[])
    p.add_argument("--expected-source-head", required=True)
    p.add_argument("--expected-tested-head", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    controls = parse_controls(args.required_controls_json)
    legacy_required = parse_bool(args.legacy_required)
    declarative_required = CONTROL in controls
    if legacy_required != declarative_required:
        raise SystemExit(
            f"FAIL_PARITY_EQUIVALENCE_APPLICABILITY legacy={legacy_required} declarative={declarative_required}"
        )
    if not legacy_required:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_NOT_APPLICABLE")

    if not _SHA40.fullmatch(args.expected_source_head):
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_SOURCE_HEAD")
    if not _SHA40.fullmatch(args.expected_tested_head):
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_TESTED_HEAD")

    legacy_stdout = Path(args.legacy_stdout)
    legacy_stderr = Path(args.legacy_stderr)
    shadow_summary_path = Path(args.shadow_summary)
    for path, label in (
        (legacy_stdout, "legacy_stdout"),
        (legacy_stderr, "legacy_stderr"),
        (shadow_summary_path, "shadow_summary"),
    ):
        require_file(path, label)

    input_rows = []
    if not args.input_pair:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_INPUT_PAIRS_MISSING")
    for raw in args.input_pair:
        try:
            legacy_path, shadow_path = parse_pair(raw)
            require_file(legacy_path, "legacy_input")
            require_file(shadow_path, "shadow_input")
        except ValueError as exc:
            raise SystemExit(f"FAIL_PARITY_EQUIVALENCE_INPUT:{exc}") from exc
        legacy_sha = sha256_bytes(legacy_path)
        shadow_sha = sha256_bytes(shadow_path)
        if legacy_sha != shadow_sha:
            raise SystemExit(
                f"FAIL_PARITY_EQUIVALENCE_INPUT_DIGEST:{legacy_path.as_posix()}:{shadow_path.as_posix()}"
            )
        input_rows.append(
            {
                "legacy_ref": legacy_path.as_posix(),
                "shadow_ref": shadow_path.as_posix(),
                "sha256": legacy_sha,
            }
        )

    summary = json.loads(shadow_summary_path.read_text(encoding="utf-8"))
    if summary.get("producer") != "LF_GATE_GROUP_ORCHESTRATOR_V1":
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_SHADOW_PRODUCER")
    if summary.get("consumer_code") != "LF_CONTRACT_CHECK":
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_SHADOW_CONSUMER")
    if summary.get("selected_group_ids") != [CONTROL] or summary.get("executed_group_ids") != [CONTROL]:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_GROUP_SELECTION")
    if summary.get("remaining_group_ids") != []:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_REMAINING_GROUPS")
    if summary.get("gate_result") != args.legacy_result:
        raise SystemExit(
            f"FAIL_PARITY_EQUIVALENCE_RESULT legacy={args.legacy_result} shadow={summary.get('gate_result')}"
        )
    if summary.get("full_coverage") is not True:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_COVERAGE")

    groups = summary.get("groups")
    if not isinstance(groups, list) or len(groups) != 1:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_GROUP_COUNT")
    group = groups[0]
    if group.get("group_id") != CONTROL:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_GROUP_ID")
    if group.get("expected_check_count") != 1 or group.get("executed_check_count") != 1:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_CHECK_COUNT")

    report_path = Path(str(group.get("report_ref") or ""))
    require_file(report_path, "shadow_child_report")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("gate_result") != args.legacy_result:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_CHILD_RESULT")
    if report.get("expected_check_count") != 1 or report.get("executed_check_count") != 1:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_CHILD_COUNT")
    checks = report.get("checks")
    if not isinstance(checks, list) or len(checks) != 1:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_CHILD_CHECKS")
    check = checks[0]
    if check.get("source_path") != "sandbox/lf_contract_gate_test/lf_migration_source_parity.py":
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_SOURCE_PATH")
    if check.get("source_commit") != args.expected_source_head:
        raise SystemExit(
            f"FAIL_PARITY_EQUIVALENCE_SOURCE_COMMIT expected={args.expected_source_head} actual={check.get('source_commit')}"
        )
    if check.get("tested_commit") != args.expected_tested_head:
        raise SystemExit(
            f"FAIL_PARITY_EQUIVALENCE_TESTED_COMMIT expected={args.expected_tested_head} actual={check.get('tested_commit')}"
        )

    shadow_stdout = Path(str(check.get("stdout_ref") or ""))
    shadow_stderr = Path(str(check.get("stderr_ref") or ""))
    require_file(shadow_stdout, "shadow_stdout")
    require_file(shadow_stderr, "shadow_stderr")
    legacy_stdout_sha = sha256_bytes(legacy_stdout)
    legacy_stderr_sha = sha256_bytes(legacy_stderr)
    shadow_stdout_sha = sha256_bytes(shadow_stdout)
    shadow_stderr_sha = sha256_bytes(shadow_stderr)
    if check.get("stdout_sha256") != shadow_stdout_sha or check.get("stderr_sha256") != shadow_stderr_sha:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_CHILD_LOG_DIGEST")
    if legacy_stdout_sha != shadow_stdout_sha:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_STDOUT")
    if legacy_stderr_sha != shadow_stderr_sha:
        raise SystemExit("FAIL_PARITY_EQUIVALENCE_STDERR")

    receipt = {
        "schema_version": SCHEMA_VERSION,
        "control": CONTROL,
        "result": "PASS_EQUIVALENT",
        "applicability": {
            "legacy_required": legacy_required,
            "declarative_required": declarative_required,
            "required_controls": controls,
        },
        "execution": {
            "legacy_result": args.legacy_result,
            "shadow_result": summary.get("gate_result"),
            "expected_check_count": 1,
            "executed_check_count": 1,
            "full_coverage": True,
        },
        "binding": {
            "source_head": args.expected_source_head,
            "tested_head": args.expected_tested_head,
            "shadow_manifest_sha256": summary.get("manifest_sha256"),
        },
        "inputs": input_rows,
        "outputs": {
            "stdout_sha256": legacy_stdout_sha,
            "stderr_sha256": legacy_stderr_sha,
            "shadow_summary_ref": shadow_summary_path.as_posix(),
            "shadow_child_report_ref": report_path.as_posix(),
        },
        "divergence_count": 0,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS_LF_CONTRACT_CHECK_PARITY_EQUIVALENCE divergence_count=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
