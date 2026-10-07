from material_front_coverage_gate_r4 import *

FRONTS=[
"ARCHITECTURE_TOPOLOGY","CONTROLS_GUARDS_ENFORCEMENT","POLICIES_CONTRACTS_AUTHORITY",
"CONTEXT_INPUT_TRANSPORT","WIRING_REACHABILITY_ROUTING","IDENTITY_VERSION_CURRENTNESS",
"COMPATIBILITY_TRANSITION_MIGRATION","STATE_LIFECYCLE_TERMINALITY",
"RECOVERY_ROLLBACK_IDEMPOTENCY_REPLAY","CONSUMERS_DEPENDENCY_BLAST_RADIUS",
"OBSERVABILITY_EVIDENCE_READBACK","SECURITY_PRIVACY_PERMISSIONS",
"PERFORMANCE_COST_CAPACITY","TESTING_ASSURANCE_FALSIFICATION",
"OPERABILITY_MAINTENANCE_OWNERSHIP"]

def axes(v="NO_CHANGE_PROVEN"): return {a:v for a in SIX_AXES}
def low(code): return {"front_code":code,"applicable":True,"evidence_refs":["e:"+code],"decision_axes":axes(),"decision_link_refs":{}}
def material(code,origin="OBSERVED_LIVE"):
    a=axes(); a["root_cause"]="CAN_CHANGE"
    return {"front_code":code,"applicable":True,"evidence_refs":["e:"+code],"decision_axes":a,
      "decision_link_refs":{"root_cause":[{"ref":"e:"+code,"verification_origins":[origin]}]},
      "method_receipts":[{"method_or_capability":"SRCR_V07_METHOD","execution_id":"x1","subject_revision":"r1","evidence_refs":["m1"],"executed":True}]}
def base():
    return {"fronts":[low(x) for x in FRONTS],"items":[],"unconsumed_reinspection_triggers":[],
            "mfc_incremental_cost":{"db_queries":0,"file_reads":0,"subagent_calls":0,"external_searches":0}}
def add(name,f,expected,reason=None,item_type=None):
    cases.append((name,f,expected,reason,item_type))
cases=[]

f=base(); f["items"]=[{"finding_id":"D1","subject_bound":True,"positive_incorrect_condition":True,"verification_origins":["CASE_ASSERTION"],"decision_bearing":True}]
add("01_case_premise_not_defect",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_BEARING_EVIDENCE_REQUIREMENT","EVIDENCE_REQUIREMENT")

f=base(); f["items"]=[{"finding_id":"D1","subject_bound":True,"positive_incorrect_condition":True,"verification_origins":["CASE_ASSERTION","EXECUTED_TEST"],"decision_bearing":False}]
add("02_case_plus_test_is_defect",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="DEFECT")

f=base(); f["items"]=[{"finding_id":"G1","subject_bound":True,"required_element_exists":True,"required_element_absent":True,"verification_origins":["CASE_ASSERTION"],"decision_bearing":True}]
add("03_case_premise_not_gap",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_BEARING_EVIDENCE_REQUIREMENT","EVIDENCE_REQUIREMENT")

f=base(); f["items"]=[{"finding_id":"G1","subject_bound":True,"required_element_exists":True,"required_element_absent":True,"verification_origins":["CANONICAL_AUTHORITY"],"decision_bearing":False}]
add("04_authority_proven_gap",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="GAP")

f=base(); common={"subject_bound":True,"positive_incorrect_condition":True,"verification_origins":["OBSERVED_LIVE"],"bad_boundary":"B","violated_invariant":"I","observed_effect":"E","repair_implication":"R","decision_bearing":False}
f["items"]=[{"finding_id":"D1",**common},{"finding_id":"D2",**common}]
add("05_duplicate_collapsed",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="DUPLICATE")

f=base(); a=axes(); a["root_cause"]="CAN_CHANGE"; f["fronts"][0]={"front_code":FRONTS[0],"applicable":True,"evidence_refs":["case"],"decision_axes":a,"decision_link_refs":{"root_cause":[{"ref":"case","verification_origins":["CASE_ASSERTION"]}]},"method_receipts":[{"method_or_capability":"M","execution_id":"x","subject_revision":"r1","evidence_refs":["m"],"executed":True}]}
add("06_case_only_cannot_make_material",f,"RETURN_TO_EVIDENCE_ACQUISITION","MATERIAL_DECISION_LINK_UNPROVEN")

f=base(); f["fronts"][0]=material(FRONTS[0])
add("07_verified_material_passes",f,"MATERIAL_FRONT_COVERAGE_PASS")

f=base(); f["mfc_incremental_cost"]["db_queries"]=1
add("08_active_query_is_protocol_violation",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","MFC_ACTIVE_INVESTIGATION_FORBIDDEN")

f=base(); f["mfc_incremental_cost"]["file_reads"]=1
add("09_active_file_read_is_protocol_violation",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","MFC_ACTIVE_INVESTIGATION_FORBIDDEN")

f=base(); f["fronts"]=f["fronts"][:14]
add("10_ledger_incomplete",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","UNIVERSAL_LEDGER_INCOMPLETE")

f=base(); f["fronts"][0]={"front_code":FRONTS[0],"applicable":False,"evidence_refs":[],"decision_axes":axes(),"decision_link_refs":{}}
add("11_na_needs_positive_proof",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","N_A_WITHOUT_POSITIVE_EVIDENCE")

f=base(); f["fronts"][0]={"front_code":FRONTS[0],"applicable":False,"evidence_refs":["e"],"na_proof_ref":"authority://na","decision_axes":axes(),"decision_link_refs":{}}
add("12_na_positive",f,"MATERIAL_FRONT_COVERAGE_PASS")

f=base(); a=axes(); a["root_cause"]="UNRESOLVED"; f["fronts"][0]={**low(FRONTS[0]),"decision_axes":a}
add("13_unresolved_returns",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_AXIS_UNRESOLVED")

f=base(); m=material(FRONTS[0]); m["method_receipts"]=[]; f["fronts"][0]=m
add("14_material_needs_method_receipt",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","MATERIAL_METHOD_RECEIPT_MISSING")

f=base(); m=material(FRONTS[0]); m["method_receipts"][0]["claim_outside_supported_scope"]=True; f["fronts"][0]=m
add("15_provider_limit_unproven",f,"RETURN_TO_EVIDENCE_ACQUISITION","PROVIDER_SCOPE_UNPROVEN")

f=base(); f["unconsumed_reinspection_triggers"]=["t"]
add("16_reinspection_trigger_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","REINSPECTION_TRIGGER_NOT_CONSUMED")

fails=[]
for name,f,expected,reason,item_type in cases:
    r=evaluate_coverage(f)
    ok=r["status"]==expected
    if reason: ok=ok and any(reason in x for x in r.get("reasons",[]))
    if item_type: ok=ok and any(x.get("item_type")==item_type for x in r.get("items",[]))
    print(name,"PASS" if ok else "FAIL",r)
    if not ok:fails.append(name)
print("SUMMARY",len(cases)-len(fails),"/",len(cases),"failures",fails)
raise SystemExit(1 if fails else 0)
