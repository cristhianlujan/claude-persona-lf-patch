from material_front_coverage_harness_v5 import *
import copy

REV="r1"

def ch():
    m={"state":"INDEPENDENT","dimensions":{"dependency":"INDEPENDENT","data":"INDEPENDENT","author":"INDEPENDENT"}}
    return {"execution_id":"review-1","executor_identity":"reviewer","subject_revision":REV,
            "independence_receipt":{"verification_state":"VERIFIED","provider_bound":True,"measurement":m,"measurement_digest":canon_sha(m)}}

def receipt(cap="CAP"):
    return {"capability_code":cap,"verification_state":"VERIFIED","subject_revision":REV,"scope_supported":True,"evidence_refs":["e1"]}

def front(**kw):
    d={"code":"F1","applicable":True,"evidence_refs":["e"],"material_signal":False,
       "low_risk_axes":{a:"NO_CHANGE_PROVEN" for a in SIX_AXES},"deep_inspection_complete":True}
    d.update(kw)
    return d

def base():
    return {"subject_revision":REV,"producer_execution_id":"prod-1","producer_identity":"producer",
      "front_catalog_version":"v1","selection_policy_version":"v1","evidence_state":"CURRENT",
      "signal_rounds":[[]],"max_reselection_rounds":3,"converged":True,"needs_another_reselection":False,
      "required_flags":[],"module_receipts":{},"fronts":[front()],"closure_claim_requested":True,
      "challenger":ch(),"unconsumed_reinspection_triggers":[]}

cases=[]
def add(name, mutate, expected, contains=None):
    f=base(); mutate(f); cases.append((name,f,expected,contains))

add("01_baseline",lambda f:None,PASS)
add("02_injected_expected",lambda f:f.update({"expected_status":"PASS"}),BLOCK,"INJECTED_EXPECTATION_FIELD")
add("03_stale_evidence",lambda f:f.update({"evidence_state":"STALE"}),RETURN,"EVIDENCE_STATE_STALE")
add("04_current_false_signal",lambda f:f.update({"signal_rounds":[[{"module":"M","current":False,"subject_bound":True,"evidence_ref":"x","directness":"DIRECT","provider":"p","authority_ref":"a","source_subject_digest":"d"}]]}),RETURN,"TRIGGER_STRENGTH_UNRESOLVED")
add("05_two_weak_same_group_no_activation",lambda f:f.update({"signal_rounds":[[
 {"module":"M","current":True,"subject_bound":True,"evidence_ref":"1","directness":"INDIRECT","provider":"p","authority_ref":"a","source_subject_digest":"d"},
 {"module":"M","current":True,"subject_bound":True,"evidence_ref":"2","directness":"INDIRECT","provider":"p","authority_ref":"a","source_subject_digest":"d"}]]}),PASS)
add("06_two_weak_distinct_require_receipt",lambda f:f.update({"signal_rounds":[[
 {"module":"M","current":True,"subject_bound":True,"evidence_ref":"1","directness":"INDIRECT","provider":"p1","authority_ref":"a","source_subject_digest":"d"},
 {"module":"M","current":True,"subject_bound":True,"evidence_ref":"2","directness":"INDIRECT","provider":"p2","authority_ref":"a","source_subject_digest":"d"}]]}),BLOCK,"REQUIRED_PROVIDER_RECEIPT_MISSING")

def c7(f):
    f["signal_rounds"]=[[{"module":"M","current":True,"subject_bound":True,"evidence_ref":"1","directness":"DIRECT","provider":"p","authority_ref":"a","source_subject_digest":"d"}]]
    f["module_receipts"]={"M":receipt("X")}
add("07_direct_with_receipt",c7,PASS)

add("08_converged_at_limit",lambda f:f.update({"signal_rounds":[[],[],[]],"max_reselection_rounds":3,"converged":True}),PASS)
add("09_nonconverged_at_limit",lambda f:f.update({"signal_rounds":[[],[],[]],"max_reselection_rounds":3,"converged":False}),BLOCK,"NON_CONVERGENT")
add("10_needs_another_at_limit",lambda f:f.update({"signal_rounds":[[],[],[]],"max_reselection_rounds":3,"needs_another_reselection":True}),BLOCK,"NON_CONVERGENT")

