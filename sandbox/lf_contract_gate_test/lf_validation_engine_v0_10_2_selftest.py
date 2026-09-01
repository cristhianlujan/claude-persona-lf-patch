#!/usr/bin/env python3
"""LF Validation Engine Python Local v0.10.2 — sandbox self-test."""
from __future__ import annotations
import copy, hashlib, json, subprocess, sys
from pathlib import Path
from typing import Any, Dict
ALLOWED_OPERATION_TYPES={"CREACION_ACTIVO_LF","REPARACION_ACTIVO_LF","ACTUALIZACION_CAPACIDAD_ACTIVO_LF","PROMOCION_ACTIVO_READ_ONLY_LF","AUDITORIA_READ_ONLY_LF","SANDBOX_SIMULATION_LF","VALIDATION_ENGINE_TEST_LF"}; ALLOWED_FINAL_RESULTS={"PASS","FAIL","BLOCKED_WITH_OBSERVATIONS","RETURN_TO_WORKER"}; ALLOWED_JUDGE_RESULTS={"PASS","FAIL","BLOCKED","PASS_WITH_RESTRICTIONS","NOT_RUN"}; ALLOWED_NA_REASONS={"NOT_APPLICABLE_BY_OPERATION_TYPE","DEFERRED_BY_APPROVED_SCOPE","BLOCKED_BY_DEPENDENCY","READ_ONLY_AUDIT_ONLY"}; HASH64=set("0123456789abcdef")
def canonical_json(data): return json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(",",":"))
def compute_hash(proof):
 d=copy.deepcopy(proof); d.setdefault("verification",{}); d["verification"]["verification_hash"]=""; return hashlib.sha256(canonical_json(d).encode()).hexdigest()
def gp(data,path,default=None):
 cur=data
 for part in path.split("."):
  if not isinstance(cur,dict) or part not in cur:return default
  cur=cur[part]
 return cur
def is_sha256(v): return isinstance(v,str) and len(v)==64 and all(c in HASH64 for c in v)
def src_ref_ok(r): return isinstance(r,dict) and r.get("source_type") and r.get("source_id") and r.get("source_sha_or_row_id")
def ev_ref_ok(r): return isinstance(r,dict) and r.get("id") and r.get("hash_referencia")
def validate(p):
 f=[]; req=["schema_version","context_integrity_ref.source_event_id","context_integrity_ref.source_snapshot_version","context_integrity_ref.context_hash","operation_type","operation_code","execution_id","actor.actor_type","actor.actor_id","actor.producer_validator_separated","target_asset.asset_code","target_asset.asset_type","phase","step.step_order","step.step_id","step.is_canonical","protocol.protocol_id","protocol.max_canonical_step","judge.judge_result","result.final_result","result.clean_pass_allowed","result.closure_allowed","result.promotion_allowed","readback.required","readback.performed","verification.hash_algorithm","verification.verification_hash"]
 for x in req:
  if gp(p,x) is None:f.append("MISSING_FIELD:"+x)
 if gp(p,"operation_type") not in ALLOWED_OPERATION_TYPES:f.append("FAIL_OPERATION_TYPE_NOT_REGISTERED")
 if gp(p,"result.final_result") not in ALLOWED_FINAL_RESULTS:f.append("FAIL_INVALID_FINAL_RESULT_ENUM")
 if gp(p,"judge.judge_result") not in ALLOWED_JUDGE_RESULTS:f.append("FAIL_INVALID_JUDGE_RESULT_ENUM")
 if gp(p,"actor.producer_validator_separated") is not True:f.append("FAIL_PRODUCER_VALIDATOR_NOT_SEPARATED")
 if gp(p,"verification.hash_algorithm")!="SHA-256":f.append("FAIL_INVALID_HASH_ALGORITHM")
 if gp(p,"context_integrity_ref.context_hash") and not is_sha256(gp(p,"context_integrity_ref.context_hash")):f.append("FAIL_CONTEXT_HASH_INVALID")
 if not isinstance(p.get("source_refs"),list) or not p.get("source_refs"):f.append("FAIL_SOURCE_REFS_EMPTY")
 elif not all(src_ref_ok(r) for r in p["source_refs"]):f.append("FAIL_SOURCE_REF_WEAK")
 if not isinstance(p.get("assertions_checked"),list) or not p.get("assertions_checked"):f.append("FAIL_ASSERTIONS_EMPTY")
 if not isinstance(p.get("hard_fails_checked"),list) or not p.get("hard_fails_checked"):f.append("FAIL_HARD_FAILS_EMPTY")
 so=gp(p,"step.step_order",999999); ms=gp(p,"protocol.max_canonical_step",-1)
 if gp(p,"step.is_canonical") is not True or not isinstance(so,int) or so>ms:f.append("FATAL_NON_CANONICAL_STEP")
 if gp(p,"result.final_result")=="PASS" and (gp(p,"result.clean_pass_allowed") is not True or gp(p,"result.closure_allowed") is not True):f.append("FAIL_MANIFEST_BLOCKED_BUT_PASS_ATTEMPTED")
 if gp(p,"result.final_result")=="PASS" and gp(p,"result.promotion_allowed") is True:f.append("FAIL_PROMOTION_ATTEMPTED_WITHOUT_SEPARATE_OPERATION")
 for a in p.get("assertions_checked",[]) if isinstance(p.get("assertions_checked"),list) else []:
  if a.get("status") in {"FAIL","BLOCKED"} and gp(p,"result.final_result")=="PASS":f.append("FAIL_ASSERTION_BAD_BUT_PASS")
  if not ev_ref_ok(a.get("evidence_ref")):f.append("FAIL_ASSERTION_EVIDENCE_WEAK")
 for h in p.get("hard_fails_checked",[]) if isinstance(p.get("hard_fails_checked"),list) else []:
  if h.get("triggered") is True and gp(p,"result.final_result")=="PASS":f.append("FAIL_HARD_FAIL_TRIGGERED_BUT_PASS")
  if not ev_ref_ok(h.get("evidence_ref")):f.append("FAIL_HARD_FAIL_EVIDENCE_WEAK")
 if gp(p,"readback.required") is True:
  refs=gp(p,"readback.readback_refs",[])
  if gp(p,"readback.performed") is not True:f.append("FAIL_READBACK_REQUIRED_NOT_PERFORMED")
  if not isinstance(refs,list) or not refs:f.append("FAIL_READBACK_REFS_MISSING")
  for r in refs if isinstance(refs,list) else []:
   if not isinstance(r,dict):f.append("FAIL_READBACK_NARRATIVE_NOT_STRUCTURED")
   elif not src_ref_ok(r):f.append("FAIL_READBACK_REF_WEAK")
 if gp(p,"verification.verification_hash")!=compute_hash(p):f.append("FATAL_VERIFICATION_HASH_MISMATCH")
 f=sorted(set(f)); return {"status":"PASS" if not f else ("FAIL" if any(x.startswith("FATAL") for x in f) else "RETURN_TO_WORKER"),"fail_codes":f}
