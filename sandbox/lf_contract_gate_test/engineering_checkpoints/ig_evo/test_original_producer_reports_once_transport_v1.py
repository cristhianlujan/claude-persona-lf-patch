"""Structural gates for candidate migration. This is NOT a database execution receipt."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
SQL = ROOT / "supabase/migrations/20261107203000_lf_ig_original_producer_reports_transport_v1.sql"
DOC = ROOT / "docs/input-governance/IG_EVO_ORIGINAL_PRODUCER_REPORT_TRANSPORT_V1.md"


class OriginalProducerTransportContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text(encoding="utf-8")
        cls.doc = DOC.read_text(encoding="utf-8")

    def test_original_source_hashes_exact(self):
        for sha in (
            "9a04278f4a4b7345da88a5ae1d7875e4",
            "071fdce8c6ac9851e8106afd511fd3fb",
            "ab091d641cc1d3d923d20c0db96d9bc5",
        ):
            with self.subTest(sha=sha):
                self.assertIn(sha, self.sql)
        self.assertEqual(self.sql.count("SOURCE_DRIFT"), 3)

    def test_one_capture_per_run_with_no_overwrite(self):
        self.assertIn("run_id bigint PRIMARY KEY", self.sql)
        self.assertIn("INSERT INTO programacion.input_governance_producer_raw_v1", self.sql)
        self.assertNotIn("ON CONFLICT", self.sql)
        self.assertNotRegex(self.sql, r"UPDATE\s+programacion\.input_governance_producer_raw_v1")
        self.assertIn("original_curator_output_sha256", self.sql)

    def test_same_curator_payload_stored_then_returned(self):
        self.assertIn("v_full_original_response:=v_result || jsonb_build_object", self.sql)
        self.assertIn("v_full_original_response,\n      programacion.fn_v09_sha256_jsonb(v_full_original_response)", self.sql)
        self.assertIn("RETURN v_full_original_response", self.sql)

    def test_g1_carries_raw_graph_from_existing_computation(self):
        self.assertIn("'raw_graph',g.doc", self.sql)
        self.assertIn("fn_input_governance_materialize_gap_proposals_v1(bigint)", self.sql)
        self.assertNotIn("programacion.fn_ig_evo_rule_graph_inventory_v1(", self.sql)

    def test_g1_full_scope_comes_from_canonical_effective_rule_selector(self):
        sql = self.sql
        count = sql.split("$new_count$")[1]
        roots = sql.split("$new_roots$")[1]
        self.assertIn("count(distinct e.regla_id)", count)
        self.assertIn("select distinct e.regla_id AS rule_id", roots)
        for selected in (count, roots):
            self.assertIn(
                "fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE')",
                selected,
            )
            self.assertIn("e.binding_source<>'DERIVED_GLOBAL'", selected)
            self.assertIn("rr.estado in ('VIGENTE','CANDIDATO')", selected)
        self.assertNotIn("v_r2_r6_scan", roots)
        self.assertNotIn("limit 8", roots.lower())
        self.assertNotIn("LIMIT 71", roots.upper())

    def test_any_number_of_roots_requires_exact_accounting(self):
        self.assertIn(
            "jsonb_array_length(v_ig_evo_graph_index)<>v_ig_evo_graph_total",
            self.sql,
        )
        self.assertIn("ALL_CANONICALLY_EFFECTIVE_SCREEN_RULES", self.sql)
        self.assertIn(
            "ALL_EFFECTIVE_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS", self.sql
        )
        self.assertIn("ig_evo_graph_total_effective_rules", self.sql)
        reader = self.sql.split(
            "CREATE OR REPLACE FUNCTION programacion.fn_input_governance_producer_raw_read_v1"
        )[1].split("$raw_get$;")[0]
        self.assertIn("'graph_eligible_rule_count'", reader)
        self.assertIn("'graph_captured_root_count'", reader)
        self.assertIn("'graph_truncated'", reader)
        self.assertNotIn(")>8", reader)

    def test_internal_graph_truncation_is_not_misreported_complete(self):
        self.assertIn("'graph_limit_hit'='true'", self.sql)
        self.assertIn("ig_evo_graph_internal_truncation_count", self.sql)
        self.assertIn("ig_evo_graph_internal_truncated_rule_ids", self.sql)
        self.assertIn(
            "ALL_EFFECTIVE_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION",
            self.sql,
        )
        self.assertIn("'graph_internal_truncation_count'", self.sql)
        self.assertIn("IG_G1_ROOT_SCOPE_RESIDUAL", self.sql)

    def test_getter_is_pure_storage_read_without_r_scans(self):
        getter = self.sql.split(
            "CREATE OR REPLACE FUNCTION programacion.fn_input_governance_producer_raw_read_v1"
        )[1].split("$raw_get$;")[0]
        self.assertIn("SELECT * INTO v_report FROM programacion.input_governance_producer_raw_v1", getter)
        self.assertNotRegex(getter, r"fn_ig_evo_r[1-6]_\w+\s*\(")
        self.assertNotIn("fn_ig_evo_rule_graph_inventory_v1(", getter)
        self.assertNotIn("fn_input_governance_curator_materialize_v1(", getter)
        self.assertNotRegex(getter, r"\bINSERT\b|\bUPDATE\b|\bDELETE\b")

    def test_legacy_and_stale_do_not_fabricate_reports(self):
        self.assertIn("NOT_CAPTURED_LEGACY_RUN", self.sql)
        self.assertIn("RUN_STALE", self.sql)
        self.assertIn("RUN_NOT_CURRENT", self.sql)
        self.assertIn("fn_input_readiness_run_is_current(p_run_id)", self.sql)
        self.assertIn("PARTIAL_ORIGINALS_NOT_EMITTED", self.sql)
        self.assertIn("IG_ORIGINAL_REPORT_INTEGRITY_DRIFT", self.sql)
        self.assertIn("'research_reexecuted',false", self.sql)

    def test_transport_is_existing_profile_input_not_a_new_dispatcher(self):
        self.assertIn("'ig_original_producer_reports',v_original_reports", self.sql)
        self.assertIn("fn_lf_profile_input_governance_resolve_v1", self.sql)
        self.assertIn("fn_input_governance_execute(v_pantalla_id,p_consumer)", self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_router", self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1", self.sql)

    def test_no_semantic_pass_or_auth_escalation(self):
        self.assertIn("'semantic_pass_authorized',false", self.sql)
        self.assertIn("'production_authorized',false", self.sql)
        self.assertIn("'model_has_read_report',false", self.sql)
        self.assertNotIn("'semantic_pass_authorized',true", self.sql)
        self.assertNotRegex(self.sql, r"\bGRANT\s+EXECUTE\b")

    def test_permissions_explicit_and_no_profile_secret(self):
        self.assertIn("REVOKE ALL ON programacion.input_governance_producer_raw_v1", self.sql)
        self.assertIn("REVOKE ALL ON FUNCTION programacion.fn_input_governance_producer_raw_read_v1", self.sql)
        for role in ("PUBLIC", "anon", "authenticated", "service_role"):
            self.assertIn(role, self.sql)
        self.assertNotIn("SERVICE_ROLE_KEY", self.sql)

    def test_unsupported_root_scope_is_reported(self):
        self.assertIn("'graph_truncated'", self.sql)
        self.assertIn("'ig_evo_graph_total_roots'", self.sql)
        self.assertIn("'graph_root_scope'", self.sql)
        self.assertIn("PARTIAL_ORIGINALS_NOT_EMITTED", self.sql)

    def test_document_does_not_claim_completed_runtime(self):
        self.assertIn("implementación candidata / NO-GO", self.doc)
        self.assertIn("no re-ejecutar", self.doc)
        self.assertNotIn("11 handles obligatorios", self.doc)
        self.assertIn("model_has_read_report=false", self.doc)

if __name__ == "__main__":
    unittest.main()