def c11(f):
    ax={a:"NO_CHANGE_PROVEN" for a in SIX_AXES}; ax["root_cause"]="CAN_CHANGE"; ax["blast_radius"]="UNRESOLVED"
    f["fronts"]=[front(low_risk_axes=ax,deep_inspection_complete=True)]
add("11_can_change_dominates_unresolved",c11,PASS)

def c12(f):
    ax={a:"NO_CHANGE_PROVEN" for a in SIX_AXES}; ax["blast_radius"]="UNRESOLVED"
    f["fronts"]=[front(low_risk_axes=ax)]
add("12_unresolved_axis_returns",c12,RETURN,"LOW_RISK_AXIS_UNRESOLVED")

add("13_front_evidence_missing",lambda f:f.update({"fronts":[front(evidence_refs=[])]}),BLOCK,"FRONT_EVIDENCE_REFS_MISSING")
add("14_material_not_deep",lambda f:f.update({"fronts":[front(material_signal=True,low_risk_axes=None,deep_inspection_complete=False)]}),BLOCK,"MATERIAL_FRONT_NOT_DEEP_INSPECTED")
add("15_na_positive",lambda f:f.update({"fronts":[front(applicable=False,na_proof_ref="n",evidence_refs=["n"])]}),PASS)
add("16_na_without_evidence",lambda f:f.update({"fronts":[front(applicable=False,na_proof_ref=None,evidence_refs=[])]}),BLOCK,"N_A_WITHOUT_EVIDENCE")
add("17_same_challenger_execution",lambda f:f["challenger"].update({"execution_id":"prod-1"}),BLOCK,"NOT_INDEPENDENT")
add("18_same_challenger_identity",lambda f:f["challenger"].update({"executor_identity":"producer"}),BLOCK,"NOT_INDEPENDENT")
add("19_challenger_revision_mismatch",lambda f:f["challenger"].update({"subject_revision":"other"}),BLOCK,"REVISION_MISMATCH")
add("20_challenger_unverified",lambda f:f["challenger"]["independence_receipt"].update({"verification_state":"UNVERIFIED"}),BLOCK,"ASSURANCE_CHAIN")
add("21_challenger_tampered_digest",lambda f:f["challenger"]["independence_receipt"].update({"measurement_digest":"0"*64),BLOCK,"DIGEST_INVALID")
add("22_provider_scope_unproven",lambda f:(f.update({"required_flags":["write_capable"]}),f["module_receipts"].update({"AGENT_ACTION_SIDE_EFFECT":{**receipt(), "scope_supported":False}})),BLOCK,"PROVIDER_SCOPE_UNPROVEN")
add("23_provider_subject_mismatch",lambda f:(f.update({"required_flags":["write_capable"]}),f["module_receipts"].update({"AGENT_ACTION_SIDE_EFFECT":{**receipt(), "subject_revision":"x"}})),BLOCK,"PROVIDER_SUBJECT_REVISION_MISMATCH")
add("24_orphan_material",lambda f:f.update({"fronts":[front(orphan_required=True)]}),BLOCK,"ORPHAN_METHOD_UNPROVEN")
add("25_reinspection_pending",lambda f:f.update({"unconsumed_reinspection_triggers":["t1"]}),BLOCK,"REINSPECTION_TRIGGER_NOT_CONSUMED")
add("26_missing_budget",lambda f:f.update({"max_reselection_rounds":0}),BLOCK,"SEARCH_BUDGET_MISSING")

fails=[]
for name,f,expected,contains in cases:
    r=evaluate(f)
    ok=r["status"]==expected and (contains is None or any(contains in x for x in r.get("reasons",[])))
    print(name, "PASS" if ok else "FAIL", r)
    if not ok:
        fails.append(name)

print("SUMMARY",len(cases)-len(fails),"/",len(cases),"failures",fails)
raise SystemExit(1 if fails else 0)
