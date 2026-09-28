#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "gobernanza/contratos/ci_control_rebind_validate_packs_controls_v1.json"
SOURCE = ROOT / ".github/workflows/validate-lf-packs.yml"
CORE = ROOT / ".github/workflows/lf-pack-validation-core.yml"
STAGED = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/lf-pack-validation-core.staged.yml"
RUNNER = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/run_pack_validation_flow_v1.py"
E2E = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/verify_pack_validation_e2e_v1.py"
CLOSE_TEST = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/test_pack_validation_readback_traceability_close_v1.py"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    source = SOURCE.read_text(encoding="utf-8")
    core = CORE.read_text(encoding="utf-8")
    staged = STAGED.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")

    assert contract["durable_name"] == "CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS"
    assert contract["owner"] == "PACK_VALIDATION"
    assert contract["source_carrier"] == "VALIDATE_LF_PACKS"
    assert contract["next_handoff"] == "PACK_VALIDATION_VERIFY_E2E_FLOW"
    assert '"next_handoff": "PACK_VALIDATION_VERIFY_E2E_FLOW"' in runner
    assert '"next_handoff": "CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS"' not in runner

    existing = contract["preexisting_asset_boundaries"]
    assert existing["PACK_VALIDATION_HARNESS"]["invoked_by_this_cutover"] is False
    assert existing["PACK_VALIDATION_HARNESS"]["activation_or_promotion_by_this_cutover"] is False
    assert existing["POL-PACK-VALIDATION-FLOOR"]["consumed_by_clean_pack_validation_flow"] is False

    assert core == staged, "FAIL_PACK_CORE_DIFFERS_FROM_QUALIFIED_STAGED_DEFINITION"
    assert "workflow_call:" in core
    for forbidden_trigger in ("pull_request:", "push:", "workflow_dispatch:", "schedule:"):
        assert forbidden_trigger not in core, f"FAIL_PACK_CORE_AUTONOMOUS_TRIGGER:{forbidden_trigger}"
    for foreign in (
        "PROFILE_RUNTIME_V3",
        "S30_BOUNDED_REGRESSION",
        "S30_BROKER",
        "GATE_CHECK_OBSERVABILITY",
        "SUPABASE",
        "PGPASSWORD",
        "psql ",
        "persist_gate_failures_to_ekb",
    ):
        assert foreign.lower() not in core.lower(), f"FAIL_PACK_CORE_FOREIGN_RESPONSIBILITY:{foreign}"

    assert source.count("run_pack_validation_flow_v1.py") == 1
    assert "LF_CHANGED_PATHS_JSON: ${{ steps.ci_plan.outputs.changed_paths_json }}" in source
    assert "git worktree add --detach \"$worktree\" \"$head\"" in source
    assert "--repo-root \"$worktree\"" in source
    assert "Persist bounded Pack Validation evidence" in source
    assert 'git rev-parse --is-shallow-repository' in source
    assert 'git fetch --no-tags --unshallow origin "$head"' in source
    assert "include-hidden-files: true" in source
    assert "include-hidden-files: true" in core

    for old_call in (
        "python profiles/_template/validators/validate_pack.py profiles/_template",
        "python skills/_template/validators/validate_pack.py skills/_template",
        "python skills/skill_creator/validators/validate_pack.py skills/skill_creator",
        "python skills/profile_creator/validators/validate_pack.py skills/profile_creator",
        "python skills/learning_engine/validators/validate_pack.py skills/learning_engine",
    ):
        assert old_call not in source, f"FAIL_DIRECT_PACK_EXECUTION_REMAINS:{old_call}"

    assert "Validate Pack Validation harness v1 regressions" in source
    assert "test_pack_validation_harness_v1.py" in source

    for control in (
        "PROFILE_RUNTIME_V3",
        "GATE_CHECK_OBSERVABILITY",
        "S30_BOUNDED_REGRESSION",
        "TRANSVERSAL_README",
    ):
        assert control in source, f"FAIL_FOREIGN_CONTROL_REMOVED_EARLY:{control}"
        row = contract["foreign_controls_retained"][control]
        assert row["destination_wiring"] == "NOT_PROVEN_IN_THIS_CHANGE"
        assert row["remove_from_source_carrier"] is False

    assert "Validate Work Protocol V1 deprecation tombstone" in source
    assert "s30-governed-write-broker:" in source
    assert "S30_BROKER_DEPLOY_KEY" in source
    assert "git push s30-broker" in source

    for control in ("PROFILE_PACK", "SKILL_PACK", "LEARNING_ENGINE_PACK"):
        row = contract["pack_owned_controls"][control]
        assert row["target_owner"] == "PACK_VALIDATION"
        assert row["target_execution"] == "PACK_VALIDATION_CLEAN_WORKFLOW"
        assert row["rebind_allowed"] is True
        assert control in source

    completed = subprocess.run(
        [sys.executable, str(E2E)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "PACK_VALIDATION_VERIFY_E2E_FLOW=PASS" in completed.stdout, completed.stdout

    closed = subprocess.run(
        [sys.executable, str(CLOSE_TEST)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert closed.returncode == 0, closed.stdout + closed.stderr
    assert "PACK_VALIDATION_READBACK_TRACEABILITY_CLOSE=PASS" in closed.stdout, closed.stdout

    print("CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS=PASS")


if __name__ == "__main__":
    main()
