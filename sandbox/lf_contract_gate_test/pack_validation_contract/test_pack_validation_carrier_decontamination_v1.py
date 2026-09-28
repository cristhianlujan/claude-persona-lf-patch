#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/validate-lf-packs.yml"
CORE = ROOT / ".github/workflows/lf-pack-validation-core.yml"
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_carrier_decontamination_v1.json"

FORBIDDEN = (
    "workflow_dispatch:", "emit_ci_execution_plan_v2.py", "authority_current",
    "CI_AUTHORITY_CURRENTNESS", "S30_", "s30-", "PROFILE_RUNTIME",
    "profile_runtime_api", "GATE_CHECK_OBSERVABILITY", "TRANSVERSAL_README",
    "work_protocol", "SUPABASE", "PGPASSWORD", "psql ",
    "persist_gate_failures_to_ekb", "lf-db-regression", "assurance"
)


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    core = CORE.read_text(encoding="utf-8")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["owner"] == "PACK_VALIDATION"
    assert contract["boundary_invariants"]["carrier_calls_reusable_core_once"] is True
    assert contract["boundary_invariants"]["merge_authorized"] is False
    assert contract["external_prerequisite"] == "STEP_10_UPSTREAM_ORCHESTRATOR_AND_FOREIGN_COVERAGE_PROOF"
    assert workflow.count("uses: ./.github/workflows/lf-pack-validation-core.yml") == 1
    assert "workflow_call:" in workflow and "pull_request:" in workflow and "push:" in workflow
    assert "Resolve exact Pack Validation context" in workflow
    assert "workflow_call:" in core
    assert "run_pack_validation_flow_v1.py" in core
    for token in FORBIDDEN:
        assert token.lower() not in workflow.lower(), f"FAIL_FOREIGN_CARRIER_TOKEN:{token}"
        assert token.lower() not in core.lower(), f"FAIL_FOREIGN_CORE_TOKEN:{token}"
    print("PACK_VALIDATION_CARRIER_DECONTAMINATION_V1=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
