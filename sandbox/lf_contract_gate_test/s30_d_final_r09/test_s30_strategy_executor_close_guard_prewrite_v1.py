from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
VALIDATOR_PATH = ROOT / "gobernanza" / "judges" / "validate_s30_self_governance_gate.py"
CONTRACT_PATH = ROOT / "gobernanza" / "contratos" / "s30_self_governance_gate_v1.json"
RECEIPT_PATH = HERE / "s30_strategy_executor_close_guard_v1_prewrite_receipt.json"
EXPECTED_BASE = "d4051d9c57fdfd09741da5ba2718c032eac56c92"

spec = importlib.util.spec_from_file_location("s30_self_governance_validator", VALIDATOR_PATH)
validator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = validator
assert spec.loader is not None
spec.loader.exec_module(validator)

contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
receipt = json.loads(RECEIPT_PATH.read_text(encoding="utf-8"))
result = validator.evaluate(contract, receipt, EXPECTED_BASE)

assert result["result"] == "PASS_TO_MATERIAL_WORK", result
assert result["material_work_allowed"] is True, result
assert result["bounded_repair_allowed"] is False, result
assert result["first_bad_hop"] is None, result
assert result["sequence_failures"] == [], result
assert result["failed_checks"] == [], result
assert result["hard_guard_failures"] == [], result
assert result["blocker_failures"] == [], result

print("S30_STRATEGY_EXECUTOR_CLOSE_GUARD_PREWRITE_V1_PASS")
