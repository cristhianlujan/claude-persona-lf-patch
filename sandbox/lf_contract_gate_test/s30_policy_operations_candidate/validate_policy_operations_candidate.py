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
}
REQUIRED_TOP = {
    "version", "status", "source_strategy", "source_model", "purpose", "authority",
    "asset_contract", "operations", "state_ceiling", "lifecycle_model",
    "create_contract", "update_contract", "hard_guards",
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
        errors.append("TOP_KEYS_MISSING:" + ",".join(missing))
        return errors

    if data.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("CONTRACT_STATUS_CEILING_MISMATCH")
    if data.get("source_model") != "GIT_FIRST_YAML":
        errors.append("SOURCE_MODEL_MISMATCH")

    asset = data.get("asset_contract") or {}
    if asset.get("asset_type") != "REGLA":
        errors.append("ASSET_TYPE_MUST_BE_REGLA")
    if asset.get("required_subtype_prefix") != "POLICY_":
        errors.append("POLICY_SUBTYPE_PREFIX_MISMATCH")
    if asset.get("create_action_code") != "POLICY_CREATE":
        errors.append("CREATE_ACTION_CODE_MISMATCH")
    if asset.get("update_action_code") != "POLICY_UPDATE":
        errors.append("UPDATE_ACTION_CODE_MISMATCH")
    if asset.get("action_decision_status") != "CANDIDATE_DERIVED_FROM_ROUTER_CONVENTION":
        errors.append("ACTION_DECISION_MUST_REMAIN_CANDIDATE")

    ops = data.get("operations") or {}
    expected = {
        "create": {
            "operation_code": "CREACION_POLITICA_LF",
            "operation_type": "CREATION_PROTOCOL",
            "requires_existing_target": False,
            "requires_missing_target": True,
        },
        "update": {
            "operation_code": "ACTUALIZACION_POLITICA_LF",
            "operation_type": "UPDATE_PROTOCOL",
            "requires_existing_target": True,
            "requires_missing_target": False,
        },
    }
    for name, spec in expected.items():
        op = ops.get(name) or {}
        for key, value in spec.items():
            if op.get(key) != value:
                errors.append(f"{name.upper()}_{key.upper()}_MISMATCH")
        if op.get("applies_to_asset_type") != "REGLA":
            errors.append(f"{name.upper()}_APPLIES_TO_MUST_BE_REGLA")
        if op.get("write_allowed") is not True:
            errors.append(f"{name.upper()}_WRITE_MUST_BE_EXPLICIT")
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
    for key, value in expected_ceiling.items():
        if ceiling.get(key) != value:
            errors.append("STATE_CEILING_MISMATCH:" + key)

    lifecycle = data.get("lifecycle_model") or {}
    mapping = lifecycle.get("persisted_status_mapping") or {}
    if mapping != EXPECTED_PHASE_MAP:
        errors.append("LIFECYCLE_PERSISTENCE_MAPPING_MISMATCH")
    invalid_statuses = sorted(set(mapping.values()) - ALLOWED_POLICY_STATUSES)
    if invalid_statuses:
        errors.append("UNSUPPORTED_POLICY_STATUSES:" + ",".join(invalid_statuses))
    phases = lifecycle.get("phases") or []
    if phases != list(EXPECTED_PHASE_MAP):
        errors.append("LIFECYCLE_PHASE_ORDER_MISMATCH")

    create = data.get("create_contract") or {}
    asset_rules = create.get("asset_rules") or {}
    first = create.get("first_version_rules") or {}
    if asset_rules.get("tipo_activo") != "REGLA":
        errors.append("CREATE_ASSET_RULE_NOT_REGLA")
    if asset_rules.get("subtype_must_start_with") != "POLICY_":
        errors.append("CREATE_SUBTYPE_RULE_MISMATCH")
    if first.get("status") != "CANDIDATE":
        errors.append("FIRST_VERSION_MUST_BE_CANDIDATE")
    if first.get("sha256_required") is not True:
        errors.append("POLICY_SHA_REQUIRED")

    update = data.get("update_contract") or {}
    successor = update.get("successor_rules") or {}
    expected_successor = {
        "create_new_row_only": True,
        "candidate_status_on_creation": "CANDIDATE",
        "overwrite_prior_version": False,
        "mutate_prior_payload": False,
        "mutate_prior_sha": False,
        "supersede_active_before_verified_promotion": False,
        "activation_requires_separate_verified_gate": True,
    }
    for key, value in expected_successor.items():
        if successor.get(key) != value:
            errors.append("SUCCESSOR_RULE_MISMATCH:" + key)

    guards = set(data.get("hard_guards") or [])
    missing_guards = sorted(REQUIRED_GUARDS - guards)
    if missing_guards:
        errors.append("HARD_GUARDS_MISSING:" + ",".join(missing_guards))

    after = set(data.get("required_after_candidate_materialization") or [])
    for required in {
        "github_exact_head_readback", "rollback_canary_pass", "no_durable_canary_residue",
        "no_runtime_change", "no_production_change", "no_main_change",
    }:
        if required not in after:
            errors.append("AFTER_EVIDENCE_MISSING:" + required)

    promotion = str(data.get("promotion_rule") or "")
    for phrase in ("does not authorize Router ACTIVE", "policy ACTIVE", "merge to main", "supersession"):
        if phrase not in promotion:
            errors.append("PROMOTION_RULE_INCOMPLETE:" + phrase)

    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("contract")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    data = load_yaml(args.contract)
    errors = validate(data)
    result = {"valid": not errors, "blocking_codes": errors}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print("PASS_POLICY_OPERATIONS_CANDIDATE" if not errors else "FAIL_POLICY_OPERATIONS_CANDIDATE")
        for error in errors:
            print(error)
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
