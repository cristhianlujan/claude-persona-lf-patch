#!/usr/bin/env python3
"""Temporary C0 execution bridge.

The historical router self-test still invokes this filename. The bridge contains
no routing/planning logic; it delegates only to the root-clean LF contract-core
baseline harness outside the router package.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

TARGET = (
    Path(__file__).resolve().parent.parent
    / "c0_contract_check"
    / "contract_check_c0_core_baseline_v2.py"
)

if __name__ == "__main__":
    raise SystemExit(subprocess.run([sys.executable, str(TARGET)], check=False).returncode)