def base_proof():
 src={"source_type":"SUPABASE_ROW","source_id":"public.lf_eventos.id=38","source_sha_or_row_id":"38"}; ev={"id":"EV-PROOF-001","hash_referencia":hashlib.sha256(b"evidence").hexdigest()}; p={"schema_version":"PROOF_OBJECT_SCHEMA_LF_v0.2_DRAFT","context_integrity_ref":{"source_event_id":38,"source_snapshot_version":"v0.8_consolidado","context_hash":hashlib.sha256(b"lf-context-v0.10.2").hexdigest()},"operation_type":"VALIDATION_ENGINE_TEST_LF","operation_code":"PYTHON_LOCAL_VALIDATION_ENGINE_TEST","execution_id":"EXEC-LF-PY-VALIDATION-001","actor":{"actor_type":"LLM","actor_id":"chatgpt","producer_validator_separated":True},"target_asset":{"asset_code":"PLAN_GOV_SECURITY_PROFILE_CARDS_CORRECCION_ORIGEN_LF","asset_type":"PLAN"},"phase":"E","step":{"step_order":29,"step_id":"report_output","is_canonical":True},"protocol":{"protocol_id":"PROTOCOLO_TEST_LF","max_canonical_step":29},"source_refs":[src],"judge":{"judge_result":"PASS"},"result":{"final_result":"PASS","clean_pass_allowed":True,"closure_allowed":True,"promotion_allowed":False},"assertions_checked":[{"assertion_id":"A001","status":"PASS","evidence_ref":ev}],"hard_fails_checked":[{"hard_fail_id":"HF001","triggered":False,"evidence_ref":ev}],"na_controls":[],"readback":{"required":True,"performed":True,"readback_refs":[src]},"verification":{"hash_algorithm":"SHA-256","verification_hash":""}}; p["verification"]["verification_hash"]=compute_hash(p); return p
