"""Step70: the only true independent review is a separate attested LLM call.

Synthetic fixtures test contracts, not real provider independence.
"""
import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/"scripts"))
from lf_step70_separate_call_receipt_v1 import (assess_separate_call_receipt,normalize_when_unverified)
from lf_step70_same_llm_eval_v1 import evaluate,EXPECTED,SCHEMA_ID,EVAL_ID

RUN="EXEC-PROFILE-GATE2-ABCDEF012345678901234567"
S50="a"*64
S40="b"*64

def fixture():
    checks={key:{"result":True if key!="router_direct_consistency" else "not_applicable",
       "reason":"Aporte verificado contra las referencias vigentes",
       "source_refs":["supabase://fixture/readback"]}
       for key in EXPECTED}
    body={"verdict":"PASS_INDEPENDENT_SEMANTIC","decision_checks":checks,
          "unsupported_claims":[],"blocking_codes":[],
          "reason":"Las doce comprobaciones están respaldadas por fuentes vigentes"}
    receipt={"schema_version":"LF_STEP70_SAME_LLM_SEPARATE_CALL_RECEIPT_V1",
         "receipt_ref":"actions://reviewer/run/200/artifact/receipt",
         "execution_id":RUN,"model_id":"GPT-6",
         "model_call_id":"different-native-model-call-0002",
         "producer_call_ref":"actions://producer/run/100/artifact/raw",
         "reviewer_call_ref":"actions://reviewer/run/200/artifact/raw",
         "prompt_sha256":"c"*64,"producer_prompt_sha256":"d"*64,
         "schema_id":SCHEMA_ID,"producer_schema_id":"PROFILE_PRODUCT_DIRECTION_SPEC",
         "eval_id":EVAL_ID,"producer_eval_id":"PROFILE_OUTPUT_VALIDATION_RESULT_V1",
         "eval_status":"PASS","model_call_count":1,
         "candidate_sha256":S50,"scope_packet_sha256":S40,
         "decision_body":body,"provider_attestation":True}
    return {"execution_id":RUN,"review_mode":"INDEPENDENT_SEMANTIC",
          "verdict":"PASS_INDEPENDENT_SEMANTIC","candidate_sha256":S50,
          "scope_packet_sha256":S40,"source_refs":["supabase://fixture/readback"],
          "separate_model_call_receipt":receipt}

