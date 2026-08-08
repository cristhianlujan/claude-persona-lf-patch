#!/usr/bin/env python3
"""Engineering smoke for governed P0 handoff -> Screen Decomposer -> J02 wiring."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

from adapt_p0_to_screen_decomposer import adapt
from validate_p0_j02_handoff import positive_fixture

REPO_ROOT = Path(__file__).resolve().parents[4]
SKILL_SCRIPTS = REPO_ROOT / "skills" / "creating-integral-user-stories" / "scripts"
sys.path.insert(0, str(SKILL_SCRIPTS))
import validate_screen_decomposition as j02  # noqa: E402


def decomposition_from_adapter(worker_input: dict) -> dict:
    unit_code = "FU-LOGIN"
    coverage = []
    for item in worker_input["context_inventory"]:
        coverage.append({"source_item_code": item["code"], "source_type": "CONTEXT", "source_ref": item["source_ref"], "mapping_status": "MAPPED", "mapped_to": [unit_code], "justification": "Mapped from governed P0 context"})
    for item in worker_input["field_inventory"]:
        coverage.append({"source_item_code": item["code"], "source_type": "FIELD", "source_ref": item["source_ref"], "mapping_status": "MAPPED", "mapped_to": [unit_code], "justification": "Mapped from governed P0 field"})
    for item in worker_input["permission_inventory"]:
        coverage.append({"source_item_code": item["permission_code"], "source_type": "PERMISSION", "source_ref": item["source_ref"], "mapping_status": "MAPPED", "mapped_to": [unit_code], "justification": "Mapped from governed auxiliary permission"})
    for index, item in enumerate(worker_input["transition_inventory"]):
        coverage.append({"source_item_code": f"TR-{index + 1}", "source_type": "TRANSITION", "source_ref": item["source_ref"], "mapping_status": "MAPPED", "mapped_to": [unit_code], "justification": "Mapped from governed transition"})
    summary = {"source_items_count": len(coverage), "mapped_count": len(coverage), "justified_count": 0, "unmapped_count": 0, "unjustified_count": 0, "conflicting_count": 0, "duplicate_functional_units_count": 0}
    return {
        "target_screen_code": worker_input["target_screen_code"],
        "screen_decomposition": {
            "screen_code": worker_input["target_screen_code"],
            "module_code": "MOD-AUTH",
            "source_version": worker_input["source_snapshot"]["version"],
            "source_snapshot_sha": worker_input["source_snapshot"]["sha256"],
            "main_responsibility": "Allow a customer to authenticate into the product",
            "context_inventory": worker_input["context_inventory"],
            "field_inventory": worker_input["field_inventory"],
            "permission_inventory": worker_input["permission_inventory"],
            "transition_inventory": worker_input["transition_inventory"],
            "functional_units": [{"functional_unit_code": unit_code, "actor": "Customer", "goal": "Authenticate into the product", "trigger": "Submit login credentials", "observable_output": "Authenticated session or explicit rejection", "resource_ref": "AUTH_SESSION", "risk_level": "HIGH", "decision": "CREATE_STORY", "justification": "Independent observable authentication result", "source_ref": worker_input["p0_provenance"]["evidence_refs"][0], "classification": "CONFIRMED"}],
            "coverage_items": coverage,
            "coverage_summary": summary,
            "pending_decisions": worker_input["pending_decisions"],
        },
    }


def main() -> int:
    handoff = positive_fixture()
    worker_input = adapt(handoff)
    payload = decomposition_from_adapter(worker_input)
    meta = j02.runtime_meta()
    result = j02.build(payload, ["p0-smoke://synthetic-contract-fixture"], 0, "P0_SMOKE_JUDGE", j02.VERSION, meta["semantic_validator_sha256"], j02.REGISTRATION, j02.canonical_sha(payload), None, "smoke_p0_j02")
    stale = copy.deepcopy(handoff); stale["effective_decision"]["is_current"] = False
    stale_blocked = False
    try:
        adapt(stale)
    except ValueError:
        stale_blocked = True
    passed = result["result"] == "PASS_WITH_EVIDENCE" and result["assertions_passed"] == result["assertions_total"] and stale_blocked
    report = {
        "evidence_mode": "SYNTHETIC_CONTRACT_FIXTURE",
        "empirical_visual_quality_claimed": False,
        "adapter_routes_to_j02": worker_input["next_judge"] == "J02_SCREEN_DECOMPOSITION",
        "p0_provenance_preserved": bool(worker_input["p0_provenance"]["handoff_sha256"]),
        "j02_result": result["result"],
        "j02_assertions": f"{result['assertions_passed']}/{result['assertions_total']}",
        "stale_p0_rejected_before_j02": stale_blocked,
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
    }
    print(json.dumps(report, sort_keys=True))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