def with_hash(p):p["verification"]["verification_hash"]=compute_hash(p);return p
def validate_learning_behavioral_readiness_manifest(root):
 path=root/"learning_behavioral_readiness_v1.json"
 if not path.exists():return
 d=json.loads(path.read_text()); assert d["schema"]=="LF_LEARNING_BEHAVIORAL_READINESS_V1" and d["mode"]=="READ_ONLY" and d["rule"]=="UNRELATED_SCREEN_READINESS_RUNS_MUST_NOT_BE_REUSED_AS_CONSUMER_AUTHORITY" and d["automatic_promotion"] is False and d["production_authorized"] is False
 assert {r["consumer_id"] for r in d["consumer_targets"]}=={"PERFIL-PRODUCT-DIRECTOR-LF","PERFIL-UI-ARCHITECT"}; assert all(r["exact_target_bound_readiness_receipt_observed"] is False and r["behavioral_ab_status"]=="INSUFFICIENT_EVIDENCE" for r in d["consumer_targets"]); print("LEARNING_BEHAVIORAL_READINESS=PASS consumers=2/2 behavioral_ab=INSUFFICIENT_EVIDENCE")
def run_optional_learning_suites():
 root=Path(__file__).resolve().parent; scripts=["validate_product_director_learning_suite_v1.py","validate_ui_architect_learning_suite_v1.py","validate_learning_cluster_consumer_coverage_v1.py","validate_learning_next_consumer_applicability_v1.py","validate_learning_additional_consumer_applicability_v1.py","validate_learning_unbound_cluster_card_readback_v1.py","validate_learning_exact_nonbinding_guard_v1.py","validate_learning_additional_consumer_binding_candidates_v1.py","validate_learning_additional_consumer_context_pack_candidates_v1.py","validate_learning_specialized_consumer_authority_guard_v1.py","validate_learning_specialized_consumer_authority_negative_cases_v1.py","validate_learning_readonly_technical_closure_v1.py"]
 executed=0
 for s in scripts:
  p=root/s
  if not p.exists():continue
  r=subprocess.run([sys.executable,str(p)],capture_output=True,text=True)
  if r.stdout:print(r.stdout.strip())
  if r.returncode!=0:
   if r.stderr:sys.stderr.write(r.stderr)
   raise SystemExit(r.returncode)
  executed+=1
 validate_learning_behavioral_readiness_manifest(root); print(f"PASS_OPTIONAL_LEARNING_READ_ONLY_SUITES={executed}/{executed} production_authorized=false")
def main():
 cases={"valid_pass":"PASS"}; proofs={"valid_pass":base_proof()}
 def add(n,e,m):p=copy.deepcopy(base_proof());m(p);proofs[n]=with_hash(p);cases[n]=e
 add("invalid_noncanonical_step_30","FAIL",lambda p:p["step"].update({"step_order":30,"step_id":"production_read_only_promotion","is_canonical":False})); add("invalid_pass_when_blocked","RETURN_TO_WORKER",lambda p:p["result"].update({"closure_allowed":False,"clean_pass_allowed":False,"final_result":"PASS"})); p=copy.deepcopy(base_proof());p["verification"]["verification_hash"]="0"*64;proofs["invalid_bad_hash"]=p;cases["invalid_bad_hash"]="FAIL"; add("invalid_narrative_readback","RETURN_TO_WORKER",lambda p:p["readback"].update({"readback_refs":["lo revise en el chat anterior"]})); add("invalid_empty_assertions","RETURN_TO_WORKER",lambda p:p.update({"assertions_checked":[]})); add("invalid_empty_hard_fails","RETURN_TO_WORKER",lambda p:p.update({"hard_fails_checked":[]})); add("invalid_empty_source_refs","RETURN_TO_WORKER",lambda p:p.update({"source_refs":[]})); add("invalid_weak_evidence_ref","RETURN_TO_WORKER",lambda p:p["assertions_checked"][0].update({"evidence_ref":{"id":"EV-WEAK"}}))
 ok=True;results=[]
 for n,e in cases.items():o=validate(proofs[n]);k=o["status"]==e;ok=ok and k;results.append({"case":n,"expected":e,"actual":o["status"],"ok":k,"fail_codes":o["fail_codes"]})
 print(json.dumps({"suite":"LF_VALIDATION_ENGINE_PYTHON_LOCAL_v0_10_2_SELFTEST","overall_status":"PASS" if ok else "FAIL","results":results},indent=2));
 if not ok:raise SystemExit(1)
 run_optional_learning_suites()
if __name__=="__main__":main()
