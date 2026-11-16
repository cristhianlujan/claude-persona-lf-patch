"""LF-PIGP-03/04/05: actual evaluator and native-call receipt logic, no synthetic attestation."""
import unittest
from scripts.lf_step70_separate_call_receipt_v1 import normalize_when_unverified
from scripts.lf_step70_same_llm_eval_v1 import evaluate,SCHEMA_ID,EXPECTED

RUN="EXEC-PROFILE-GATE2-A1A1A1A1A1A1A1A1"
OTHER="EXEC-PROFILE-GATE2-B2B2B2B2B2B2B2B2"
CAND="a"*64
SCOPE="b"*64

def raw(refs):
 checks={k:{"source_refs":["supabase://public.lf_operation_execution_steps/real-run/execute_profile"],
             "reason":"Confirmed source-bound semantic review","result":True}
         for k in EXPECTED}
 decision={"verdict":"PASS_INDEPENDENT_SEMANTIC","decision_checks":checks,
           "unsupported_claims":[],"blocking_codes":[],
           "reason":"Reviewed against the canonical source refs"}
 return {"schema_id":SCHEMA_ID,"execution_id":RUN,"candidate_sha256":CAND,
         "scope_packet_sha256":SCOPE,"verdict":"PASS_INDEPENDENT_SEMANTIC",
         "decision_body":decision,"source_refs":refs}

def receipt(run=OTHER):
 return {"schema_version":"LF_STEP70_SAME_LLM_SEPARATE_CALL_RECEIPT_V1",
         "receipt_ref":"actions://owner/repo/runs/1/receipt",
         "execution_id":run,"model_id":"test-model",
         "model_call_id":"call-00000000000000000001",
         "producer_call_ref":"actions://owner/repo/runs/1/producer",
         "reviewer_call_ref":"actions://owner/repo/runs/1/reviewer",
         "prompt_sha256":"c"*64,"producer_prompt_sha256":"d"*64,
         "schema_id":SCHEMA_ID,"producer_schema_id":"OTHER",
         "eval_id":"LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1",
         "producer_eval_id":"OTHER","eval_status":"PASS",
         "model_call_count":1,"candidate_sha256":CAND,
         "scope_packet_sha256":SCOPE,
         "decision_body":{"verdict":"PASS_INDEPENDENT_SEMANTIC"},
         "provider_attestation":False}

class PIGPMaterialStep70(unittest.TestCase):
 def test_missing_receipt_remains_current_context(self):
  candidate=raw(["supabase://public.lf_operation_execution_steps/real-run/execute_profile"])
  normalized,assessment=normalize_when_unverified(candidate,execution_id=RUN)
  self.assertEqual(normalized["verdict"],"PASS_REVIEWED_CURRENT_CONTEXT")
  self.assertFalse(assessment["producer_independence_proven"])
  self.assertEqual(assessment["status"],"JUDGE_INDEPENDENCE_NOT_PROVEN")

 def test_cross_run_receipt_is_material_error(self):
  candidate=raw(["supabase://public.lf_operation_execution_steps/real-run/execute_profile"])
  candidate["separate_model_call_receipt"]=receipt()
  with self.assertRaisesRegex(ValueError,"^STEP70_RUN_ID_DRIFT$"):
   normalize_when_unverified(candidate,execution_id=RUN)

 def test_short_source_ref_is_not_evaluation_pass(self):
  res=evaluate(raw(["x"]),RUN,CAND,SCOPE)
  self.assertEqual(res["eval_status"],"FAIL")
  self.assertIn("REVIEW_SOURCE_REFS_MISSING",res["errors"])

 def test_well_formed_refs_do_not_fail_min_length(self):
  res=evaluate(raw(["supabase://public.lf_operation_execution_steps/real-run/execute_profile"]),
               RUN,CAND,SCOPE)
  self.assertNotIn("REVIEW_SOURCE_REFS_MISSING",res["errors"])
  self.assertEqual(res["eval_status"],"PASS")

if __name__=="__main__":
 unittest.main()
