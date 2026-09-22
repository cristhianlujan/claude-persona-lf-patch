#!/usr/bin/env python3
"""SRCR V0.6 validator ownership regression.

The deterministic validator owns structural blocking codes. The semantic utility
may add independent utility checks, but it must not re-emit the same structural
code set. This prevents two rule engines from drifting over the same invariant.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
det = (ROOT / "validators" / "runtime_validate.py").read_text(encoding="utf-8")
sem = (ROOT / "validators" / "runtime_semantic_utility.py").read_text(encoding="utf-8")

det_codes = set(re.findall(r'_error\("([A-Z0-9_]+)"', det))
sem_codes = set(re.findall(r'codes\.append\("([A-Z0-9_]+)"\)', sem))
overlap = sorted(det_codes & sem_codes)

if overlap:
    print("FAIL V06_CONTROL_OWNERSHIP_OVERLAP " + ",".join(overlap))
    sys.exit(1)

if "SEMANTIC_UTILITY_ONLY_NO_STRUCTURAL_DUPLICATION" not in sem:
    print("FAIL V06_CONTROL_OWNERSHIP_DECLARATION_MISSING")
    sys.exit(1)

print(f"SRCR_V06_CONTROL_OWNERSHIP=PASS deterministic={len(det_codes)} semantic={len(sem_codes)} overlap=0")
