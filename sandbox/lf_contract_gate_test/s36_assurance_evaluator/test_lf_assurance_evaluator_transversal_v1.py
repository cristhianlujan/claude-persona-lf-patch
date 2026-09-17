#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[3]
MIG = REPO / "supabase" / "migrations"
SOURCE = MIG / "20260917190500_lf_assurance_evaluator_transversal_v1.sql"
RECORDER = MIG / "20260914230317_s36_qualification_independent_review_finalizer_v1.sql"
SUPERSEDED = (
    MIG / "20260917190501_lf_assurance_evaluator_transversal_v1_hardening.sql",
    MIG / "20260917190502_lf_assurance_evaluator_transversal_v1_control_hardening.sql",
    MIG / "20260917190503_lf_assurance_evaluator_transversal_v1_independent_review_fix.sql",
)


def text(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"SOURCE_MISSING:{path.relative_to(REPO)}")
    return path.read_text(encoding="utf-8")


SQL = text(SOURCE)
RECORDER_SQL = text(RECORDER)


class AssuranceEvaluatorSourceControlTests(unittest.TestCase):
    def test_single_consolidated_source_no_predeployment_patch_stack(self):
        for path in SUPERSEDED:
            self.assertFalse(path.exists(), f"SUPERSEDED_SOURCE_MUST_BE_REMOVED:{path.name}")
        self.assertNotIn("create table", SQL.lower())
        for table in (
            "lf_assurance_claim_catalog",
            "lf_assurance_obligation_catalog",
            "lf_assurance_defeater_catalog",
            "lf_assurance_subject_bindings",
            "lf_assurance_evaluations",
            "lf_test_runs",
        ):
            self.assertIn(table, SQL)
        for forbidden in ("CURRENTNESS_AUTHORITY", "TS-CURRENTNESS-AUTHORITY-V1", "PARITY"):
            self.assertNotIn(forbidden, SQL)

    def test_result_is_derived_not_caller_declared(self):
        signature = re.search(
            r"create or replace function public\.lf_assurance_claim_evaluate_and_record_v1\((.*?)\)\s*returns uuid",
            SQL,
            re.S | re.I,
        )
        self.assertIsNotNone(signature)
        self.assertNotIn("p_result", signature.group(1).lower())
        self.assertIn("v_eval := public.lf_assurance_claim_evaluate_v1", SQL)
        self.assertIn("v_result := coalesce(v_eval->>'result','UNPROVEN')", SQL)

    def test_exact_revision_and_governed_execution_are_mandatory(self):
        self.assertIn("and commit_sha=p_subject_revision", SQL)
        self.assertIn("RUN_EXECUTION_ID_MISSING", SQL)
        self.assertIn("RUN_EXECUTION_NOT_GOVERNED", SQL)
        self.assertIn("LF_ASSURANCE_EVALUATOR_EXECUTION_NOT_FOUND", SQL)
        self.assertIn("LF_ASSURANCE_EVALUATOR_ACTOR_EXECUTION_NOT_FOUND", SQL)

    def test_live_terminal_aliases_are_normalized(self):
        self.assertIn("v_run_status in ('FAIL','FAILED')", SQL)
        self.assertIn("v_run_status in ('PASS','PASSED')", SQL)
        self.assertIn("v_run_status in ('REVIEW_REQUIRED','PASS','PASSED')", SQL)
        self.assertIn("TEST_RUN_STATUS_UNKNOWN", SQL)

    def test_pass_cannot_hide_assertion_or_expected_output_failure(self):
        self.assertIn("PASS_RUN_CONTAINS_FAILED_ASSERTION", SQL)
        self.assertIn("PASS_RUN_CONTAINS_NONPASS_ASSERTION", SQL)
        self.assertIn("PASS_RUN_EXPECTED_OUTPUT_NOT_PROVEN", SQL)
        self.assertIn("actual_output,'{}'::jsonb) @> coalesce(v_case.expected_output", SQL)
        self.assertIn("PASS_RUN_DURABLE_EVIDENCE_MISSING", SQL)

    def test_independent_review_uses_canonical_recorder_lineage(self):
        self.assertIn("'recorder','lf_record_test_judge_result_v1'", RECORDER_SQL)
        self.assertIn("'reviewer_execution_id',p_reviewer_execution_id", RECORDER_SQL)
        self.assertIn("'test_producer_execution_id',tr.execution_id", RECORDER_SQL)
        self.assertIn("JUDGE_REVIEWER_SAME_AS_TEST_PRODUCER", RECORDER_SQL)
        self.assertIn("JUDGE_REVIEWER_OPERATION_NOT_INDEPENDENT", RECORDER_SQL)

        self.assertIn("j.metadata->>'recorder'='lf_record_test_judge_result_v1'", SQL)
        self.assertIn("j.metadata->>'reviewer_execution_id'=j.created_by_execution_id", SQL)
        self.assertIn("j.metadata->>'test_producer_execution_id'=v_run.execution_id", SQL)
        self.assertIn("j.created_by_execution_id<>v_run.execution_id", SQL)
        self.assertIn("j.judge_type in ('INDEPENDENT_HOLDOUT','S36_ASSURANCE')", SQL)
        self.assertIn("reviewer.operation_code is distinct from v_run.operation_code", SQL)
        self.assertIn("coalesce(j.evidence_payload,'{}'::jsonb)<>'{}'::jsonb", SQL)

    def test_review_required_can_close_only_with_canonical_pass(self):
        self.assertIn("v_case.execution_mode='INDEPENDENT_REVIEW'", SQL)
        self.assertIn("v_run_status in ('REVIEW_REQUIRED','PASS','PASSED')", SQL)
        self.assertIn("REVIEW_REQUIRED_WITH_CANONICAL_INDEPENDENT_PASS", SQL)
        self.assertIn("INDEPENDENT_REVIEW_PENDING", SQL)
        self.assertIn("MATERIALIZED_INDEPENDENT_PASS_WITHOUT_CANONICAL_JUDGE", SQL)
        self.assertIn("INDEPENDENT_REVIEW_FAIL_JUDGE_PRESENT", SQL)

    def test_claim_closure_cannot_skip_required_obligations(self):
        self.assertIn("create or replace function public.lf_assurance_obligation_evidence_v1", SQL)
        self.assertIn("required_obligation_results", SQL)
        self.assertIn("o.required=true", SQL)
        self.assertIn("v_obl_eval := public.lf_assurance_obligation_evidence_v1", SQL)
        self.assertIn("OBLIGATION_TEST_REF_UNMAPPED", SQL)
        self.assertIn("OBLIGATION_SUITE_BINDING_MISSING", SQL)

    def test_required_obligation_resolves_all_declared_test_refs(self):
        obligation_fn = SQL.split("create or replace function public.lf_assurance_obligation_evidence_v1", 1)[1]
        obligation_fn = obligation_fn.split("create or replace function public.lf_assurance_defeater_evidence_v1", 1)[0]
        self.assertIn("('POSITIVE',v_obl.positive_test_ref)", obligation_fn)
        self.assertIn("('NEGATIVE',v_obl.negative_test_ref)", obligation_fn)
        self.assertIn("('ADVERSARIAL',v_obl.adversarial_test_ref)", obligation_fn)
        self.assertIn("v_mapped<>v_declared", obligation_fn)
        self.assertIn("v_passed<>v_mapped", obligation_fn)
        self.assertIn("verification_method='INDEPENDENT_REVIEW'", obligation_fn)

    def test_defeater_never_closes_from_happy_path_only(self):
        fn = SQL.split("create or replace function public.lf_assurance_defeater_evidence_v1", 1)[1]
        fn = fn.split("create or replace function public.lf_assurance_claim_resolve_core_v1", 1)[0]
        self.assertIn("values (v_obl.negative_test_ref),(v_obl.adversarial_test_ref)", fn)
        self.assertNotIn("v_obl.positive_test_ref", fn)
        self.assertIn("DEFEATER_NEGATIVE_ADVERSARIAL_CASE_UNMAPPED", fn)
        self.assertIn("DEFEATER_COUNTERTEST_NOT_PASS", fn)

    def test_defeater_requires_declared_counterevidence_and_zero_effect(self):
        self.assertIn("required_counterevidence", SQL)
        self.assertIn("DEFEATER_COUNTEREVIDENCE_CONTRACT_UNPROVEN", SQL)
        self.assertIn("DEFEATER_ZERO_EFFECT_UNPROVEN", SQL)
        self.assertIn("not v_def.zero_effect_required or v_zero_effect_seen", SQL)
        self.assertIn("v_run.evidence_payload->'counterevidence'", SQL)

    def test_unsupported_closure_rules_fail_closed(self):
        self.assertIn("CLOSURE_RULE_HAS_UNSUPPORTED_KEYS", SQL)
        self.assertIn("CLOSURE_RULE_NOT_MACHINE_RESOLVABLE", SQL)
        self.assertIn("PASS_REQUIRES_NOT_BOUND_TO_CHILD_CLAIMS", SQL)
        self.assertIn("BENCHMARK_SUITE_BINDING_MISSING", SQL)
        self.assertIn("MANDATORY_DEFEATER_NOT_CLOSED", SQL)

    def test_recorder_is_append_only_and_concurrency_idempotent(self):
        self.assertIn("pg_advisory_xact_lock", SQL)
        self.assertIn("insert into public.lf_assurance_evaluations", SQL.lower())
        recorder_fn = SQL.split("create or replace function public.lf_assurance_claim_evaluate_and_record_v1", 1)[1]
        self.assertNotRegex(recorder_fn.lower(), r"\bupdate\s+public\.lf_assurance_evaluations\b")
        self.assertNotRegex(recorder_fn.lower(), r"\bdelete\s+from\s+public\.lf_assurance_evaluations\b")

    def test_privilege_boundary_is_service_role_only(self):
        for signature in (
            "lf_assurance_case_evidence_v1(text,text,text)",
            "lf_assurance_obligation_evidence_v1(text,text,text,integer)",
            "lf_assurance_defeater_evidence_v1(text,text,text,integer)",
            "lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer)",
            "lf_assurance_claim_evaluate_v1(text,text,text,text,integer)",
            "lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text)",
        ):
            self.assertIn(f"revoke all on function public.{signature} from public,anon,authenticated", SQL)
            self.assertIn(f"grant execute on function public.{signature} to service_role", SQL)


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(
        "S36_ASSURANCE_EVALUATOR_CONTROL_EXECUTED=1 "
        f"TEST_COUNT={result.testsRun} RESULT={'PASS' if result.wasSuccessful() else 'FAIL'}"
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
