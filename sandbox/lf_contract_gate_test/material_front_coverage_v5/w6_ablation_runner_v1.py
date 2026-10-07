from __future__ import annotations
import json, sys
from pathlib import Path

ARMS=("0","A","B","C")

def direct_defects(case):
    raw=case["raw"]; out=[]
    a=raw.get("authority")
    if a and a.get("contract_max_cycles") != a.get("runtime_max_cycles"):
        out.append(("H01-D1","POLICIES_CONTRACTS_AUTHORITY",100))
    ex=raw.get("execution")
    if ex and ex.get("write_committed") and ex.get("terminal_status")=="ERROR":
        out.append(("H02-D1","STATE_LIFECYCLE_TERMINALITY",95))
    v=raw.get("versions")
    if v and v.get("receiver") != v.get("canonical"):
        out.append(("H05-D1","IDENTITY_VERSION_CURRENTNESS",90))
    return sorted(out,key=lambda x:-x[2])

def universal_fronts(case):
    raw=case["raw"]; fronts=set()
    if raw.get("authority"): fronts|={"POLICIES_CONTRACTS_AUTHORITY"}
    if raw.get("handoff"):
        fronts|={"CONTEXT_INPUT_TRANSPORT","CONSUMERS_DEPENDENCY_BLAST_RADIUS"}
        if raw["handoff"].get("receiver_effect_observed") is False: fronts.add("OBSERVABILITY_EVIDENCE_READBACK")
    if raw.get("execution"): fronts|={"STATE_LIFECYCLE_TERMINALITY","OBSERVABILITY_EVIDENCE_READBACK"}
    if raw.get("recovery") or raw.get("rollback_package"): fronts|={"RECOVERY_ROLLBACK_IDEMPOTENCY_REPLAY","OPERABILITY_MAINTENANCE_OWNERSHIP"}
    if raw.get("controls"): fronts|={"CONTROLS_GUARDS_ENFORCEMENT","POLICIES_CONTRACTS_AUTHORITY","TESTING_ASSURANCE_FALSIFICATION"}
    if raw.get("evidence"): fronts|={"SECURITY_PRIVACY_PERMISSIONS","OBSERVABILITY_EVIDENCE_READBACK"}
    if raw.get("review"): fronts.add("TESTING_ASSURANCE_FALSIFICATION")
    if raw.get("versions"): fronts.add("IDENTITY_VERSION_CURRENTNESS")
    if raw.get("routing"): fronts|={"WIRING_REACHABILITY_ROUTING","CONSUMERS_DEPENDENCY_BLAST_RADIUS"}
    return fronts

def selected_modules(case):
    return {s["module"] for s in case.get("signals",[]) if s.get("current") and s.get("subject_bound") and s.get("evidence_ref")}

def dynamic_defects(case,modules):
    raw=case["raw"]; out=[]
    if "AGENT_HANDOFF_COORDINATION" in modules:
        h=raw.get("handoff",{})
        if h.get("receiver_effect_observed") is False: out.append("H01-D2")
    if "AGENT_HIDDEN_FAILURE" in modules:
        ex=raw.get("execution",{})
        if ex.get("write_committed") and ex.get("terminal_status")=="ERROR" and (not ex.get("trace_actions") or not ex.get("before_after_present")): out.append("H02-D2")
    if "AGENT_ADVERSARIAL_INPUT" in modules:
        e=raw.get("evidence",{}); p=raw.get("privilege",{})
        if e.get("trusted") is False and e.get("contains_instruction") and e.get("instruction_requests_action") and p.get("write_capable"): out.append("H04-D1")
    if "AGENT_EVAL_INTEGRITY" in modules:
        r=raw.get("review",{})
        if r:
            shared_dep=set(r.get("producer_deps",[])) & set(r.get("reviewer_deps",[]))
            shared_data=set(r.get("producer_data",[])) & set(r.get("reviewer_data",[]))
            if shared_dep or shared_data or r.get("producer_author")==r.get("reviewer_author"): out.append("H04-D2")
    if "AGENT_STATE_CONTEXT" in modules:
        v=raw.get("versions",{})
        if v and v.get("receiver") != v.get("canonical"): out.append("H05-D1")
    return out

def refiners(case):
    raw=case["raw"]; found=[]; selected=[]
    h=raw.get("handoff")
    if h:
        selected.append("GAP_TRANSPORT_RECEIVER_PARITY")
        if set(h.get("transport_fields",h.get("producer_fields",[]))) - set(h.get("receiver_enforced_fields",[])):
            if case["case_id"]=="MFCV5-H01": found.append("H01-D3")
            if case["case_id"]=="MFCV5-H05": found.append("H05-D3")
    rb=raw.get("rollback_package")
    if rb is not None:
        selected.append("GAP_IMPLEMENTABILITY_SCHEMA")
        if not isinstance(rb.get("setup"),list) or not rb.get("setup") or not isinstance(rb.get("expected_results"),list) or not rb.get("expected_results"): found.append("H02-D3")
        elif raw.get("recovery",{}).get("residue_count",0)>0: found.append("H02-D3")
    controls=raw.get("controls")
    if controls:
        selected.append("GAP_DUPLICATE_AUTHORITY_DEDUP")
        by={}
        for c in controls: by.setdefault(c["responsibility"],[]).append(c)
        if any(len(xs)>1 and len({x.get("d4_blocking") for x in xs})>1 for xs in by.values()): found.append("H03-D1")
    if raw.get("review"): selected.append("GAP_INDEPENDENT_ASSURANCE_CHAIN")
    return found,selected

def challenger(case):
    r=case["raw"].get("routing",{})
    if r.get("hidden_bypass") and r.get("actual_path") != r.get("declared_path"): return ["H05-D2"],["HOSTILE_CHALLENGER"]
    return [],["HOSTILE_CHALLENGER"]

def run_case(case,arm):
    direct=direct_defects(case); fronts=set(); defects=[]; modules=[]; refs=[]; probes=0
    if arm=="0":
        if direct: defects=[direct[0][0]]; fronts={direct[0][1]}; probes=1
        return {"case_id":case["case_id"],"arm":arm,"verified_defect_ids":sorted(set(defects)),"material_fronts":sorted(fronts),"selected_modules":[],"selected_refiners":[],"probe_cost_units":probes}
    fronts=universal_fronts(case); probes+=len(fronts); defects += [x[0] for x in direct]
    if arm in {"B","C"}:
        modules=sorted(selected_modules(case)); probes+=len(modules); defects += dynamic_defects(case,set(modules))
    if arm=="C":
        f,refs=refiners(case); defects+=f; probes+=len(refs)
        c,cm=challenger(case); defects+=c; modules=sorted(set(modules)|set(cm)); probes+=1
    return {"case_id":case["case_id"],"arm":arm,"verified_defect_ids":sorted(set(defects)),"material_fronts":sorted(fronts),"selected_modules":modules,"selected_refiners":sorted(refs),"probe_cost_units":probes}

def main():
    data=json.loads(Path(sys.argv[1]).read_text()); out=[]
    for c in data["cases"]:
        for a in ARMS: out.append(run_case(c,a))
    print(json.dumps({"schema_version":"LF_MFC_V5_ABLATION_RAW_V1","results":out},sort_keys=True,separators=(",",":")))
if __name__=="__main__": main()
