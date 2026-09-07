#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import yaml


REQUIRED_CONTRACT_KEYS = {
    "version",
    "status",
    "operation",
    "source_model",
    "asset_type",
    "router_action",
    "authority",
    "state_ceiling",
    "required_before_write",
    "registry_contract",
    "router_binding_contract",
    "negative_controls",
    "blocked",
    "required_after_candidate_write",
    "promotion_rule",
}

REQUIRED_NEGATIVES = {
    "missing_created_by_execution_id_rejected",
    "missing_execution_row_rejected",
    "bootstrap_operation_code_mismatch_rejected",
    "duplicate_operation_code_rejected",
    "duplicate_router_action_rejected",
    "requires_existing_and_missing_both_true_rejected",
    "production_status_without_materialization_evidence_rejected",
    "route_activation_without_contract_judge_readback_rejected",
}

REQUIRED_JUDGE_ASSERTIONS = {
    "router_current",
    "target_absent",
    "candidate_ceiling",
    "no_runtime",
    "no_production",
    "provenance_execution",
    "bootstrap_exactness",
    "registry_shape",
    "router_shape",
    "missing_target_only",
    "unique_route",
    "target_flag_guard",
    "rollback_clean",
    "source_exactness",
    "activation_blocked",
}


def load_yaml(path: str):
    with open(path, "r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"YAML_OBJECT_REQUIRED:{path}")
    return data


def validate(contract, steps_doc, judge):
    errors = []

    missing = sorted(REQUIRED_CONTRACT_KEYS - set(contract))
    if missing:
        errors.append("CONTRACT_KEYS_MISSING:" + ",".join(missing))

    if contract.get("operation") != "CREACION_OPERACION_LF":
        errors.append("OPERATION_CODE_MISMATCH")
    if contract.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("CONTRACT_STATUS_CEILING_MISMATCH")
    if contract.get("asset_type") != "OPERATION_CODE":
        errors.append("ASSET_TYPE_MISMATCH")
    if contract.get("router_action") != "OPERATION_CREATE":
        errors.append("ROUTER_ACTION_MISMATCH")

    ceiling = contract.get("state_ceiling") or {}
    expected_ceiling = {
        "operation_status": "CANDIDATO_READ_ONLY",
        "router_status": "CANDIDATE_SANDBOX",
        "runtime_state": "NO_HABILITADO",
        "automatic_impact": "BLOQUEADO",
        "production_allowed": False,
        "runtime_allowed": False,
        "main_merge_allowed": False,
    }
    for key, expected in expected_ceiling.items():
        if ceiling.get(key) != expected:
            errors.append(f"STATE_CEILING_MISMATCH:{key}")

    authority = contract.get("authority") or {}
    if authority.get("router") != "ACT-0001":
        errors.append("ROUTER_AUTHORITY_MISMATCH")
    if authority.get("bootstrap_precedent") != "VULNERABILITY_COVERAGE_REPAIR_LF":
        errors.append("BOOTSTRAP_PRECEDENT_MISMATCH")

    registry = contract.get("registry_contract") or {}
    invariants = registry.get("invariants") or {}
    if invariants.get("operation_type") != "CREATION_PROTOCOL":
        errors.append("REGISTRY_OPERATION_TYPE_MISMATCH")
    if invariants.get("applies_to_asset_type") != "OPERATION_CODE":
        errors.append("REGISTRY_APPLIES_TO_MISMATCH")
    if invariants.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("REGISTRY_STATUS_MISMATCH")
    if invariants.get("created_execution_required") is not True:
        errors.append("PROVENANCE_EXECUTION_NOT_REQUIRED")
    if invariants.get("created_execution_scope_match_or_governance_bootstrap") is not True:
        errors.append("PROVENANCE_SCOPE_GUARD_NOT_REQUIRED")

    router = contract.get("router_binding_contract") or {}
    expected_router = {
        "asset_type": "OPERATION_CODE",
        "action_code": "OPERATION_CREATE",
        "operation_code": "CREACION_OPERACION_LF",
        "operation_resolution": "STATIC",
        "requires_existing_target": False,
        "requires_missing_target": True,
        "write_allowed": True,
        "status": "CANDIDATE_SANDBOX",
        "activation_allowed_in_candidate": False,
    }
    for key, expected in expected_router.items():
        if router.get(key) != expected:
            errors.append(f"ROUTER_BINDING_MISMATCH:{key}")

    negatives = set(contract.get("negative_controls") or [])
    missing_negatives = sorted(REQUIRED_NEGATIVES - negatives)
    if missing_negatives:
        errors.append("NEGATIVE_CONTROLS_MISSING:" + ",".join(missing_negatives))

    blocked = set(contract.get("blocked") or [])
    for required in {
        "direct_registry_write_without_router",
        "direct_registry_write_without_provenance",
        "reuse_unrelated_execution_id",
        "operation_code_scope_mismatch",
        "auto_activate_router",
        "production_promotion",
        "runtime_enablement",
        "bypass_materialization_guard",
    }:
        if required not in blocked:
            errors.append(f"BLOCKED_RULE_MISSING:{required}")

    steps = steps_doc.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("STEPS_REQUIRED")
    else:
        orders = [item.get("order") for item in steps if isinstance(item, dict)]
        expected_orders = list(range(1, len(steps) + 1))
        if orders != expected_orders:
            errors.append("STEP_ORDER_NOT_CONTIGUOUS")
        ids = [item.get("id") for item in steps if isinstance(item, dict)]
        if len(ids) != len(set(ids)):
            errors.append("STEP_IDS_NOT_UNIQUE")
        for required in {
            "router",
            "operational_source",
            "ekb_preflight",
            "target_missing_check",
            "governance_bootstrap_start",
            "provenance_preflight",
            "rollback_canary_registry",
            "rollback_canary_router",
            "rollback_cleanup",
            "independent_candidate_validation",
            "activation_gate",
            "report_output",
        }:
            if required not in ids:
                errors.append(f"STEP_MISSING:{required}")

    if steps_doc.get("operation") != "CREACION_OPERACION_LF":
        errors.append("STEPS_OPERATION_MISMATCH")
    if steps_doc.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("STEPS_STATUS_MISMATCH")

    assertions = judge.get("required_assertions")
    assertion_ids = {
        item.get("id")
        for item in assertions or []
        if isinstance(item, dict) and item.get("id")
    }
    missing_assertions = sorted(REQUIRED_JUDGE_ASSERTIONS - assertion_ids)
    if missing_assertions:
        errors.append("JUDGE_ASSERTIONS_MISSING:" + ",".join(missing_assertions))
    if judge.get("operation") != "CREACION_OPERACION_LF":
        errors.append("JUDGE_OPERATION_MISMATCH")
    if judge.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("JUDGE_STATUS_MISMATCH")
    if judge.get("verdicts") != ["PASS", "FAIL"]:
        errors.append("JUDGE_VERDICTS_MISMATCH")

    claim = str(judge.get("claim_ceiling") or "")
    for forbidden_claim in ("does not authorize registration", "Router ACTIVE", "production promotion"):
        if forbidden_claim not in claim:
            errors.append("CLAIM_CEILING_INCOMPLETE:" + forbidden_claim)

    promotion = str(contract.get("promotion_rule") or "")
    if "does not authorize promotion" not in promotion:
        errors.append("PROMOTION_RULE_NOT_FAIL_CLOSED")

    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--steps", required=True)
    parser.add_argument("--judge", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    contract = load_yaml(args.contract)
    steps_doc = load_yaml(args.steps)
    judge = load_yaml(args.judge)
    errors = validate(contract, steps_doc, judge)
    result = {"valid": not errors, "blocking_codes": errors}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        if errors:
            print("FAIL_OPERATION_FACTORY_CANDIDATE")
            for error in errors:
                print(error)
        else:
            print("PASS_OPERATION_FACTORY_CANDIDATE")
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
