#!/usr/bin/env python3
"""Source-contract tests for the existing trusted-receipt reader extension.

These are NOT a provider-bound receipt, reviewer assurance or a DB rollback
test. The candidate remains inactive until the real producer is qualified.
"""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/"skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql"


class VerifiedOutputReceiptReaderCandidate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql=SRC.read_text(encoding="utf8")

    def test_one_canonical_reader_and_no_parallel_ledger(self):
        self.assertEqual(self.sql.count("CREATE OR REPLACE FUNCTION public.lf_profile_update_verified_receipt_v1("),1)
        self.assertEqual(self.sql.count("FROM private.lf_evidence_ledger_v1 l"),1)
        self.assertNotIn("CREATE TABLE",self.sql)
        self.assertNotIn("INSERT INTO",self.sql)

    def test_legacy_subject_classes_preserved(self):
        for name in ("PROFILE_ASSESSMENT","METHOD_QUALIFICATION"):
            self.assertIn(name,self.sql)

    def test_positive_requires_executed_canonical_validator(self):
        for evidence in (
            "l.capability_code='PACK_VALIDATION_HARNESS'",
            "l.receipt_kind='PROFILE_OUTPUT_VALIDATION_RESULT'",
            "l.gate_code='PROFILE_OUTPUT_CONTRACT_VALIDATION'",
            "l.receipt_payload->>'status'='CANDIDATE_OUTPUT_PARITY_OBSERVED'",
            "l.receipt_payload->>'profile_validator_executed'='true'",
            "l.receipt_payload->>'validator_exit_code'='0'",
        ):
            self.assertIn(evidence,self.sql)

    def test_negative_has_two_proven_rejection_routes(self):
        for evidence in (
            "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR",
            "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE",
            "l.receipt_payload->>'profile_validator_executed'='false'",
            "l.receipt_payload->>'profile_validator_executed'='true'",
        ):
            self.assertIn(evidence,self.sql)
        # A validator is allowed to emit valid=false with process exit=0.
        negative=self.sql.split("p_subject_type='PROFILE_OUTPUT_VALIDATION_NEGATIVE'",1)[1]
        self.assertNotIn("validator_exit_code'<>'0'",negative)

    def test_bad_json_payloads_fail_closed_without_cardinality_exception(self):
        for key in ("validator_errors","shape_errors"):
            self.assertIn(f"CASE WHEN jsonb_typeof(l.receipt_payload->'{key}')='array'",self.sql)

    def test_bound_to_trusted_resolver_not_declared_pass(self):
        for source in (
            "rr.trust_level='TRUSTED_PROVIDER_BOUND'",
            "l.verification_state = 'VERIFIED'",
            "l.source_head_sha = p_source_head_sha",
            "l.subject_sha256 = p_subject_sha256",
            "l.receipt_payload->>'raw_output_sha256'=l.subject_sha256",
            "l.receipt_payload->>'admission_authorized'='false'",
        ):
            self.assertIn(source,self.sql)

    def test_no_broad_reader_permissions(self):
        self.assertIn("REVOKE ALL ON FUNCTION",self.sql)
        self.assertIn("GRANT EXECUTE ON FUNCTION",self.sql)
        self.assertNotIn("GRANT SELECT ON private.lf_evidence_ledger_v1",self.sql)
        self.assertNotIn("GRANT ALL",self.sql)

    def test_candidate_is_not_a_cutover(self):
        self.assertIn("PACK_VALIDATION_HARNESS is not cut over",self.sql)
        self.assertIn("NOT a deployed migration",self.sql)


if __name__=="__main__":
    unittest.main(verbosity=2)
