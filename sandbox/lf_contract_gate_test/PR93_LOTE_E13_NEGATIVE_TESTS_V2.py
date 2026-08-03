#!/usr/bin/env python3
"""Run the original E.13 mutation matrix through V2 and add semantic false-PASS tests."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import PR93_LOTE_E13_SEMANTICS as semantics


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    v2 = repo / "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY_V2.py"
    old_negative = repo / "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS.py"
    result = subprocess.run([
        sys.executable, str(old_negative),
        "--bundle-dir", str(args.bundle_dir.resolve()),
        "--trusted-receipt-sha256", args.trusted_receipt_sha256,
        "--repo-root", str(repo),
        "--verifier", str(v2),
    ], check=False)
    if result.returncode != 0:
        return result.returncode

    receipt = json.loads((args.bundle_dir / "PR93_E13_RECEIPT.json").read_text())
    t1_path = args.bundle_dir / "PR93_E13_T1_TRANSCRIPT.log"
    lines = t1_path.read_text(encoding="utf-8").splitlines()
    index = lines.index("E13_T1_DEPENDENCY_PREFLIGHT")
    value = json.loads(lines[index + 1])
    value["preflight_ready"] = False
    lines[index + 1] = json.dumps(value, separators=(",", ":"))
    checks = semantics.parse_t1_semantics(("\n".join(lines) + "\n").encode(), receipt["head_sha"])
    if checks.get("all_pass") is not False:
        raise SystemExit("semantic false-PASS case unexpectedly passed")
    print("PASS_NEGATIVE_11=t1-preflight-false-cannot-pass")

    duplicate = t1_path.read_text(encoding="utf-8").splitlines()
    head = next(line for line in duplicate if line.startswith("E13_T1_HEAD_SHA="))
    duplicate.insert(duplicate.index(head) + 1, head)
    try:
        semantics.parse_t1_semantics(("\n".join(duplicate) + "\n").encode(), receipt["head_sha"])
    except ValueError:
        pass
    else:
        raise SystemExit("duplicate T1 head marker unexpectedly passed")
    print("PASS_NEGATIVE_12=duplicate-t1-head-rejected")
    print("PASS_E13_NEGATIVE_MATRIX=12/12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
