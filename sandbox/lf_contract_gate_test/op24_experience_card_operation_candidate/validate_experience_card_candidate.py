#!/usr/bin/env python3
import argparse
import json
import yaml

REQUIRED_FIELDS = {"codigo","titulo","descripcion","validacion","lifecycle_phase","consumer_role","source_ref"}
REQUIRED_NEGATIVES = {
    "missing_source_ref_blocks",
    "missing_validation_blocks",
    "contradiction_evaluated_before_dedup",
    "duplicate_blocks_second_card_candidate",
    "competitor_field_not_required",
    "self_confirming_evidence_does_not_authorize_promotion",
    "direct_card_write_blocked",
    "direct_official_rule_write_blocked",
    "production_impact_without_approval_blocked",
    "factory_dependency_missing_blocks_registration",
    "missing_experience_route_blocks_execution",
    "experience_route_write_enabled_blocks",
    "router_bypass_blocked",
}

EXPECTED_INVOCATION_ROUTE = {
    "asset_type": "EXPERIENCE",
    "action_code": "EXPERIENCE_LEARNING_BRIDGE",
    "operation_code": "LEARNING_BRIDGE_EXPERIENCE_CARD_LF",
    "operation_resolution": "STATIC",
    "requires_existing_target": False,
    "requires_missing_target": False,
    "write_allowed": False,
    "status": "CANDIDATE_SANDBOX",
    "activation_allowed_in_candidate": False,
    "required_for_execution": True,
}


def load_yaml(path):
    with open(path, "r", encoding="utf-8") as handle:
        value = yaml.safe_load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"YAML_OBJECT_REQUIRED:{path}")
    return value


