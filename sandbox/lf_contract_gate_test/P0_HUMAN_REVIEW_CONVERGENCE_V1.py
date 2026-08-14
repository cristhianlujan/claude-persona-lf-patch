#!/usr/bin/env python3
"""Execution-only wrapper for the dual-OCR microbenchmark branch.

It runs the exact Human Review Convergence contract from the pinned clean main
parent, then runs the isolated OCR experiment. This wrapper MUST NOT be merged.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PINNED_CLEAN_MAIN = "045e1214f7320f3632d88ec0ed9cc1ada1d7bc07"
CONTRACT_PATH = "sandbox/lf_contract_gate_test/P0_HUMAN_REVIEW_CONVERGENCE_V1.py"
BENCHMARK = Path(__file__).with_name("P0_DUAL_OCR_MICROBENCHMARK_EXEC_V1.py")
EXPECTED_REF = "refs/heads/lf/p0-dual-ocr-microbenchmark-exec"


def run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, cwd=REPO, env=os.environ.copy(), check=False)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def main() -> int:
    if os.environ.get("GITHUB_REF") != EXPECTED_REF:
        raise SystemExit(f"FAIL_DUAL_OCR_WRAPPER_REF:{os.environ.get('GITHUB_REF')}")
    original = subprocess.check_output(
        ["git", "show", f"{PINNED_CLEAN_MAIN}:{CONTRACT_PATH}"], cwd=REPO
    )
    with tempfile.TemporaryDirectory(prefix="lf-p0-contract-") as td:
        contract = Path(td) / "P0_HUMAN_REVIEW_CONVERGENCE_V1.py"
        contract.write_bytes(original)
        run([sys.executable, str(contract)])
    run([sys.executable, str(BENCHMARK)])
    print("PASS_DUAL_OCR_EXECUTION_WRAPPER=1/1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
