from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260917034500_s30_router_ready_downstream_authority_v1.sql"
INPUT_GOV_ROUTER = ROOT / "supabase/migrations/20260901000922_input_governance_enforce_router_v1.sql"
PROFILE_RUNTIME_ENQUEUE = ROOT / "supabase/migrations/20260904091702_lf_profile_runtime_queue_native_hetzner_producer_v1.sql"
NONCANONICAL_ENQUEUE = ROOT / "supabase/migrations/20260913014028_lf_profile_runtime_noncanonical_materializer_v1.sql"
PROFILE_RUNTIME_STATE_GATE = ROOT / "supabase/migrations/20260905110903_lf_router_profile_runtime_state_gate_v1.sql"


class RouterDownstreamAuthorityV1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.input_gov_router = INPUT_GOV_ROUTER.read_text(encoding="utf-8")
        cls.enqueue = PROFILE_RUNTIME_ENQUEUE.read_text(encoding="utf-8")
        cls.noncanonical_enqueue = NONCANONICAL_ENQUEUE.read_text(encoding="utf-8")
        cls.state_gate = PROFILE_RUNTIME_STATE_GATE.read_text(encoding="utf-8")

    def test_ready_to_execute_owns_positive_downstream_authority(self):
        # Positive path: authority is part of the base READY_TO_EXECUTE object,
        # so adapterless profiles do not depend on Input Governance existing.
        self.assertIn(
            "''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES''),\\n"
            "    ''downstream_execution_allowed'',true\\n"
            "  ) || case when v_input_governance is null then ''{}''::jsonb else "
            "jsonb_build_object(''input_governance'',v_input_governance) end;",
            self.migration,
        )

    def test_old_adapter_owned_authority_is_exact_patch_anchor_only(self):
        # The legacy shape is retained only as the source-bound replacement anchor.
        # The migration itself asserts exactly one match before rewriting it.
        legacy = (
            "jsonb_build_object(''input_governance'',v_input_governance,"
            "''downstream_execution_allowed'',true)"
        )
        self.assertIn(legacy, self.migration)
        self.assertIn("S30_ROUTER_DOWNSTREAM_AUTHORITY_ANCHOR_NOT_UNIQUE", self.migration)
        self.assertIn("S30_ROUTER_DOWNSTREAM_AUTHORITY_POSTCONDITION_FAILED", self.migration)

    def test_profile_runtime_consumers_remain_fail_closed(self):
        # Repair the authority producer, not the consumer. Both enqueue paths must
        # continue requiring explicit true from the Router.
        strict = "coalesce((v_route->>'downstream_execution_allowed')::boolean,false) is not true"
        self.assertIn(strict, self.enqueue)
        self.assertIn("PROFILE_RUNTIME_ROUTER_NOT_READY", self.enqueue)
        self.assertIn(strict, self.noncanonical_enqueue)
        self.assertIn("PROFILE_RUNTIME_ROUTER_NOT_READY", self.noncanonical_enqueue)

    def test_blocked_profile_runtime_state_still_denies_downstream(self):
        # Negative path: blocked/incomplete runtime state must still emit false.
        self.assertIn("BLOCK_PROFILE_STATE_INCOMPLETE", self.state_gate)
        self.assertIn("BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED", self.state_gate)
        self.assertGreaterEqual(self.state_gate.count("''downstream_execution_allowed'',false"), 2)

    def test_input_governance_blocked_path_still_denies_downstream(self):
        # Negative path: an adapter/Input Governance denial must remain false.
        self.assertIn("''downstream_execution_allowed'',false", self.input_gov_router)
        self.assertIn("continuation_allowed", self.input_gov_router)

    def test_source_patch_does_not_relax_runtime_or_impact_state(self):
        # Scope lock: this fix changes only Router response authority semantics.
        forbidden = (
            "runtime_estado='RUNTIME_OPERATIVO'",
            "impacto_automatico='PERMITIDO_CONTROLADO'",
            "production_enabled=true",
        )
        for token in forbidden:
            self.assertNotIn(token, self.migration)


if __name__ == "__main__":
    unittest.main()
