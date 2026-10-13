from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(R/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha
cases={x["case_id"]:x for x in json.loads((R/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json").read_text())["cases"]}
plans={x["case_id"]:x["stages"][-1] for x in json.loads((R/"pe_causal_disruptive_consumption_v1.json").read_text())["cases"]}
methods={x["case_id"]:x["stages"][-1] for x in json.loads((R/"pe_causal_disruptive_method_raw_v1.json").read_text())["cases"]}
n=0
for cid,case in cases.items():
  step=plans[cid]
  plan={"status":"TEST_ONLY_RECONCILED","method_receipt_sha256":step["receipt"],"falsified_hypotheses":step["falsified_hypotheses"],"recommended_action":step["reconciled_action"],"causality_proven":False}
  rec=methods[cid]["receipt"]
  out=methods[cid]["hypothesis_report"]
  actual={"verification_state":"VERIFIED","candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V1","result":out}
  def source_verified(p):
    return (p==plan and rec["receipt_sha256"]==p["method_receipt_sha256"] and
            rec["receipt_sha256"]==_sha({k:v for k,v in rec.items() if k!="receipt_sha256"}) and
            rec["result_sha256"]==_sha(actual) and rec["result_state"]=="EXECUTED_VERIFIED")
  result=independently_compile_grounded_answer(case,plan,verify_method_receipt=source_verified)
  assert result["status"]=="TEST_ONLY_EVIDENCE_COMPILED",(cid,result)
  assert result["recommended_action"]==step["reconciled_action"]
  assert all(x["evidence_refs"] for x in result["claims"])
  assert result["causality_proven"] is False
  n+=1
  if cid=="PE-CAUS-06":
    assert "replica is stale" not in result["final_text"].lower()
    assert any(x["type"]=="EVIDENCE_GAP" and x["probe_id"]=="REPLICA_VALID" for x in result["claims"])
    n+=1
  mismatch=dict(plan,recommended_action="INVESTIGATE_H1")
  blocked=independently_compile_grounded_answer(case,mismatch,verify_method_receipt=lambda p:p==mismatch)
  assert blocked["status"]=="BLOCKED"
  n+=1
  blocked=independently_compile_grounded_answer(case,plan,verify_method_receipt=None)
  assert blocked["blocking_code"]=="EXTERNAL_METHOD_RECEIPT_VERIFIER_REQUIRED"
  n+=1
  blocked=independently_compile_grounded_answer(case,plan,verify_method_receipt=lambda p:p==plan,proposed_claim_ids=["UNKNOWN"])
  assert blocked["blocking_code"]=="MODEL_REFERENCES_UNSUPPORTED_CLAIMS"
  n+=1
print("GROUNDED_CLAIM_COMPILER_TEST_PASS",n)
