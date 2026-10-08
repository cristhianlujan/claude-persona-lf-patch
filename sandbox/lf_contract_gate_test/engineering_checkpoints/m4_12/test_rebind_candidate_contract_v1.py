#!/usr/bin/env python3
"""Guardrails for candidate rebind repair. Does NOT execute PL/pgSQL."""
from __future__ import annotations
import pathlib
import re
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "validator_rebind_fail_closed_candidate_v1.sql"
NEGATIVE = HERE / "test_rebind_assertion_mutation_readonly_v1.sql"


class RebindCandidateContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SOURCE.read_text(encoding="utf-8")
        cls.negative = NEGATIVE.read_text(encoding="utf-8")
        cls.selector = (HERE / "validator_semantic_scope_v1.sql").read_text(encoding="utf-8")
        cls.v2 = (HERE / "validator_validate_v2_fail_closed_candidate_v1.sql").read_text(encoding="utf-8")
        cls.bootstrap = (HERE / "validator_bootstrap_fail_closed_candidate_v1.sql").read_text(encoding="utf-8")

    def test_canonical_existing_function_only(self):
        self.assertIn("CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_rebind_v1(",self.code)
        self.assertEqual(len(re.findall(r"CREATE OR REPLACE FUNCTION",self.code,re.I)),1)

    def test_existing_source_evaluator_reused(self):
        self.assertIn("programacion.fn_input_evaluate_assertion(p_run_id,a.family_code,v_assertion)",self.code)
        self.assertIn("if coalesce((v_evaluation->>'passed')::boolean,false) is not true",self.code)
        self.assertIn("SOURCE_ASSERTION_FAILED",self.code)

    def test_no_silent_empty_assertion_pass(self):
        self.assertIn("REBOUND_VALIDATOR_ASSERTIONS_REQUIRED",self.code)
        self.assertIn("jsonb_array_length(v_assertions)=0",self.code)

    def test_unscoped_structural_pass_is_preserved(self):
        self.assertIn("v_outcome:='PASS'",self.code)
        self.assertIn("IF v_fail=0 AND v_blocked=0 THEN",self.code)
        self.assertIn("UPDATE programacion.input_readiness_runs SET status='COMPLETED'",self.code)
        self.assertIn("'validator_pass_scope','SOURCE_INTEGRITY_ONLY'",self.code)
        self.assertIn("'independent_semantic_oracle_verified',false",self.code)

    def test_explicit_comparison_is_blocked_without_oracle_receipt(self):
        for script in (self.code,self.v2,self.bootstrap):
            self.assertIn("IF v_comparison_requested THEN",script)
            self.assertIn("v_outcome:='BLOCKED'",script)
            self.assertIn("INDEPENDENT_SEMANTIC_ORACLE_UNPROVEN",script)
            self.assertIn("v_outcome:='PASS'",script)
            self.assertIn("semantic_comparison_requested",script)
            self.assertIn("semantic_independence_credited",script)
            self.assertIn("fn_input_validator_semantic_scope_v1(p_run_id)",script)

    def test_selector_is_dynamic_exact_and_fail_closed(self):
        for marker in ("validator_semantic_comparison_families",
                       "VALIDATOR_SCOPE_RUN_NOT_FOUND",
                       "VALIDATOR_SEMANTIC_COMPARISON_SCOPE_INVALID",
                       "VALIDATOR_SEMANTIC_COMPARISON_DUPLICATE",
                       "VALIDATOR_SEMANTIC_COMPARISON_FAMILY_UNREGISTERED",
                       "INPUT_FAMILY_POLICY_REGISTRY", "jsonb_array_elements_text",
                       "RETURNS text[]", "SECURITY INVOKER"):
            self.assertIn(marker,self.selector)
        self.assertIn("IF NOT v_scope ? 'validator_semantic_comparison_families' THEN",self.selector)
        self.assertNotIn("REC_001",self.selector)
        self.assertNotIn("SELECT DISTINCT family_code FROM programacion.input_family_assessments",self.selector)

    def test_identity_and_source_controls_preserved(self):
        for invariant in ("VALIDATOR_IDENTITY_NOT_INDEPENDENT",
                          "fn_input_governance_ekb_checkpoint",
                          "fn_input_validator_evidence_rehydrate_v1",
                          "R5D_ASSERTION_SET_READBACK_MISMATCH",
                          "VALIDATOR_IDENTITY_MISMATCH",
                          "INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH"):
            self.assertIn(invariant,self.code)

    def test_no_new_transversal_or_frozen_screen(self):
        self.assertNotIn("REC_001",self.code)
        self.assertNotIn("pantalla_id=51",self.code)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_independent_assurance",self.code)

    def test_negative_sql_does_not_mutate_authority(self):
        self.assertIn("selected_run_id",self.negative)
        self.assertIn("fn_input_evaluate_assertion",self.negative)
        self.assertIn("NEGATIVE_MUTATION_DETECTED",self.negative)
        body = re.sub(r"(?m)^\s*--[^\n]*$", "", self.negative)
        self.assertIsNone(re.search(r"\b(?:UPDATE|DELETE|INSERT|TRUNCATE|MERGE|CREATE|DROP|ALTER)\b",body,re.I))



    def test_all_legacy_routes_preserve_source_checks_not_semantic_pass(self):
        for name, code in (("rebind", self.code), ("validate_v2", self.v2), ("bootstrap", self.bootstrap)):
            with self.subTest(path=name):
                self.assertIn("fn_input_evaluate_assertion",code)
                self.assertIn("IF v_comparison_requested THEN",code)
                self.assertIn("v_outcome:='BLOCKED'",code)
                self.assertIn("v_outcome:='FAIL'",code)
                self.assertIn("v_outcome:='PASS'",code)
                self.assertIn("'validation_phase','SOURCE_INTEGRITY'",code)

    def test_no_curator_shared_classifier_in_v2_or_bootstrap(self):
        self.assertNotIn("fn_input_governance_bootstrap_classify_v2", self.v2)
        self.assertNotIn("fn_input_governance_bootstrap_classify_v1", self.bootstrap)
        for code in (self.v2,self.bootstrap):
            self.assertNotIn("v_classifier_block", code)
            self.assertNotIn("v_expected",code)

    def test_v2_retains_checkpoint_pagination_and_failclosed_exit(self):
        for required in ("limit 10", "fn_input_evaluate_assertion",
                         "if v_pass<v_family_count", "'VALIDATION_BLOCKED'",
                         "fn_input_governance_ekb_checkpoint",
                         "fn_input_validator_evidence_rehydrate_v1"):
            self.assertIn(required, self.v2)
        self.assertIn("'semantic_conclusion_independence','UNPROVEN'",self.v2)

    def test_bootstrap_does_not_mark_completed_without_full_pass(self):
        for required in ("fn_input_evaluate_assertion", "v_pass<>v_family_count",
                         "fn_input_validator_evidence_rehydrate_v1",
                         "BOOTSTRAP_VALIDATOR_CARDINALITY_MISMATCH"):
            self.assertIn(required,self.bootstrap)

if __name__ == "__main__":
    unittest.main(verbosity=2)
