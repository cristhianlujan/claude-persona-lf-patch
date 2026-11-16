"""R17 checks LF-PIGP-03/04/05 against actual Python modules on branch HEAD."""
import copy
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"scripts"))
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"))
from test_step70_same_llm_separate_call_v1 import fixture, RUN, S50, S40
from lf_step70_separate_call_receipt_v1 import normalize_when_unverified
from lf_step70_same_llm_eval_v1 import evaluate,SCHEMA_ID

class PIGPMaterialStep70R17(unittest.TestCase):
 def test_missing_receipt_content_continuation_remains_available(self):
  review=fixture()
  review.pop("separate_model_call_receipt")
  safe,assessment=normalize_when_unverified(review,execution_id=RUN)
  self.assertEqual(safe["verdict"],"PASS_REVIEWED_CURRENT_CONTEXT")
  self.assertEqual(assessment["status"],"JUDGE_INDEPENDENCE_NOT_PROVEN")
  self.assertFalse(safe["producer_independence_proven"])

 def test_cross_run_receipt_rejected(self):
  review=fixture()
  review["separate_model_call_receipt"]["execution_id"]="EXEC-PROFILE-GATE2-OTHER-001"
  with self.assertRaisesRegex(ValueError,"STEP70_RUN_ID_DRIFT"):
   normalize_when_unverified(review,execution_id=RUN)

 def test_material_receipt_failures_rejected(self):
  scenarios=[
   ("STEP70_REVIEW_NOT_SOURCE_BOUND",lambda x:x["separate_model_call_receipt"].update(
     candidate_sha256="e"*64)),
   ("STEP70_REVIEW_EVAL_NOT_PASS",lambda x:x["separate_model_call_receipt"].update(
     eval_status="FAIL")),
   ("STEP70_CALL_NOT_SEPARATE",lambda x:x["separate_model_call_receipt"].update(
     reviewer_call_ref=x["separate_model_call_receipt"]["producer_call_ref"])),
   ("STEP70_SEPARATE_EVALUATOR_NOT_PASS",lambda x:x["separate_model_call_receipt"]
     ["decision_body"]["decision_checks"]["context_resolution_valid"].update(result=False))]
  for code,change in scenarios:
   with self.subTest(code=code):
    review=fixture()
    change(review)
    with self.assertRaisesRegex(ValueError,code):
     normalize_when_unverified(review,execution_id=RUN)

 def test_source_refs_short_are_rejected(self):
  review=fixture()
  raw={"schema_id":SCHEMA_ID,"execution_id":RUN,
   "candidate_sha256":S50,"scope_packet_sha256":S40,
   "verdict":"PASS_INDEPENDENT_SEMANTIC",
   "decision_body":review["separate_model_call_receipt"]["decision_body"],
   "source_refs":["x"]}
  evaluated=evaluate(raw,RUN,S50,S40)
  self.assertEqual(evaluated["eval_status"],"FAIL")
  self.assertIn("REVIEW_SOURCE_REFS_MISSING",evaluated["errors"])

 def test_resume_catches_material_error_not_python_traceback(self):
  src=(ROOT/"scripts/lf_profile_native_resume.py").read_text(encoding="utf-8")
  self.assertIn("normalize_when_unverified(semantic_review, execution_id=execution_id)",src)
  self.assertIn('except ValueError as exc:\n            print(json.dumps({"phase":"SEMANTIC_REVIEW","code":str(exc)}))\n            return 1',src)

if __name__=="__main__": unittest.main()
