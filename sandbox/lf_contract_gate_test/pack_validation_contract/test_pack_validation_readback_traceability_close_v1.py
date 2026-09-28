#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLOSE = ROOT / "gobernanza/contratos/pack_validation_readback_traceability_close_v1.json"
PLAN = ROOT / "gobernanza/contratos/pack_validation_clean_workflow_v1.json"
DECONTAM = ROOT / "gobernanza/contratos/pack_validation_carrier_decontamination_v1.json"
REBIN = ROOT / "gobernanza/contratos/ci_control_rebind_validate_packs_controls_v1.json"
BOUNDARY = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/validate_clean_boundary_v1.py"
E2E = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/verify_pack_validation_e2e_v1.py"


def run_test(path: Path, marker: str) -> None:
    completed = subprocess.run([sys.executable, str(path)], cwd=ROOT, text=True, capture_output=True, check=False)
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert marker in completed.stdout, completed.stdout


def main() -> None:
    close = json.loads(CLOSE.read_text(encoding="utf-8"))
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    decontam = json.loads(DECONTAM.read_text(encoding="utf-8"))
    rebind = json.loads(REBIN.read_text(encoding="utf-8"))
    assert close["owner"] == plan["owner"] == decontam["owner"] == rebind["owner"] == "PACK_VALIDATION"
    assert close["active_candidate_model"]["shape"] == "CONSOLIDATED_ON_CURRENT_MAIN"
    assert close["active_candidate_model"]["old_stacked_sha_topology_required"] is False
    assert close["active_candidate_model"]["historical_evidence_preserved"] is True
    assert close["local_progress_percent"] == 100
    assert close["external_prerequisites_count_toward_pack_validation_progress"] is False
    assert plan["operational_plan"]["local_progress_percent"] == 100
    assert plan["scope_invariants"]["foreign_owner_work_forbidden"] is True
    assert decontam["boundary_invariants"]["merge_authorized"] is False
    assert close["local_closure_invariants"]["merge_authorized"] is False
    assert close["local_closure_invariants"]["deployment_authorized"] is False
    assert close["local_closure_invariants"]["production_authorized"] is False
    run_test(BOUNDARY, "PACK_VALIDATION_CLEAN_BOUNDARY=PASS")
    run_test(E2E, "PACK_VALIDATION_VERIFY_E2E_FLOW=PASS")
    print("PACK_VALIDATION_READBACK_TRACEABILITY_CLOSE=PASS")


if __name__ == "__main__":
    main()
