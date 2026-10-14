#!/usr/bin/env python3
"""Static, offline admission tests. NOT a substitute for a live transactional test.

Candidate SQL is intentionally NOT deployed; no execution against Supabase occurs.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
GENERIC = ROOT / "operation_candidate_v1.sql"
PILOT = ROOT / "ig_m105_cp2_provider_candidate_v1.sql"
REGISTRATION = ROOT / "operation_registration_candidate_v1.sql"
FAMILIES = {
    "STATES", "SECURITY", "API_DATA_CONTRACT",
    "FRESHNESS_INVALIDATION", "ACCESSIBILITY",
}


class CandidateAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generic = GENERIC.read_text(encoding="utf8")
        cls.provider = PILOT.read_text(encoding="utf8")
        cls.registration = REGISTRATION.read_text(encoding="utf8")

    def test_both_sources_outside_migrations_and_explicitly_candidate(self):
        self.assertNotIn("supabase/migrations", str(GENERIC))
        for source in (self.generic, self.provider):
            self.assertIn("CANDIDATE", source.splitlines()[0].upper())
            self.assertIn("CREATE OR REPLACE FUNCTION", source)

    def test_generic_has_no_m105_or_screen_literals(self):
        for value in ("M10.5", "ONB_001", "931", "INPUT_GOVERNANCE"):
            self.assertNotIn(value, self.generic)

    def test_scope_is_one_checkpoint_and_router_execution_bound(self):
        for term in (
            "CIERRE_CHECKPOINT_INGENIERIA_LF", "ENGINEERING_CHECKPOINT",
            "CHECKPOINT_CLOSE", "v_exec.target_code IS DISTINCT FROM",
            "v_exec.operation_code IS DISTINCT FROM",
            "v_exec.status IS DISTINCT FROM 'IN_PROGRESS'",
            "lf_router_downstream_authority_consumer_v1",
            "lf_router_downstream_authority_validate_v1",
            "v_authority->>'applicable' IS DISTINCT FROM 'true'",
            "v_authority->>'valid' IS DISTINCT FROM 'true'",
        ):
            self.assertIn(term, self.generic)

    def test_no_client_claimed_pass_or_provider_sql(self):
        self.assertNotIn("p_status", self.generic)
        self.assertNotIn("p_observed", self.generic)
        self.assertNotIn("p_provider_sql", self.generic)
        self.assertIn("engineering_checkpoint_closure_providers_v1", self.generic)
        self.assertIn("v_binding.binding_state='ACTIVE'", self.generic.replace("b.binding_state='ACTIVE'", "v_binding.binding_state='ACTIVE'"))
        self.assertIn("to_regprocedure(", self.generic)
        self.assertIn("v_provider_security", self.generic)

    def test_hash_and_receipt_are_guarded(self):
        for term in (
            "coalesce(v_exec.request_sha256,'') !~",
            "coalesce(v_receipt_sha,'') !~",
            "fn_engineering_action_spec_assertion_contract_v1",
            "fn_engineering_checkpoint_assertion_record_v1",
            "fn_engineering_checkpoint_transition_v1",
            "fn_v09_sha256_jsonb(c.assertion_receipt)",
            "lf_operation_effect_guard", "state='SUCCEEDED'",
        ):
            self.assertIn(term, self.generic)

    def test_generic_reuses_transversal_and_never_replaces_it(self):
        banned = ("CREATE OR REPLACE FUNCTION public.lf_router_resolve_v1",
                  "CREATE OR REPLACE FUNCTION programacion.fn_guard_engineering_material_checkpoint_done_v1",
                  "DROP TRIGGER", "ALTER ROLE", "DISABLE TRIGGER",
                  "DB_WRITE_TRANSPORT", "MERGE TRAIN")
        for term in banned:
            if term in ("DB_WRITE_TRANSPORT", "MERGE TRAIN"):
                self.assertNotIn(term, re.sub(r"(?m)^--.*$", "", self.generic))
            else:
                self.assertNotIn(term, self.generic)
        self.assertIn("REVOKE ALL ON FUNCTION programacion.fn_engineering_checkpoint_close_governed_v1", self.generic)
        self.assertNotIn("GRANT EXECUTE", self.generic)

    def test_order_no_write_before_authority_or_provider(self):
        self.assertLess(self.generic.index("lf_router_downstream_authority_validate_v1"),
                        self.generic.index("EXECUTE format('SELECT %I.%I"))
        self.assertLess(self.generic.index("EXECUTE format('SELECT %I.%I"),
                        self.generic.index("fn_engineering_checkpoint_assertion_record_v1"))
        self.assertLess(self.generic.index("fn_engineering_checkpoint_assertion_record_v1"),
                        self.generic.index("fn_engineering_checkpoint_transition_v1"))
        self.assertLess(self.generic.index("fn_engineering_checkpoint_transition_v1"),
                        self.generic.index("SET state='SUCCEEDED'"))

    def test_failure_fails_closed_and_is_atomic_by_exception(self):
        for term in ("ENGINEERING_CLOSE_AUTHORITY_REQUIRED",
                     "ENGINEERING_CLOSE_PROVIDER_PROOF_FAILED",
                     "ENGINEERING_CLOSE_EFFECT_NOT_RESERVED",
                     "ENGINEERING_CLOSE_READBACK_MISMATCH"):
            self.assertIn("RAISE EXCEPTION '" + term, self.generic)
        self.assertNotIn("EXCEPTION WHEN OTHERS", self.generic)

    def test_pilot_exactly_five_distinct_families(self):
        self.assertEqual(5, len(FAMILIES))
        for fam in FAMILIES:
            self.assertIn("'" + fam + "'", self.provider)
        self.assertIn("v.valid_family_count IS DISTINCT FROM 5", self.provider)
        self.assertIn("v.authorizes_production IS DISTINCT FROM false", self.provider)
        self.assertIn("fn_input_run_is_source_current", self.provider)
        self.assertIn("a.validator_identity IS NOT NULL", self.provider)
        self.assertIn("a.validator_sha256 ~", self.provider)


    def test_registration_cannot_activate_or_authorize_write(self):
        self.assertIn("'CANDIDATO_READ_ONLY'", self.registration)
        self.assertIn("'CANDIDATE'", self.registration)
        self.assertIn("write_allowed,status", self.registration)
        self.assertIn("false,false,false,'CANDIDATE'", self.registration)
        self.assertNotIn("GRANT EXECUTE", self.registration)
        self.assertNotIn("UPDATE public.lf_activos", self.registration)
        self.assertNotIn("UPDATE public.lf_operation_registry", self.registration)

    def test_pilot_binding_not_active(self):
        self.assertIn("'CANDIDATE','M105_CP2_REPRESENTATIVE_SAMPLE_V1'", self.provider)
        self.assertNotIn("'ACTIVE','M105_CP2_REPRESENTATIVE_SAMPLE_V1'", self.provider)


if __name__ == "__main__":
    unittest.main(verbosity=2)
