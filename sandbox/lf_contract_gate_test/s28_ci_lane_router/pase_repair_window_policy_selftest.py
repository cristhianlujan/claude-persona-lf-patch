#!/usr/bin/env python3
from pathlib import Path

EDGE = Path("supabase/functions/lf-github-reconcile-v3/index.ts")
FALLBACK = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py")
WORKFLOW = Path(".github/workflows/lf-github-reconcile-v3.yml")

edge = EDGE.read_text(encoding="utf-8")
fallback = FALLBACK.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")

assert "pase_repair_window_required_checks_empty" in workflow
assert "pase_repair_window_required_checks_empty" in edge
assert "pase_repair_window_required_checks_empty" in fallback
assert "c.lf_contract_check_required === true" not in edge
assert 'c.get("lf_contract_check_required") is True' not in fallback
assert 'workflows: ["lf-contract-check", "PASE"]' in workflow
assert 'expected_required_checks: []' in workflow
assert 'expected_required_workflow_paths: []' in workflow
print("PASS_PASE_REPAIR_WINDOW_POLICY_SELFTEST=8/8")
