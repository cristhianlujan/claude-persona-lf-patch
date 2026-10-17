"""Source-level regression for ACT-0001 canonical identity and checkpoint artifact binding.

Run with:
  python -m unittest discover -s sandbox/lf_contract_gate_test/canonical_route_guard \
      -p 'test_router_exact_identity_source_v1.py' -v

This is NOT a live DB execution or a provider/consumer attestation.
"""
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[3]
MIGRATION = REPO / (
    "supabase/migrations/"
    "20261017033000_lf_router_exact_identity_structured_discovery_v1.sql"
)


class RouterExactIdentityMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.function = cls.sql.split(
            "CREATE OR REPLACE FUNCTION public.lf_router_resolve_v1", 1
        )[-1].split("\ninsert into public.lf_error_knowledge(", 1)[0]

    def test_source_currentness_guard(self):
        self.assertIn("ROUTER_SOURCE_CURRENTNESS_DRIFT", self.sql)
        self.assertIn("29280cb8b2cb50c97d41134e92d7de2e", self.sql)

    def test_no_keyword_score_as_asset_identity(self):
        for unsafe in (
            "count(*)*25", "count(*)*10", "count(*)*2",
            "then 1200 else 0", "then 900 else 0",
            "max(800)", "max(300)",
        ):
            self.assertNotIn(unsafe, self.function.lower())
        self.assertIn("v_exact_asset_candidates", self.function)
        self.assertIn("v_exact_asset_count", self.function)

    def test_full_asset_identity_not_word_tokens(self):
        for field in ("b.codigo_activo", "b.nombre_canonico", "b.aliases"):
            self.assertIn(field, self.function)
        self.assertIn("BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE", self.function)
        self.assertIn("POSITIVE_NEGATIVE_TARGET_ROLES_UNATTESTED", self.function)

    def test_repository_artifact_bound_to_checkpoint_declared_target(self):
        for expression in (
            "programacion.engineering_plan_units",
            "programacion.engineering_work_items",
            "programacion.engineering_work_checkpoints",
            "sp.value#>'{target,mutation_artifacts}'",
            "a.obj->>'role'='MUTATION_TARGET'",
            "pu.disposition='ASSIGNED'",
            "lower(split_part(a.obj->>'path',':',2))",
            "match_count",
        ):
            self.assertIn(expression, self.sql)

    def test_request_paths_materialized_once_and_prefilter_all_references(self):
        for expression in (
            "with requested_paths as materialized",
            "regexp_matches(",
            "as m(path_match)",
            "cross join programacion.engineering_plan_units",
            "position(rp.path in lower(pu.unit_metadata::text))>0",
            "exact_refs as materialized",
        ):
            self.assertIn(expression, self.sql.lower())

    def test_subject_does_not_become_executor(self):
        for code in (
            "BLOCK_ARTIFACT_CONSUMER_UNATTESTED",
            "BLOCK_MULTIPLE_ARTIFACT_TARGETS",
            "BLOCK_EXACT_ARTIFACT_BINDING_UNRESOLVED",
            "'executor_selection_state','NOT_SELECTED'",
            "'downstream_execution_allowed',false",
            "EXECUTOR_AND_REQUEST_SCOPE_UNATTESTED",
            "request_sha256",
        ):
            self.assertIn(code, self.function)

    def test_artifact_discovery_before_lifecycle_selection(self):
        self.assertLess(
            self.function.index("lf_router_declared_artifact_candidates_v1"),
            self.function.index("Actor-role guard after canonical discovery"),
        )
        self.assertLess(
            self.function.index("Actor-role guard after canonical discovery"),
            self.function.index("select * into v_rule"),
        )

    def test_preserves_existing_operation_and_input_gov_gates(self):
        for source in (
            "public.lf_router_action_registry",
            "public.lf_operation_registry",
            "public.lf_operation_contracts",
            "public.lf_operation_step_contracts",
            "public.v_lf_operation_policy_snapshot",
            "programacion.fn_lf_router_input_governance_resolve_v1",
            "BLOCK_EXECUTOR_CAPABILITY_UNATTESTED",
        ):
            self.assertIn(source, self.function)

    def test_no_case_specific_artifact_in_router(self):
        for target in ("no_false_pass.py", "M10.7", "PAULO-165", "ACT-0013"):
            self.assertNotIn(target, self.function)

    def test_semantic_handoff_preserves_full_literal_and_no_execution(self):
        for required in (
            "LF_ROUTER_INTENT_HANDOFF_V1",
            "public.lf_router_intent_handoff_v1(",
            "'literal_request',p_request_text",
            "'candidate_subjects',coalesce(p_candidates",
            "'positive_target_refs','[]'::jsonb",
            "'excluded_target_refs','[]'::jsonb",
            "'scope_binding_state','UNATTESTED'",
            "'semantic_consumer_receipt',null",
            "'downstream_execution_allowed',false",
        ):
            self.assertIn(required, self.sql)

    def test_ambiguous_assets_and_negations_never_promote_identity(self):
        for required in (
            "BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE",
            "BLOCK_SCOPE_SEMANTICS_UNATTESTED",
            "POSITIVE_NEGATIVE_SCOPE_NOT_BOUND",
            "v_action <> 'ASSET_INSPECTION'",
            "p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'",
        ):
            self.assertIn(required, self.sql)

    def test_transactional_sql_regressions_cover_adversarial_paths(self):
        for required in (
            "ROUTER_SMOKE_EXACT_ARTIFACT_UNSAFE",
            "ROUTER_SMOKE_MULTIPLE_EXCLUSION_UNSAFE",
            "ROUTER_SMOKE_NEGATED_CREATE_UNSAFE",
            "ROUTER_SMOKE_TYPED_HINT_NEGATION_BYPASS",
            "ROUTER_SMOKE_SCREEN_EXECUTOR_BOUNDARY_UNSAFE",
        ):
            self.assertIn(required, self.sql)

    def test_no_prod_or_privilege_activation(self):
        for side_effect in (
            "grant execute", "security definer", "alter policy",
            "create trigger", "create table", "runtime_enabled=true",
        ):
            self.assertNotIn(side_effect, self.sql.lower())

    def test_ekb_is_recorded_by_migration_not_fake_live_receipt(self):
        self.assertIn("LF-ROUTER-ACT0001-LEXICAL-ARTIFACT-MISIDENTITY", self.sql)
        self.assertIn("where not exists(", self.sql.lower())


if __name__ == "__main__":
    unittest.main()
