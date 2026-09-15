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
    "missing_receiver_id_card_blocks_card_creada",
    "missing_lineage_carrier_blocks_card_creada",
    "missing_exact_lineage_payload_blocks_card_creada",
    "wrong_lineage_source_code_blocks",
    "wrong_lineage_target_card_blocks",
    "wrong_lineage_relation_blocks",
    "direct_lineage_table_write_blocked",
    "router_bypass_blocked",
}
EXPECTED_INVOCATION_ROUTE = {
    "asset_type":"EXPERIENCE",
    "action_code":"EXPERIENCE_LEARNING_BRIDGE",
    "operation_code":"LEARNING_BRIDGE_EXPERIENCE_CARD_LF",
    "operation_resolution":"STATIC",
    "requires_existing_target":False,
    "requires_missing_target":False,
    "write_allowed":False,
    "status":"CANDIDATE_SANDBOX",
    "activation_allowed_in_candidate":False,
    "required_for_execution":True,
}
EXPECTED_LINEAGE = {
    "parent_strategy":"LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904",
    "carrier":"programacion.learned_context_lineage",
    "recorder":"programacion.record_learned_context_lineage_v1",
    "required_before_card_creada_transition":True,
    "source_type":"EKB",
    "source_ref_field":"codigo",
    "target_type":"CARD",
    "target_ref_field":"receiver_factory_receipt.id_card",
    "relation_type":"TRANSFORMED_TO",
    "transformation_group_required":True,
    "exact_clean_step_lineage_required":True,
    "direct_lineage_table_write":False,
    "carrier_source_candidate_only":True,
}


def load_yaml(path):
    with open(path,"r",encoding="utf-8") as handle:
        value=yaml.safe_load(handle)
    if not isinstance(value,dict):
        raise ValueError(f"YAML_OBJECT_REQUIRED:{path}")
    return value


