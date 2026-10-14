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
