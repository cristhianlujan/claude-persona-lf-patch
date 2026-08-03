#!/usr/bin/env python3
"""E.13.1 verifier overlay over the immutable E.13 receipt verifier."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import PR93_LOTE_E13_SEMANTICS as semantics


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    old_verifier = repo_root / "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py"
    command = [
        sys.executable, str(old_verifier),
        "--bundle-dir", str(args.bundle_dir.resolve()),
        "--trusted-receipt-sha256", args.trusted_receipt_sha256,
        "--repo-root", str(repo_root),
    ]
    if args.receipt:
        command.extend(["--receipt", str(args.receipt.resolve())])
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    if result.returncode != 0:
        sys.stdout.buffer.write(result.stdout)
        return result.returncode

    bundle = args.bundle_dir.resolve()
    receipt_path = (args.receipt or (bundle / "PR93_E13_RECEIPT.json")).resolve()
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if receipt.get("semantic_contract_version") != "PR93_E13_SEMANTICS_V1":
        fail("missing semantic contract version")
    t1_data = (bundle / "PR93_E13_T1_TRANSCRIPT.log").read_bytes()
    computed = semantics.parse_t1_semantics(t1_data, receipt["head_sha"])
    if computed != receipt.get("t1", {}).get("semantic_checks"):
        fail("T1 semantic checks mismatch")
    if receipt.get("t1", {}).get("status") == "PASS" and computed.get("all_pass") is not True:
        fail("T1 PASS lacks semantic readiness")

    t2 = (bundle / "PR93_E13_T2_TRANSCRIPT.log").read_text(encoding="utf-8", errors="replace").splitlines()
    if receipt.get("t2", {}).get("exit_code") != 99:
        marker = f"E13_T2_HEAD_SHA={receipt['head_sha']}"
        if sum(line == marker for line in t2) != 1:
            fail("T2 head marker mismatch")
    for prefix in ("PRE", "POST"):
        log_value = json.loads((bundle / f"PR93_E13_{prefix}_STATE_COMMAND.log").read_text().strip())
        state_value = json.loads((bundle / f"PR93_E13_{prefix}_STATE.json").read_text())
        if log_value != state_value:
            fail(f"{prefix.lower()} state command output mismatch")
    if receipt.get("t2", {}).get("state_command_outputs_match") is not True:
        fail("receipt does not attest state command equality")
    if receipt.get("overall_status") == "PASS":
        if receipt.get("t1", {}).get("status") != "PASS" or receipt.get("t2", {}).get("status") != "PASS":
            fail("overall PASS requires T1 and T2 PASS")
    print("PASS_E13_V2_RECEIPT_VERIFIED")
    print(f"HEAD_SHA={receipt['head_sha']}")
    print(f"RECEIPT_SHA256={args.trusted_receipt_sha256}")
    print(f"OVERALL_STATUS={receipt.get('overall_status')}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"FAIL_E13_V2_RECEIPT_VERIFICATION={exc}", file=sys.stderr)
        raise SystemExit(2)
