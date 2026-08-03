#!/usr/bin/env python3
"""E.13.1 capture overlay: semantic readiness, unique head markers and exact state evidence."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import PR93_LOTE_E13_CAPTURE as base
import PR93_LOTE_E13_SEMANTICS as semantics

OVERLAY_PATHS = (
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_SEMANTICS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_1_GUARDS.md",
)


def exact_line_count(data: bytes, value: str) -> int:
    return sum(line == value for line in data.decode("utf-8", "replace").splitlines())


def json_log_matches(log_path: Path, state_path: Path) -> bool:
    try:
        log_value = json.loads(log_path.read_text(encoding="utf-8").strip())
        state_value = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return log_value == state_value


def add_overlay_sources(receipt: dict, repo_root: Path, timeout: int) -> None:
    sources = receipt.setdefault("source_artifacts", {})
    for relative in OVERLAY_PATHS:
        path = repo_root / relative
        if not path.is_file():
            raise RuntimeError(f"missing overlay source artifact: {relative}")
        data = path.read_bytes()
        sources[relative] = {
            "git_blob_sha1": base.git_text(repo_root, ["rev-parse", f"HEAD:{relative}"], timeout),
            "sha256": base.sha256_bytes(data),
            "size_bytes": len(data),
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--psql-bin", default="psql")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    output_dir = args.output_dir.resolve()
    base_script = repo_root / "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE.py"
    command = [
        sys.executable, str(base_script),
        "--head-sha", args.head_sha,
        "--repo-root", str(repo_root),
        "--output-dir", str(output_dir),
        "--psql-bin", args.psql_bin,
        "--timeout-seconds", str(args.timeout_seconds),
    ]
    result = subprocess.run(
        command, cwd=repo_root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        check=False, timeout=args.timeout_seconds + 30, env=os.environ.copy(),
    )
    receipt_path = output_dir / "PR93_E13_RECEIPT.json"
    if not receipt_path.is_file():
        sys.stderr.buffer.write(result.stdout)
        return result.returncode or 20

    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    t1_data = (output_dir / "PR93_E13_T1_TRANSCRIPT.log").read_bytes()
    t2_data = (output_dir / "PR93_E13_T2_TRANSCRIPT.log").read_bytes()
    try:
        semantic_checks = semantics.parse_t1_semantics(t1_data, args.head_sha)
    except (UnicodeDecodeError, ValueError) as exc:
        semantic_checks = {"all_pass": False, "validation_error": str(exc)}

    receipt["semantic_contract_version"] = "PR93_E13_SEMANTICS_V1"
    receipt["t1"]["semantic_checks"] = semantic_checks
    t1_ok = receipt["t1"].get("status") == "PASS" and semantic_checks.get("all_pass") is True
    receipt["t1"]["status"] = "PASS" if t1_ok else "FAIL"

    t2_exit = receipt["t2"].get("exit_code")
    t2_head_ok = t2_exit == 99 or exact_line_count(t2_data, f"E13_T2_HEAD_SHA={args.head_sha}") == 1
    state_logs_match = (
        json_log_matches(output_dir / "PR93_E13_PRE_STATE_COMMAND.log", output_dir / "PR93_E13_PRE_STATE.json")
        and json_log_matches(output_dir / "PR93_E13_POST_STATE_COMMAND.log", output_dir / "PR93_E13_POST_STATE.json")
    )
    receipt["t2"]["head_marker_match"] = t2_head_ok
    receipt["t2"]["state_command_outputs_match"] = state_logs_match
    t2_ok = receipt["t2"].get("status") == "PASS" and t2_head_ok and state_logs_match
    receipt["t2"]["status"] = "PASS" if t2_ok else "FAIL"
    receipt["overall_status"] = "PASS" if t1_ok and t2_ok else "FAIL"
    receipt["capture_invariants"]["semantic_overlay_required"] = True
    receipt["capture_invariants"]["distinct_head_markers_required"] = True
    receipt["capture_invariants"]["state_command_json_equality_required"] = True
    add_overlay_sources(receipt, repo_root, args.timeout_seconds)

    receipt_bytes = base.canonical_json_bytes(receipt)
    receipt_path.write_bytes(receipt_bytes)
    digest = base.sha256_bytes(receipt_bytes)
    (output_dir / "PR93_E13_RECEIPT.sha256").write_text(
        f"{digest}  PR93_E13_RECEIPT.json\n", encoding="utf-8"
    )
    print(f"E13_RECEIPT_SHA256={digest}")
    print(f"E13_OVERALL_STATUS={receipt['overall_status']}")
    print(f"E13_T2_ROLLBACK_STATUS={receipt['t2'].get('rollback_status')}")
    if receipt["overall_status"] == "PASS":
        return 0
    if not t1_ok:
        return 10
    if receipt["t2"].get("rollback_status") == "NOT_VERIFIED":
        return 12
    return 11


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"E13_CAPTURE_V2_FATAL={exc}", file=sys.stderr)
        raise SystemExit(20)
