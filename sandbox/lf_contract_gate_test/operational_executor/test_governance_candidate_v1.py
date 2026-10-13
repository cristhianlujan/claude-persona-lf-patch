"""Static, offline negative gates for the single migration candidate.
NOT a substitute for PostgreSQL rollback/apply tests.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIGRATION_SUFFIX="_lf_operational_executor_lane_v1.sql"


def resolve_candidate() -> Path:
    matches=sorted((ROOT/"supabase/migrations").glob("*"+MIGRATION_SUFFIX))
    if len(matches)!=1:
        raise AssertionError(f"GOVERNANCE_SOURCE_CARDINALITY_INVALID:{len(matches)}")
    return matches[0]


SQL=resolve_candidate()


def verify(source: str) -> list[str]:
    problems=[]
    for marker in (
      "BEGIN;", "COMMIT;",
      "EJECUCION_OPERATIVA_LF","OPERATIONAL_DB","OPERATION_EXECUTE",
      "ACTUALIZACION_DB_LF","MIGRATION_TRAIN_ROUTE_NOT_PRESERVED",
      "lf_router_downstream_authority_consumer_v1",
      "lf_router_resolve_v1",
      "lf_router_downstream_authority_validate_v1",
      "fn_lf_operation_acquire_lease_v1",
      "fn_lf_operation_reserve_effect_v1",
      "fn_lf_operation_mark_effect_succeeded_v1",
      "lf_record_operation_step_core_v1",
      "CREATE OR REPLACE FUNCTION public.lf_operational_executor_assert_principal_v1",
      "OPERATIONAL_PRINCIPAL_EXTERNAL_LOGIN_REQUIRED",
      "OPERATIONAL_PRINCIPAL_LEAST_PRIVILEGE_REQUIRED",
      "OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID",
      "OPERATIONAL_PRINCIPAL_EXTRA_ROLE_MEMBERSHIP_FORBIDDEN",
      "REVOKE ALL ON FUNCTION public.lf_operational_executor_assert_principal_v1",
      "GRANT EXECUTE ON FUNCTION public.lf_operational_executor_assert_principal_v1",
      "CREATE OR REPLACE FUNCTION public.lf_operational_executor_admit_v1",
      "lf_operational_admission_authority",
      "OPERATIONAL_AUTHORITY_ROLE_PRIVILEGES_UNSAFE",
      "OPERATIONAL_AUTHORITY_ROLE_CROSS_MEMBERSHIP_FORBIDDEN",
      "fn_lf_human_decision_consume_v1",
      "lf_operational_executor_assert_decision_current_v1",
      "OPERATIONAL_DECISION_NO_LONGER_CURRENT",
      "OPERATIONAL_DECISION_SUPERSEDED_OR_OPEN",
      "fn_lf_human_decision_current_for_subject_v1",
      "OPERATIONAL_DECISION_ROUTE_POLICY_NO_LONGER_ACTIVE",
      "fn_lf_human_decision_resolve_policy_v1",
      "fn_lf_human_decision_assert_authority_receipt_v1",
      "OPERATIONAL_ADMISSION_DURABLE_DECISION_REF_REQUIRED",
      "OPERATIONAL_ADMISSION_VERIFIED_DECISION_NOT_CURRENT",
      "OPERATIONAL_ADMISSION_DECISION_SCOPE_OR_EXPIRY_INVALID",
      "OPERATIONAL_ADMISSION_AUTHORITY_POLICY_NOT_ACTIVE",
      "OPERATIONAL_ADMISSION_AUTHORITY_RECEIPT_INVALID",
      "OPERATIONAL_DECISION_PENDING_AUTHORITY_INVARIANT_VIOLATED",
      "OPERATIONAL_DECISION_CATALOGUE_COLLISION_REQUIRES_RECONCILIATION",
      "OPERATIONAL_ADMISSION_EXTERNAL_DECISION_NOT_EXACT",
      "OPERATIONAL_ADMISSION_REPLAY_OR_EXECUTION_MISMATCH",
      "OPERATIONAL_BEGIN_INDEPENDENT_ADMISSION_PROVENANCE_MISSING",
      "fn_lf_operation_reserve_execution_v1",
      "CREATE OR REPLACE FUNCTION public.lf_operational_executor_begin_v1",
      "CREATE OR REPLACE FUNCTION public.lf_operational_executor_finish_v1",
      "CREATE OR REPLACE FUNCTION public.lf_close_operational_execution_v1",
      "SECURITY DEFINER",
      "REVOKE ALL ON FUNCTION public.lf_operational_executor_admit_v1",
      "GRANT EXECUTE ON FUNCTION public.lf_operational_executor_admit_v1",
      "NOLOGIN NOINHERIT",
      "REVOKE ALL ON FUNCTION public.lf_operational_executor_begin_v1",
      "REVOKE ALL ON FUNCTION public.lf_operational_executor_finish_v1",
      "REVOKE ALL ON FUNCTION public.lf_close_operational_execution_v1",
      "GRANT EXECUTE ON FUNCTION public.lf_operational_executor_begin_v1",
      "GRANT EXECUTE ON FUNCTION public.lf_operational_executor_finish_v1",
      "OPERATIONAL_CLOSE_CANONICAL_JUDGE_BLOCKED",
      "OPERATIONAL_BEGIN_EFFECT_REPLAY_OR_AMBIGUOUS",
      "OPERATIONAL_FINISH_ROUTER_AUTHORITY_STALE",
    ):
      if marker not in source: problems.append("MISSING:"+marker)
    for regex in (
      r"(?i)\bGRANT\s+(?:INSERT|UPDATE|DELETE|ALL)\s+ON\s+(?:TABLE|ALL\s+TABLES)\b",
      r"(?i)\bGRANT\s+(?:pg_write_all_data|service_role|postgres)\b",
      r"(?i)\bCREATE\s+ROLE\s+lf_operation_executor_runtime\s+LOGIN\b",
      r"(?i)\bEXECUTE\s+IMMEDIATE\b",
      r"(?i)\bGRANT\s+ALL\s+PRIVILEGES\b",
      r"(?i)\bUPDATE\s+public\.lf_router_action_registry\b",
      r"(?i)\bDELETE\s+FROM\s+public\.lf_router_action_registry\b",
      r"(?i)\bINSERT\s+INTO\s+public\.lf_operation_execution_steps\b",
    ):
      if re.search(regex,source): problems.append("FORBIDDEN:"+regex)
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\.lf_operational_executor_begin_v1\(",source))!=1:
      problems.append("AMBIGUOUS_BEGIN_FACADE")
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\.lf_operational_executor_finish_v1\(",source))!=1:
      problems.append("AMBIGUOUS_FINISH_FACADE")
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\.lf_close_operational_execution_v1\(",source))!=1:
      problems.append("AMBIGUOUS_CLOSE_FACADE")
    if not source.strip().startswith("-- LF_OPERATION_EXECUTOR governance candidate"):
      problems.append("NOT_A_GOVERNANCE_CANDIDATE")
    if not source.rstrip().endswith("COMMIT;"):
      problems.append("NOT_TRANSACTION_BOUND")
    return problems


class GovernedCandidateStaticTests(unittest.TestCase):
    def test_plpgsql_bodies_have_unique_balanced_delimiters(self):
        source=SQL.read_text(encoding="utf-8")
        tags=["guard","authority","close","begin","finish","principal",
              "admit","role","roles_verify","verify"]
        self.assertEqual(source.count("COMMIT;"),1)
        self.assertTrue(source.rstrip().endswith("COMMIT;"))
        for tag in tags:
            self.assertEqual(source.count("$"+tag+"$"),2,
                             "UNBALANCED_PLPGSQL_DOLLAR_TAG:"+tag)
        for fn in ("admit","begin","finish","assert_principal"):
            self.assertEqual(source.count(
                "CREATE OR REPLACE FUNCTION public.lf_operational_executor_"+fn+"_v1("),1)
        a=source.index("AS $admit$")
        b=source.index("END $admit$;",a)
        self.assertNotIn("DO $role$",source[a:b])
        self.assertNotIn("COMMIT;",source[a:b])
        self.assertIn("p_payload_sha",source[a:b])
        self.assertEqual(source.count("REVOKE ALL ON FUNCTION public.lf_operational_executor_admit_v1"),1)

    def test_durable_verified_decision_required(self):
        source=SQL.read_text(encoding="utf-8")
        start=source.index("CREATE OR REPLACE FUNCTION public.lf_operational_executor_admit_v1(")
        end=source.index("END $admit$;",start)
        admission=source[start:end]
        for item in ("private.fn_lf_human_decision_consume_v1",
                     "private.fn_lf_human_decision_resolve_policy_v1",
                     "private.fn_lf_human_decision_assert_authority_receipt_v1",
                     "request_status' IS DISTINCT FROM 'DECIDED'",
                     "v_subject->>'handler_code' IS DISTINCT FROM p_handler_code",
                     "v_subject->>'payload_sha256' IS DISTINCT FROM p_payload_sha",
                     "v_subject->>'effect_scope' IS DISTINCT FROM p_effect_scope",
                     "v_subject->>'idempotency_key' IS DISTINCT FROM p_idempotency_key",
                     "v_policy->>'state' IS DISTINCT FROM 'ACTIVE'"):
            self.assertIn(item,admission)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_ADMISSION_VERIFIED_DECISION_NOT_CURRENT",
            "UNVERIFIED_CALLER_DECISION")))
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_ADMISSION_AUTHORITY_POLICY_NOT_ACTIVE",
            "POLICY_BYPASSED")))

    def test_no_superseded_human_decision_is_accepted(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertEqual(source.count(
            "private.fn_lf_human_decision_current_for_subject_v1("),2)
        self.assertEqual(source.count(
            "RAISE EXCEPTION 'OPERATIONAL_DECISION_SUPERSEDED_OR_OPEN'"),2)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_DECISION_SUPERSEDED_OR_OPEN",
            "ALLOW_SUPERSEDED_DECISION")))

    def test_mutated_admission_body_is_rejected(self):
        source=SQL.read_text(encoding="utf-8")
        corrupted=source.replace(
            "OR p_approval_receipt->>'decision' IS DISTINCT FROM 'APPROVED'",
            "COMMIT; OR p_approval_receipt->>'decision' IS DISTINCT FROM 'APPROVED'")
        self.assertNotEqual(corrupted.count("COMMIT;"),1)

    def test_candidate_version_can_be_assigned_by_train(self):
        self.assertTrue(SQL.name.endswith(MIGRATION_SUFFIX))
        self.assertEqual(len(list((ROOT/"supabase/migrations").glob("*"+MIGRATION_SUFFIX))),1)

    def test_decision_route_is_pending_never_approved_by_migration(self):
        source=SQL.read_text(encoding="utf-8")
        for marker in (
            "HDR_RULE_LF_OPERATION_EXECUTOR_ALL",
            "HDR_ROUTE_LF_OPERATION_EXECUTOR_DATA_OPERATIONS",
            "'LF_DATA_OPERATIONS'",
            "private.fn_lf_human_decision_rule_sha_v1(",
            "private.fn_lf_human_decision_route_policy_sha_v1(",
            "OPERATIONAL_DECISION_CATALOGUE_COLLISION_REQUIRES_RECONCILIATION",
            "OPERATIONAL_DECISION_PENDING_AUTHORITY_INVARIANT_VIOLATED",
        ):
            self.assertIn(marker,source)
        catalogue=source[source.index("-- Register classification and a *pending* decision route only."):
                         source.index("INSERT INTO public.lf_operation_registry (")]
        self.assertIn("'PENDING_AUTHORITY'",catalogue)
        self.assertNotIn("INSERT INTO private.lf_human_decision_authority_policies_v1",catalogue)
        self.assertNotIn("INSERT INTO private.lf_human_decision_receipts_v1",catalogue)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_DECISION_PENDING_AUTHORITY_INVARIANT_VIOLATED",
            "OPERATIONAL_DECISION_SELF_ACTIVATED")))

    def test_complete_candidate(self):
        self.assertEqual(verify(SQL.read_text(encoding="utf-8")),[])
    def test_cannot_disable_router_authority(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s.replace("lf_router_downstream_authority_validate_v1",
                                         "missing_authority_function")))
    def test_cannot_grant_direct_dml(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s+"\nGRANT UPDATE ON TABLE public.lf_operation_execution TO lf_operation_executor_runtime;\n"))
    def test_cannot_fake_canonical_judge_by_direct_step_inserts(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s.replace("lf_record_operation_step_core_v1","unused_core")))
        self.assertTrue(verify(s+"\nINSERT INTO public.lf_operation_execution_steps SELECT 1;\n"))
    def test_cannot_open_general_role(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s.replace("NOLOGIN NOINHERIT","LOGIN")))
    def test_runtime_role_cannot_admit_its_own_execution(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertIn("TO lf_operational_admission_authority",source)
        self.assertIn("TO lf_operation_executor_runtime",source)
        self.assertIn("g.rolname<>p_expected_role",source)
        self.assertIn("u.rolname=session_user",source)
        self.assertIn("session_user IN ('postgres','authenticator','service_role','programacion_builder')",source)
        self.assertTrue(verify(source.replace("OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID",
                                              "ROUTER_NOT_ENFORCED")))

    def test_all_three_facades_require_same_principal_verifier(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertEqual(source.count(
            "CREATE OR REPLACE FUNCTION public.lf_operational_executor_assert_principal_v1("),1)
        for fname,role in (
            ("admit","lf_operational_admission_authority"),
            ("begin","lf_operation_executor_runtime"),
            ("finish","lf_operation_executor_runtime"),
        ):
            start=source.index("CREATE OR REPLACE FUNCTION public.lf_operational_executor_"+fname+"_v1")
            end=source.index("END $"+fname+"$;",start)
            body=source[start:end]
            self.assertIn("PERFORM public.lf_operational_executor_assert_principal_v1('"+role+"')",body)
            self.assertLess(body.index("PERFORM public.lf_operational_executor_assert_principal_v1"),
                            body.index("v_auth:=") if "v_auth:=" in body else body.index("v_route:="))
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID",
            "AUTHORITY_PRINCIPAL_NOT_CHECKED")))

    def test_extra_role_memberships_fail_closed(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertIn("WITH RECURSIVE effective_memberships(roleid)",source)
        self.assertIn("JOIN effective_memberships parent ON parent.roleid=m.member",source)
        self.assertIn("WHERE granted.rolname<>p_expected_role",source)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_PRINCIPAL_EXTRA_ROLE_MEMBERSHIP_FORBIDDEN",
            "ALLOW_EXTRA_PRIVILEGES")))

    def test_existing_authority_roles_are_fail_closed(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertIn("AND r.rolcanlogin=false AND r.rolinherit=false",source)
        self.assertIn("AND r.rolsuper=false",source)
        self.assertIn("AND r.rolbypassrls=false",source)
        self.assertTrue(verify(source.replace(
          "OPERATIONAL_AUTHORITY_ROLE_CROSS_MEMBERSHIP_FORBIDDEN","UNSAFE_ROLE_REUSE")))

    def test_independent_admission_provenance_cannot_be_removed(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertIn("operational_authority_receipt",source)
        self.assertIn("created_by_execution_id",source)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_BEGIN_INDEPENDENT_ADMISSION_PROVENANCE_MISSING",
            "UNGUARDED")))

    def test_generic_execution_reservation_is_reused(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^  v_reserved:=public\.fn_lf_operation_reserve_execution_v1\(",source)),1)
        self.assertIn("RESERVED_NEW_EXECUTION",source)
        self.assertTrue(verify(source.replace(
          "OPERATIONAL_ADMISSION_REPLAY_OR_EXECUTION_MISMATCH","PERMIT_REPLAY")))

    def test_cannot_redirect_migration_route(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s.replace("MIGRATION_TRAIN_ROUTE_NOT_PRESERVED","NO_ROUTE_GUARD")))


if __name__=="__main__":
    unittest.main()
