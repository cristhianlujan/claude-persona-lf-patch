#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import yaml

ALLOWED_POLICY_STATUSES = {"CANDIDATE", "ACTIVE", "SUPERSEDED", "RETIRED"}
EXPECTED_PHASE_MAP = {
    "DRAFT": "CANDIDATE",
    "REVIEWED": "CANDIDATE",
    "SANDBOX": "CANDIDATE",
    "CANARY": "CANDIDATE",
    "VERIFIED": "CANDIDATE",
    "ACTIVE": "ACTIVE",
    "SUPERSEDED": "SUPERSEDED",
    "RETIRED": "RETIRED",
}
REQUIRED_GUARDS = {
    "NO_DIRECT_POLICY_WRITE_WITHOUT_ROUTER_OPERATION",
    "NO_POLICY_ASSET_TYPE_INVENTION",
    "NO_UNSUPPORTED_POLICY_VERSION_STATUS",
    "NO_DRAFT_TO_ACTIVE_SHORTCUT",
    "NO_PRIOR_VERSION_OVERWRITE",
    "NO_ACTIVE_VERSION_SUPERSEDE_BEFORE_VERIFIED_PROMOTION",
    "NO_SELF_PROMOTION_FROM_LEARNING",
    "NO_AUTOMATIC_RUNTIME_ENABLE",
    "NO_AUTOMATIC_PRODUCTION_PROMOTION",
    "NO_SAME_STATEMENT_READBACK_AS_CLOSURE_EVIDENCE",
    "FAIL_CLOSED_ON_UNKNOWN_OR_AMBIGUOUS_TARGET",
    "NO_CROSS_LANE_BRANCH_BASE",
    "NO_CROSS_LANE_BLOCK_FOR_INDEPENDENT_CANARY",
}
REQUIRED_TOP = {
    "version", "status", "source_strategy", "source_model", "purpose", "authority",
    "cross_lane_dependency_policy", "asset_contract", "operations", "state_ceiling",
    "lifecycle_model", "create_contract", "update_contract", "hard_guards",
    "required_after_candidate_materialization", "promotion_rule",
}


def load_yaml(path):
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("CONTRACT_OBJECT_REQUIRED")
    return data


