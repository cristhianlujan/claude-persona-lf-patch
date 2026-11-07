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
            "68a6a5466ed40a06d673eb1cffc24ec2",
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
        self.assertIn("ALL_G1_ATTESTED_SCREEN_RULES", self.sql)
        self.assertIn(
            "ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS", self.sql
        )
        self.assertIn("ig_evo_graph_total_attested_rules", self.sql)
        reader = self.sql.split(
            "CREATE OR REPLACE FUNCTION programacion.fn_input_governance_producer_raw_read_v1"
        )[1].split("$raw_get$;")[0]
        self.assertIn("'graph_eligible_rule_count'", reader)
        self.assertIn("'graph_captured_root_count'", reader)
        self.assertIn("'graph_truncated'", reader)
        self.assertNotIn(")>8", reader)

    def test_unattested_derived_global_links_are_reported_not_assumed(self):
        self.assertIn("ig_evo_graph_unattested_global_count", self.sql)
        self.assertIn("ig_evo_graph_total_linked_rules", self.sql)
        self.assertIn(
            "UNATTESTED_SCREEN_APPLICABILITY_NOT_G1_ROOT_ELIGIBLE",
            self.sql,
        )
        self.assertIn("'graph_derived_global_unattested_count'", self.sql)
        self.assertIn("'graph_derived_global_retrieval_ref'", self.sql)
        self.assertIn("e.binding_source='DERIVED_GLOBAL'", self.sql)
        self.assertIn("212", self.doc)  # observed example, not SQL cardinality
        self.assertNotIn("=212", self.sql)

    def test_internal_graph_truncation_is_not_misreported_complete(self):
        self.assertIn("'graph_limit_hit'='true'", self.sql)
        self.assertIn("ig_evo_graph_internal_truncation_count", self.sql)
        self.assertIn("ig_evo_graph_internal_truncated_rule_ids", self.sql)
        self.assertIn(
            "ALL_G1_ATTESTED_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION",
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

    def test_curator_emission_is_proven_by_all_original_payloads(self):
        self.assertIn("v_r1_emitted:=coalesce", self.sql)
        self.assertIn("v_r2_r6_emitted:=coalesce", self.sql)
        self.assertIn("v_g1_emitted:=coalesce", self.sql)
        self.assertIn(
            "AND v_r1_emitted AND v_r2_r6_emitted AND v_g1_emitted",
            self.sql,
        )
        self.assertIn("'producer_emission',jsonb_build_object(", self.sql)
        self.assertIn("CAPTURED_AS_EMITTED", self.sql)
        self.assertIn("EMITTED_IN_THIS_RUN", self.sql)

    def test_each_producer_hash_is_derived_from_stored_original(self):
        self.assertIn("'producer_original_sha256',jsonb_build_object(", self.sql)
        for original in (
            "v_report.original_curator_output_sha256",
            "v_pm->'ig_evo_r1_diagnostics'",
            "v_pm->'ig_evo_r2_r6_diagnostics'",
            "v_graph",
        ):
            with self.subTest(original=original):
                self.assertIn(original, self.sql)
        self.assertIn("CASE WHEN v_r1_emitted THEN programacion.fn_v09_sha256_jsonb(", self.sql)
        self.assertIn("CASE WHEN v_r2_r6_emitted THEN programacion.fn_v09_sha256_jsonb(", self.sql)
        self.assertIn("CASE WHEN v_g1_emitted THEN programacion.fn_v09_sha256_jsonb(", self.sql)

    def test_rebind_actual_output_not_inferred_from_strategy_label(self):
        self.assertIn(
            "v_curator_strategy:=v_report.original_curator_output#>>"
            "'{performance_observation,strategy}'",
            self.sql,
        )
        self.assertIn("ORIGINALS_NOT_EMITTED_FOR_REBIND", self.sql)
        self.assertIn("NOT_EMITTED_FOR_REBIND", self.sql)
        self.assertIn("'automatic_parent_raw_as_current_run_authorized',false", self.sql)
        self.assertIn("'historical_raw_as_current_evidence_authorized',false", self.sql)
        self.assertIn("SAME_SOURCE_SNAPSHOT_NOT_RUN_EQUIVALENCE", self.sql)
        self.assertIn("SOURCE_SNAPSHOT_CHANGED", self.sql)
        self.assertIn("source_lineage", self.sql)

    def test_delayed_source_snapshot_pin_is_not_false_integrity_drift(self):
        self.assertIn("universe_snapshot_sha256 text", self.sql)
        self.assertIn("r.source_snapshot_sha256,r.universe_snapshot_sha256", self.sql)
        self.assertIn(
            "v_report.universe_snapshot_sha256 IS DISTINCT FROM "
            "v_run.universe_snapshot_sha256",
            self.sql,
        )
        self.assertIn(
            "v_report.source_snapshot_sha256 IS NOT NULL",
            self.sql,
        )
        self.assertIn("source_snapshot_sha256_at_capture", self.sql)
        self.assertIn("PINNED_AFTER_CURATOR_CAPTURE", self.sql)
        self.assertIn("SOURCE_SNAPSHOT_NOT_ATTESTED", self.sql)
        self.assertIn("IG_ORIGINAL_REPORT_INTEGRITY_DRIFT", self.sql)

    def test_noop_and_block_do_not_create_a_new_original(self):
        self.assertIn(
            "IF v_strategy IN ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE',"
            "'FULL_RECURATE') THEN",
            self.sql,
        )
        self.assertNotIn(
            "IF v_strategy IN ('NOOP','BLOCK') THEN\n    INSERT",
            self.sql,
        )
        self.assertIn("NOT_CAPTURED_LEGACY_RUN", self.sql)
        self.assertIn("research_reexecuted',false", self.sql)

    def test_profile_receives_one_canonical_governance_payload(self):
        self.assertIn("fn_lf_profile_input_governance_resolve_v1",self.sql)
        self.assertIn("md5(v_profile)<>'ab091d641cc1d3d923d20c0db96d9bc5'",self.sql)
        self.assertIn("/length('''governance_result'',v_result,') <> 3",self.sql)
        self.assertIn("strpos(v_profile,'''ig_original_producer_reports''')>0",self.sql)
        self.assertIn("'ig_consolidated_original_reports',v_ig_originals",self.sql)
        self.assertNotIn("'ig_original_producer_reports',v_original_reports",self.sql)
        self.assertNotIn("IG_ORIGINAL_REPORT_PROFILE_TRANSPORT_SOURCE_DRIFT",self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_router",self.sql)

    def test_no_new_profile_dispatcher_or_bridge(self):
        self.assertIn("fn_input_governance_execute(integer,text)",self.sql)
        self.assertIn("IG_CONSOLIDATION_EXECUTE_SOURCE_DRIFT",self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1",self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1",self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_adapter_input_governance_resolve_v1",self.sql)

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

    def test_consolidation_uses_existing_ig_executor_result(self):
        self.assertIn("IG_CONSOLIDATION_EXECUTE_SOURCE_DRIFT", self.sql)
        self.assertIn("v_ig_originals:=programacion.fn_input_governance_original_consolidate_v1(v_run,v_stage)", self.sql)
        self.assertIn("'ig_consolidated_original_reports',v_ig_originals", self.sql)
        self.assertIn("'ig_original_reports_complete'", self.sql)
        self.assertIn("IG_CONSOLIDATION_STAGE_GATE_NOT_BOUND", self.sql)

    def test_consolidated_validator_original_sha_and_no_rerun(self):
        b=self.sql.split("CREATE OR REPLACE FUNCTION programacion.fn_input_governance_original_consolidate_v1")[1].split("$ig_original_consolidate$;")[0]
        self.assertIn("fn_input_validator_evidence_rehydrate_v1(", b)
        self.assertIn("'original_assessment_row',to_jsonb(a)", b)
        self.assertIn("'validator_evidence_logical_rehydrated',v_logical", b)
        self.assertIn("v_receipt_digest IS DISTINCT FROM a.validator_sha256", b)
        self.assertIn("'validator_original_rows',v_validator_originals", b)
        self.assertNotIn("fn_input_governance_validator_validate_v1(", b)
        self.assertNotIn("fn_input_governance_curator_materialize_v1(", b)
        self.assertNotIn("fn_ig_evo_rule_graph_inventory_v1(", b)

    def test_validator_pass_does_not_override_qa_production_or_semantics(self):
        b=self.sql.split("CREATE OR REPLACE FUNCTION programacion.fn_input_governance_original_consolidate_v1")[1].split("$ig_original_consolidate$;")[0]
        for t in ("'stage_gate',p_stage_gate",
                  "'full_qa_stage_closed',p_stage_gate->'full_qa_stage_closed'",
                  "'full_production_stage_closed',p_stage_gate->'full_production_stage_closed'",
                  "v_run.scope->>'validator_semantic_mode'",
                  "'independent_semantic_judgement_here','NOT_TESTED'",
                  "'semantic_promotion_authorized',false",
                  "'model_has_read_report',false"):
            self.assertIn(t,b)
        self.assertNotIn("'semantic_promotion_authorized',true",b)

    def test_consolidation_acl_and_incomplete_archive_fail_safely(self):
        self.assertIn("REVOKE ALL ON FUNCTION\n programacion.fn_input_governance_original_consolidate_v1(bigint,jsonb)",self.sql)
        self.assertIn("has_function_privilege('service_role','programacion.fn_input_governance_original_consolidate_v1",self.sql)
        self.assertIn("IG_CONSOLIDATION_VALIDATOR_ORIGINAL_MISSING_OR_STALE",self.sql)
        self.assertIn("IG_CONSOLIDATION_FAMILY_CARDINALITY_MISMATCH",self.sql)
        self.assertIn("VALIDATOR_EVIDENCE_PRESENT_CURATOR_ORIGINAL_INCOMPLETE",self.sql)
        self.assertIn("IG_CONSOLIDATION_EXECUTE_SQL_TERMINATOR_MISSING",self.sql)
        self.assertNotIn("GRANT EXECUTE",self.sql)

    def test_document_does_not_claim_completed_runtime(self):
        self.assertIn("implementación candidata / NO-GO", self.doc)
        self.assertIn("no re-ejecutar", self.doc)
        self.assertNotIn("11 handles obligatorios", self.doc)
        self.assertIn("model_has_read_report=false", self.doc)

if __name__ == "__main__":
    unittest.main()
