from __future__ import annotations

import json
import unittest
from profile_runtime_api.engine import _deterministic_ui_outcome
from profile_runtime_api.llama import decode_ui_production_transport
from profile_runtime_api.ui_semantic_quality import apply_ui_production_semantic_quality_v1
from profiles.ui_architect.validators.validate_composer_payload_boundary import build_composer_payload


class UIProductionSemanticRepairTest(unittest.TestCase):
    def setUp(self):
        self.acceptance = {
            "task_mode":"CREATE_NEW",
            "implementation_readiness":"STRUCTURED_SPEC_READY_FOR_NEXT_AGENT",
            "required_component_ids":["header_search","category_navigation","featured_services","service_cards","service_card_template","service_title","service_provider","service_price","service_cta"],
            "required_state_component_ids":["header_search","category_navigation","featured_services","service_cards","service_cta"],
            "required_sections":["header","categories","featured_services","service_cards"],
            "required_design_intents":["clear","professional","easy_to_navigate"],
            "required_responsive_modes":["desktop","mobile"],
            "required_service_leaf_components":["service_title","service_provider","service_price","service_cta"],
            "required_source_bindings":{
                "category_navigation.items":"DATA_BOUND",
                "featured_services.items":"DATA_BOUND",
                "service_card_template.fields":"title|provider|price|call_to_action",
                "service_card_template.values":"DATA_BOUND",
                "service_cards.items":"DATA_BOUND",
                "service_cta.destination":"UNRESOLVED_UNTIL_SOURCE",
                "service_cta.label":"DATA_BOUND:call_to_action",
                "service_price.format":"SOURCE_DEFINED",
                "service_price.value":"DATA_BOUND:price",
                "service_provider.value":"DATA_BOUND:provider",
                "service_title.value":"DATA_BOUND:title",
            },
            "minimum_component_count":9,
            "minimum_hierarchy_depth_edges":3,
            "minimum_risk_control_count":4,
        }
        out, kind = decode_ui_production_transport(
            {"v":5,"d":{"l":"STANDARD_GRID_STACK"}},
            self.acceptance,
            domain_scope="GENERIC_SERVICE_MARKETPLACE",
        )
        self.assertEqual(kind, "UICT5")
        self.deliverable = apply_ui_production_semantic_quality_v1(
            out["deliverable_created"],
            self.acceptance,
            layout_choice="STANDARD_GRID_STACK",
        )

    def test_layout_flow_contains_only_top_level_components(self):
        self.assertEqual(
            self.deliverable["layout_grid"]["flow"],
            ["header_search","category_navigation","featured_services","service_cards"],
        )
        self.assertNotIn("service_title", self.deliverable["layout_grid"]["flow"])
        self.assertEqual(
            self.deliverable["visual_hierarchy"][-1]["child_ids"],
            ["service_title","service_provider","service_price","service_cta"],
        )

    def test_featured_and_categories_are_structurally_explicit_without_invented_values(self):
        comps={x["component_id"]:x for x in self.deliverable["component_tree"]}
        self.assertEqual(comps["featured_services"]["content"]["selection_rule"], "SOURCE_DESIGNATED_ONLY")
        self.assertEqual(comps["featured_services"]["content"]["item_template_ref"], "service_card_template")
        self.assertEqual(comps["service_cards"]["content"]["item_template_ref"], "service_card_template")
        self.assertEqual(comps["category_navigation"]["content"]["item_structure"]["label"], "DATA_BOUND")
        self.assertIn("never infer featured status", comps["featured_services"]["role"])
        self.assertEqual(comps["featured_services"]["state"], "source_conditional")
        self.assertEqual(
            comps["featured_services"]["content"]["overlap_policy"],
            "SOURCE_DESIGNATED_SUBSET_MAY_REPEAT_FROM_SERVICE_CARDS",
        )
        self.assertIn("compare", comps["service_cards"]["role"])
        self.assertIn("compare", comps["service_provider"]["role"])

    def test_search_states_cover_results_empty_and_error(self):
        states=self.deliverable["state_map"]["header_search"]
        self.assertEqual(states["results_available"], "render_source_results_only")
        self.assertEqual(states["no_results"], "render_empty_result_without_invented_items")
        self.assertEqual(states["error"], "render_non_fabricated_error_state")
        featured = self.deliverable["state_map"]["featured_services"]
        self.assertEqual(featured["source_designated"], "render_only_source_marked_featured_items")
        self.assertEqual(featured["not_source_designated"], "omit_or_render_empty_state_without_invented_items")

    def test_tokens_and_lf_safety_are_bounded(self):
        self.assertEqual(self.deliverable["token_map"]["text"], ["text_primary"])
        joined=" ".join(self.deliverable["risk_controls"])
        self.assertIn("pressure", joined)
        self.assertIn("internal governance", joined)
        self.assertIn("render items only when the source explicitly marks them featured", joined)
        self.assertIn("presentation subset of service_cards", joined)

    def test_composer_projection_is_single_authoritative_recipient_view(self):
        composer = build_composer_payload(self.deliverable)
        self.assertNotIn("prompt_constraints", composer)
        self.assertIn("prompt_constraints", self.deliverable)
        self.assertEqual(set(composer), set(self.deliverable) - {"prompt_constraints"})
        for key in composer:
            self.assertEqual(composer[key], self.deliverable[key])

    def test_deterministic_evidence_summaries_are_specific(self):
        composer=build_composer_payload(self.deliverable)
        outcome=_deterministic_ui_outcome(
            deliverable=self.deliverable,
            acceptance=self.acceptance,
            composer_payload=composer,
            strict_semantic_repair=True,
        )
        score=outcome["score"]
        evidence=score["evidence_by_criterion"]
        summaries=[evidence[k]["summary"] for k in evidence]
        self.assertEqual(len(set(summaries)), 5)
        self.assertTrue(all(evidence[k]["result"] == "PASS" for k in evidence))
        self.assertTrue(all(isinstance(evidence[k]["rule"], str) and evidence[k]["rule"] for k in evidence))
        self.assertTrue(all(isinstance(evidence[k]["observed"], dict) and evidence[k]["observed"] for k in evidence))
        self.assertEqual(score["total"], 25)
        self.assertEqual([score[k] for k in ("layout_precision","visual_hierarchy","lf_system_fidelity","state_mapping","handoff_quality")], [5,5,5,5,5])
        self.assertNotIn(4, [score[k] for k in ("layout_precision","visual_hierarchy","lf_system_fidelity","state_mapping","handoff_quality")])
        self.assertEqual(evidence["visual_hierarchy"]["observed"]["observed_depth_edges"], 3)
        self.assertTrue(evidence["layout_precision"]["observed"]["layout_flow_matches_hierarchy"])
        self.assertTrue(evidence["handoff_quality"]["observed"]["source_bindings_matched"])
        self.assertTrue(all("sha256" in summaries[i] for i in range(len(summaries))))


    def test_invented_cta_route_fails_handoff_closed_with_localized_evidence(self):
        broken=json.loads(json.dumps(self.deliverable))
        for component in broken["component_tree"]:
            if component["component_id"] == "service_cta":
                component["content"]["destination"] = "/checkout"
                break
        composer=build_composer_payload(broken)
        outcome=_deterministic_ui_outcome(
            deliverable=broken,
            acceptance=self.acceptance,
            composer_payload=composer,
            strict_semantic_repair=True,
        )
        score=outcome["score"]
        evidence=score["evidence_by_criterion"]["handoff_quality"]
        self.assertEqual(score["handoff_quality"], 0)
        self.assertEqual(outcome["self_verdict"], "BLOCKED")
        self.assertEqual(evidence["result"], "FAIL")
        self.assertFalse(evidence["observed"]["source_bindings_matched"])
        self.assertIn("source-binding mismatch=0 fail-closed", evidence["rule"])

    def test_layout_hierarchy_regression_fails_deterministic_acceptance(self):
        broken=json.loads(json.dumps(self.deliverable))
        broken["layout_grid"]["flow"].append("service_title")
        outcome=_deterministic_ui_outcome(
            deliverable=broken,
            acceptance=self.acceptance,
            composer_payload=build_composer_payload(broken),
            strict_semantic_repair=True,
        )
        self.assertEqual(outcome["score"]["layout_precision"], 3)
        self.assertEqual(outcome["self_verdict"], "BLOCKED")
        self.assertEqual(outcome["score"]["evidence_by_criterion"]["layout_precision"]["result"], "PARTIAL")

    def test_missing_search_result_state_fails_state_mapping(self):
        broken=json.loads(json.dumps(self.deliverable))
        del broken["state_map"]["header_search"]["error"]
        outcome=_deterministic_ui_outcome(
            deliverable=broken,
            acceptance=self.acceptance,
            composer_payload=build_composer_payload(broken),
            strict_semantic_repair=True,
        )
        self.assertEqual(outcome["score"]["state_mapping"], 3)
        self.assertEqual(outcome["self_verdict"], "BLOCKED")
        self.assertEqual(outcome["score"]["evidence_by_criterion"]["state_mapping"]["result"], "PARTIAL")


if __name__ == "__main__":
    unittest.main()
