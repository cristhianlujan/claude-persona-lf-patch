"""Regression checks for staged Updater recorder source, NOT PostgreSQL proof.

These assertions only catch source-level omissions. Actual SQL compilation,
rollback, OIDC invocation, step-judge receipts and historical readback remain
requirements of the governed migration Train.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "skills/profile_creator/contracts/profile_update_recorder_conditional_route_candidate_v1.sql"
ROUTE = ROOT / "skills/profile_creator/contracts/profile_update_effective_route_reader_candidate_v1.sql"
CONTRACT = ROOT / "skills/profile_creator/contracts/profile_update_evolved_routing_candidate_v1.json"


class RecorderCandidate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SOURCE.read_text(encoding="utf8")
        cls.route = ROUTE.read_text(encoding="utf8")
        import json
        cls.policy = json.loads(CONTRACT.read_text(encoding="utf8"))

    def test_output_parity_guard_v02_update_only(self):
        self.assertIn("and v_route_resolution->>'outcome'='UPDATE'", self.sql)
        self.assertIn("and p_step_id='deterministic_validation'", self.sql)
        self.assertIn("if v_block_code is null and v_has_evolved_route", self.sql)
        self.assertIn("PROFILE_EVOLUTION_OUTPUT_PARITY_RECEIPT_UNVERIFIED", self.sql)
        self.assertIn("PROFILE_EVOLUTION_OUTPUT_PARITY_SOURCE_UNRESOLVED", self.sql)
        gate=self.policy["output_contract_gate"]
        self.assertEqual(gate["existing_step_id"],"deterministic_validation")
        self.assertEqual(gate["applies_to_frozen_outcome"],"UPDATE")
        self.assertTrue(gate["does_not_authorize_cutover"])

    def test_verified_positive_and_negative_receipts_are_required(self):
        self.assertIn("'PROFILE_OUTPUT_VALIDATION_POSITIVE'",self.sql)
        self.assertIn("'PROFILE_OUTPUT_VALIDATION_NEGATIVE'",self.sql)
        self.assertIn("public.lf_profile_update_verified_receipt_v1(",self.sql)
        self.assertIn("v_output_gate->>'positive_receipt_id'",self.sql)
        self.assertIn("v_output_gate->>'negative_receipt_id'",self.sql)
        self.assertTrue(self.policy["output_contract_gate"]["candidate_without_supported_reader_must_block"])
        self.assertFalse(self.policy["output_contract_gate"]["current_reader_supports_output_classes"])

    def test_refuses_claimed_pass_without_exact_readback(self):
        for guard in (
            "v_output_gate->>'candidate_head_sha' is distinct from v_output_head",
            "v_output_readback->>'recorded_by_rpc' is distinct from",
            "v_output_readback->>'sha_match' is distinct from 'true'",
            "v_output_gate->>'positive_output_sha256' is not distinct from",
        ):
            self.assertIn(guard,self.sql)

    def test_legacy_v01_and_nochange_untouched(self):
        self.assertIn("v_has_evolved_route :=",self.sql)
        self.assertIn("required_steps_by_outcome",self.sql)
        self.assertTrue(self.policy["route_validation"]["legacy_v01_frozen_runs_unchanged"])
        self.assertFalse(self.policy["route_validation"]["no_change_requires_new_candidate_output"])
        self.assertFalse(self.policy["output_contract_gate"]["current_reader_supports_output_classes"])

    def test_no_second_recorder_or_parallel_operation(self):
        self.assertEqual(self.sql.count("CREATE OR REPLACE FUNCTION public.lf_record_profile_operation_step_v1("), 1)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_record_profile_operation_step_v2", self.sql)

    def test_existing_operation_only(self):
        self.assertIn("v_execution.operation_code='ACTUALIZACION_PERFIL_LF'", self.sql)
        self.assertIn("'CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF'", self.sql)

    def test_snapshot_required_even_for_evolution(self):
        self.assertIn("operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome",self.sql)
        self.assertIn("v_snapshot_steps:=v_route_resolution->'effective_steps'",self.sql)

    def test_route_fail_closed(self):
        self.assertIn("PROFILE_UPDATE_EVOLUTION_ROUTE_UNRESOLVED",self.sql)
        self.assertIn("PROFILE_UPDATE_STEP_NOT_ON_FROZEN_ROUTE",self.sql)

    def test_minijudge_guard_from_existing_recorder(self):
        self.assertIn("p_step_id IN ('method_selection','evolution_decision')",self.sql)
        self.assertIn("lf_profile_update_evolution_step_guard_v1(",self.sql)
        self.assertIn("lf_profile_update_substantive_block_v1(",self.sql)

    def test_all_three_completion_checks_use_effective_steps(self):
        # replay-close, preceding step, normal close reuse one resolution.
        self.assertEqual(self.sql.count("v_snapshot_steps:=v_route_resolution->'effective_steps';"),1)
        self.assertGreaterEqual(self.sql.count("v_snapshot_applies"),5)
        self.assertGreaterEqual(self.sql.count("jsonb_array_elements_text(v_snapshot_steps)"),4)

    def test_clean_close_still_prohibits_missing_required_steps(self):
        self.assertIn("'PROFILE_UPDATE_COMPLETION_NOT_CLEAN'",self.sql)
        self.assertIn("p_step_id='report_output'",self.sql)

    def test_no_new_runtime_or_public_broad_grants(self):
        self.assertNotIn("GRANT ALL",self.sql.upper())
        self.assertNotIn("UPDATE public.lf_operation_registry",self.sql)
        self.assertNotIn("INSERT INTO public.lf_operation_steps",self.sql)

    def test_evolved_routes_reject_unproven_substantive_results(self):
        self.assertIn("v_route_resolution->>'outcome' in ('NO_CHANGE','UPDATE')",self.sql)
        self.assertIn("public.lf_profile_update_result_class_v1(p_evidence_payload->'validator_result') is distinct from 'PASS'",self.sql)
        self.assertIn("public.lf_profile_update_result_class_v1(p_evidence_payload->'malformed_input_result') is distinct from 'PASS'",self.sql)
        self.assertIn("public.lf_profile_update_result_class_v1(p_evidence_payload->'semantic_judge_result') is distinct from 'PASS'",self.sql)
        for code in ("PROFILE_EVOLUTION_VALIDATOR_PASS_UNPROVEN",
                     "PROFILE_EVOLUTION_MALFORMED_GATE_PASS_UNPROVEN",
                     "PROFILE_EVOLUTION_SEMANTIC_PASS_UNPROVEN"):
            self.assertIn(code,self.sql)

    def test_immutable_legacy_route(self):
        self.assertIn("LEGACY_FROZEN",self.route)
        self.assertIn("v_snapshot_steps:=v_execution.manifest#>",self.sql)

    def test_no_change_route_never_requires_github_write(self):
        steps=self.policy["required_steps_by_outcome"]
        for prohibited in ("github_write","github_readback","pre_write_execution_binding_gate","post_merge_reconcile"):
            self.assertNotIn(prohibited,steps["NO_CHANGE"])
            self.assertIn(prohibited,steps["UPDATE"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
