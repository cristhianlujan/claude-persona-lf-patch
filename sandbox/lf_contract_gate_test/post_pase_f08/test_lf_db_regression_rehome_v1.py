#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "LF_DB_REGRESSION_legacy_carrier_rehome_v1.json"
REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
PASE = ROOT / ".github/workflows/pase.yml"
LEGACY_WORKFLOW = ROOT / ".github/workflows/lf-db-regression.yml"
REVERSIBLE_PROVIDER = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/reversible_candidate_verification_v1.py"
REVERSIBLE_README = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/README.md"

EXPECTED = {
    "DB_CANDIDATE_APPLY_ROLLBACK",
    "POLICY_RESOLVER_REGRESSION",
    "V7_RUNTIME_REGRESSION",
}


def main() -> None:
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    r = json.loads(REGISTRY.read_text(encoding="utf-8"))

    assert m["schema_version"] == "PASE_F08_P04_LF_DB_REGRESSION_REHOME_V1"
    assert m["work_code"] == "PASE-ATOM-F08-P04"
    assert m["safety"]["pase_activated"] is False
    assert m["safety"]["new_binding_created"] is False
    assert m["safety"]["production_touched"] is False
    assert m["source_cleanup_boundary"]["current_router_carrier_references_remain_until"] == "PASE-ATOM-F08-R04"

    rows = [x for x in r["controls"] if x.get("carrier") == "LF_DB_REGRESSION"]
    observed = {x["control_id"] for x in rows}
    assert observed == EXPECTED, (observed, EXPECTED)
    assert set(m["legacy_control_references"]) == EXPECTED
    assert set(m["replacement_map"]) == EXPECTED

    assert not LEGACY_WORKFLOW.exists(), "legacy DB workflow must remain absent"
    pase = PASE.read_text(encoding="utf-8")
    assert "if: ${{ false }}" in pase, "PASE must remain disabled during P04 proof"

    provider = REVERSIBLE_PROVIDER.read_text(encoding="utf-8")
    readme = REVERSIBLE_README.read_text(encoding="utf-8")
    assert 'CAPABILITY_CODE = "REVERSIBLE_CANDIDATE_VERIFICATION"' in provider
    assert "ROLLBACK_ONLY" in provider
    assert "INDEPENDENT_ASSURANCE" in provider
    assert "REVERSIBLE_CANDIDATE_VERIFICATION v1.0.1" in readme

    for control_id, mapping in m["replacement_map"].items():
        assert mapping["parent_capability"] == "REVERSIBLE_CANDIDATE_VERIFICATION", control_id
        for key in ("flow_runner", "probe", "baseline", "apply_readback", "rollback_readback", "migration_set"):
            ref = mapping.get(key)
            if ref:
                assert (ROOT / ref).is_file(), (control_id, key, ref)

    print(
        "PASS_PASE_F08_P04_LF_DB_REGRESSION_REHOME_V1 "
        f"legacy_controls={len(observed)} replacements={len(m['replacement_map'])} "
        "legacy_workflow_present=0 active_execution_authority=0"
    )


if __name__ == "__main__":
    main()
