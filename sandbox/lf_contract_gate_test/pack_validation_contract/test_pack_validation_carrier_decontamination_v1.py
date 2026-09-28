#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/validate-lf-packs.yml"
CORE = ROOT / ".github/workflows/lf-pack-validation-core.yml"
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_carrier_decontamination_v1.json"

FORBIDDEN_WORKFLOW_TOKENS = (
    "workflow_dispatch:",
    "emit_ci_execution_plan_v2.py",
    "authority_current",
    "CI_AUTHORITY_CURRENTNESS",
    "S30_",
    "s30-",
    "PROFILE_RUNTIME",
    "profile_runtime_api",
    "GATE_CHECK_OBSERVABILITY",
    "work_protocol",
    "SUPABASE",
    "PGPASSWORD",
    "psql ",
    "persist_gate_failures_to_ekb",
    "lf-db-regression",
    "assurance",
    "deploy",
    "production",
)

DIRECT_PACK_CALLS = (
    "profiles/_template/validators/validate_pack.py",
    "skills/_template/validators/validate_pack.py",
    "skills/skill_creator/validators/validate_pack.py",
    "skills/profile_creator/validators/validate_pack.py",
    "skills/learning_engine/validators/validate_pack.py",
)


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    core = CORE.read_text(encoding="utf-8")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    assert contract["durable_name"] == "PACK_VALIDATION_CARRIER_DECONTAMINATION_V1"
    assert contract["owner"] == "PACK_VALIDATION"
    assert contract["canonical_core"] == ".github/workflows/lf-pack-validation-core.yml"
    assert contract["boundary_invariants"]["single_pack_validation_engine"] is True
    assert contract["boundary_invariants"]["carrier_calls_reusable_core_once"] is True
    assert contract["boundary_invariants"]["carrier_does_not_resolve_run_skip_applicability"] is True
    assert contract["boundary_invariants"]["carrier_does_not_compare_candidate_to_current_main"] is True
    assert contract["boundary_invariants"]["merge_authorized"] is False
    assert contract["boundary_invariants"]["deployment_authorized"] is False
    assert contract["boundary_invariants"]["production_authorized"] is False
    assert contract["next_handoff"] == "STEP_10_UPSTREAM_ORCHESTRATOR_AND_FOREIGN_COVERAGE_PROOF"

    assert "pull_request:" in workflow
    assert "push:" in workflow
    assert "workflow_call:" in workflow
    assert workflow.count("uses: ./.github/workflows/lf-pack-validation-core.yml") == 1
    assert "Resolve exact Pack Validation context" in workflow
    assert 'git diff --name-only "$base" "$head" --' in workflow
    assert "INPUT_CHANGED_PATHS_JSON" in workflow
    assert "base_sha: ${{ needs.pack-context.outputs.base_sha }}" in workflow
    assert "head_sha: ${{ needs.pack-context.outputs.head_sha }}" in workflow
    assert "changed_paths_json: ${{ needs.pack-context.outputs.changed_paths_json }}" in workflow

    for token in FORBIDDEN_WORKFLOW_TOKENS:
        assert token.lower() not in workflow.lower(), f"FAIL_FOREIGN_CARRIER_TOKEN:{token}"
    for token in DIRECT_PACK_CALLS:
        assert token not in workflow, f"FAIL_DIRECT_PACK_EXECUTION:{token}"

    assert "workflow_call:" in core
    assert "run_pack_validation_flow_v1.py" in core
    assert "Persist bounded Pack Validation evidence" in core
    assert "CHANGED_PATHS" not in workflow or "changed_paths" in workflow.lower()

    plan = contract["corrected_operational_plan"]
    assert plan["steps_total"] == 11
    assert plan["steps_closed_after_this_candidate"] == 9
    assert plan["steps"][1]["id"] == "STEP_09_CARRIER_DECONTAMINATION"
    assert plan["steps"][2]["status"] == "PENDING"
    assert plan["steps"][3]["status"] == "PENDING"

    print("PACK_VALIDATION_CARRIER_DECONTAMINATION_V1=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