def validate(contract, steps_doc, judge):
    errors = []
    if contract.get("operation_code") != "LEARNING_BRIDGE_EXPERIENCE_CARD_LF":
        errors.append("OPERATION_CODE_MISMATCH")
    if contract.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("STATUS_CEILING_MISMATCH")
    if contract.get("operation_family") != "LEARNING":
        errors.append("OPERATION_FAMILY_MISMATCH")
    if contract.get("operation_domain") != "EXPERIENCE_TO_CARD":
        errors.append("OPERATION_DOMAIN_MISMATCH")
    if contract.get("operation_type") != "LEARNING_BRIDGE":
        errors.append("OPERATION_TYPE_MISMATCH")
    if contract.get("source_family") != "EXPERIENTIAL_EPISODIC_MEMORY":
        errors.append("SOURCE_FAMILY_MISMATCH")
    if contract.get("source_relation") != "transversal.error_knowledge":
        errors.append("SOURCE_RELATION_MISMATCH")
    if contract.get("receiver_operation") != "CREACION_CARD_LF" or contract.get("receiver_version") != "v0.4":
        errors.append("RECEIVER_MISMATCH")

    authority = contract.get("authority") or {}
    if authority.get("router") != "ACT-0001":
        errors.append("ROUTER_AUTHORITY_MISMATCH")
    if authority.get("parent_strategy") != "LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904" or authority.get("parent_strategy_version") != "v0.3":
        errors.append("PARENT_STRATEGY_BINDING_MISMATCH")

    dependency = contract.get("factory_dependency") or {}
    if dependency.get("operation_code") != "CREACION_OPERACION_LF":
        errors.append("FACTORY_DEPENDENCY_MISMATCH")
    if dependency.get("candidate_pr") != 570:
        errors.append("FACTORY_PR_BINDING_MISMATCH")
    if dependency.get("required_before_registration") is not True or dependency.get("active_router_binding_required_before_registration") is not True:
        errors.append("FACTORY_DEPENDENCY_NOT_FAIL_CLOSED")

    invocation = contract.get("invocation_route")
    if not isinstance(invocation, dict):
        errors.append("INVOCATION_ROUTE_MISSING")
    else:
        for key, expected in EXPECTED_INVOCATION_ROUTE.items():
            if invocation.get(key) != expected:
                errors.append(f"INVOCATION_ROUTE_MISMATCH:{key}")

    ceiling = contract.get("state_ceiling") or {}
    expected_ceiling = {
        "operation_status":"CANDIDATO_READ_ONLY",
        "runtime_state":"NO_HABILITADO",
        "automatic_impact":"BLOQUEADO",
        "production_allowed":False,
        "runtime_allowed":False,
        "durable_registration_allowed":False,
    }
    for key, expected in expected_ceiling.items():
        if ceiling.get(key) != expected:
            errors.append(f"STATE_CEILING_MISMATCH:{key}")

    eligibility = contract.get("eligibility") or {}
    required = set(eligibility.get("required_fields") or [])
    missing_fields = sorted(REQUIRED_FIELDS - required)
    if missing_fields:
        errors.append("REQUIRED_FIELDS_MISSING:" + ",".join(missing_fields))
    if "competitor" in required or eligibility.get("no_competitor_requirement") is not True:
        errors.append("COMPETITOR_REQUIREMENT_FORBIDDEN")
    if eligibility.get("contradiction_before_dedup") is not True:
        errors.append("CONTRADICTION_BEFORE_DEDUP_REQUIRED")
    if eligibility.get("independent_evidence_required_for_promotion") is not True:
        errors.append("INDEPENDENT_EVIDENCE_GATE_REQUIRED")

    required_gates = set(contract.get("required_gates") or [])
    if "experience_router_contract_gate" not in required_gates:
        errors.append("EXPERIENCE_ROUTER_GATE_REQUIRED")

    output = contract.get("output_contract") or {}
    if output.get("kind") != "CARD_CANDIDATE_DOSSIER":
        errors.append("OUTPUT_KIND_MISMATCH")
    if output.get("direct_card_write") is not False:
        errors.append("DIRECT_CARD_WRITE_MUST_BE_FALSE")
    if output.get("direct_official_rule_write") is not False:
        errors.append("DIRECT_OFFICIAL_RULE_WRITE_MUST_BE_FALSE")
    if output.get("direct_impact") is not False:
        errors.append("DIRECT_IMPACT_MUST_BE_FALSE")
    if output.get("exact_receiver_only") != "CREACION_CARD_LF:v0.4":
        errors.append("EXACT_RECEIVER_MISMATCH")

    negatives = set(contract.get("negative_controls") or [])
    missing_neg = sorted(REQUIRED_NEGATIVES - negatives)
    if missing_neg:
        errors.append("NEGATIVE_CONTROLS_MISSING:" + ",".join(missing_neg))

    expected_lifecycle = ["DETECTADO","ANALIZADO","CARD_CREADA","EN_REVISION","PRUEBA_SANDBOX","APROBADO","IMPACTADO","VERIFICADO","CERRADO"]
    if contract.get("lifecycle") != expected_lifecycle:
        errors.append("LIFECYCLE_ORDER_MISMATCH")

    steps = steps_doc.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("STEPS_REQUIRED")
        step_ids = []
    else:
        orders = [item.get("order") for item in steps]
        if orders != list(range(1, len(steps)+1)):
            errors.append("STEP_ORDER_NOT_CONTIGUOUS")
        step_ids = [item.get("id") for item in steps]
        if len(step_ids) != len(set(step_ids)):
            errors.append("STEP_IDS_NOT_UNIQUE")

    required_step_order = [
        "factory_and_invocation_route_check",
        "required_signal_gate",
        "contradiction_gate",
        "deterministic_dedup",
        "independent_evidence_gate",
        "card_factory_contract_gate",
        "card_candidate_dossier",
        "sandbox_gate",
        "quality_gate",
        "performance_gate",
        "governance_gate",
        "approval_boundary",
        "verify",
        "close",
    ]
    positions = []
    for required_step in required_step_order:
        if required_step not in step_ids:
            errors.append(f"STEP_MISSING:{required_step}")
        else:
            positions.append(step_ids.index(required_step))
    if positions and positions != sorted(positions):
        errors.append("CRITICAL_STEP_ORDER_MISMATCH")
    if "contradiction_gate" in step_ids and "deterministic_dedup" in step_ids and step_ids.index("contradiction_gate") > step_ids.index("deterministic_dedup"):
        errors.append("DEDUP_PRECEDES_CONTRADICTION")

    if steps_doc.get("operation_code") != contract.get("operation_code"):
        errors.append("STEPS_OPERATION_MISMATCH")
    if judge.get("operation_code") != contract.get("operation_code"):
        errors.append("JUDGE_OPERATION_MISMATCH")
    if judge.get("status") != "CANDIDATO_READ_ONLY":
        errors.append("JUDGE_STATUS_MISMATCH")
    if judge.get("verdicts") != ["PASS","FAIL","BLOCKED"]:
        errors.append("JUDGE_VERDICTS_MISMATCH")

    pass_if = set(judge.get("pass_if") or [])
    if "experience_invocation_route_contract_valid" not in pass_if:
        errors.append("JUDGE_PASS_CONDITION_MISSING:experience_invocation_route_contract_valid")
    fail_if = set(judge.get("fail_if") or [])
    for needed in {"experience_route_shape_mismatch", "experience_route_write_enabled"}:
        if needed not in fail_if:
            errors.append(f"JUDGE_FAIL_CONDITION_MISSING:{needed}")
    blocked_if = set(judge.get("blocked_if") or [])
    for needed in {
        "creacion_operacion_lf_not_approved",
        "operation_create_router_binding_missing",
        "experience_learning_bridge_route_missing",
        "independent_evidence_missing_for_promotion",
        "explicit_approval_missing_for_impact",
    }:
        if needed not in blocked_if:
            errors.append(f"JUDGE_BLOCKED_CONDITION_MISSING:{needed}")

    claim = str(contract.get("claim_ceiling") or "") + " " + str(judge.get("claim_ceiling") or "")
    for phrase in ("does not authorize", "Card creation", "runtime", "production"):
        if phrase not in claim:
            errors.append("CLAIM_CEILING_INCOMPLETE:" + phrase)

    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--steps", required=True)
    parser.add_argument("--judge", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    errors = validate(load_yaml(args.contract), load_yaml(args.steps), load_yaml(args.judge))
    result = {"valid": not errors, "blocking_codes": errors}
    print(json.dumps(result, sort_keys=True) if args.json else ("PASS_EXPERIENCE_CARD_CANDIDATE" if not errors else "FAIL_EXPERIENCE_CARD_CANDIDATE\n" + "\n".join(errors)))
    raise SystemExit(0 if not errors else 1)

if __name__ == "__main__":
    main()
