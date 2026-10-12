#!/usr/bin/env python3
import json
from pathlib import Path

from lf_changeset_governance import evaluate_pr_integrity
from lf_ci_lane_router import classify

HERE = Path(__file__).resolve().parent
REGISTRY = HERE / "lf_product_lane_ownership_registry_v1.json"
PR1019_PATHS = [
    "gobernanza/contratos/pilot_srcr_unified_execution_task_contract_v1.json",
    "gobernanza/procedimientos/pilot_srcr_unified_execution_v1.md",
    "sandbox/lf_contract_gate_test/receipts/pilot-srcr-unified-execution-v1-g01-pr1019-candidate-20260922-001.json",
]
SOLUTION_REF = "PILOT-SRCR-UNIFIED-EXECUTION-V1"
MANIFEST_PATH = f"changesets/{SOLUTION_REF}.json"
MANIFEST = {"solution_ref": SOLUTION_REF, "paths": {path: "PILOT_GOVERNANCE" for path in PR1019_PATHS}}


def main():
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    assert all(row.get("namespace") != "PILOT-SRCR-UNIFIED" for row in registry["namespaces"])
    assert all(row.get("lane_id") != "PILOT-SRCR-UNIFIED-TRANSIENT" for row in registry["lanes"])

    changed = [MANIFEST_PATH, *PR1019_PATHS]
    integrity = evaluate_pr_integrity(changed, manifest_data=MANIFEST)
    assert integrity["solution_ref"] == SOLUTION_REF
    assert integrity["classification_required"] is False, integrity
    assert integrity["violations"] == [], integrity
    assert all(integrity["families"][path] == "PILOT_GOVERNANCE" for path in PR1019_PATHS)

    routed = classify(changed, manifest_data=MANIFEST)
    assert routed.mode != "CLASSIFICATION_REQUIRED", routed
    assert routed.migration_parity_required is False, routed
    assert not any("PILOT-SRCR-UNIFIED-TRANSIENT" in reason for reason in routed.reasons), routed
    print("PASS_PR7_TRANSIENT_LANE_RETIRED=1/1")
    print("PASS_PR7_PR1019_MANIFEST_CLASSIFICATION=1/1")


if __name__ == "__main__":
    main()