def validate(data):
    errors = []
    missing = sorted(REQUIRED_TOP - set(data))
    if missing:
        return ["TOP_KEYS_MISSING:" + ",".join(missing)]

    if data.get("status") != "CANDIDATO_READ_ONLY": errors.append("CONTRACT_STATUS_CEILING_MISMATCH")
    if data.get("source_model") != "GIT_FIRST_YAML": errors.append("SOURCE_MODEL_MISMATCH")

    dep = data.get("cross_lane_dependency_policy") or {}
    if dep.get("dependency_mode") != "OPTIONAL_REUSE_NOT_BRANCH_BASE": errors.append("CROSS_LANE_DEPENDENCY_MODE_MISMATCH")
    if dep.get("blocking_scope") != "DURABLE_MATERIALIZATION_ONLY_IF_SELECTED": errors.append("CROSS_LANE_BLOCKING_SCOPE_MISMATCH")
    non_blocking = set(dep.get("non_blocking_scope") or [])
    for required in {"contract_design", "deterministic_validation", "rollback_canary", "router_resolution_canary", "inference_canary"}:
        if required not in non_blocking: errors.append("CROSS_LANE_NON_BLOCKING_SCOPE_MISSING:" + required)

    asset = data.get("asset_contract") or {}
    if asset.get("asset_type") != "REGLA": errors.append("ASSET_TYPE_MUST_BE_REGLA")
    if asset.get("required_subtype_prefix") != "POLICY_": errors.append("POLICY_SUBTYPE_PREFIX_MISMATCH")
    if asset.get("create_action_code") != "POLICY_CREATE": errors.append("CREATE_ACTION_CODE_MISMATCH")
    if asset.get("update_action_code") != "POLICY_UPDATE": errors.append("UPDATE_ACTION_CODE_MISMATCH")
    if asset.get("action_decision_status") != "CANDIDATE_DERIVED_FROM_ROUTER_CONVENTION": errors.append("ACTION_DECISION_MUST_REMAIN_CANDIDATE")

    expected_ops = {
        "create": ("CREACION_POLITICA_LF", "CREATION_PROTOCOL", False, True),
        "update": ("ACTUALIZACION_POLITICA_LF", "UPDATE_PROTOCOL", True, False),
    }
    for name, (code, op_type, existing, missing_target) in expected_ops.items():
        op = (data.get("operations") or {}).get(name) or {}
        checks = {
            "operation_code": code,
            "operation_type": op_type,
            "requires_existing_target": existing,
            "requires_missing_target": missing_target,
            "applies_to_asset_type": "REGLA",
            "write_allowed": True,
        }
        for key, expected in checks.items():
            if op.get(key) != expected: errors.append(f"{name.upper()}_{key.upper()}_MISMATCH")
        if op.get("requires_existing_target") and op.get("requires_missing_target"):
            errors.append(f"{name.upper()}_CONTRADICTORY_TARGET_FLAGS")

    ceiling = data.get("state_ceiling") or {}
    expected_ceiling = {
        "operation_registry_status": "CANDIDATO_READ_ONLY",
        "router_status": "CANDIDATE_SANDBOX",
        "policy_version_status": "CANDIDATE",
        "runtime_state": "NO_HABILITADO",
        "automatic_impact": "BLOQUEADO",
        "production_allowed": False,
        "runtime_allowed": False,
        "main_merge_allowed": False,
        "automatic_promotion_allowed": False,
    }
    for key, expected in expected_ceiling.items():
        if ceiling.get(key) != expected: errors.append("STATE_CEILING_MISMATCH:" + key)

    mapping = ((data.get("lifecycle_model") or {}).get("persisted_status_mapping") or {})
    if mapping != EXPECTED_PHASE_MAP: errors.append("LIFECYCLE_PERSISTENCE_MAPPING_MISMATCH")
    invalid = sorted(set(mapping.values()) - ALLOWED_POLICY_STATUSES)
    if invalid: errors.append("UNSUPPORTED_POLICY_STATUSES:" + ",".join(invalid))
    if (data.get("lifecycle_model") or {}).get("phases") != list(EXPECTED_PHASE_MAP): errors.append("LIFECYCLE_PHASE_ORDER_MISMATCH")

    first = ((data.get("create_contract") or {}).get("first_version_rules") or {})
    if first.get("status") != "CANDIDATE": errors.append("FIRST_VERSION_MUST_BE_CANDIDATE")
    if first.get("sha256_required") is not True: errors.append("POLICY_SHA_REQUIRED")

    successor = ((data.get("update_contract") or {}).get("successor_rules") or {})
    expected_successor = {
        "create_new_row_only": True,
        "candidate_status_on_creation": "CANDIDATE",
        "overwrite_prior_version": False,
        "mutate_prior_payload": False,
        "mutate_prior_sha": False,
        "supersede_active_before_verified_promotion": False,
        "activation_requires_separate_verified_gate": True,
    }
    for key, expected in expected_successor.items():
        if successor.get(key) != expected: errors.append("SUCCESSOR_RULE_MISMATCH:" + key)

    guards = set(data.get("hard_guards") or [])
    missing_guards = sorted(REQUIRED_GUARDS - guards)
    if missing_guards: errors.append("HARD_GUARDS_MISSING:" + ",".join(missing_guards))

    after = set(data.get("required_after_candidate_materialization") or [])
    for required in {"github_exact_head_readback", "rollback_canary_pass", "no_durable_canary_residue", "no_runtime_change", "no_production_change", "no_main_change"}:
        if required not in after: errors.append("AFTER_EVIDENCE_MISSING:" + required)

    promotion = str(data.get("promotion_rule") or "")
    for phrase in ("does not authorize Router ACTIVE", "policy ACTIVE", "merge to main", "supersession"):
        if phrase not in promotion: errors.append("PROMOTION_RULE_INCOMPLETE:" + phrase)
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("contract")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    errors = validate(load_yaml(args.contract))
    result = {"valid": not errors, "blocking_codes": errors}
    print(json.dumps(result, sort_keys=True) if args.json else ("PASS_POLICY_OPERATIONS_CANDIDATE" if not errors else "FAIL_POLICY_OPERATIONS_CANDIDATE\n" + "\n".join(errors)))
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
