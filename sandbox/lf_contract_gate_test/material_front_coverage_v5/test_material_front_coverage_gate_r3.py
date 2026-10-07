from material_front_coverage_gate_r3 import *

FRONTS=[
"ARCHITECTURE_TOPOLOGY","CONTROLS_GUARDS_ENFORCEMENT","POLICIES_CONTRACTS_AUTHORITY",
"CONTEXT_INPUT_TRANSPORT","WIRING_REACHABILITY_ROUTING","IDENTITY_VERSION_CURRENTNESS",
"COMPATIBILITY_TRANSITION_MIGRATION","STATE_LIFECYCLE_TERMINALITY",
"RECOVERY_ROLLBACK_IDEMPOTENCY_REPLAY","CONSUMERS_DEPENDENCY_BLAST_RADIUS",
"OBSERVABILITY_EVIDENCE_READBACK","SECURITY_PRIVACY_PERMISSIONS",
"PERFORMANCE_COST_CAPACITY","TESTING_ASSURANCE_FALSIFICATION",
"OPERABILITY_MAINTENANCE_OWNERSHIP"]

def axes(v="NO_CHANGE_PROVEN"):
    return {a:v for a in SIX_AXES}

def low(code):
    return {"front_code":code,"applicable":True,"evidence_refs":["e:"+code],"decision_axes":axes()}

def material(code):
    a=axes(); a["root_cause"]="CAN_CHANGE"
    return {"front_code":code,"applicable":True,"evidence_refs":["e:"+code],"decision_axes":a,
            "method_receipts":[{"method_or_capability":"SRCR_V07_METHOD","execution_id":"x1","subject_revision":"r1","evidence_refs":["m1"],"executed":True,"limitations":[]}]}

def base():
    return {"fronts":[low(x) for x in FRONTS],"items":[],"unconsumed_reinspection_triggers":[]}

cases=[]

def add(name,fixture,expected,reason=None,item_type=None):
    cases.append((name,fixture,expected,reason,item_type))

f=base()
f["items"]=[
 {"finding_id":"F1","subject_bound":True,"positive_incorrect_condition":True,"bad_boundary":"COMPOSITION","violated_invariant":"BASELINE_GUARD_REQUIRED","observed_effect":"ISOLATED_PASS_NOT_COMPOSITION_SAFE","repair_implication":"TEST_COMPOSED_OR_SERIALIZED","decision_bearing":True},
 {"finding_id":"F2","subject_bound":True,"positive_incorrect_condition":True,"bad_boundary":"COMPOSITION","violated_invariant":"BASELINE_GUARD_REQUIRED","observed_effect":"ISOLATED_PASS_NOT_COMPOSITION_SAFE","repair_implication":"TEST_COMPOSED_OR_SERIALIZED","decision_bearing":True},
]
add("01_rc078_duplicate_collapsed",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="DUPLICATE")

