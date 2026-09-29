#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

CORE = Path(__file__).with_name("operation_definition_integrity_core_v1.py")
spec = importlib.util.spec_from_file_location("operation_definition_integrity_core_v1", CORE)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_OPERATION_DEFINITION_INTEGRITY_CORE_LOAD")
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def fixture() -> dict:
    # Live-shaped regression: operation steps may legitimately expose
    # execution_order=NULL while step contracts retain executable ordering.
    steps = [
        {"step_id": "contract_read", "step_order": 1, "execution_order": None, "required": True, "active": True},
        {"step_id": "binding_read", "step_order": 2, "execution_order": None, "required": True, "active": True},
        {"step_id": "report_output", "step_order": 3, "execution_order": None, "required": False, "active": True},
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
    assert clean["definition_scope"]["resolver_ref_semantic_resolution"] is False
    assert clean["definition_scope"]["currentness_validation"] is False
    assert len(clean["snapshot_sha256"]) == 64
    # Explicitly pin the live-shaped condition that invalidated the previous candidate.
    assert all(step["execution_order"] is None for step in fixture()["steps"])
    checks = 6

    negative_cases = [
        (lambda s: s["contracts"][0].update(contract_sha=""), "FAIL_CONTRACT_SHA_MISSING_OR_INVALID"),
        (lambda s: s["contracts"][0].update(contract_path=""), "FAIL_CONTRACT_PATH_MISSING"),
        (lambda s: s["steps"].append(copy.deepcopy(s["steps"][0])), "FAIL_ACTIVE_STEP_DUPLICATE"),
        (lambda s: s["step_contracts"].pop(0), "FAIL_REQUIRED_STEP_CONTRACT_CARDINALITY"),
        (lambda s: s["step_contracts"][0].update(step_order=99), "FAIL_STEP_CONTRACT_ORDER_MISMATCH"),
        (lambda s: s["step_contracts"][0].update(resolver_ref=""), "FAIL_STEP_RESOLVER_REF_MISSING"),
        (lambda s: s["step_contracts"][0].update(mini_judge_code=""), "FAIL_STEP_MINI_JUDGE_CODE_MISSING"),
        (lambda s: s["step_contracts"][0].update(next_if_pass="missing"), "FAIL_STEP_TRANSITION_TARGET_MISSING"),
        (lambda s: s["step_contracts"][0].update(next_if_pass="contract_read"), "FAIL_STEP_TRANSITION_SELF_LOOP"),
        (lambda s: s["judge_bindings"].pop(0), "FAIL_REQUIRED_STEP_JUDGE_BINDING_CARDINALITY"),
        (lambda s: s["judges"].pop(0), "FAIL_ACTIVE_JUDGE_MISSING"),
        (lambda s: s["judge_bindings"][0].update(step_order=99), "FAIL_JUDGE_BINDING_ORDER_MISMATCH"),
        (lambda s: s["policies"][0].update(policy_sha=""), "FAIL_REQUIRED_POLICY_UNRESOLVED"),
        (lambda s: s["step_contracts"].append({
            "step_id": "ghost", "step_order": 99, "execution_order": 99,
            "contract_code": "CONTRACT_GHOST", "resolver_ref": "GHOST",
            "mini_judge_code": "MINI_JUDGE_GHOST", "status": "ACTIVE_ENFORCEMENT"
        }), "FAIL_ORPHAN_ACTIVE_STEP_CONTRACT"),
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

    assert checks == 22, checks
    print("PASS_OPERATION_DEFINITION_INTEGRITY_CORE_V1=22/22")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
