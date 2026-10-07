from __future__ import annotations

SIX_AXES=(
    "root_cause","repair_topology","blast_radius",
    "acceptance_criteria","rollback_recovery","terminality_lifecycle",
)

def semantic_duplicate(item:dict, existing:dict)->bool:
    keys=("bad_boundary","violated_invariant","observed_effect","repair_implication")
    return all(item.get(k) is not None and item.get(k)==existing.get(k) for k in keys)

def classify_item(item:dict, existing_findings:list[dict])->dict:
    if item.get("future_probe_needed") is True:
        return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}
    if item.get("subject_bound") is not True:
        return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}
    for existing in existing_findings:
        if existing.get("item_type") in {"DEFECT","GAP"} and semantic_duplicate(item,existing):
            return {"item_type":"DUPLICATE","canonical_finding_id":existing.get("finding_id")}
    if item.get("positive_incorrect_condition") is True:
        return {"item_type":"DEFECT","canonical_finding_id":None}
    if item.get("required_element_exists") is True and item.get("required_element_absent") is True:
        return {"item_type":"GAP","canonical_finding_id":None}
    return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}

def classify_front(front:dict)->tuple[str|None,str|None]:
    refs=front.get("evidence_refs")
    if front.get("applicable") is False:
        if front.get("na_proof_ref") and isinstance(refs,list) and refs:
            return "N_A_PROVED",None
        return None,"N_A_WITHOUT_POSITIVE_EVIDENCE"
    if not isinstance(refs,list) or not refs:
        return None,"FRONT_EVIDENCE_REFS_MISSING"
    axes=front.get("decision_axes")
    if not isinstance(axes,dict) or any(a not in axes for a in SIX_AXES):
        return None,"SIX_AXIS_BOUNDING_INCOMPLETE"
    vals=[axes[a] for a in SIX_AXES]
    if "CAN_CHANGE" in vals:
        return "MATERIAL",None
    if "UNRESOLVED" in vals:
        return None,"DECISION_AXIS_UNRESOLVED"
    if vals==["NO_CHANGE_PROVEN"]*6:
        return "LOW_RISK_CLOSED",None
    return None,"INVALID_AXIS_VALUE"

def validate_material_method(front:dict)->tuple[bool,str|None]:
    receipts=front.get("method_receipts")
    if not isinstance(receipts,list) or not receipts:
        return False,"MATERIAL_METHOD_RECEIPT_MISSING"
    for r in receipts:
        if r.get("executed") is not True:
            continue
        if not r.get("method_or_capability") or not r.get("execution_id") or not r.get("subject_revision"):
            continue
        if not r.get("evidence_refs"):
            continue
        limitations=r.get("limitations") or []
        if r.get("claim_outside_supported_scope") is True:
            return False,"PROVIDER_SCOPE_UNPROVEN"
        return True,None
    return False,"MATERIAL_METHOD_RECEIPT_INVALID"

def evaluate_coverage(fixture:dict)->dict:
    fronts=fixture.get("fronts")
    if not isinstance(fronts,list) or len(fronts)!=15:
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["UNIVERSAL_LEDGER_INCOMPLETE"]}
    classified={}
    for front in fronts:
        code=front.get("front_code")
        if not code:
            return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["FRONT_CODE_MISSING"]}
        cls,reason=classify_front(front)
        if reason=="DECISION_AXIS_UNRESOLVED":
            return {"status":"RETURN_TO_EVIDENCE_ACQUISITION","reasons":[reason+":"+code]}
        if reason:
            return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":[reason+":"+code]}
        classified[code]=cls
        if cls=="MATERIAL":
            ok,why=validate_material_method(front)
            if not ok:
                if why=="PROVIDER_SCOPE_UNPROVEN":
                    return {"status":"RETURN_TO_EVIDENCE_ACQUISITION","reasons":[why+":"+code]}
                return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":[why+":"+code]}
    items=[]
    existing=[]
    for raw in fixture.get("items",[]):
        out=classify_item(raw,existing)
        rec={**raw,**out}
        items.append(rec)
        if out["item_type"] in {"DEFECT","GAP"}:
            existing.append(rec)
    if any(i["item_type"]=="EVIDENCE_REQUIREMENT" and i.get("decision_bearing",True) for i in items):
        return {"status":"RETURN_TO_EVIDENCE_ACQUISITION","reasons":["DECISION_BEARING_EVIDENCE_REQUIREMENT"],"items":items,"classified":classified}
    if any(i["item_type"]=="DUPLICATE" and not i.get("canonical_finding_id") for i in items):
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["DUPLICATE_WITHOUT_CANONICAL_FINDING"],"items":items}
    if fixture.get("unconsumed_reinspection_triggers"):
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["REINSPECTION_TRIGGER_NOT_CONSUMED"],"items":items}
    return {"status":"MATERIAL_FRONT_COVERAGE_PASS","reasons":[],"items":items,"classified":classified}
