#!/usr/bin/env python3
from __future__ import annotations
import copy, json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VALIDATOR = HERE.parent.parent / "validators" / "validate_semantic_judge_result.py"
RESULT = HERE / "mr02_r2_semantic_judge_result.json"

def run(payload: dict, name: str) -> tuple[str, dict]:
    tmp = HERE / (".tmp_" + name + ".json")
    try:
        tmp.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(VALIDATOR), str(tmp)], text=True, capture_output=True)
        data = json.loads(proc.stdout)
        return ("PASS" if proc.returncode == 0 else "FAIL", data)
    finally:
        tmp.unlink(missing_ok=True)

base = json.loads(RESULT.read_text(encoding="utf-8"))
out = {}

state, data = run(base, "expected_return")
out["mr02_r2_expected_return_shape"] = {"observed": state, "detail": data, "expected": "PASS"}

bad = copy.deepcopy(base)
bad["verdict"] = "PASS_INDEPENDENT_SEMANTIC"
bad["blocking_codes"] = []
bad["open_design_decisions_found"] = []
state, data = run(bad, "malicious_pass")
out["malicious_pass_fail_closed"] = {"observed": state, "detail": data, "expected": "FAIL"}

missing = copy.deepcopy(base)
missing["scope_conformance_reconciliation"] = [
    x for x in missing["scope_conformance_reconciliation"] if x["change_id"] != "JCHG-002"
]
state, data = run(missing, "missing_coverage")
out["missing_change_scope_coverage"] = {"observed": state, "detail": data, "expected": "FAIL"}

ok = all(v["observed"] == v["expected"] for v in out.values())
print(json.dumps({"status": "PASS" if ok else "FAIL", "cases": out}, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
