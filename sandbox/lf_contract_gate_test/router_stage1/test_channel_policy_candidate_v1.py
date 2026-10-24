#!/usr/bin/env python3
"""Static checks for the ACT-0001 channel policy candidate.

This does NOT test the live Router, model classification, PG-01, or execution.
"""
import json
from pathlib import Path
import unittest

POLICY_PATH = Path(__file__).with_name("channel_policy_candidate_v1.json")


class ChannelPolicySourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p = json.loads(POLICY_PATH.read_text(encoding="utf-8"))

    def test_source_only_no_effects(self):
        self.assertEqual(self.p["state"], "SOURCE_ONLY_CANDIDATE")
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
            "PRODUCTO", "PROGRAMACION", "PERFILES_SKILLS", "SISTEMA"
        })
        b2b = next(x for x in examples if x["id"] == "B2B_LABEL_CHANGE")
        self.assertEqual(b2b["initial_channel"], "PRODUCTO")
        self.assertIn("NO_DUPLICATE_WRITE", b2b["expected_next"])

    def test_channel_field_is_not_existing_sistema_field(self):
        contract = self.p["channel_selection_contract"]
        self.assertEqual(contract["channel_field"], "canal_candidato")
        self.assertEqual(contract["independent_existing_field"], "sistema")
        self.assertEqual(set(contract["channel_values"]), {
            "PRODUCTO", "PROGRAMACION", "OPERACIONES"
        })
        self.assertTrue(contract["channel_is_not_execution_authorization"])
        self.assertTrue(contract["semantic_validation_before_dispatch"])

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
        self.assertEqual(example["route_kind"], "DIRECT_GOVERNED_OPERATION")
        self.assertIsNone(example["initial_channel"])

    def test_operational_and_programming_boundaries(self):
        dp = self.p["decision_policy"]
        self.assertEqual(dp["platform_technical_operations_owner"], "PROGRAMACION")
        self.assertEqual(dp["product_live_operations_owner"], "OPERACIONES")
        self.assertIn("NO_ARBITRARY_SQL", dp["operational_channel_requires"])
        self.assertEqual(next(x for x in self.p["examples"] if x["id"] ==
                              "OFFER_STATUS")["initial_channel"], "OPERACIONES")
        self.assertEqual(next(x for x in self.p["examples"] if x["id"] ==
                              "DEFINE_AND_IMPLEMENT")["initial_channel"], "PRODUCTO")


if __name__ == "__main__":
    unittest.main(verbosity=2)
