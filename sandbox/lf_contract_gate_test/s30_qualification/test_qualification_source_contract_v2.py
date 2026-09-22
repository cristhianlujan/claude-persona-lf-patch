#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SQL = (HERE / "qualification_source_candidate_v2.sql").read_text(encoding="utf-8")


class QualificationSourceContractV2Test(unittest.TestCase):
    def test_no_strategy_specific_authority_literal(self) -> None:
        self.assertNotIn("S37-MODEL-HOLDOUT-A03", SQL)
        self.assertNotIn("LF_EXPLORATION_INNOVATION_ENGINE_20260913", SQL)

    def test_model_is_table_driven(self) -> None:
        self.assertIn("lf_test_requirement_bindings", SQL)
        self.assertIn("independent_review_required is true", SQL)
        self.assertIn("lf_test_suite_cases", SQL)
        self.assertIn("execution_mode <> 'INDEPENDENT_REVIEW'", SQL)
        self.assertIn("lf_strategy_test_characteristics", SQL)

    def test_exact_identity_and_currentness_are_required(self) -> None:
        self.assertIn("lf_strategy_revision_sha256_v1", SQL)
        self.assertIn("QUAL_QUALIFYING", SQL)
        self.assertIn("RECEIPT_IDENTITY_MISMATCH", SQL)
        self.assertIn("PASS_WITH_BLOCKERS", SQL)

    def test_review_case_is_metadata_not_authority(self) -> None:
        self.assertIn("v_review_case", SQL)
        self.assertNotIn("review_case' is distinct from", SQL)

    def test_v2_is_service_role_only(self) -> None:
        signature = "public.lf_apply_independent_strategy_review_v2(uuid,uuid,uuid,bigint,text,jsonb,text)"
        self.assertIn(f"revoke execute on function {signature} from public, anon, authenticated", SQL)
        self.assertIn(f"grant execute on function {signature} to service_role", SQL)

    def test_candidate_does_not_replace_v1(self) -> None:
        self.assertNotIn("create or replace function public.lf_apply_independent_strategy_review_v1", SQL)


if __name__ == "__main__":
    unittest.main()
