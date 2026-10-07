#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
ASSESS_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
SELECT_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
for p in (ASSESS_DIR, SELECT_DIR):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

from evaluate_s26_learning_preflight import evaluate_learning_preflight
from evaluate_s26_profile_baseline import evaluate as evaluate_s26
from profile_assessment_v1 import assess_profile
from capability_selector_v2 import compose_capabilities


def build_evolution_plan(
    repo: Path,
    slug: str,
    preflight_payload: object,
    assessment_payload: dict[str, Any],
    capability_catalog: list[dict[str, Any]],
    capability_policy: dict[str, Any],
    method_registry: dict[str, Any],
    *,
    current_revision: str | None = None,
) -> dict[str, Any]:
    structural = evaluate_s26(repo, slug)
    learning = evaluate_learning_preflight(
        preflight_payload, slug, repo_root=repo, current_revision=current_revision
    )
    preflight_pass = learning["status"] == "PASS"

    normalized = copy.deepcopy(assessment_payload)
    normalized.setdefault("evidence", {})
    if structural["decision"] == "NO_UPDATE_REQUIRED":
        normalized["evidence"]["structural_compatibility"] = {
            "status": "PASS",
            "refs": ["s26://13-of-13"],
        }
    elif structural["decision"] == "UPDATE_REQUIRED":
        normalized["evidence"]["structural_compatibility"] = {
            "status": "FAIL",
            "refs": structural.get("repair_actions", []),
        }
    else:
        normalized["evidence"]["structural_compatibility"] = {
            "status": "UNKNOWN",
            "refs": structural.get("blocking_codes", []),
        }

    assessment = assess_profile(normalized)
    composition = compose_capabilities(
        {
            **normalized.get("signals", {}),
            "profile_gaps": assessment["profile_gaps"],
            "budget": normalized.get("budget", {}),
        },
        capability_catalog,
        capability_policy,
        method_registry,
    )

    blockers: list[str] = []
    if not preflight_pass:
        blockers.append("BLOCKED_LEARNING_PREFLIGHT")
    if structural["decision"] == "BLOCKED_AUTHORITY_REQUIRED":
        blockers.append("BLOCKED_AUTHORITY_REQUIRED")
    if composition["fallback_state"] in {"CONTRADICTORY", "CAPABILITY_FAILURE"}:
        blockers.append("BLOCKED_SELECTOR_UNRESOLVED")

    mode = assessment["evolution_mode"]
    change_needed = mode != "NO_CHANGE"
    candidate_allowed = change_needed and not blockers
    patch_minimality_required = mode == "PATCH"

    return {
        "schema": "PROFILE_EVOLUTION_PLAN_V1",
        "operation_code": "ACTUALIZACION_PERFIL_LF",
        "conceptual_responsibility": "PROFILE_EVOLUTION_ORCHESTRATOR",
        "profile_slug": slug,
        "structural_baseline": structural,
        "structural_status": (
            "STRUCTURALLY_COMPATIBLE"
            if structural["decision"] == "NO_UPDATE_REQUIRED"
            else structural["decision"]
        ),
        "learning_preflight": learning,
        "profile_assessment": assessment,
        "evolution_mode": mode,
        "selection": composition,
        "candidate_materialization_allowed": candidate_allowed,
        "candidate_boundary": "REVERSIBLE_NON_AUTHORITY",
        "profile_source_write_allowed": False,
        "write_requires_admission": True,
        "patch_minimality_required": patch_minimality_required,
        "bounded_delta_required": change_needed,
        "blocking_codes": blockers,
        "next_gate": (
            "CANDIDATE_MATERIALIZATION"
            if candidate_allowed
            else "NO_CHANGE"
            if mode == "NO_CHANGE" and not blockers
            else "RETURN_TO_EVIDENCE_OR_AUTHORITY"
        ),
        "automatic_runtime_activation": False,
        "automatic_production_activation": False,
    }


def main() -> int:
    if len(sys.argv) != 7:
        print(
            "usage: plan_profile_evolution.py <slug> <preflight.json> <assessment.json> "
            "<capability_catalog.json> <capability_policy.json> <method_registry.json>",
            file=sys.stderr,
        )
        return 2
    slug = sys.argv[1]
    payloads = [json.loads(Path(p).read_text(encoding="utf-8")) for p in sys.argv[2:]]
    result = build_evolution_plan(ROOT, slug, *payloads)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not result["blocking_codes"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
