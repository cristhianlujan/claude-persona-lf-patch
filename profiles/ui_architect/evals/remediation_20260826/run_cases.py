#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
VALIDATOR = ROOT / "profiles/ui_architect/validators/validate_ui_architect_output.py"
RUNS = ROOT / "sandbox_runs/ui_architect/remediation_20260826"
HISTORICAL = ROOT / "sandbox_runs/ui_architect/home_ruta_claridad_001/worker_output.json"

cases = [
    (HISTORICAL, False, "historical_false_pass_rejected"),
    (RUNS / "before_checkout_direct_001.json", False, "direct_generic_before_rejected"),
    (RUNS / "before_checkout_router_001.json", False, "router_generic_before_rejected"),
    (RUNS / "after_home_ruta_claridad_001.json", True, "home_after_accepted"),
    (RUNS / "after_checkout_direct_001.json", True, "direct_after_accepted"),
    (RUNS / "after_checkout_router_001.json", True, "router_after_accepted")
]

results = []
for path, expected, name in cases:
    cp = subprocess.run([sys.executable, str(VALIDATOR), str(path)], text=True, capture_output=True)
    actual = cp.returncode == 0
    results.append({"case": name, "expected_valid": expected, "actual_valid": actual, "pass": actual == expected})

left = json.loads((RUNS / "after_checkout_direct_001.json").read_text(encoding="utf-8"))["deliverable_created"]["remediation_actions"]
right = json.loads((RUNS / "after_checkout_router_001.json").read_text(encoding="utf-8"))["deliverable_created"]["remediation_actions"]
consistency = left == right
results.append({"case": "router_direct_remediation_consistency", "expected_valid": True, "actual_valid": consistency, "pass": consistency})

print(json.dumps({"passed": sum(r["pass"] for r in results), "total": len(results), "results": results}, indent=2))
raise SystemExit(0 if all(r["pass"] for r in results) else 1)
