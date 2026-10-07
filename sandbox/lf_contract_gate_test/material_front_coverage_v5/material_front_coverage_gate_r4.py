from __future__ import annotations

SIX_AXES=("root_cause","repair_topology","blast_radius","acceptance_criteria","rollback_recovery","terminality_lifecycle")
INDEPENDENT_ORIGINS={"OBSERVED_LIVE","CANONICAL_AUTHORITY","EXECUTED_TEST","RECEIVER_READBACK"}

def has_independent_origin(origins):
    return bool(set(origins or []) & INDEPENDENT_ORIGINS)

def semantic_duplicate(item, existing):
    keys=("bad_boundary","violated_invariant","observed_effect","repair_implication")
    return all(item.get(k) is not None and item.get(k)==existing.get(k) for k in keys)

def classify_item(item, existing_findings):
    if item.get("future_probe_needed") is True or item.get("subject_bound") is not True:
        return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}
    origins=item.get("verification_origins") or []
    if not has_independent_origin(origins):
        return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}
    for existing in existing_findings:
        if existing.get("item_type") in {"DEFECT","GAP"} and semantic_duplicate(item,existing):
            return {"item_type":"DUPLICATE","canonical_finding_id":existing.get("finding_id")}
    if item.get("positive_incorrect_condition") is True:
        return {"item_type":"DEFECT","canonical_finding_id":None}
    if item.get("required_element_exists") is True and item.get("required_element_absent") is True:
        return {"item_type":"GAP","canonical_finding_id":None}
    return {"item_type":"EVIDENCE_REQUIREMENT","canonical_finding_id":None}

def valid_material_link(front, axis):
    links=(front.get("decision_link_refs") or {}).get(axis) or []
    for link in links:
        if isinstance(link,dict) and link.get("ref") and has_independent_origin(link.get("verification_origins")):
            return True
    return False

def classify_front(front):
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
    can=[a for a in SIX_AXES if axes[a]=="CAN_CHANGE"]
    if can:
        if all(valid_material_link(front,a) for a in can):
            return "MATERIAL",None
        return None,"MATERIAL_DECISION_LINK_UNPROVEN"
    if "UNRESOLVED" in vals:
        return None,"DECISION_AXIS_UNRESOLVED"
    if vals==["NO_CHANGE_PROVEN"]*6:
        return "LOW_RISK_CLOSED",None
    return None,"INVALID_AXIS_VALUE"

def validate_material_method(front):
    receipts=front.get("method_receipts")
    if not isinstance(receipts,list) or not receipts:
        return False,"MATERIAL_METHOD_RECEIPT_MISSING"
    for r in receipts:
        if r.get("executed") is not True: continue
        if not r.get("method_or_capability") or not r.get("execution_id") or not r.get("subject_revision"): continue
        if not r.get("evidence_refs"): continue
        if r.get("claim_outside_supported_scope") is True:
            return False,"PROVIDER_SCOPE_UNPROVEN"
        return True,None
    return False,"MATERIAL_METHOD_RECEIPT_INVALID"

def evaluate_coverage(fixture):
    cost=fixture.get("mfc_incremental_cost") or {}
    if any((cost.get(k) or 0)>0 for k in ("db_queries","file_reads","subagent_calls","external_searches")):
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["MFC_ACTIVE_INVESTIGATION_FORBIDDEN"]}
    fronts=fixture.get("fronts")
    if not isinstance(fronts,list) or len(fronts)!=15:
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["UNIVERSAL_LEDGER_INCOMPLETE"]}
    classified={}
    for front in fronts:
        code=front.get("front_code")
        if not code:
            return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["FRONT_CODE_MISSING"]}
        cls,reason=classify_front(front)
        if reason in {"DECISION_AXIS_UNRESOLVED","MATERIAL_DECISION_LINK_UNPROVEN"}:
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
    items=[]; existing=[]
    for raw in fixture.get("items",[]):
        out=classify_item(raw,existing)
        rec={**raw,**out}; items.append(rec)
        if out["item_type"] in {"DEFECT","GAP"}: existing.append(rec)
    if any(i["item_type"]=="EVIDENCE_REQUIREMENT" and i.get("decision_bearing",True) for i in items):
        return {"status":"RETURN_TO_EVIDENCE_ACQUISITION","reasons":["DECISION_BEARING_EVIDENCE_REQUIREMENT"],"items":items,"classified":classified}
    if any(i["item_type"]=="DUPLICATE" and not i.get("canonical_finding_id") for i in items):
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["DUPLICATE_WITHOUT_CANONICAL_FINDING"],"items":items}
    if fixture.get("unconsumed_reinspection_triggers"):
        return {"status":"MATERIAL_FRONT_COVERAGE_BLOCKED","reasons":["REINSPECTION_TRIGGER_NOT_CONSUMED"],"items":items}
    return {"status":"MATERIAL_FRONT_COVERAGE_PASS","reasons":[],"items":items,"classified":classified}
