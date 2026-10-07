from __future__ import annotations
import json,sys
from pathlib import Path

def select(signals):
    scores={}; weak={}
    for s in signals:
        if not s.get("current") or not s.get("subject_bound") or not s.get("evidence_ref"): continue
        m=s.get("module")
        if s.get("directness")=="DIRECT": scores[m]=scores.get(m,0)+2
        elif s.get("directness")=="INDIRECT":
            g=(s.get("provider"),s.get("authority_ref"),s.get("source_subject_digest"))
            if all(g): weak.setdefault(m,set()).add(g)
    for m,gs in weak.items(): scores[m]=scores.get(m,0)+len(gs)
    return {m for m,v in scores.items() if v>=2}

def dynamic(raw,mods):
    out=[]
    if "AGENT_ACTION_SIDE_EFFECT" in mods:
        w=raw.get("write_path",{})
        if w.get("write_capable") and w.get("write_committed") and (not w.get("safe_change_admission_verified") or not w.get("rollback_receipt_verified")):
            out.append("UNSAFE_SIDE_EFFECT_ADMISSION_MISSING")
    if "AGENT_IDENTITY_PRIVILEGE" in mods:
        i=raw.get("identity",{})
        if i.get("before_role")!=i.get("after_role") and not i.get("authority_receipt_verified"):
            out.append("UNAUTHORIZED_PRIVILEGE_ESCALATION")
    if "AGENT_BLAST_RADIUS" in mods:
        d=raw.get("dependency",{})
        new=set(d.get("candidate_consumers",[]))-set(d.get("baseline_consumers",[]))
        receipts=set(d.get("closure_receipts",[]))
        if any(d.get("consumer_impacts",{}).get(x)=="MATERIAL" and x+":CLOSED" not in receipts for x in new):
            out.append("NEW_MATERIAL_CONSUMER_UNCLOSED")
    if "AGENT_LONG_HORIZON_RECOVERY" in mods:
        w=raw.get("workflow",{})
        total=w.get("steps_total",0); cps=set(w.get("checkpoints",[]))
        if total and (cps!=set(range(1,total+1)) or not w.get("resume_receipt_verified")):
            out.append("RECOVERY_CHECKPOINT_GAP")
    return out

def refiners(raw):
    out=[]
    refs=raw.get("evidence_refs",[])
    if any(x.get("decision_bearing") and (not x.get("resolved") or not x.get("current")) for x in refs):
        out.append("MATERIAL_EVIDENCE_REF_UNRESOLVED")
    return out

def run(case,arm):
    mods=select(case.get("signals",[]))
    findings=[]
    if arm in {"B","C"}: findings+=dynamic(case["raw"],mods)
    if arm=="C": findings+=refiners(case["raw"])
    return {"case_id":case["case_id"],"arm":arm,"selected_modules":sorted(mods) if arm in {"B","C"} else [],"findings":sorted(set(findings))}

def main():
    data=json.loads(Path(sys.argv[1]).read_text()); out=[]
    for c in data["cases"]:
        for arm in ("A","B","C"): out.append(run(c,arm))
    print(json.dumps({"schema_version":"LF_MFC_V5_W7_TARGETED_RAW_V1","results":out},sort_keys=True,separators=(",",":")))
if __name__=="__main__": main()
