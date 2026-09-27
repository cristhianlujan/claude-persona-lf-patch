#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

CORE = Path(__file__).with_name("contract_reference_integrity_core_v1.py")
spec = importlib.util.spec_from_file_location("contract_reference_integrity_core_v1", CORE)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_CONTRACT_REFERENCE_CORE_LOAD")
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def fixture() -> dict:
    steps = [
        {"step_id": "contract_read", "step_order": 1, "execution_order": 1, "required": True, "active": True},
        {"step_id": "binding_read", "step_order": 2, "execution_order": 2, "required": True, "active": True},
        {"step_id": "report_output", "step_order": 3, "execution_order": 3, "required": False, "active": True},
    ]
    step_contracts = []
    bindings = []
    judges = []
    for index, step in enumerate(steps, start=1):
        step_id = step["step_id"]
        judge = f"MINI_JUDGE_{step_id.upper()}"
        step_contracts.append(
            {
                "step_id": step_id,
                "step_order": index,
                "execution_order": index,
                "contract_code": f"CONTRACT_{step_id.upper()}",
                "resolver_ref": f"public.example_{step_id}",
                "mini_judge_code": judge,
                "next_if_pass": steps[index]["step_id"] if index < len(steps) else None,
                "next_if_blocked": "STOP",
                "status": "ACTIVE_ENFORCEMENT",
            }
        )
        bindings.append(
            {
                "step_id": step_id,
                "step_order": index,
                "judge_code": judge,
                "status": "ACTIVE_ENFORCEMENT",
            }
        )
        judges.append({"judge_code": judge, "status": "ACTIVE_ENFORCEMENT"})
    return {
        "schema_version": core.SCHEMA_VERSION,
        "operation": {
            "operation_code": "GITHUB_CONTRACT_GATE_LF",
            "status": "PRODUCCION_CONTROLADA_READ_ONLY",
            "lifecycle_state_code": "OP_OPERATIONAL",
        },
        "contracts": [
            {
                "contract_code": "CONTRACT-GITHUB-CONTRACT-GATE-LF-READONLY-PROTOCOL-v0.1",
                "contract_path": "supabase://public/lf_operation_contracts/GITHUB_CONTRACT_GATE_LF/readonly_protocol",
                "contract_sha": "c" * 64,
                "status": "ACTIVE_ENFORCEMENT",
            }
        ],
        "steps": steps,
        "step_contracts": step_contracts,
        "judge_bindings": bindings,
        "judges": judges,
        "policies": [
            {
                "policy_code": "POL-LF-OPERATION-LIFECYCLE",
                "policy_role": "GOVERNANCE_LIFECYCLE",
                "required": True,
                "policy_sha": "d" * 64,
            }
        ],
        "operation_revision_sha256": "e" * 64,
    }


def require_block(mutator, expected: str) -> None:
    snap = fixture()
    mutator(snap)
    result = core.evaluate(snap)
    if result["verdict"] != "BLOCK":
        raise AssertionError((expected, result))
    codes = {row["code"] for row in result["failures"]}
    if expected not in codes:
        raise AssertionError((expected, sorted(codes)))


def main() -> int:
    clean = core.evaluate(fixture())
    assert clean["verdict"] == "PASS", clean
    assert clean["counts"]["required_steps"] == 2, clean
    assert clean["formal_reference_scope"]["resolver_ref_semantic_resolution"] is False
    assert len(clean["snapshot_sha256"]) == 64
    checks = 4

    negative_cases = [
        (lambda s: s["contracts"][0].update(contract_sha=""), "FAIL_CONTRACT_SHA_MISSING_OR_INVALID"),
        (lambda s: s["step_contracts"].pop(0), "FAIL_REQUIRED_STEP_CONTRACT_CARDINALITY"),
        (lambda s: s["step_contracts"][0].update(resolver_ref=""), "FAIL_STEP_RESOLVER_REF_MISSING"),
        (lambda s: s["step_contracts"][0].update(next_if_pass="missing"), "FAIL_STEP_TRANSITION_TARGET_MISSING"),
        (lambda s: s["judge_bindings"].pop(0), "FAIL_REQUIRED_STEP_JUDGE_BINDING_CARDINALITY"),
        (lambda s: s["judges"].pop(0), "FAIL_ACTIVE_JUDGE_MISSING"),
        (lambda s: s["judge_bindings"][0].update(judge_code="MINI_JUDGE_OTHER"), "FAIL_ACTIVE_JUDGE_MISSING"),
        (lambda s: s["policies"][0].update(policy_sha=""), "FAIL_REQUIRED_POLICY_UNRESOLVED"),
        (lambda s: s["steps"][1].update(execution_order=1), "FAIL_STEP_EXECUTION_ORDER_DUPLICATE"),
        (lambda s: s["step_contracts"].append({
            "step_id": "ghost", "step_order": 99, "execution_order": 99,
            "contract_code": "CONTRACT_GHOST", "resolver_ref": "GHOST",
            "mini_judge_code": "MINI_JUDGE_GHOST", "status": "ACTIVE_ENFORCEMENT"
        }), "FAIL_ORPHAN_ACTIVE_STEP_CONTRACT"),
        (lambda s: s.update(operation_revision_sha256="not-a-sha"), "FAIL_OPERATION_REVISION_SHA_INVALID"),
    ]
    for mutator, expected in negative_cases:
        require_block(mutator, expected)
        checks += 1

    mismatch = fixture()
    mismatch["judges"].append({"judge_code": "MINI_JUDGE_OTHER", "status": "ACTIVE_ENFORCEMENT"})
    mismatch["judge_bindings"][0]["judge_code"] = "MINI_JUDGE_OTHER"
    result = core.evaluate(mismatch)
    assert "FAIL_STEP_MINI_JUDGE_BINDING_MISMATCH" in {row["code"] for row in result["failures"]}
    checks += 1

    malformed = fixture()
    malformed["schema_version"] = "wrong"
    try:
        core.evaluate(malformed)
    except core.SnapshotError as exc:
        assert str(exc) == "snapshot_schema_version_invalid"
    else:
        raise AssertionError("malformed snapshot unexpectedly accepted")
    checks += 1

    assert checks == 17, checks
    print("PASS_CONTRACT_REFERENCE_INTEGRITY_CORE_V1=17/17")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
