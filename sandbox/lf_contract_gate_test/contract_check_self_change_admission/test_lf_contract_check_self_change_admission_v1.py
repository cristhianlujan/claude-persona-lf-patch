#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE = HERE / "lf_contract_check_self_change_admission_v1.py"
spec = importlib.util.spec_from_file_location("guard", MODULE)
guard = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(guard)

result = guard.self_test()
assert result == {"status": "PASS_SELF_TEST", "checks": 9}, result

fixture = guard._base_fixture()
out = guard.evaluate_admission(fixture)
assert out["status"] == "PASS_SELF_CHANGE_ADMISSION"
assert out["protected_touched"] == [guard.PROTECTED_SURFACES[1]]
assert out["execution_id"] == "EXEC-SELF-CHANGE-001"

unrelated = guard.evaluate_admission({"changed_files": ["docs/architecture.md"]})
assert unrelated["status"] == "PASS_NOT_APPLICABLE"
assert unrelated["applicable"] is False

print(json.dumps({"status": "PASS", "self_test_checks": 9, "integration_checks": 5}, sort_keys=True))
