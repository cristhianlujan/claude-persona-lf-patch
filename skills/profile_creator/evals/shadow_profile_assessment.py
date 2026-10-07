#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSESS_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
VALIDATORS_DIR = ROOT / "skills/profile_creator/validators"
sys.path.insert(0, str(ASSESS_DIR))
sys.path.insert(0, str(VALIDATORS_DIR))

from profile_assessment_v1 import assess_profile
from evaluate_s26_profile_baseline import evaluate as evaluate_s26

TARGETS = Path(__file__).with_name("profile_evolution_shadow_targets_v1.json")


def unknown():
    return {"status": "UNKNOWN", "refs": []}


def run() -> dict:
    cfg = json.loads(TARGETS.read_text(encoding="utf-8"))
    rows = []
    for target in cfg["targets"]:
        slug = target["profile_slug"]
        baseline = evaluate_s26(ROOT, slug)
        structural = {
            "status": "PASS" if baseline["decision"] == "NO_UPDATE_REQUIRED" else
                      "FAIL" if baseline["decision"] == "UPDATE_REQUIRED" else "UNKNOWN",
            "refs": ["s26://13-of-13"] if baseline["decision"] == "NO_UPDATE_REQUIRED" else baseline.get("repair_actions", []) or baseline.get("blocking_codes", []),
        }
        payload = {
            "evidence": {
                "structural_compatibility": structural,
                "domain_task_uplift": unknown(),
                "strategy_routing": unknown(),
                "expert_holdout": unknown(),
                "repeated_optimization": unknown(),
                "architecture_fit": unknown(),
                "optimization_opportunity": unknown(),
            },
            "signals": {
                "task_family": "PROFILE_EVOLUTION_SHADOW",
                "complexity": "UNKNOWN",
                "novelty": "UNKNOWN",
                "uncertainty": "HIGH",
                "risk": "UNKNOWN",
                "evidence_sufficiency": "INSUFFICIENT",
            },
        }
        assessment = assess_profile(payload)
        rows.append({
            "profile_code": target["profile_code"],
            "profile_slug": slug,
            "s26_decision": baseline["decision"],
            "maturity": assessment["maturity"],
            "evolution_mode": assessment["evolution_mode"],
            "gap_count": len(assessment["profile_gaps"]),
            "capability_evidence_state": "UNPROVEN_UNTIL_DOMAIN_TASK_BENCHMARK",
        })
    return {
        "schema": "PROFILE_EVOLUTION_SHADOW_RESULT_V1",
        "mode": cfg["mode"],
        "target_count": len(rows),
        "rows": rows,
        "writes": 0,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2, sort_keys=True))
