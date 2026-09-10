#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("validator",ROOT/"validate_experience_card_candidate.py")
validator=importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)

def load(name):
    with (ROOT/name).open("r",encoding="utf-8") as handle: return yaml.safe_load(handle)

contract=load("contrato_learning_bridge_experience_card_lf.yaml")
steps=load("learning_bridge_experience_card_lf_steps.yaml")
judge=load("judge_learning_bridge_experience_card_lf.yaml")
assert validator.validate(contract,steps,judge)==[]
cases=[]

def add(name,c=None,s=None,j=None,expected=None):
    cases.append((name,c or contract,s or steps,j or judge,expected))

c=copy.deepcopy(contract); c["eligibility"]["required_fields"].remove("source_ref")
add("missing_source_ref_contract",c=c,expected="REQUIRED_FIELDS_MISSING:source_ref")
c=copy.deepcopy(contract); c["eligibility"]["required_fields"].append("competitor")
add("competitor_wrongly_required",c=c,expected="COMPETITOR_REQUIREMENT_FORBIDDEN")
s=copy.deepcopy(steps)
a=next(i for i,x in enumerate(s["steps"]) if x["id"]=="contradiction_gate"); b=next(i for i,x in enumerate(s["steps"]) if x["id"]=="deterministic_dedup")
s["steps"][a]["id"],s["steps"][b]["id"]=s["steps"][b]["id"],s["steps"][a]["id"]
add("dedup_before_contradiction",s=s,expected="DEDUP_PRECEDES_CONTRADICTION")
c=copy.deepcopy(contract); c["output_contract"]["direct_card_write"]=True
add("direct_card_write",c=c,expected="DIRECT_CARD_WRITE_MUST_BE_FALSE")
c=copy.deepcopy(contract); c["factory_dependency"]["active_router_binding_required_before_registration"]=False
add("factory_bypass",c=c,expected="FACTORY_DEPENDENCY_NOT_FAIL_CLOSED")
c=copy.deepcopy(contract); del c["invocation_route"]
add("missing_experience_route",c=c,expected="INVOCATION_ROUTE_MISSING")
c=copy.deepcopy(contract); c["invocation_route"]["write_allowed"]=True
add("experience_route_write_enabled",c=c,expected="INVOCATION_ROUTE_MISMATCH:write_allowed")
c=copy.deepcopy(contract); c["invocation_route"]["action_code"]="KNOWLEDGE_LEARNING_BRIDGE"
add("experience_route_wrong_action",c=c,expected="INVOCATION_ROUTE_MISMATCH:action_code")
s=copy.deepcopy(steps); s["steps"]=[x for x in s["steps"] if x["id"]!="factory_and_invocation_route_check"]
for i,item in enumerate(s["steps"],start=1): item["order"]=i
add("missing_factory_and_route_step",s=s,expected="STEP_MISSING:factory_and_invocation_route_check")

c=copy.deepcopy(contract); del c["lineage_dependency"]
add("missing_lineage_dependency",c=c,expected="LINEAGE_DEPENDENCY_MISSING")
c=copy.deepcopy(contract); c["lineage_dependency"]["source_ref_field"]="source_ref"
add("wrong_lineage_source_field",c=c,expected="LINEAGE_DEPENDENCY_MISMATCH:source_ref_field")
c=copy.deepcopy(contract); c["lineage_dependency"]["target_ref_field"]="card_code"
add("wrong_lineage_target_field",c=c,expected="LINEAGE_DEPENDENCY_MISMATCH:target_ref_field")
c=copy.deepcopy(contract); c["lineage_dependency"]["relation_type"]="DERIVED_FROM"
add("ambiguous_lineage_relation",c=c,expected="LINEAGE_DEPENDENCY_MISMATCH:relation_type")
c=copy.deepcopy(contract); c["lineage_dependency"]["direct_lineage_table_write"]=True
add("direct_lineage_write",c=c,expected="LINEAGE_DEPENDENCY_MISMATCH:direct_lineage_table_write")
c=copy.deepcopy(contract); c["output_contract"]["card_created_transition_requires_receiver_id_card"]=False
add("receiver_id_gate_removed",c=c,expected="RECEIVER_ID_CARD_GATE_REQUIRED")
c=copy.deepcopy(contract); c["output_contract"]["card_created_transition_requires_lineage_record"]=False
add("lineage_record_gate_removed",c=c,expected="LINEAGE_RECORD_GATE_REQUIRED")
s=copy.deepcopy(steps)
idx=next(i for i,x in enumerate(s["steps"]) if x["id"]=="lifecycle_card_creada")
s["steps"][idx]["evidence_required"]="receiver_factory_receipt_if_authorized"
add("card_creada_lineage_evidence_removed",s=s,expected="CARD_CREADA_LINEAGE_EVIDENCE_MISMATCH")

j=copy.deepcopy(judge); j["blocked_if"].remove("independent_evidence_missing_for_promotion")
add("self_confirmation_guard_removed",j=j,expected="JUDGE_BLOCKED_CONDITION_MISSING:independent_evidence_missing_for_promotion")
j=copy.deepcopy(judge); j["blocked_if"].remove("experience_learning_bridge_route_missing")
add("route_missing_not_fail_closed",j=j,expected="JUDGE_BLOCKED_CONDITION_MISSING:experience_learning_bridge_route_missing")
j=copy.deepcopy(judge); j["blocked_if"].remove("lineage_carrier_not_materialized")
add("lineage_carrier_missing_not_blocked",j=j,expected="JUDGE_BLOCKED_CONDITION_MISSING:lineage_carrier_not_materialized")
j=copy.deepcopy(judge); j["fail_if"].remove("experience_route_write_enabled")
add("route_write_guard_removed",j=j,expected="JUDGE_FAIL_CONDITION_MISSING:experience_route_write_enabled")
j=copy.deepcopy(judge); j["fail_if"].remove("lineage_relation_not_transformed_to")
add("lineage_relation_guard_removed",j=j,expected="JUDGE_FAIL_CONDITION_MISSING:lineage_relation_not_transformed_to")
j=copy.deepcopy(judge); j["fail_if"].remove("direct_lineage_table_write")
add("direct_lineage_guard_removed",j=j,expected="JUDGE_FAIL_CONDITION_MISSING:direct_lineage_table_write")

for name,c_doc,s_doc,j_doc,expected in cases:
    errors=validator.validate(c_doc,s_doc,j_doc)
    assert expected in errors,(name,expected,errors)
print(f"PASS_EXPERIENCE_CARD_ADVERSARIAL_TESTS {1+len(cases)}/{1+len(cases)}")
