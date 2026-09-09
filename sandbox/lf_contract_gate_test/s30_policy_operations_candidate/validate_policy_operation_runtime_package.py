#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import yaml

EXPECTED_OPS = {
    "CREACION_POLITICA_LF": {
        "action_code": "POLICY_CREATE",
        "operation_type": "CREATION_PROTOCOL",
        "requires_existing_target": False,
        "requires_missing_target": True,
        "step_ids": ["preflight", "materialize_candidate", "verify", "close"],
    },
    "ACTUALIZACION_POLITICA_LF": {
        "action_code": "POLICY_UPDATE",
        "operation_type": "UPDATE_PROTOCOL",
        "requires_existing_target": True,
        "requires_missing_target": False,
        "step_ids": ["preflight", "materialize_successor", "verify", "close"],
    },
}
REQUIRED_GUARDS = {
    "ROUTER_BEFORE_WRITE", "EKB_BEFORE_WRITE", "SCHEMA_CONTRACT_BEFORE_WRITE",
    "EXECUTION_BINDING_BEFORE_WRITE", "NO_UNSUPPORTED_POLICY_STATUS",
    "NO_PRIOR_VERSION_OVERWRITE", "NO_PREMATURE_SUPERSESSION",
    "READBACK_BEFORE_CLOSE", "NO_AUTOMATIC_PROMOTION",
    "NO_RUNTIME_OR_PRODUCTION_ENABLE", "NO_CROSS_LANE_BRANCH_BASE",
}


def load(path):
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("PACKAGE_OBJECT_REQUIRED")
    return data


def validate(data):
    errors = []
    if data.get("status") != "CANDIDATO_READ_ONLY": errors.append("STATUS_CEILING_MISMATCH")

    isolation = data.get("isolation") or {}
    if isolation.get("base_branch") != "main": errors.append("ISOLATION_BASE_MUST_BE_MAIN")
    if isolation.get("cross_lane_branch_dependency_allowed") is not False: errors.append("CROSS_LANE_BRANCH_DEPENDENCY_FORBIDDEN")
    non_blocking = set(isolation.get("external_lane_must_not_block") or [])
    for item in {"runtime_package_validation", "rollback_router_canary", "deterministic_regressions"}:
        if item not in non_blocking: errors.append("ISOLATION_NON_BLOCKING_SCOPE_MISSING:" + item)

    shared = data.get("shared") or {}
    if shared.get("asset_type") != "REGLA": errors.append("ASSET_TYPE_MUST_BE_REGLA")
    if shared.get("subtype_prefix") != "POLICY_": errors.append("SUBTYPE_PREFIX_MISMATCH")
    if shared.get("operation_registry_status") != "CANDIDATO_READ_ONLY": errors.append("OP_REGISTRY_STATUS_MISMATCH")
    if shared.get("router_status_for_durable_candidate") != "CANDIDATE_SANDBOX": errors.append("DURABLE_ROUTER_STATUS_MISMATCH")
    if shared.get("router_status_for_rollback_probe") != "ACTIVE": errors.append("ROLLBACK_ROUTER_PROBE_STATUS_MISMATCH")
    for key in ("contract_status", "step_contract_status", "judge_status", "judge_binding_status"):
        if shared.get(key) != "ACTIVE_ENFORCEMENT": errors.append(key.upper() + "_MISMATCH")
    guards = set(shared.get("hard_guards") or [])
    missing = sorted(REQUIRED_GUARDS - guards)
    if missing: errors.append("HARD_GUARDS_MISSING:" + ",".join(missing))

    ops = data.get("operations") or {}
    if set(ops) != set(EXPECTED_OPS): errors.append("OPERATION_SET_MISMATCH")
    for code, spec in EXPECTED_OPS.items():
        op = ops.get(code) or {}
        for key in ("action_code", "operation_type", "requires_existing_target", "requires_missing_target"):
            if op.get(key) != spec[key]: errors.append(f"{code}_{key.upper()}_MISMATCH")
        if op.get("requires_existing_target") and op.get("requires_missing_target"):
            errors.append(f"{code}_CONTRADICTORY_TARGET_FLAGS")
        steps = op.get("steps") or []
        if [s.get("order") for s in steps] != [10,20,30,40]: errors.append(f"{code}_STEP_ORDER_MISMATCH")
        if [s.get("id") for s in steps] != spec["step_ids"]: errors.append(f"{code}_STEP_IDS_MISMATCH")
        for step in steps:
            if not step.get("required_evidence_keys"): errors.append(f"{code}_{step.get('id')}_EVIDENCE_EMPTY")
            if not step.get("blocking_code"): errors.append(f"{code}_{step.get('id')}_BLOCKING_CODE_MISSING")

    judge = data.get("judge_contract") or {}
    if judge.get("result_values") != ["PASS","FAIL","BLOCKED"]: errors.append("JUDGE_RESULT_VALUES_MISMATCH")
    for item in ("all_required_evidence_present","state_ceiling_preserved","independent_readback_passes"):
        if item not in (judge.get("pass_if") or []): errors.append("JUDGE_PASS_RULE_MISSING:" + item)
    for item in ("unsupported_policy_status","prior_version_overwritten","premature_supersession","runtime_or_production_enabled","automatic_promotion_attempted"):
        if item not in (judge.get("fail_if") or []): errors.append("JUDGE_FAIL_RULE_MISSING:" + item)

    canary = data.get("router_canary") or {}
    for name, expected_op in (("create","CREACION_POLITICA_LF"),("update","ACTUALIZACION_POLITICA_LF")):
        c = canary.get(name) or {}
        if c.get("expected_status") != "READY_TO_EXECUTE": errors.append(f"CANARY_{name.upper()}_STATUS_MISMATCH")
        if c.get("expected_operation_code") != expected_op: errors.append(f"CANARY_{name.upper()}_OPERATION_MISMATCH")
        if c.get("asset_type_hint") != "REGLA": errors.append(f"CANARY_{name.upper()}_ASSET_TYPE_MISMATCH")
    natural = canary.get("natural_language_without_action_hint") or {}
    if natural.get("expected_status") != "BLOCKED" or natural.get("expected_blocking_code") != "BLOCK_OPERATION_NOT_REGISTERED":
        errors.append("NATURAL_INFERENCE_BOUNDARY_MISMATCH")
    return errors


def main():
    p = argparse.ArgumentParser(); p.add_argument("package"); p.add_argument("--json", action="store_true"); a=p.parse_args()
    errors = validate(load(a.package))
    result = {"valid": not errors, "blocking_codes": errors}
    print(json.dumps(result, sort_keys=True) if a.json else ("PASS_POLICY_OPERATION_RUNTIME_PACKAGE" if not errors else "FAIL_POLICY_OPERATION_RUNTIME_PACKAGE\n" + "\n".join(errors)))
    raise SystemExit(0 if not errors else 1)

if __name__ == "__main__": main()