def validate(contract,steps_doc,judge):
    errors=[]
    exact={
        "operation_code":"LEARNING_BRIDGE_EXPERIENCE_CARD_LF",
        "status":"CANDIDATO_READ_ONLY",
        "operation_family":"LEARNING",
        "operation_domain":"EXPERIENCE_TO_CARD",
        "operation_type":"LEARNING_BRIDGE",
        "source_family":"EXPERIENTIAL_EPISODIC_MEMORY",
        "source_relation":"transversal.error_knowledge",
        "receiver_operation":"CREACION_CARD_LF",
        "receiver_version":"v0.4",
    }
    for key,expected in exact.items():
        if contract.get(key)!=expected:
            errors.append(f"CONTRACT_MISMATCH:{key}")

    authority=contract.get("authority") or {}
    if authority.get("router")!="ACT-0001": errors.append("ROUTER_AUTHORITY_MISMATCH")
    if authority.get("parent_strategy")!="LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904" or authority.get("parent_strategy_version")!="v0.3":
        errors.append("PARENT_STRATEGY_BINDING_MISMATCH")

    dependency=contract.get("factory_dependency") or {}
    if dependency.get("operation_code")!="CREACION_OPERACION_LF" or dependency.get("candidate_pr")!=570:
        errors.append("FACTORY_DEPENDENCY_MISMATCH")
    if dependency.get("required_before_registration") is not True or dependency.get("active_router_binding_required_before_registration") is not True:
        errors.append("FACTORY_DEPENDENCY_NOT_FAIL_CLOSED")

    invocation=contract.get("invocation_route")
    if not isinstance(invocation,dict): errors.append("INVOCATION_ROUTE_MISSING")
    else:
        for key,expected in EXPECTED_INVOCATION_ROUTE.items():
            if invocation.get(key)!=expected: errors.append(f"INVOCATION_ROUTE_MISMATCH:{key}")

    lineage=contract.get("lineage_dependency")
    if not isinstance(lineage,dict): errors.append("LINEAGE_DEPENDENCY_MISSING")
    else:
        for key,expected in EXPECTED_LINEAGE.items():
            if lineage.get(key)!=expected: errors.append(f"LINEAGE_DEPENDENCY_MISMATCH:{key}")

    ceiling=contract.get("state_ceiling") or {}
    for key,expected in {
        "operation_status":"CANDIDATO_READ_ONLY","runtime_state":"NO_HABILITADO",
        "automatic_impact":"BLOQUEADO","production_allowed":False,
        "runtime_allowed":False,"durable_registration_allowed":False,
    }.items():
        if ceiling.get(key)!=expected: errors.append(f"STATE_CEILING_MISMATCH:{key}")

    eligibility=contract.get("eligibility") or {}
    required=set(eligibility.get("required_fields") or [])
    missing=sorted(REQUIRED_FIELDS-required)
    if missing: errors.append("REQUIRED_FIELDS_MISSING:"+",".join(missing))
    if "competitor" in required or eligibility.get("no_competitor_requirement") is not True:
        errors.append("COMPETITOR_REQUIREMENT_FORBIDDEN")
    if eligibility.get("contradiction_before_dedup") is not True: errors.append("CONTRADICTION_BEFORE_DEDUP_REQUIRED")
    if eligibility.get("independent_evidence_required_for_promotion") is not True: errors.append("INDEPENDENT_EVIDENCE_GATE_REQUIRED")

    gates=set(contract.get("required_gates") or [])
    for gate in {"experience_router_contract_gate","lineage_contract_gate"}:
        if gate not in gates: errors.append(f"REQUIRED_GATE_MISSING:{gate}")

    output=contract.get("output_contract") or {}
    if output.get("kind")!="CARD_CANDIDATE_DOSSIER": errors.append("OUTPUT_KIND_MISMATCH")
    if output.get("direct_card_write") is not False: errors.append("DIRECT_CARD_WRITE_MUST_BE_FALSE")
    if output.get("direct_official_rule_write") is not False: errors.append("DIRECT_OFFICIAL_RULE_WRITE_MUST_BE_FALSE")
    if output.get("direct_impact") is not False: errors.append("DIRECT_IMPACT_MUST_BE_FALSE")
    if output.get("exact_receiver_only")!="CREACION_CARD_LF:v0.4": errors.append("EXACT_RECEIVER_MISMATCH")
    if output.get("card_created_transition_requires_receiver_id_card") is not True: errors.append("RECEIVER_ID_CARD_GATE_REQUIRED")
    if output.get("card_created_transition_requires_lineage_record") is not True: errors.append("LINEAGE_RECORD_GATE_REQUIRED")

    negatives=set(contract.get("negative_controls") or [])
    missing_neg=sorted(REQUIRED_NEGATIVES-negatives)
    if missing_neg: errors.append("NEGATIVE_CONTROLS_MISSING:"+",".join(missing_neg))

    expected_lifecycle=["DETECTADO","ANALIZADO","CARD_CREADA","EN_REVISION","PRUEBA_SANDBOX","APROBADO","IMPACTADO","VERIFICADO","CERRADO"]
    if contract.get("lifecycle")!=expected_lifecycle: errors.append("LIFECYCLE_ORDER_MISMATCH")

    steps=steps_doc.get("steps")
    if not isinstance(steps,list) or not steps:
        errors.append("STEPS_REQUIRED"); step_ids=[]
    else:
        orders=[x.get("order") for x in steps]
        if orders!=list(range(1,len(steps)+1)): errors.append("STEP_ORDER_NOT_CONTIGUOUS")
        step_ids=[x.get("id") for x in steps]
        if len(step_ids)!=len(set(step_ids)): errors.append("STEP_IDS_NOT_UNIQUE")
    required_order=["factory_and_invocation_route_check","required_signal_gate","contradiction_gate","deterministic_dedup","independent_evidence_gate","card_factory_contract_gate","card_candidate_dossier","lifecycle_card_creada","sandbox_gate","quality_gate","performance_gate","governance_gate","approval_boundary","verify","close"]
    positions=[]
    for step_id in required_order:
        if step_id not in step_ids: errors.append(f"STEP_MISSING:{step_id}")
        else: positions.append(step_ids.index(step_id))
    if positions and positions!=sorted(positions): errors.append("CRITICAL_STEP_ORDER_MISMATCH")
    if "contradiction_gate" in step_ids and "deterministic_dedup" in step_ids and step_ids.index("contradiction_gate")>step_ids.index("deterministic_dedup"):
        errors.append("DEDUP_PRECEDES_CONTRADICTION")
    if "lifecycle_card_creada" in step_ids:
        step=steps[step_ids.index("lifecycle_card_creada")]
        if step.get("evidence_required")!="receiver_factory_receipt_id_card_and_exact_ekb_to_card_transformed_to_lineage":
            errors.append("CARD_CREADA_LINEAGE_EVIDENCE_MISMATCH")

    if steps_doc.get("operation_code")!=contract.get("operation_code"): errors.append("STEPS_OPERATION_MISMATCH")
    if judge.get("operation_code")!=contract.get("operation_code"): errors.append("JUDGE_OPERATION_MISMATCH")
    if judge.get("status")!="CANDIDATO_READ_ONLY": errors.append("JUDGE_STATUS_MISMATCH")
    if judge.get("verdicts")!=["PASS","FAIL","BLOCKED"]: errors.append("JUDGE_VERDICTS_MISMATCH")

    pass_if=set(judge.get("pass_if") or [])
    for needed in {"experience_invocation_route_contract_valid","card_creada_requires_receiver_id_card","card_creada_requires_exact_ekb_to_card_transformed_to_lineage","lineage_direct_table_write_forbidden"}:
        if needed not in pass_if: errors.append(f"JUDGE_PASS_CONDITION_MISSING:{needed}")
    fail_if=set(judge.get("fail_if") or [])
    for needed in {"experience_route_shape_mismatch","experience_route_write_enabled","card_creada_without_receiver_id_card","card_creada_without_lineage","lineage_source_not_ekb_codigo","lineage_target_not_receiver_card_id","lineage_relation_not_transformed_to","direct_lineage_table_write"}:
        if needed not in fail_if: errors.append(f"JUDGE_FAIL_CONDITION_MISSING:{needed}")
    blocked_if=set(judge.get("blocked_if") or [])
    for needed in {"creacion_operacion_lf_not_approved","operation_create_router_binding_missing","experience_learning_bridge_route_missing","lineage_carrier_not_materialized","lineage_recorder_not_available","independent_evidence_missing_for_promotion","explicit_approval_missing_for_impact"}:
        if needed not in blocked_if: errors.append(f"JUDGE_BLOCKED_CONDITION_MISSING:{needed}")

    claim=str(contract.get("claim_ceiling") or "")+" "+str(judge.get("claim_ceiling") or "")
    for phrase in ("does not authorize","Card creation","runtime","production"):
        if phrase not in claim: errors.append("CLAIM_CEILING_INCOMPLETE:"+phrase)
    return errors


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--contract",required=True); parser.add_argument("--steps",required=True); parser.add_argument("--judge",required=True); parser.add_argument("--json",action="store_true")
    args=parser.parse_args()
    errors=validate(load_yaml(args.contract),load_yaml(args.steps),load_yaml(args.judge))
    result={"valid":not errors,"blocking_codes":errors}
    print(json.dumps(result,sort_keys=True) if args.json else ("PASS_EXPERIENCE_CARD_CANDIDATE" if not errors else "FAIL_EXPERIENCE_CARD_CANDIDATE\n"+"\n".join(errors)))
    raise SystemExit(0 if not errors else 1)

if __name__=="__main__": main()
