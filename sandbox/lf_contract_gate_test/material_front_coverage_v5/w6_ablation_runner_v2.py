from __future__ import annotations
import json, sys
from pathlib import Path

ARMS=("0","A","B","C")

def review_not_independent(r):
    if not r: return False
    return bool(set(r.get("producer_deps",[])) & set(r.get("reviewer_deps",[]))
                or set(r.get("producer_data",[])) & set(r.get("reviewer_data",[]))
                or (r.get("producer_author") is not None and r.get("producer_author")==r.get("reviewer_author")))

def direct_findings(raw):
    out=[]
    a=raw.get("authority")
    if a and a.get("contract_max_cycles") != a.get("runtime_max_cycles"):
        out.append(("RUNTIME_AUTHORITY_DIVERGENCE","POLICIES_CONTRACTS_AUTHORITY",100))
    ex=raw.get("execution")
    if ex and ex.get("write_committed") and ex.get("terminal_status")=="ERROR":
        out.append(("POST_WRITE_TERMINAL_ERROR","STATE_LIFECYCLE_TERMINALITY",95))
    v=raw.get("versions")
    if v and v.get("receiver") != v.get("canonical"):
        out.append(("STALE_RECEIVER_VERSION","IDENTITY_VERSION_CURRENTNESS",90))
    return sorted(out,key=lambda x:-x[2])

def universal_sweep(raw):
    fronts=set()
    a=raw.get("authority")
    if a and a.get("contract_max_cycles") != a.get("runtime_max_cycles"):
        fronts.add("POLICIES_CONTRACTS_AUTHORITY")
    h=raw.get("handoff")
    if h:
        field_loss=set(h.get("transport_fields",h.get("producer_fields",[]))) - set(h.get("receiver_enforced_fields",[]))
        if field_loss or h.get("receiver_effect_observed") is False:
            fronts|={"CONTEXT_INPUT_TRANSPORT","CONSUMERS_DEPENDENCY_BLAST_RADIUS"}
        if h.get("receiver_effect_observed") is False:
            fronts.add("OBSERVABILITY_EVIDENCE_READBACK")
    ex=raw.get("execution")
    if ex and ex.get("write_committed") and ex.get("terminal_status")=="ERROR":
        fronts|={"STATE_LIFECYCLE_TERMINALITY","OBSERVABILITY_EVIDENCE_READBACK"}
    rec=raw.get("recovery",{})
    rb=raw.get("rollback_package")
    if rb is not None and (not isinstance(rb.get("setup"),list) or not rb.get("setup") or not isinstance(rb.get("expected_results"),list) or not rb.get("expected_results") or rec.get("residue_count",0)>0):
        fronts|={"RECOVERY_ROLLBACK_IDEMPOTENCY_REPLAY","OPERABILITY_MAINTENANCE_OWNERSHIP"}
    controls=raw.get("controls",[])
    by={}
    for c in controls: by.setdefault(c.get("responsibility"),[]).append(c)
    if any(len(xs)>1 and len({x.get("d4_blocking") for x in xs})>1 for xs in by.values()):
        fronts|={"CONTROLS_GUARDS_ENFORCEMENT","POLICIES_CONTRACTS_AUTHORITY","TESTING_ASSURANCE_FALSIFICATION"}
    e=raw.get("evidence",{}); p=raw.get("privilege",{})
    if e.get("trusted") is False and e.get("contains_instruction") and e.get("instruction_requests_action") and p.get("write_capable"):
        fronts|={"SECURITY_PRIVACY_PERMISSIONS","OBSERVABILITY_EVIDENCE_READBACK"}
    if review_not_independent(raw.get("review",{})):
        fronts.add("TESTING_ASSURANCE_FALSIFICATION")
    v=raw.get("versions")
    if v and v.get("receiver") != v.get("canonical"):
        fronts.add("IDENTITY_VERSION_CURRENTNESS")
    r=raw.get("routing",{})
    if r.get("actual_path") and r.get("declared_path") and r.get("actual_path") != r.get("declared_path"):
        fronts|={"WIRING_REACHABILITY_ROUTING","CONSUMERS_DEPENDENCY_BLAST_RADIUS"}
    return fronts

def selected_modules(signals):
    scores={}; weak_groups={}
    for s in signals:
        if not s.get("current") or not s.get("subject_bound") or not s.get("evidence_ref"): continue
        m=s.get("module")
        if not m: continue
        if s.get("directness")=="DIRECT":
            scores[m]=scores.get(m,0)+2
        elif s.get("directness")=="INDIRECT":
            g=(s.get("provider"),s.get("authority_ref"),s.get("source_subject_digest"))
            if all(g): weak_groups.setdefault(m,set()).add(g)
    for m,groups in weak_groups.items():
        scores[m]=scores.get(m,0)+len(groups)
    return {m for m,v in scores.items() if v>=2}

