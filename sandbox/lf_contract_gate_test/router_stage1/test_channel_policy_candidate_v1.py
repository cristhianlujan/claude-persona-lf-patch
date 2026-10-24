#!/usr/bin/env python3
"""Static checks for the ACT-0001 LF V2 channel policy reference.

This does NOT grant execution authority; it verifies source/runtime naming parity.
"""
import json
from pathlib import Path
import unittest

POLICY_PATH = Path(__file__).with_name("channel_policy_candidate_v1.json")


class ChannelPolicySourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p = json.loads(POLICY_PATH.read_text(encoding="utf-8"))

    def test_deployed_policy_still_grants_no_effects(self):
        self.assertEqual(self.p["state"], "DEPLOYED_LF_V2")
        self.assertEqual(self.p["stage1_contract_ref"], "LF_ROUTER_STAGE1_V2")
        self.assertIs(self.p["applies_effects"], False)
        self.assertIs(self.p["decision_policy"]["stage1_cannot_grant_execution"], True)

    def test_exactly_three_channels(self):
        got = [c["code"] for c in self.p["channels"]]
        self.assertEqual(len(got), 3)
        self.assertEqual(set(got), {"PRODUCTO", "PROGRAMACION", "OPERACIONES"})

    def test_intent_responsibilities_and_exclusions(self):
        for channel in self.p["channels"]:
            self.assertTrue(channel["responsibility"])
            self.assertTrue(channel["intents"])
            self.assertTrue(channel["excluded"])

    def test_product_definition_before_programming(self):
        d = self.p["decision_policy"]
        self.assertEqual(d["product_definition_change"], "PRODUCTO_FIRST")
        self.assertEqual(d["programming_on_definition_missing_or_changed"], "RETURN_TO_PRODUCTO_NO_CODE")
        self.assertEqual(d["programming_on_analysis_missing_or_stale"], "RETURN_TO_ANALYSIS_NO_CODE")
        self.assertEqual(d["verified_unmodified_definition"], "REUSE_CANONICAL_DEFINITION_NO_DUPLICATE_WRITE")

    def test_programming_admission_gate_cannot_be_skipped(self):
        must = {
            "EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS",
            "A9_ADMITTED_READY_SCOPE",
            "PERSISTED_PROGRAMMING_CONTEXT_RECEIPT",
            "PG01_ADMISSION",
            "RUNTIME_AND_OPERATION_AUTHORIZATION"
        }
        self.assertTrue(must.issubset(set(self.p["decision_policy"]["programming_gate"])))

    def test_reuse_registry_without_snapshotting_operation_list(self):
        r = self.p["reused_authorities"]
        self.assertEqual(r["action_registry"], "public.lf_router_action_registry")
        self.assertEqual(r["selector"], "CAPABILITY_SELECTOR")
        self.assertNotIn("hardcoded_operation_list", self.p)

    def test_fixtures_cover_channels_and_b2b(self):
        examples = self.p["examples"]
        self.assertEqual(len(examples), len({x["id"] for x in examples}))
        self.assertEqual({x["initial_channel"] for x in examples if x["initial_channel"] is not None}, {
            "PRODUCTO", "PROGRAMACION", "OPERACIONES"
        })
        b2b = next(x for x in examples if x["id"] == "B2B_LABEL_CHANGE")
        self.assertEqual(b2b["initial_channel"], "PRODUCTO")
        self.assertIn("NO_DUPLICATE_WRITE", b2b["expected_next"])

    def test_channel_field_is_not_existing_sistema_field(self):
        contract = self.p["channel_selection_contract"]
        self.assertEqual(contract["channel_field"], "canal_candidato")
        self.assertEqual(set(contract["channel_values"]), {
            "PRODUCTO", "PROGRAMACION", "OPERACIONES"
        })
        self.assertTrue(contract["channel_is_not_execution_authorization"])
        self.assertTrue(contract["semantic_validation_before_dispatch"])
        self.assertNotIn("sistema", contract.get("selector_inputs", []))
        self.assertEqual(contract["business_field"], "negocio_codigo")

    def test_routing_rules_cover_boundaries(self):
        rules = self.p["routing_rules"]
        self.assertEqual({r["rule_id"] for r in rules}, {
            "R00_IA_ASSET_MAINTENANCE", "R10_READ_EXISTING_PRODUCT_STATE",
            "R20_PRODUCT_DEFINITION", "R30_IMPLEMENTATION_LIFECYCLE",
            "R40_INCIDENT_DIAGNOSIS", "R50_MIXED_REQUEST", "R60_UNCERTAIN"
        })
        self.assertEqual(next(r for r in rules if r["rule_id"] ==
                              "R50_MIXED_REQUEST")["channel"], "PRODUCTO")
        self.assertEqual(next(r for r in rules if r["rule_id"] ==
                              "R40_INCIDENT_DIAGNOSIS")["initial_mode"],
                         "READ_ONLY_DIAGNOSIS")

    def test_transversal_profile_management_not_channel(self):
        self.assertNotIn("PERFILES_SKILLS", [c["code"] for c in self.p["channels"]])
        family = self.p["transversal_operation_families"][0]
        self.assertFalse(family["is_channel"])
        self.assertEqual(family["entrypoint"], "ACT-0001")
        example = next(x for x in self.p["examples"] if x["id"] == "UPDATE_PROFILE")
        self.assertEqual(example["ruta_transversal"], "GESTION_ACTIVOS_IA")
        self.assertIsNone(example["initial_channel"])


    def test_no_obsolete_route_or_dead_selector_fields(self):
        serialized = json.dumps(self.p, ensure_ascii=False)
        for forbidden in (
            '"route_kind"',
            '"special_route_kind"',
            '"intencion_tipificada"',
            '"precondiciones_no_satisfechas"',
            '"siguiente_paso_propuesto"',
            '"system_business_operations_scope"',
            '"channel_name_is_candidate"',
        ):
            self.assertNotIn(forbidden, serialized)

        outputs = self.p["channel_selection_contract"]["selector_outputs"]
        self.assertEqual(outputs, [
            "canal_candidato",
            "negocio_codigo",
            "negocios_afectados",
            "ruta_transversal",
            "razon_seleccion",
            "alcance",
        ])

    def test_operational_and_programming_boundaries(self):
        dp = self.p["decision_policy"]
        self.assertEqual(dp["platform_technical_operations_owner"], "PROGRAMACION")
        self.assertEqual(dp["product_live_operations_owner"], "OPERACIONES")
        self.assertIn("NO_ARBITRARY_SQL", dp["operational_channel_requires"])
        self.assertEqual(next(x for x in self.p["examples"] if x["id"] ==
                              "OFFER_STATUS")["initial_channel"], "OPERACIONES")
        self.assertEqual(next(x for x in self.p["examples"] if x["id"] ==
                              "DEFINE_AND_IMPLEMENT")["initial_channel"], "PRODUCTO")

    def test_business_is_independent_from_channel_and_legacy_sistema(self):
        contract = self.p["business_context_contract"]
        self.assertEqual(contract["channel_field"], "canal_candidato")
        self.assertEqual(contract["canonical_business_field"], "negocio_codigo")
        self.assertEqual(contract["current_phase"], "LF_ONLY")
        self.assertEqual(contract["saly_acceptance_status"], "DEFERRED_NOT_BLOCKING_LF_CLOSURE")
        self.assertEqual(contract["scoped_context"]["company_ref"], "company_id")
        self.assertTrue(contract["scoped_context"]["company_scope_must_be_bound_server_side"])
        self.assertTrue(contract["scoped_context"]["group_membership_must_be_verified"])
        self.assertTrue(contract["scoped_context"]["business_owner_org_not_equivalent_to_customer_company"])

    def test_same_channel_different_businesses_and_cross_scope(self):
        x = {e["id"]: e for e in self.p["business_scope_examples"]}
        self.assertEqual(x["LF_OFFER_STATUS"]["canal"], "OPERACIONES")
        self.assertEqual(x["SALY_ADVANCE_STATUS"]["canal"], "OPERACIONES")
        self.assertEqual(x["LF_OFFER_STATUS"]["negocio_codigo"], "LF")
        self.assertEqual(x["SALY_ADVANCE_STATUS"]["negocio_codigo"], "SALY")
        self.assertEqual(x["LF_GROUP_REPORT"]["scope_hint"], "GRUPO_CORPORATIVO")
        self.assertEqual(x["LF_COMPANY_PAYMENTS"]["scope_hint"], "EMPRESA")
        self.assertEqual(x["SHARED_AUTH_RULE"]["negocios_afectados"], ["LF", "SALY"])
        self.assertIsNone(x["UNSCOPED_AMBIGUOUS"]["negocio_codigo"])


    def test_dynamic_scope_is_optional_and_extensible(self):
        ctx = self.p["business_context_contract"]
        rules = ctx["scoped_context"]
        self.assertEqual(rules["scope_type_model"], "EXTENSIBLE_REGISTERED_TARGET_TYPES_NOT_FIXED_ENUM")
        self.assertTrue(rules["resolve_only_when_needed"])
        self.assertTrue(rules["do_not_create_scope_rows_for_classification"])
        self.assertIn("NOT_REQUIRED", rules["target_resolution_status"])
        self.assertIn("UNRESOLVED", rules["target_resolution_status"])
        self.assertTrue(self.p["channel_selection_contract"]["scope_is_optional"])
        self.assertTrue(self.p["channel_selection_contract"]["scope_resolver_is_business_specific"])
        self.assertTrue(self.p["decision_policy"]["scope_can_expand_through_existing_canonical_resolvers"])
        self.assertTrue(self.p["decision_policy"]["target_type_is_hint_not_query_selector"])
        self.assertTrue(self.p["decision_policy"]["resolve_canonical_subject_before_product_context_classification"])
        self.assertTrue(self.p["decision_policy"]["aggregate_product_context_preferred_when_available"])
        self.assertEqual(
            self.p["decision_policy"]["aggregate_context_missing_fallback"],
            "BOUNDED_CANONICAL_SEARCH_WITHOUT_TARGET_TYPE_PRE_FILTER",
        )
        self.assertEqual(
            self.p["decision_policy"]["product_structure_assessment_statuses"],
            ["FOUND_CANONICAL","FOUND_NON_CANONICAL","STRUCTURAL_GAP","NOT_FOUND"],
        )
        self.assertEqual(
            self.p["decision_policy"]["structural_gap_route"],
            "PROGRAMACION_STRUCTURE_ONLY_THEN_RETURN_PRODUCTO",
        )
        self.assertFalse(self.p["decision_policy"]["structural_repair_may_write_functional_truth"])
        self.assertEqual(self.p["decision_policy"]["structural_repair_return_channel"], "PRODUCTO")
        self.assertTrue(
            self.p["decision_policy"]["implementation_after_structural_repair_requires_product_currentness"]
        )
        self.assertEqual(
            self.p["decision_policy"]["product_cycle_resume_entrypoint"],
            "public.lf_router_product_cycle_v1",
        )
        self.assertTrue(self.p["decision_policy"]["profile_outputs_return_to_router_before_next_channel"])
        self.assertEqual(
            self.p["decision_policy"]["structural_repair_no_capability_behavior"],
            "CAPABILITY_GAP",
        )
        self.assertEqual(
            self.p["decision_policy"]["profile_gate2_pass_behavior"],
            "AUTO_MATERIALIZE_EJECUCION_PERFIL_LF",
        )
        self.assertEqual(
            self.p["decision_policy"]["profile_execution_handoff_schema"],
            "LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1",
        )
        self.assertFalse(
            self.p["decision_policy"]["authorized_profile_execution_reenters_router"]
        )
        self.assertEqual(
            self.p["decision_policy"]["profile_execution_context_owner"],
            "EJECUCION_PERFIL_LF_CONTEXT_ADMISSION",
        )
        self.assertFalse(
            self.p["decision_policy"]["router_loads_profile_channel_context"]
        )
        self.assertTrue(
            self.p["decision_policy"]["profile_execution_returns_to_router_after_result"]
        )
        self.assertTrue(
            self.p["decision_policy"]["executor_mode_selected_by_profile_execution_not_channel"]
        )

    def test_no_scope_for_general_question(self):
        examples = {e["id"]: e for e in self.p["business_scope_examples"]}
        self.assertFalse(examples["GENERAL_DESCRIPTION_NO_SCOPE"]["scope_required"])
        self.assertIsNone(examples["GENERAL_DESCRIPTION_NO_SCOPE"]["scope_hint"])
        self.assertEqual(examples["LF_LOGIN_COMPONENT"]["scope_hint"], "PANTALLA")
        self.assertEqual(examples["FUTURE_SCOPE_TYPE"]["scope_hint"], "REGLA")


if __name__ == "__main__":
    unittest.main(verbosity=2)
