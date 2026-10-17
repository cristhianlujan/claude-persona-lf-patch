"""Source/contract regression for generic unstructured-mutating-intent fail closed.

Runtime functionality is independently asserted by transactional SQL probes
inside the migration; these tests are NOT that live readback.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
_MATCHES = list(ROOT.glob("supabase/migrations/*_lf_router_unstructured_mutation_fail_closed_v1.sql"))
if len(_MATCHES) != 1:
    raise AssertionError(f"Expected exactly one canonical migration: {_MATCHES!r}")
MIG = _MATCHES[0]


class UnstructuredIntentSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIG.read_text(encoding="utf-8")
        cls.router = cls.sql.split(
            "CREATE OR REPLACE FUNCTION public.lf_router_resolve_v1", 1
        )[1].split("\n$function$;", 1)[0]

    def test_current_source_is_frozen(self):
        self.assertIn("ROUTER_INTENT_BOUNDARY_SOURCE_DRIFT", self.sql)
        self.assertIn("2c94edcb7982373d5b761f57ef790741", self.sql)

    def test_free_form_mutating_action_is_never_authority(self):
        self.assertIn("v_action <> 'ASSET_INSPECTION'", self.router)
        for field in ("p_target_hint", "p_action_hint", "p_asset_type_hint"):
            self.assertIn("nullif(btrim(coalesce("+field+",'')),'') is null",
                          self.router)
        self.assertIn("BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED",
                      self.router)
        self.assertIn("'downstream_execution_allowed',false", self.router)

    def test_action_and_asset_type_are_candidates_not_selected_authority(self):
        self.assertIn("'action_code',null,'operation_code',null", self.router)
        self.assertIn("'candidate_action_code',v_action", self.router)
        self.assertIn("'candidate_asset_type',v_type_hint", self.router)
        self.assertIn("NATURAL_LANGUAGE_ACTION_SCOPE_NOT_ATTESTED",
                      self.router)

    def test_exact_request_fidelity_and_semantic_consumer_handoff(self):
        self.assertIn("public.lf_router_intent_handoff_v1(", self.router)
        self.assertIn("p_request_text,", self.router)
        self.assertIn("'next_governance_entrypoint',"
                      "'GOVERNED_SEMANTIC_CONSUMER_REQUIRED'", self.router)
        self.assertIn("request_sha256", self.router)

    def test_rule_applies_before_any_registry_authorization(self):
        self.assertLess(
            self.router.index("BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED"),
            self.router.index("select * into v_rule"),
        )

    def test_canonical_discovery_and_positive_inspection_are_preserved(self):
        for needed in (
            "public.lf_router_declared_artifact_candidates_v1",
            "BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE",
            "BLOCK_ARTIFACT_CONSUMER_UNATTESTED",
            "BLOCK_SCOPE_SEMANTICS_UNATTESTED",
            "BLOCK_EXECUTOR_CAPABILITY_UNATTESTED",
            "READY_INSPECTION",
            "public.lf_operation_registry",
            "programacion.fn_lf_router_input_governance_resolve_v1",
        ):
            self.assertIn(needed, self.router)

    def test_no_new_router_or_privilege_bypass(self):
        for forbidden in (
            "security definer", "grant execute", "create trigger",
            "runtime_enabled=true", "alter policy", "create table",
        ):
            self.assertNotIn(forbidden, self.sql.lower())

    def test_runtime_sql_smoke_covers_root_cause_cases(self):
        for name in (
            "ROUTER_MULTIOBJECT_FALSE_READY",
            "ROUTER_CONDITIONAL_FALSE_READY",
            "ROUTER_UNEXPRESSED_EXCLUSION_FALSE_READY",
            "ROUTER_EXACT_ARTIFACT_REGRESSED",
            "ROUTER_POSITIVE_INSPECTION_REGRESSED",
        ):
            self.assertIn(name, self.sql)
        self.assertIn("is distinct from", self.sql.lower())

    def test_ekb_append_only_root_cause(self):
        self.assertIn("LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY",
                      self.sql)
        self.assertIn("where not exists(", self.sql.lower())


if __name__ == "__main__":
    unittest.main()
