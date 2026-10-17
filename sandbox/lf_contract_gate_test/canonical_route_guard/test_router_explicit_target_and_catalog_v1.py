"""ACT-0001 explicit-target authority and DB Train catalog-readback contract tests.

These are source tests. Transactional SQL in the migration independently probes
the live route, catalog and read-only preservation; this suite never asserts
production authority, semantic-consumer execution, or an actual DB apply.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
MATCHES = list(ROOT.glob(
    "supabase/migrations/*_lf_router_explicit_target_semantic_admission_v1.sql"
))
if len(MATCHES) != 1:
    raise AssertionError(f"Expected one canonical migration: {MATCHES}")
MIG = MATCHES[0]


def get_def(sql: str, name: str, next_marker: str) -> str:
    begin = f"create or replace function public.{name}"
    idx = sql.lower().find(begin)
    if idx < 0:
        raise AssertionError(f"Definition not present: {name}")
    return sql[idx + len(begin):].split(next_marker, 1)[0]


class RouterTypedTargetCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIG.read_text(encoding="utf-8")
        cls.router = get_def(
            cls.sql, "lf_router_resolve_v1", "\n$function$;"
        )
        cls.build = get_def(
            cls.sql, "lf_router_downstream_authority_build_v1", "\n$function$;"
        )
        cls.validate = get_def(
            cls.sql, "lf_router_downstream_authority_validate_v1", "\n$function$;"
        )
        cls.post = get_def(
            cls.sql, "lf_router_downstream_authority_post_effect_validate_v1",
            "\n$function$;"
        )

    def test_exact_source_revisions_frozen_before_migration(self):
        for expected in (
            "ROUTER_EXPLICIT_TARGET_SOURCE_CURRENTNESS_DRIFT",
            "ROUTER_DOWNSTREAM_BUILD_SOURCE_DRIFT",
            "ROUTER_DOWNSTREAM_VALIDATE_SOURCE_DRIFT",
            "ROUTER_DOWNSTREAM_POST_SOURCE_DRIFT",
        ):
            self.assertIn(expected, self.sql)

    def test_explicit_target_not_action_authority(self):
        for expected in (
            "nullif(btrim(coalesce(p_target_hint,'')),'') is not null",
            "public.lf_router_action_registry ar",
            "requires_existing_target or ar.requires_missing_target",
            "BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED",
            "'candidate_asset_type',v_type_hint",
            "'candidate_action_code',v_action",
            "'action_code',null,'operation_code',null",
            "'downstream_execution_allowed',false",
        ):
            self.assertIn(expected, self.router)

    def test_neither_mode_nor_hint_can_forge_user_scope(self):
        self.assertNotIn("p_distribution_mode='DIRECT'", self.router)
        self.assertNotIn("p_distribution_mode='ROUTER'", self.router)
        for expected in (
            "ROUTER_EXPLICIT_MUTATION_FALSE_READY",
            "ROUTER_DISTRIBUTION_MODE_SPOOFED",
        ):
            self.assertIn(expected, self.sql)

    def test_operation_catalog_readback_is_not_router_or_semantics_engine(self):
        source = get_def(
            self.sql, "lf_router_operation_catalog_match_v1", "\n$catalog$;"
        )
        for expected in (
            "lf_router_downstream_authority_consumer_v1",
            "public.lf_router_action_registry",
            "public.lf_operation_registry",
            "public.lf_operation_contracts",
            "public.lf_operation_step_contracts",
            "public.v_lf_operation_policy_snapshot",
            "'route_valid',true",
            "'scope_attested',false",
            "'downstream_execution_allowed',false",
            "ROUTE_CATALOG_VALID",
        ):
            self.assertIn(expected, source)
        self.assertNotIn("lf_router_resolve_v1(", source)

    def test_downstream_internal_validation_no_synthetic_request(self):
        for source in (self.build,self.validate,self.post):
            self.assertIn("lf_router_operation_catalog_match_v1(", source)
            self.assertIn("ROUTE_CATALOG_VALID",source)
            self.assertIn("route_valid",source)
            self.assertNotIn("canonical authority bind",source)
            self.assertNotIn("public.lf_router_resolve_v1(",source)

    def test_downstream_receipts_explicitly_route_only(self):
        self.assertIn("'route_eligibility_only',true",self.build)
        self.assertIn("'scope_attested',false",self.build)
        self.assertIn("'public.lf_router_operation_catalog_match_v1'",self.build)
        self.assertIn("'public.lf_router_resolve_v1'",self.validate)

    def test_production_checks_fail_closed_without_new_engine(self):
        for expected in (
            "ROUTER_DB_TRAIN_CATALOG_ELIGIBILITY_REGRESSED",
            "ROUTER_TECHNICAL_REQUEST_GUARD_REGRESSED",
            "ROUTER_READONLY_INSPECTION_REGRESSED",
            "ROUTER_FREEFORM_MULTIOBJECT_REGRESSED",
        ):
            self.assertIn(expected, self.sql)
        self.assertIn("LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS",self.sql)

    def test_no_security_definer_or_dml_bypass(self):
        catalog = get_def(
            self.sql,"lf_router_operation_catalog_match_v1","\n$catalog$;"
        )
        self.assertNotIn("security definer",catalog.lower())
        self.assertNotIn("insert into",catalog.lower())
        self.assertNotIn("update public.",catalog.lower())
        self.assertNotIn("delete from",catalog.lower())

    def test_existing_obligation_to_bind_original_request_remains(self):
        self.assertIn("'semantic_resolution_required',true",self.router)
        self.assertIn("public.lf_router_intent_handoff_v1(",self.router)
        self.assertIn("EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY",self.router)


if __name__ == "__main__":
    unittest.main()
