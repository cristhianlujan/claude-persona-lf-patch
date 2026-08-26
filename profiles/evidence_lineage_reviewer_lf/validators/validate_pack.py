#!/usr/bin/env python3
import json, sys
from pathlib import Path

REQUIRED = [
"SKILL.md","README.md","contracts/main_contract.md","contracts/missing_input_policy.md",
"schemas/output.schema.json","schemas/missing_input.schema.json","judges/score_rubric.md","judges/mini_judge.md",
"checklists/preflight_checklist.md","checklists/priority_checklist.md","examples/good_output.json",
"examples/bad_output.json","examples/self_repair_output.json","fixtures/happy_path/input.json",
"fixtures/missing_inputs/input.json","fixtures/unsafe_or_blocked/input.json","fixtures/self_repair/bad_output.json",
"evals/eval_matrix.json","handoffs/to_quality_pack.handoff.json","adapters/github_pack_adapter.md",
"adapters/document_patch_adapter.md","references/research_to_rules_matrix.md","references/decision_matrix.md",
"manifest.json","validators/validate_pack.py"
]
STATUSES={"PASS_EVIDENCE_LINEAGE","PASS_WITH_RESTRICTIONS","RETURN_TO_SOURCE_FOR_READBACK","BLOCK_PIPELINE"}

def load(p): return json.loads(p.read_text(encoding="utf-8"))

def main():
    root=Path(sys.argv[1]) if len(sys.argv)>1 else Path.cwd()
    blocking=[]
    for rel in REQUIRED:
        if not (root/rel).exists(): blocking.append("MISSING_REQUIRED_FILE:"+rel)
    if not blocking:
        try:
            m=load(root/"manifest.json")
            if m.get("profile_pack_id")!="EVIDENCE_LINEAGE_REVIEWER_LF_V0_1": blocking.append("MANIFEST_PACK_ID_MISMATCH")
            if m.get("profile_slug")!="evidence_lineage_reviewer_lf": blocking.append("MANIFEST_SLUG_MISMATCH")
            if m.get("document_status")!="CANDIDATO": blocking.append("DOCUMENT_STATUS_MUST_BE_CANDIDATO")
            if m.get("operational_status")!="READ_ONLY": blocking.append("OPERATIONAL_STATUS_MUST_BE_READ_ONLY")
            if m.get("runtime")!="NO_HABILITADO": blocking.append("RUNTIME_MUST_BE_NO_HABILITADO")
            if m.get("automatic_impact")!="BLOQUEADO": blocking.append("AUTOMATIC_IMPACT_MUST_BE_BLOQUEADO")
            declared=set(m.get("files",[]))
            for rel in REQUIRED:
                if rel not in declared: blocking.append("MANIFEST_MISSING_DECLARATION:"+rel)
            for name in ["good_output.json","bad_output.json","self_repair_output.json"]:
                obj=load(root/"examples"/name)
                if obj.get("status") not in STATUSES: blocking.append("INVALID_EXAMPLE_STATUS:"+name)
                for key in ["claim","authority_reads","source_readbacks","revision_binding","structural_identifier_reconciliation","evidence_map","blocking_codes","next_gate"]:
                    if key not in obj: blocking.append("EXAMPLE_MISSING_FIELD:"+name+":"+key)
            matrix=load(root/"evals/eval_matrix.json")
            cases=matrix.get("cases",[])
            if len(cases)<5: blocking.append("EVAL_MATRIX_REQUIRES_MINIMUM_5_CASES")
            seen=set()
            for c in cases:
                cid=c.get("id")
                if not cid or cid in seen: blocking.append("EVAL_CASE_ID_INVALID")
                seen.add(cid)
                fixture=c.get("fixture")
                if not fixture or not (root/fixture).exists(): blocking.append("EVAL_FIXTURE_MISSING:"+str(fixture))
                if c.get("expected_status") not in STATUSES: blocking.append("EVAL_EXPECTED_STATUS_INVALID:"+str(cid))
        except Exception as exc:
            blocking.append("VALIDATION_EXCEPTION:"+str(exc))
    result={"status":"PASS" if not blocking else "FAIL","profile_pack_id":"EVIDENCE_LINEAGE_REVIEWER_LF_V0_1","blocking_codes":blocking,"runtime_authorized":False,"automatic_impact_authorized":False,"recommended_action":"READY_FOR_QUALITY_PACK" if not blocking else "RETURN_TO_WORKER_FOR_SELF_REPAIR"}
    print(json.dumps(result,indent=2))
    return 0 if not blocking else 1
if __name__=="__main__": raise SystemExit(main())
