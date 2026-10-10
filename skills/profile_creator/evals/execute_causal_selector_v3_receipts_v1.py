#!/usr/bin/env python3
"""Actual selector-V3 execution over existing known synthetic cases. Not authority."""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
ASSETS=ROOT/"sandbox/lf_contract_gate_test/transversal_assets"
sys.path.insert(0,str(ASSETS/"capability_selector"))
from capability_selector_v3 import compose_capabilities_v3
CASES=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
REG=ASSETS/"method_pack_registry/method_pack_registry_v2.json"
OUT=ROOT/"pe_causal_v3_selector_real_receipts_v1.json"
def digest(x):
 return hashlib.sha256(json.dumps(x,sort_keys=True,ensure_ascii=False,separators=(",",":")).encode()).hexdigest()
def main():
 assert not OUT.exists()
 corpus=json.loads(CASES.read_text())
 reg=json.loads(REG.read_text())
 assert reg["execution_permission"] is False
 receipts=[]
 for c in corpus["cases"]:
  assert len(c["hypotheses"])>=2
  source_refs=[o["evidence_ref"] for o in c["observations"]]
  assert source_refs
  context={"causal_requirement":"HIGH","budget":{"max_method_cost_points":2},"selection_cycle":0}
  pre={"evidence_sufficiency":{"value":"SUFFICIENT","verification_state":"VERIFIED",
      "evidence_refs":["fixture://verified-corpus:"+digest({"case_id":c["case_id"],"refs":source_refs})]}}
  selection=compose_capabilities_v3(context,[],{"fallback_capabilities":[]},reg,pre)
  assert [m["method_id"] for m in selection["selected_methods"]]==["CAUSAL_ANALYSIS"]
  assert selection["execution_authorized"] is False and selection["admission_required"] is True
  assert len(selection["selected_methods"])==1
  receipts.append({"case_id":c["case_id"],"method_id":"CAUSAL_ANALYSIS",
     "selection":selection,"selection_sha256":digest(selection),
     "input_context_sha256":digest(context),"input_preconditions_sha256":digest(pre),
     "source_evidence_refs":source_refs,
     "method_execution":"NOT_EXECUTED",
     "source_registry_execution_permission":False})
 doc={"schema":"PE_SELECTOR_V3_REAL_SELECTION_RECEIPTS_V1",
      "status":"FROZEN_NON_AUTHORITY_SELECTION",
      "corpus_sha256":hashlib.sha256(CASES.read_bytes()).hexdigest(),
      "registry_sha256":hashlib.sha256(REG.read_bytes()).hexdigest(),
      "count":len(receipts),"receipts":receipts,
      "actual_selector_version":"V3_DEVELOPMENT",
      "selector_calls":len(receipts),"method_invocations":0,
      "authority_activation":False,"cutover_eligible":False}
 OUT.write_text(json.dumps(doc,ensure_ascii=False,sort_keys=True,indent=2)+"\n")
 print(json.dumps({"status":doc["status"],"selector_calls":doc["selector_calls"],
      "verified_selected_methods":[r["method_id"] for r in receipts],
      "raw_sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()},sort_keys=True))
if __name__=="__main__":main()
