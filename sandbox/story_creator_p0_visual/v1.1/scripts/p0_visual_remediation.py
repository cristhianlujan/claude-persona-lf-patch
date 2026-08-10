#!/usr/bin/env python3
from p0_visual_quality_primitives import *
from p0_visual_quality_primitives import _crop_reread,_inside,_region_box,_contains_box,_next_element_id
def finding_fingerprint(audit:dict[str,Any])->str:
    payload={"findings":audit.get("findings",[]),"audit_only":audit.get("audit_only",[]),"contradictions":audit.get("contradictions",[]),"unsupported_claims":audit.get("unsupported_claims",[]),"remediation_targets":audit.get("remediation_targets",[])};return canonical_sha(payload)
def remediate_once(image_path:Path,candidate:dict[str,Any],audit:dict[str,Any],config:dict[str,Any],cycle:int)->tuple[dict[str,Any],list[dict[str,Any]]]:
    updated=copy.deepcopy(candidate);actions=[];by_id={e.get("element_id"):e for e in updated.get("elements",[])};illustrations=[e for e in updated.get("elements",[]) if e.get("element_type")=="ILLUSTRATION"]
    for target in audit.get("remediation_targets",[]):
        code=target.get("code");eid=target.get("element_id");element=by_id.get(eid) if eid else None
        if code=="READER_UNCERTAINTY" and element is not None:
            reread=_crop_reread(image_path,element["region"],config);nonempty=[norm(r["text"]) for r in reread["readings"] if norm(r["text"])];old=norm(element.get("visible_text"));agreement=max((sim(old,text) for text in nonempty),default=0.0);inside_illustration=any(_inside(element["region"],ill["region"],6) for ill in illustrations);stable_pairs=[]
            for i,a in enumerate(nonempty):
                for b in nonempty[i+1:]:
                    if sim(a,b)>=.82:stable_pairs.append((a,b))
            if inside_illustration and (agreement<.75 or not stable_pairs):
                remove_element(updated,eid);actions.append({"cycle":cycle,"target":target,"action":"REMOVE_UNSUPPORTED_LOW_CONFIDENCE_TEXT","old_text":element.get("visible_text"),"targeted_reread":reread,"reason":"low-confidence OCR token inside a detected illustration was not corroborated by independent high-resolution rereads"});continue
            if stable_pairs:
                replacement=stable_pairs[0][0]
                if replacement and sim(old,replacement)<.75:element["visible_text"]=replacement
                element["classification"]="CONFIRMED";element["machine_resolution_status"]="RESOLVED";element["uncertainty_codes"]=[];element.pop("inference_basis",None);actions.append({"cycle":cycle,"target":target,"action":"TARGETED_HIGH_RES_REREAD_RESOLVED","targeted_reread":reread})
            else:actions.append({"cycle":cycle,"target":target,"action":"NO_SAFE_MACHINE_REPAIR","targeted_reread":reread})
        elif code=="CONTROL_SEMANTIC_TYPE_MISMATCH" and element is not None:
            green=expanded_background_green(image_path,_region_box(element["region"]));corrected="BUTTON" if green>.25 else ("INPUT" if element.get("element_type")=="BUTTON" else element.get("element_type"));old_type=element.get("element_type");element["element_type"]=corrected;element["semantic_role"]="primary_action" if corrected=="BUTTON" else "form_control";actions.append({"cycle":cycle,"target":target,"action":"CORRECT_CONTROL_SEMANTIC_TYPE_FROM_SOURCE","old_type":old_type,"new_type":corrected,"green_background_ratio":round(green,4)})
        elif code=="ICON_TEXT_CONFUSION" and element is not None:
            reread=_crop_reread(image_path,element["region"],config,tight=True);original=(element.get("visible_text") or "").strip();clean=re.sub(r"^[©®()□◇◆⚠]+\s*","",original).strip();corroborated=bool(clean) and any(norm(clean) in norm(r.get("text")) or sim(clean,r.get("text"))>=.82 for r in reread["readings"] if r.get("text"))
            if corroborated:element["visible_text"]=clean;element["classification"]="CONFIRMED";element["machine_resolution_status"]="RESOLVED";element["uncertainty_codes"]=[];actions.append({"cycle":cycle,"target":target,"action":"REMOVE_OCR_ICON_PREFIX_KEEP_CORROBORATED_TEXT","old_text":original,"new_text":clean,"targeted_reread":reread})
            else:actions.append({"cycle":cycle,"target":target,"action":"NO_SAFE_MACHINE_REPAIR","targeted_reread":reread})
        elif code=="TEXT_DISAGREEMENT" and element is not None:
            reread=_crop_reread(image_path,element["region"],config,tight=True);reads=[r["text"].strip() for r in reread["readings"] if r["text"].strip()];candidates=[]
            for i,a in enumerate(reads):
                for b in reads[i+1:]:
                    if sim(a,b)>=.90:candidates.append(a)
            if candidates:
                replacement=min(candidates,key=lambda t:(len(norm(t)),len(t)));element["visible_text"]=replacement;element["classification"]="CONFIRMED";element["machine_resolution_status"]="RESOLVED";element["uncertainty_codes"]=[];actions.append({"cycle":cycle,"target":target,"action":"TARGETED_TEXT_RECONCILIATION","targeted_reread":reread})
            else:actions.append({"cycle":cycle,"target":target,"action":"NO_SAFE_MACHINE_REPAIR","targeted_reread":reread})
        elif code in {"AUDIT_ONLY_CONTROL","AUDIT_ONLY_CHECKBOX","AUDIT_ONLY_PROGRESS","CONTROL_ICON_CHILD_MISSING"}:
            region=target.get("region")
            if not isinstance(region,dict):actions.append({"cycle":cycle,"target":target,"action":"NO_SAFE_MACHINE_REPAIR"});continue
            form=next((e for e in updated.get("elements",[]) if e.get("element_type")=="CONTAINER" and e.get("semantic_role")=="form_card"),None);parent_id=target.get("parent_id") or (form.get("element_id") if form else next((e.get("element_id") for e in updated.get("elements",[]) if e.get("element_type")=="SCREEN"),None))
            if code=="AUDIT_ONLY_CONTROL":green=expanded_background_green(image_path,_region_box(region));etype="BUTTON" if green>.25 else "INPUT";role="primary_action" if etype=="BUTTON" else "form_control"
            elif code=="AUDIT_ONLY_CHECKBOX":etype,role="CHECKBOX","consent_control"
            elif code=="AUDIT_ONLY_PROGRESS":etype,role="PROGRESS_INDICATOR","progress_segment"
            else:etype,role="ICON","control_icon"
            eid=add_source_grounded_element(updated,region=region,element_type=etype,parent_id=parent_id,source_image_ref=updated["source_image_refs"][0],role=role,source_observation_ref=f"J00:{audit.get('execution_id')}:{code}");actions.append({"cycle":cycle,"target":target,"action":"ADD_AUDIT_ONLY_SOURCE_GROUNDED_ELEMENT","element_id":eid,"element_type":etype})
        elif code=="CHECKBOX_TEXT_CONFUSION" and element is not None:remove_element(updated,element["element_id"]);actions.append({"cycle":cycle,"target":target,"action":"REMOVE_CHECKBOX_AS_TEXT_HALLUCINATION"})
        elif code=="UNSUPPORTED_CLAIM_RECONCILE" and element is not None:remove_element(updated,element["element_id"]);actions.append({"cycle":cycle,"target":target,"action":"REMOVE_UNSUPPORTED_READER_CLAIM"})
        elif code=="STRUCTURE_REBUILD_REQUIRED":rebuild_hierarchy(updated);actions.append({"cycle":cycle,"target":target,"action":"REBUILD_VISUAL_CONTAINMENT_FROM_SOURCE_GEOMETRY"})
        else:actions.append({"cycle":cycle,"target":target,"action":"NO_SAFE_MACHINE_REPAIR"})
    updated["execution_id"]=f"{candidate.get('execution_id','reader')}-R{cycle}";updated["created_at"]=now_iso();return updated,actions
def counts_from(candidate:dict[str,Any],audit:dict[str,Any])->dict[str,int]:
    elements=candidate.get("elements",[]);return {"consolidated_elements":len(elements),"confirmed":sum(1 for e in elements if e.get("classification")=="CONFIRMED"),"inferred":sum(1 for e in elements if e.get("classification")=="INFERRED"),"not_observable":sum(1 for e in elements if e.get("classification")=="NOT_OBSERVABLE"),"audit_only":len(audit.get("audit_only",[])),"reader_only":len(audit.get("reader_only",[])),"contradictions":len(audit.get("contradictions",[])),"unsupported_claims":len(audit.get("unsupported_claims",[])),"critical_omissions":sum(1 for x in audit.get("audit_only",[]) if x.get("material")),"noncritical_omissions":sum(1 for x in audit.get("audit_only",[]) if not x.get("material")),"unresolved_critical_uncertainties":sum(1 for e in elements if e.get("machine_resolution_status")=="REMEDIATION_REQUIRED" and e.get("criticality_ref")),"pending_remediations":len(audit.get("remediation_targets",[]))}
