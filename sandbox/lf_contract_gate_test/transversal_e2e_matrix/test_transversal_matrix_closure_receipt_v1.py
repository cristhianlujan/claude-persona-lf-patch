#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
r = json.loads((HERE / "transversal_matrix_closure_receipt_v1.json").read_text(encoding="utf-8"))

assert r["decision"] == "BLOCK"
assert r["freeze_effect"] == {
    "s26_transversal_assurance_clean": False,
    "s30_transversal_assurance_clean": False,
    "s30_formal_freeze_allowed": False,
}

for key, item in r["coverage"].items():
    assert item["coverage_pct"] == 100, (key, item)

adv = r["verified_results"]["router_adversarial"]
assert adv["bypass_and_ready"] == 14
assert adv["policy_filter_bypass_but_other_gate_blocks"] == 1
assert adv["blocked_before_policy_surface"] == 2
assert adv["target_hint_override_confirmed"] is True

assert r["verified_results"]["routed_graph"] == {
    "clean_operations": 8,
    "operations_with_findings": 6,
}
assert r["verified_results"]["unrouted_provenance"]["productionish_requires_provenance"] == 10
assert r["verified_results"]["unrouted_provenance"]["productionish_structurally_proven"] == 0

reserve = r["verified_results"]["direct_execution_reservation"]
assert reserve["router_or_equivalent_authority_provenance_required"] is False
assert reserve["policy_snapshot_on_insert"] is True
assert reserve["required_policy_resolution_guard"] is True
assert reserve["policy_snapshot_currentness_and_immutability_guard"] is True
assert reserve["registered_operation_required"] is True

assert r["permanent_regression_materialization"]["checked_in_ci_consumption"] is True
assert r["permanent_regression_materialization"]["fresh_live_ci_refresh_each_run"] is False
assert r["next_gate"]["required_action"] == "OWNER_REPAIR_AND_REPLAY_TRANSVERSAL_MATRIX"
assert r["next_gate"]["shared_live_ci_binding_requires_separate_authority"] is True
assert all(value is False for value in r["safety"].values())

print("TRANSVERSAL_MATRIX_CLOSURE_RECEIPT_V1_PASS decision=BLOCK coverage=100pct")