def dynamic_findings(raw,modules):
    out=[]
    if "AGENT_HANDOFF_COORDINATION" in modules:
        if raw.get("handoff",{}).get("receiver_effect_observed") is False:
            out.append("RECEIVER_EFFECT_UNPROVEN")
    if "AGENT_HIDDEN_FAILURE" in modules:
        ex=raw.get("execution",{})
        if ex.get("write_committed") and ex.get("terminal_status")=="ERROR" and (not ex.get("trace_actions") or not ex.get("before_after_present")):
            out.append("POST_WRITE_TRACE_LOSS")
    if "AGENT_ADVERSARIAL_INPUT" in modules:
        e=raw.get("evidence",{}); p=raw.get("privilege",{})
        if e.get("trusted") is False and e.get("contains_instruction") and e.get("instruction_requests_action") and p.get("write_capable"):
            out.append("UNTRUSTED_INSTRUCTION_ON_WRITE_PATH")
    if "AGENT_EVAL_INTEGRITY" in modules and review_not_independent(raw.get("review",{})):
        out.append("REVIEWER_NOT_INDEPENDENT")
    if "AGENT_STATE_CONTEXT" in modules:
        v=raw.get("versions",{})
        if v and v.get("receiver") != v.get("canonical"):
            out.append("STALE_RECEIVER_VERSION")
    return out

def refiner_findings(raw):
    found=[]; selected=[]
    h=raw.get("handoff")
    if h:
        selected.append("GAP_TRANSPORT_RECEIVER_PARITY")
        if set(h.get("transport_fields",h.get("producer_fields",[]))) - set(h.get("receiver_enforced_fields",[])):
            found.append("RECEIVER_FIELD_LOSS")
    rb=raw.get("rollback_package")
    rec=raw.get("recovery",{})
    if rb is not None:
        selected.append("GAP_IMPLEMENTABILITY_SCHEMA")
        if not isinstance(rb.get("setup"),list) or not rb.get("setup") or not isinstance(rb.get("expected_results"),list) or not rb.get("expected_results") or rec.get("residue_count",0)>0:
            found.append("REPAIR_PACKAGE_NOT_EXECUTABLE")
    controls=raw.get("controls",[])
    if controls:
        selected.append("GAP_DUPLICATE_AUTHORITY_DEDUP")
        by={}
        for c in controls: by.setdefault(c.get("responsibility"),[]).append(c)
        if any(len(xs)>1 and len({x.get("d4_blocking") for x in xs})>1 for xs in by.values()):
            found.append("DUPLICATE_CONTROL_DIVERGENCE")
    if raw.get("review"):
        selected.append("GAP_INDEPENDENT_ASSURANCE_CHAIN")
    return found,selected

def challenger_findings(raw):
    r=raw.get("routing",{})
    if r.get("hidden_bypass") and r.get("actual_path") != r.get("declared_path"):
        return ["HIDDEN_BYPASS_ROUTE"]
    return []

def run_case(case,arm):
    raw=case["raw"]; direct=direct_findings(raw)
    fronts=set(); findings=[]; modules=[]; refiners=[]; probes=0
    if arm=="0":
        if direct: findings=[direct[0][0]]; fronts={direct[0][1]}; probes=1
        return {"case_id":case["case_id"],"arm":arm,"semantic_findings":sorted(set(findings)),"material_fronts":sorted(fronts),"selected_modules":[],"selected_refiners":[],"probe_cost_units":probes}
    fronts=universal_sweep(raw); probes+=len(fronts); findings += [x[0] for x in direct]
    if arm in {"B","C"}:
        modules=sorted(selected_modules(case.get("signals",[]))); probes+=len(modules); findings+=dynamic_findings(raw,set(modules))
    if arm=="C":
        rf,refiners=refiner_findings(raw); findings+=rf; probes+=len(refiners)
        findings+=challenger_findings(raw); probes+=1
    return {"case_id":case["case_id"],"arm":arm,"semantic_findings":sorted(set(findings)),"material_fronts":sorted(fronts),"selected_modules":modules,"selected_refiners":sorted(refiners),"probe_cost_units":probes}

def main():
    data=json.loads(Path(sys.argv[1]).read_text()); results=[]
    for case in data["cases"]:
        for arm in ARMS: results.append(run_case(case,arm))
    print(json.dumps({"schema_version":"LF_MFC_V5_ABLATION_RAW_V2","results":results},sort_keys=True,separators=(",",":")))
if __name__=="__main__": main()
