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
      "CREATE OR REPLACE FUNCTION public.lf_operational_executor_admit_v1",
      "lf_operational_admission_authority",
      "OPERATIONAL_ADMISSION_INDEPENDENT_PRINCIPAL_REQUIRED",
      "OPERATIONAL_ADMISSION_ROLE_NOT_INDEPENDENT",
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
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\\.lf_operational_executor_begin_v1\\(",source))!=1:
      problems.append("AMBIGUOUS_BEGIN_FACADE")
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\\.lf_operational_executor_finish_v1\\(",source))!=1:
      problems.append("AMBIGUOUS_FINISH_FACADE")
    if len(re.findall(r"(?m)^CREATE OR REPLACE FUNCTION public\\.lf_close_operational_execution_v1\\(",source))!=1:
      problems.append("AMBIGUOUS_CLOSE_FACADE")
    if not source.strip().startswith("-- LF_OPERATION_EXECUTOR governance candidate"):
      problems.append("NOT_A_GOVERNANCE_CANDIDATE")
    if not source.rstrip().endswith("COMMIT;"):
      problems.append("NOT_TRANSACTION_BOUND")
    return problems


class GovernedCandidateStaticTests(unittest.TestCase):
    def test_candidate_version_can_be_assigned_by_train(self):
        self.assertTrue(SQL.name.endswith(MIGRATION_SUFFIX))
        self.assertEqual(len(list((ROOT/"supabase/migrations").glob("*"+MIGRATION_SUFFIX))),1)

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
        self.assertIn("granted.rolname='lf_operation_executor_runtime'",source)
        self.assertIn("member.rolname=session_user",source)
        self.assertIn("session_user IN ('postgres','authenticator','service_role')",source)
        self.assertTrue(verify(source.replace("OPERATIONAL_ADMISSION_ROLE_NOT_INDEPENDENT",
                                              "ROUTER_NOT_ENFORCED")))

    def test_independent_admission_provenance_cannot_be_removed(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertIn("operational_authority_receipt",source)
        self.assertIn("created_by_execution_id",source)
        self.assertTrue(verify(source.replace(
            "OPERATIONAL_BEGIN_INDEPENDENT_ADMISSION_PROVENANCE_MISSING",
            "UNGUARDED")))

    def test_generic_execution_reservation_is_reused(self):
        source=SQL.read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^  v_reserved:=public\\.fn_lf_operation_reserve_execution_v1\\(",source)),1)
        self.assertIn("RESERVED_NEW_EXECUTION",source)
        self.assertTrue(verify(source.replace(
          "OPERATIONAL_ADMISSION_REPLAY_OR_EXECUTION_MISMATCH","PERMIT_REPLAY")))

    def test_cannot_redirect_migration_route(self):
        s=SQL.read_text(encoding="utf-8")
        self.assertTrue(verify(s.replace("MIGRATION_TRAIN_ROUTE_NOT_PRESERVED","NO_ROUTE_GUARD")))


if __name__=="__main__":
    unittest.main()
