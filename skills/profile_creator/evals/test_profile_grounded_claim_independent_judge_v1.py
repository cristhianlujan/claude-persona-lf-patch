#!/usr/bin/env python3
import copy,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(R/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha
from profile_grounded_claim_independent_judge_v1 import audit_grounded_rationale
cases={x["case_id"]:x for x in json.loads((R/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json").read_text())["cases"]}
plans={x["case_id"]:x["stages"][-1] for x in json.loads((R/"pe_causal_disruptive_consumption_v1.json").read_text())["cases"]}
methods={x["case_id"]:x["stages"][-1] for x in json.loads((R/"pe_causal_disruptive_method_raw_v1.json").read_text())["cases"]}
count=0
for cid,case in cases.items():
 x=plans[cid];mr=methods[cid];rec=mr["receipt"]
 plan={"status":"TEST_ONLY_RECONCILED","method_receipt_sha256":x["receipt"],
       "recommended_action":x["reconciled_action"],"falsified_hypotheses":x["falsified_hypotheses"],
       "causality_proven":False}
 b={"verification_state":"VERIFIED","candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V1",
       "result":mr["hypothesis_report"]}
 v=lambda x: x==plan and rec["receipt_sha256"]==_sha({k:v for k,v in rec.items() if k!="receipt_sha256"}) and rec["result_sha256"]==_sha(b)
 ans=independently_compile_grounded_answer(case,plan,verify_method_receipt=v)
 positive=audit_grounded_rationale(case,ans)
 assert positive["status"]=="TEST_ONLY_CONSTRAINED_SEMANTIC_PASS",(cid,positive)
 count+=1
 variants=[]
 bad=copy.deepcopy(ans);bad["claims"][0]["text"]="La réplica definitivamente está desactualizada"
 variants.append(bad)
 bad=copy.deepcopy(ans);bad["claims"][0]["evidence_refs"]=["fixture-verified://invalid"]
 variants.append(bad)
 bad=copy.deepcopy(ans);bad["causality_proven"]=True
 variants.append(bad)
 bad=copy.deepcopy(ans);bad["final_text"]+=" Causa definitiva."
 variants.append(bad)
 bad=copy.deepcopy(ans);bad["recommended_action"]="INVESTIGATE_H1"
 variants.append(bad)
 for mutated in variants:
  judge=audit_grounded_rationale(case,mutated)
  assert judge["status"]=="BLOCKED",(cid,judge)
  count+=1
print("PASS_INDEPENDENT_CONSTRAINED_SEMANTIC_JUDGE",count,"external_assurance_NOT_EXECUTED")