f=base()
f["items"]=[{"finding_id":"F1","subject_bound":True,"future_probe_needed":True,"bad_boundary":"RESULT_CLASSIFIER","violated_invariant":"SEMANTIC_EVIDENCE_REQUIRED","repair_implication":"PROBE_CLASSIFIER","decision_bearing":True}]
add("02_rc012_unprobed_is_evidence_requirement",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_BEARING_EVIDENCE_REQUIREMENT","EVIDENCE_REQUIREMENT")

f=base()
f["items"]=[{"finding_id":"F1","subject_bound":True,"positive_incorrect_condition":True,"bad_boundary":"RESULT_CLASSIFIER","violated_invariant":"NEGATED_PASS_MUST_NOT_PASS","observed_effect":"NOT_PASS_CLASSIFIED_PASS","repair_implication":"FIX_CLASSIFIER","decision_bearing":True}]
add("03_verified_classifier_is_defect",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="DEFECT")

f=base()
f["items"]=[{"finding_id":"G1","subject_bound":True,"required_element_exists":True,"required_element_absent":True,"bad_boundary":"METHOD_RECEIPT","violated_invariant":"METHOD_RECEIPT_REQUIRED","observed_effect":"NO_RECEIPT","repair_implication":"EXECUTE_METHOD","decision_bearing":False}]
add("04_proven_missing_required_element_is_gap",f,"MATERIAL_FRONT_COVERAGE_PASS",item_type="GAP")

f=base(); f["fronts"]=f["fronts"][:14]
add("05_incomplete_ledger_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","UNIVERSAL_LEDGER_INCOMPLETE")

f=base(); f["fronts"][0]={"front_code":FRONTS[0],"applicable":False,"evidence_refs":[],"decision_axes":axes()}
add("06_na_without_proof_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","N_A_WITHOUT_POSITIVE_EVIDENCE")

f=base(); f["fronts"][0]={"front_code":FRONTS[0],"applicable":False,"evidence_refs":["na"],"na_proof_ref":"authority://na","decision_axes":axes()}
add("07_na_with_proof_passes",f,"MATERIAL_FRONT_COVERAGE_PASS")

f=base(); a=axes(); a["blast_radius"]="UNRESOLVED"; f["fronts"][0]={**low(FRONTS[0]),"decision_axes":a}
add("08_unresolved_axis_returns",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_AXIS_UNRESOLVED")

f=base(); a=axes(); a["blast_radius"]="UNRESOLVED"; a["root_cause"]="CAN_CHANGE"; f["fronts"][0]={**material(FRONTS[0]),"decision_axes":a}
add("09_can_change_dominates_unresolved",f,"MATERIAL_FRONT_COVERAGE_PASS")

f=base(); a=axes(); a["root_cause"]="CAN_CHANGE"; f["fronts"][0]={"front_code":FRONTS[0],"applicable":True,"evidence_refs":["e"],"decision_axes":a,"method_receipts":[]}
add("10_material_without_method_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","MATERIAL_METHOD_RECEIPT_MISSING")

f=base(); mf=material(FRONTS[0]); mf["method_receipts"][0]["claim_outside_supported_scope"]=True; f["fronts"][0]=mf
add("11_provider_limit_returns",f,"RETURN_TO_EVIDENCE_ACQUISITION","PROVIDER_SCOPE_UNPROVEN")

f=base(); f["fronts"][0]["evidence_refs"]=[]
add("12_front_without_evidence_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","FRONT_EVIDENCE_REFS_MISSING")

f=base(); f["unconsumed_reinspection_triggers"]=["t1"]
add("13_unconsumed_reinspection_blocks",f,"MATERIAL_FRONT_COVERAGE_BLOCKED","REINSPECTION_TRIGGER_NOT_CONSUMED")

f=base(); f["items"]=[{"finding_id":"E1","subject_bound":False,"positive_incorrect_condition":True,"decision_bearing":True}]
add("14_unbound_claim_requires_evidence",f,"RETURN_TO_EVIDENCE_ACQUISITION","DECISION_BEARING_EVIDENCE_REQUIREMENT","EVIDENCE_REQUIREMENT")

f=base(); f["fronts"][0]=material(FRONTS[0])
add("15_material_with_receipt_passes",f,"MATERIAL_FRONT_COVERAGE_PASS")

fails=[]
for name,fixture,expected,reason,item_type in cases:
    r=evaluate_coverage(fixture)
    ok=r["status"]==expected
    if reason is not None:
        ok=ok and any(reason in x for x in r.get("reasons",[]))
    if item_type is not None:
        ok=ok and any(x.get("item_type")==item_type for x in r.get("items",[]))
    print(name,"PASS" if ok else "FAIL",r)
    if not ok: fails.append(name)

print("SUMMARY",len(cases)-len(fails),"/",len(cases),"failures",fails)
raise SystemExit(1 if fails else 0)