class SameLlmReceiptV1Tests(unittest.TestCase):
    def test_explicit_missing_receipt_yields_nonblocking_finding(self):
        candidate=fixture()
        del candidate["separate_model_call_receipt"]
        self.assertEqual(assess_separate_call_receipt(candidate)["status"],"JUDGE_INDEPENDENCE_NOT_PROVEN")
        safe,r=normalize_when_unverified(candidate)
        self.assertEqual(safe["verdict"],"PASS_REVIEWED_CURRENT_CONTEXT")
        self.assertTrue(safe["reviewer_is_producer"])
        self.assertFalse(safe["producer_independence_proven"])
        self.assertEqual(safe["model_call_count"],0)
        self.assertTrue(r["content_continuation_allowed"])

    def test_separate_contract_evaluated_but_asserted_attestation_not_proof(self):
        r=assess_separate_call_receipt(fixture(),execution_id=RUN)
        self.assertEqual(r["status"],"RECEIPT_FORMAT_VALID_PROVENANCE_UNATTESTED")
        self.assertEqual(r["evaluator_status"],"PASS")
        self.assertEqual(r["schema_id"],SCHEMA_ID)
        self.assertEqual(r["eval_id"],EVAL_ID)
        self.assertIsNone(r["independent_semantic_receipt_ref"])
        self.assertEqual(r["model_call_count"],0)
        self.assertFalse(r["producer_independence_proven"])

    def test_reused_prompt_ref_schema_eval_or_missing_call(self):
        for field,value in [
          ("reviewer_call_ref","actions://producer/run/100/artifact/raw"),
          ("prompt_sha256","d"*64),("schema_id","PROFILE_PRODUCT_DIRECTION_SPEC"),
          ("eval_id","PROFILE_OUTPUT_VALIDATION_RESULT_V1"),
          ("model_call_count",0),("receipt_ref","actions://producer/run/100/artifact/raw"),
          ("candidate_sha256","e"*64)]:
            with self.subTest(field=field):
                item=fixture()
                item["separate_model_call_receipt"][field]=value
                if field in ("reviewer_call_ref","receipt_ref","candidate_sha256"):
                    with self.assertRaises(ValueError) as err:
                        normalize_when_unverified(item,execution_id=RUN)
                    self.assertIn(str(err.exception),{
                        "STEP70_CALL_NOT_SEPARATE","STEP70_REVIEW_NOT_SOURCE_BOUND"})
                else:
                    safe,r=normalize_when_unverified(item,execution_id=RUN)
                    self.assertEqual(r["status"],"JUDGE_INDEPENDENCE_NOT_PROVEN")
                    self.assertIn("receipt_contract_error",r)
                    self.assertFalse(safe["producer_independence_proven"])
                    self.assertEqual(safe["judge_independence_finding"],"JUDGE_INDEPENDENCE_NOT_PROVEN")

    def test_second_evaluator_detects_unsupported_claim_and_scope_drift(self):
        good=fixture()
        r=good["separate_model_call_receipt"]
        raw={"schema_id":SCHEMA_ID,"execution_id":RUN,
             "candidate_sha256":S50,"scope_packet_sha256":S40,
             "verdict":"PASS_INDEPENDENT_SEMANTIC",
             "decision_body":r["decision_body"],
             "source_refs":good["source_refs"]}
        result=evaluate(raw,RUN,S50,S40)
        self.assertEqual(result["eval_status"],"PASS")
        self.assertFalse(result["independent_model_call_attested"])
        raw["decision_body"]=copy.deepcopy(raw["decision_body"])
        raw["decision_body"]["unsupported_claims"]=["wrong"]
        result=evaluate(raw,RUN,S50,S40)
        self.assertEqual(result["eval_status"],"FAIL")
        self.assertIn("UNSUPPORTED_CLAIMS",result["errors"])

    def test_pigp_material_run_id_and_source_ref_fail_closed(self):
        item=fixture()
        item["separate_model_call_receipt"]["execution_id"]="EXEC-PROFILE-GATE2-OTHER000001"
        with self.assertRaisesRegex(ValueError,"STEP70_RUN_ID_DRIFT"):
            normalize_when_unverified(item,execution_id=RUN)
        item=fixture()
        item["source_refs"]=["x"]
        raw={"schema_id":SCHEMA_ID,"execution_id":RUN,
             "candidate_sha256":S50,"scope_packet_sha256":S40,
             "verdict":"PASS_INDEPENDENT_SEMANTIC",
             "decision_body":item["separate_model_call_receipt"]["decision_body"],
             "source_refs":item["source_refs"]}
        result=evaluate(raw,RUN,S50,S40)
        self.assertEqual(result["eval_status"],"FAIL")
        self.assertIn("REVIEW_SOURCE_REFS_MISSING",result["errors"])

    def test_pigp_source_and_evaluator_failures_must_not_downgrade(self):
        for mutate,expected in [
            (lambda x:x["separate_model_call_receipt"].update(candidate_sha256="e"*64),
                "STEP70_REVIEW_NOT_SOURCE_BOUND"),
            (lambda x:x["separate_model_call_receipt"].update(eval_status="FAIL"),
                "STEP70_REVIEW_EVAL_NOT_PASS"),
            (lambda x:x["separate_model_call_receipt"]["decision_body"]["decision_checks"].get(
                "context_resolution_valid").update(result=False),
                "STEP70_SEPARATE_EVALUATOR_NOT_PASS")]:
            with self.subTest(code=expected):
                item=fixture()
                mutate(item)
                with self.assertRaisesRegex(ValueError,expected):
                    normalize_when_unverified(item,execution_id=RUN)

    def test_model_call_id_does_not_exist_as_trusted_provider_token(self):
        r=fixture()
        r["separate_model_call_receipt"]["provider_attestation"]=True
        a=assess_separate_call_receipt(r)
        self.assertFalse(a["producer_independence_proven"])
        self.assertTrue(a["reviewer_is_producer"])
        self.assertNotIn("receipt_minted",a)

if __name__=="__main__":unittest.main()
