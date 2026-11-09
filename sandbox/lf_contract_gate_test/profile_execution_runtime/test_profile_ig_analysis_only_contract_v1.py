"""Static source-first controls for the governed IG BLOCKED / read-only analysis scope.

These do NOT claim SQL runtime success. LIVE E2E and source parity remain required.
"""
import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CANDIDATE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/lf_profile_ig_blocked_analysis_only_candidate_v1.sql"
BEGIN = "  -- Scope validation and IG security clearance are distinct decisions.\n"
END = ("  IF coalesce((v_ig->>'applicable')::boolean,false)\n"
       "     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN")


class ProfileIGReadOnlyAnalysisSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = CANDIDATE.read_text(encoding="utf-8")
        cls.original_source = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION"):]
        assert cls.original_source.endswith("$function$\n;\n")
        assert cls.sql.count(BEGIN) == 1
        assert cls.sql.count(END) == 1
        cls.guard = cls.original_source.split(BEGIN, 1)[1].split(END, 1)[0]
        cls.prior_source = cls.original_source.replace(BEGIN + cls.guard, "", 1).removesuffix(";\n")

    def test_atomic_deployment_prestate_requires_exact_live_source(self):
        self.assertIn("DO $lf_profile_ig_analysis_prestate$", self.sql)
        self.assertIn("'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure", self.sql)
        self.assertIn("IS DISTINCT FROM '231072262af6be9fe3e03e68d1550c7d'", self.sql)
        self.assertIn("RAISE EXCEPTION 'BLOCK_PROFILE_IG_ANALYSIS_BASELINE_DRIFT'", self.sql)

    def test_exact_live_baseline_preserved_outside_one_guard(self):
        self.assertEqual(
            hashlib.md5(self.prior_source.encode("utf-8")).hexdigest(),
            "231072262af6be9fe3e03e68d1550c7d",
        )

    def test_scope_preconditions_fail_closed(self):
        for expr in (
            "v_task_requirement->>'status'='REQUIRED'",
            "v_exec.manifest->>'read_only'='true'",
            "v_exec.manifest->>'no_write'='true'",
            "v_exec.manifest->>'no_promotion'='true'",
            "v_exec.manifest->>'automatic_impact'='false'",
            "v_exec.manifest->>'governed_repair_write'='false'",
            "p_handoff#>>'{scope,target_type}'='PANTALLA'",
        ):
            with self.subTest(expr=expr):
                self.assertIn(expr, self.guard)

    def test_ig_blocked_unchanged_and_bound_to_same_scope(self):
        for expr in (
            "v_ig->>'applicable'='true'",
            "v_ig->>'status'='BLOCKED'",
            "v_ig->>'decision'='BLOCKED'",
            "v_ig->>'continuation_allowed'='false'",
            "v_ig->>'blocking_code'='BLOCK_PROFILE_INPUT_GOVERNANCE'",
            "v_ig->>'profile_code'=v_exec.target_code",
            "v_ig->>'consumer'='CONTEXT_PACK'",
            "v_ig->>'binding_mode'='DIRECT_PROFILE'",
            "v_ig#>>'{governance_result,status}'='BLOCKED'",
            "v_ig#>>'{governance_result,pantalla_id}'=v_ig->>'pantalla_id'",
            "v_ig#>>'{governance_result,owner_interruption_required}'='false'",
            "v_ig#>>'{governance_result,promotion_authorized}'='false'",
            "v_ig#>>'{governance_result,production_authorized}'='false'",
            "v_ig#>>'{governance_result,remediation_state}'='INTERNAL_REMEDIATION_REQUIRED'",
        ):
            with self.subTest(expr=expr):
                self.assertIn(expr, self.guard)

    def test_current_finding_receipt_and_hash_required(self):
        for expr in (
            "v_ig#>>'{governance_result,run_id}' ~ '^[1-9][0-9]*$'",
            "v_ig#>>'{governance_result,output_sha256}','') ~ '^[0-9a-f]{64}$'",
            "v_ig#>>'{governance_result,predecision_crosscheck,status}'='CANONICAL_READBACK_ONLY'",
            "v_ig#>>'{governance_result,predecision_crosscheck,run_id}'=v_ig#>>'{governance_result,run_id}'",
            "v_ig#>>'{governance_result,predecision_crosscheck,deterministic_finding_count}','') ~ '^[1-9][0-9]*$'",
        ):
            with self.subTest(expr=expr):
                self.assertIn(expr, self.guard)

    def test_output_distinguishes_input_scope_from_ig_security_clearance(self):
        for expr in (
            "'status','READY'",
            "'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION'",
            "'activation_trigger_match',true",
            "'scope_authority_packet',v_scope->'scope_authority_packet'",
            "'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256'",
            "'analysis_scope','READ_ONLY_WITH_IG_FINDINGS'",
            "'input_validation_only',true",
            "'ig_security_state','BLOCKED'",
            "'ig_security_clearance',false",
            "'ig_continuation_allowed',false",
            "'production_authorized',false",
            "'promotion_authorized',false",
            "'mutation_authorized',false",
            "'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT')",
            "'input_governance',",
            "v_ig||jsonb_build_object(",
            "'router_reentry_required',false",
        ):
            with self.subTest(expr=expr):
                self.assertIn(expr, self.guard)

    def test_no_ddl_or_security_policy_mutation_inside_guard(self):
        upper = self.guard.upper()
        for forbidden in ("UPDATE ", "DELETE ", "INSERT ", "GRANT ", "REVOKE ",
                          "DROP ", "ALTER ", "SECURITY DEFINER", "SET ROLE ",
                          "'IG_SECURITY_STATE','READY'", "'MUTATION_AUTHORIZED',TRUE"):
            with self.subTest(expr=forbidden):
                self.assertNotIn(forbidden, upper)

    def test_existing_denials_and_runtime_required_remain_intact(self):
        self.assertIn("'BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_ORCHESTRATOR_INVALID'", self.prior_source)
        self.assertIn("'INPUT_GOVERNANCE_RUNTIME_REQUIRED'", self.prior_source)
        self.assertIn("'RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'", self.prior_source)
        self.assertIn("'BLOCK_PROFILE_INPUT_VALIDATE_SCOPE_NOT_READY'", self.prior_source)
        self.assertIn("'BLOCK_PROFILE_SCREEN_SELECTION_RECEIPT_INVALID'", self.prior_source)
        self.assertIn("'status','READY'", self.prior_source)

    def test_security_definer_and_search_path_preserved_exactly(self):
        self.assertRegex(self.original_source, r"(?i)SECURITY DEFINER")
        self.assertIn("SET search_path TO 'pg_catalog', 'public'", self.original_source)
        self.assertNotIn("GRANT EXECUTE", self.original_source)


if __name__ == "__main__":
    unittest.main()
