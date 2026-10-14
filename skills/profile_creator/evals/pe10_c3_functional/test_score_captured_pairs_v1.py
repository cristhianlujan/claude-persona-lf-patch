#!/usr/bin/env python3
"""Negative controls use synthetic strings solely to test rejection logic."""
from __future__ import annotations
import json,tempfile,unittest
from pathlib import Path
from . import build_shadow_v1 as build
from . import score_captured_pairs_v1 as score

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]

class EvidenceScorerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="pe10c3-score-test-")
        self.compiled=build.compile_pair(REPO,build.git(REPO,"rev-parse","HEAD^{commit}"),Path(self.tmp.name))
        self.raw={"schema":"PE10_C3_CAPTURED_GPT_NATIVE_RAW_V1",
                  "model_route":"GPT_NATIVE_IN_CHAT","test_double":False,
                  "source_compilation_revision":self.compiled["immutable_baseline_revision"],
                  "producer_execution_id":"TEST-FIXTURE-NONATTESTED","responses":[]}
        for a in self.compiled["paired_assignments"]:
            txt="SYNTHETIC TEST STRING — NOT AN ACTUAL MODEL RESPONSE. "*4+a["case_id"]
            self.raw["responses"].append({"case_id":a["case_id"],"arm":a["arm"],
                "input_sha256":a["input_sha256"],
                "model_context_sha256":a["model_context_sha256"],
                "output":txt,"output_sha256":build.sha(txt),
                "chat_reference":"synthetic-test-fixture-not-real"})
    def tearDown(self):self.tmp.cleanup()
    def test_blind_packet_never_claims_attested(self):
        out=score.make_blind_packet(self.compiled,self.raw)
        self.assertEqual(len(out["cases"]),6)
        self.assertEqual(out["external_provider_attestation"],"NOT_VERIFIED")
        self.assertTrue(out["independent_judgment_required"])
    def test_test_double_flag_blocked(self):
        self.raw["test_double"]=True
        with self.assertRaisesRegex(score.EvidenceError,"TEST_DOUBLE_FORBIDDEN"):
            score.check_raw(self.compiled,self.raw)
    def test_missing_answer_blocked(self):
        self.raw["responses"].pop()
        with self.assertRaisesRegex(score.EvidenceError,"RAW_PAIR_COUNT_MISMATCH"):
            score.check_raw(self.compiled,self.raw)
    def test_corrupted_output_hash_blocked(self):
        self.raw["responses"][0]["output_sha256"]="0"*64
        with self.assertRaisesRegex(score.EvidenceError,"RAW_OUTPUT_DIGEST_MISMATCH"):
            score.check_raw(self.compiled,self.raw)
    def test_modified_input_blocked(self):
        self.raw["responses"][0]["input_sha256"]="1"*64
        with self.assertRaisesRegex(score.EvidenceError,"RAW_INPUT_MISMATCH"):
            score.check_raw(self.compiled,self.raw)
    def test_scoring_without_real_improvement_never_passes(self):
        rubric=json.loads((HERE/"private_oracle_v1.json").read_text())
        rows=[]
        for case in rubric["case_rubrics"]:
            for label in ("X","Y"):
                rows.append({"case_id":case["case_id"],"blind_arm":label,
                            "points":[0]*len(case["criteria"]),
                            "evidence_quotes":[""]*len(case["criteria"])})
        judge={"schema":"PE10_C3_BLIND_SEMANTIC_JUDGE_V1",
               "reviewer_execution_id":"TEST-JUDGE-DIFFERENT-ID",
               "blind_to_arm_identity":True,"scores":rows}
        out=score.evaluate(self.compiled,self.raw,judge)
        self.assertEqual(out["result"],"FUNCTIONAL_UPLIFT_NOT_ESTABLISHED")
        self.assertFalse(out["independent_assurance_admitted"])
        self.assertFalse(out["provider_attestation_verified"])
    def test_self_review_rejected(self):
        rubric=json.loads((HERE/"private_oracle_v1.json").read_text())
        j={"schema":"PE10_C3_BLIND_SEMANTIC_JUDGE_V1",
           "reviewer_execution_id":self.raw["producer_execution_id"],
           "blind_to_arm_identity":True,"scores":[]}
        with self.assertRaisesRegex(score.EvidenceError,"SELF_JUDGMENT_FORBIDDEN"):
            score.evaluate(self.compiled,self.raw,j)
    def test_unsubstantiated_score_rejected(self):
        rubric=json.loads((HERE/"private_oracle_v1.json").read_text())
        rows=[]
        for case in rubric["case_rubrics"]:
            for label in ("X","Y"):
                n=len(case["criteria"])
                rows.append({"case_id":case["case_id"],"blind_arm":label,
                            "points":[1]*n,"evidence_quotes":["invented quotation"]*n})
        judge={"schema":"PE10_C3_BLIND_SEMANTIC_JUDGE_V1",
               "reviewer_execution_id":"TEST-JUDGE-02",
               "blind_to_arm_identity":True,"scores":rows}
        with self.assertRaisesRegex(score.EvidenceError,"JUDGE_POSITIVE_UNGROUNDED"):
            score.evaluate(self.compiled,self.raw,judge)

if __name__=="__main__":unittest.main()
