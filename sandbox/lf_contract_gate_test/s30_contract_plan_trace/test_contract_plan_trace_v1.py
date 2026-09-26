#!/usr/bin/env python3
"""CI discovery wrapper for the LF_CONTRACT_PLAN_TRACE_V1 regression."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

TARGET = Path(__file__).parents[1] / "s28_ci_lane_router" / "test_lf_contract_plan_trace_v1.py"
spec = importlib.util.spec_from_file_location("test_lf_contract_plan_trace_v1", TARGET)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_CONTRACT_PLAN_TRACE_CI_WRAPPER_LOAD")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

if __name__ == "__main__":
    raise SystemExit(module.main())
