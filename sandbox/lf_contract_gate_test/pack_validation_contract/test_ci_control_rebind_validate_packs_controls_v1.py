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
E2E = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/verify_pack_validation_e2e_v1.py"
BOUNDARY = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/validate_clean_boundary_v1.py"


def run_test(path: Path, marker: str) -> None:
    completed = subprocess.run([sys.executable, str(path)], cwd=ROOT, text=True, capture_output=True, check=False)
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert marker in completed.stdout, completed.stdout


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    source = SOURCE.read_text(encoding="utf-8")
    core = CORE.read_text(encoding="utf-8")
    staged = STAGED.read_text(encoding="utf-8")
    assert contract["owner"] == "PACK_VALIDATION"
    assert contract["source_carrier"] == "VALIDATE_LF_PACKS"
    assert contract["carrier_contract"]["core_call_count"] == 1
    assert contract["carrier_contract"]["applicability_redecision_forbidden"] is True
    assert core == staged
    assert source.count("uses: ./.github/workflows/lf-pack-validation-core.yml") == 1
    assert "base_sha: ${{ needs.pack-context.outputs.base_sha }}" in source
    assert "head_sha: ${{ needs.pack-context.outputs.head_sha }}" in source
    assert "changed_paths_json: ${{ needs.pack-context.outputs.changed_paths_json }}" in source
    for control in ("PROFILE_RUNTIME_V3", "GATE_CHECK_OBSERVABILITY", "S30_BOUNDED_REGRESSION", "TRANSVERSAL_README"):
        assert contract["foreign_controls"][control] == "EXTERNAL_PENDING_ORCHESTRATOR_BINDING"
        assert control not in source
        assert control not in core
    run_test(BOUNDARY, "PACK_VALIDATION_CLEAN_BOUNDARY=PASS")
    run_test(E2E, "PACK_VALIDATION_VERIFY_E2E_FLOW=PASS")
    print("CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS=PASS")


if __name__ == "__main__":
    main()
