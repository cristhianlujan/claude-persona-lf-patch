from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
from typing import Any

from services.profile_runtime_api.profile_runtime_api.repository import RepositoryBindings
from services.profile_runtime_api.profile_runtime_api.validation import OutputGates


ROOT = Path(__file__).resolve().parents[2]


def _norm(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.lower().strip().split())


def _tokens(value: str) -> list[str]:
    return re.findall(r"[a-z0-9#%+-]+", value.lower())


def _has_any(value: str, markers: tuple[str, ...]) -> bool:
    return any(marker in value for marker in markers)


def candidate_semantic_codes(payload: dict[str, Any]) -> list[str]:
    """Sandbox-only Strategy 26 candidate checks.

    These checks intentionally do not modify the canonical schema or runtime validator.
    They target general field semantics exposed by live/lab false positives, not one
    specific overflow example.
    """

    errors: list[str] = []
    values = {
        key: _norm(payload.get(key))
        for key in (
            "decision_subject",
            "selected_visual_type",
            "base_color_or_surface",
            "size_or_coverage",
            "density_limits",
            "depth_style",
            "visual_weight",
            "relationship_to_main_element",
            "implementation_format",
        )
    }

    subject = values["decision_subject"]
    selected = values["selected_visual_type"]
    generic_subjects = {
        "ui decision",
        "visual decision",
        "design decision",
        "interface decision",
        "ui treatment",
    }
    if subject in generic_subjects:
        errors.append("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE")

    treatment_markers = (
        "affordance",
        "indicator",
        "cue",
        "icon",
        "outline",
        "border",
        "gradient",
        "fade",
        "shadow",
        "sticky",
        "divider",
        "badge",
        "highlight",
        "label",
        "tooltip",
        "scrollbar",
        "scroll bar",
        "handle",
        "rail",
        "tab",
        "chip",
        "card",
        "button",
        "link",
        "spacing",
        "layout",
        "alignment",
        "animation",
        "transition",
    )
    if selected and subject and (selected == subject or selected in subject):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_RESTATES_SUBJECT")
    if selected and len(_tokens(selected)) < 3 and not _has_any(selected, treatment_markers):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_NON_CONCRETE")

    surface = values["base_color_or_surface"]
    surface_markers = (
        "#",
        "rgb",
        "hsl",
        "var(",
        "token",
        "surface",
        "background",
        "transparent",
        "white",
        "black",
        "neutral",
        "gray",
        "grey",
        "card",
        "panel",
        "canvas",
        "existing",
        "color",
    )
    if surface and not _has_any(surface, surface_markers):
        errors.append("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE")

    coverage = values["size_or_coverage"]
    coverage_markers = (
        "only",
        "edge",
        "viewport",
        "region",
        "area",
        "component",
        "screen",
        "card",
        "table",
        "row",
        "column",
        "header",
        "footer",
        "panel",
        "section",
        "container",
        "boundary",
        "width",
        "height",
        "full",
        "%",
        "px",
    )
    if coverage and not _has_any(coverage, coverage_markers):
        errors.append("UI_FOCUSED_SIZE_OR_COVERAGE_SCOPE_MISSING")

    density = values["density_limits"]
    density_markers = (
        "one",
        "single",
        "two",
        "three",
        " per ",
        "max",
        "maximum",
        "only",
        "no more",
        "at most",
        "limit",
        "count",
        "layer",
        "line",
        "element",
        "cue",
        "viewport",
        "item",
        "%",
        "px",
    )
    if density:
        if re.fullmatch(r"\d+(?:\.\d+)?", density):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY")
        elif not _has_any(f" {density} ", density_markers):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE_V3")

    depth = values["depth_style"]
    depth_markers = (
        "elevation",
        "shadow",
        "flat",
        "depth",
        "layer",
        "raised",
        "inset",
        "border",
        "z-",
        "no added",
        "none",
    )
    if depth and (not _has_any(depth, depth_markers) or (len(_tokens(depth)) < 2 and depth not in {"flat", "none"})):
        errors.append("UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE")

    weight = values["visual_weight"]
    weight_markers = (
        "primary",
        "secondary",
        "tertiary",
        "hierarchy",
        "prominence",
        "opacity",
        "contrast",
        "relative",
        "subordinate",
        "dominant",
        "less than",
        "more than",
        "%",
    )
    if weight and (not _has_any(weight, weight_markers) or len(_tokens(weight)) < 2):
        errors.append("UI_FOCUSED_VISUAL_WEIGHT_NON_CONCRETE")

    relationship = values["relationship_to_main_element"]
    relation_markers = (
        "support",
        "without",
        "relative",
        "adjacent",
        "inside",
        "within",
        "before",
        "after",
        "below",
        "above",
        "next to",
        "around",
        "aligned",
        "anchored",
        "attached",
        "preserve",
        "competing",
        "replacing",
        "does not",
    )
    ui_target_markers = (
        "table",
        "content",
        "action",
        "cta",
        "control",
        "card",
        "component",
        "element",
        "navigation",
        "header",
        "row",
        "button",
        "field",
        "primary",
        "main",
        "selector",
        "tab",
        "panel",
    )
    if relationship and not (
        _has_any(relationship, relation_markers)
        and _has_any(relationship, ui_target_markers)
    ):
        errors.append("UI_FOCUSED_RELATIONSHIP_NON_CONCRETE")

    implementation = values["implementation_format"]
    implementation_markers = (
        "css",
        "svg",
        "token",
        "component",
        "asset",
        "layout",
        "html",
        "javascript",
        "typescript",
        "tailwind",
        "class",
        "pseudo-element",
        "style",
        "gradient",
        "border",
        "shadow",
        "icon",
    )
    implementation_target_markers = (
        "card",
        "table",
        "component",
        "token",
        "icon",
        "viewport",
        "header",
        "row",
        "field",
        "button",
        "tab",
        "panel",
        "container",
        "selector",
        "cue",
        "edge",
        "rule",
    )
    if implementation and not (
        _has_any(implementation, implementation_markers)
        and _has_any(implementation, implementation_target_markers)
        and len(_tokens(implementation)) >= 3
    ):
        errors.append("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3")

    semantic_fields = (
        "selected_visual_type",
        "size_or_coverage",
        "density_limits",
        "depth_style",
        "visual_weight",
        "relationship_to_main_element",
        "implementation_format",
    )
    seen: dict[str, str] = {}
    for key in semantic_fields:
        value = values[key]
        if not value:
            continue
        prior = seen.get(value)
        if prior is not None and prior != key:
            errors.append("UI_FOCUSED_CROSS_FIELD_DUPLICATION")
            break
        seen[value] = key

    return sorted(set(errors))


def good_overflow() -> dict[str, Any]:
    return {
        "decision_subject": "horizontal table overflow cue",
        "selected_visual_type": "subtle horizontal scroll affordance at table edge",
        "base_color_or_surface": "existing neutral surface token",
        "size_or_coverage": "table viewport edge only",
        "density_limits": "one cue per overflowing table viewport",
        "depth_style": "no added elevation",
        "visual_weight": "secondary to table content and row actions",
        "position_behavior": "anchored to horizontal overflow edge",
        "relationship_to_main_element": "supports table navigation without replacing table semantics",
        "implementation_format": "CSS overflow cue and existing component token",
        "hard_exclusions": ["no new business rules", "no hidden row actions"],
        "short_generator_prompt": "not applicable; implement as CSS affordance",
        "status": "CANDIDATE_READ_ONLY",
    }


def good_payment_selection() -> dict[str, Any]:
    p = good_overflow()
    p.update(
        {
            "decision_subject": "selected payment method state",
            "selected_visual_type": "2px accent outline with trailing check icon on selected payment card",
            "base_color_or_surface": "existing white card surface with accent token",
            "size_or_coverage": "selected payment-method card boundary and trailing icon area only",
            "density_limits": "one outline and one check icon per selected payment card",
            "depth_style": "no added shadow or elevation",
            "visual_weight": "secondary to payment amount and primary continue CTA",
            "relationship_to_main_element": "supports the selected card state without competing with the primary CTA",
            "implementation_format": "CSS border token plus existing check-icon component on payment card",
            "hard_exclusions": ["no new primary CTA", "no changes outside payment selector"],
        }
    )
    return p


def good_inline_error() -> dict[str, Any]:
    p = good_overflow()
    p.update(
        {
            "decision_subject": "invalid field feedback",
            "selected_visual_type": "inline error text with existing error icon beneath invalid field",
            "base_color_or_surface": "existing error surface token on white form background",
            "size_or_coverage": "invalid field container and its inline feedback area only",
            "density_limits": "one error message and one error icon per invalid field",
            "depth_style": "flat with no added shadow",
            "visual_weight": "secondary to field label but higher contrast than helper content",
            "relationship_to_main_element": "attached below the invalid field without replacing the field label",
            "implementation_format": "existing form-error component plus CSS error token on field container",
            "hard_exclusions": ["no modal interruption", "no new navigation"],
        }
    )
    return p


class SemanticFloorV3SandboxTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository = RepositoryBindings(ROOT, max_prompt_chars=120_000)
        cls.gates = OutputGates(cls.repository)
        cls.binding = cls.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")

    def baseline_v2(self, payload: dict[str, Any]) -> str:
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=self.binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        return self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )["status"]

    def test_good_holdouts_pass_v3(self) -> None:
        for payload in (good_overflow(), good_payment_selection(), good_inline_error()):
            self.assertEqual(candidate_semantic_codes(payload), [], payload)

    def test_observed_enum_constrained_false_positive_is_rejected(self) -> None:
        payload = {
            "decision_subject": "UI decision",
            "selected_visual_type": "horizontal overflow",
            "base_color_or_surface": "wide operational table",
            "size_or_coverage": "horizontal overflow",
            "density_limits": "no more than one treatment per affected component",
            "depth_style": "subtle",
            "visual_weight": "discovery without hiding row actions",
            "relationship_to_main_element": "without adding business rules",
            "implementation_format": "JSON object",
            "hard_exclusions": ["no hidden actions", "no extra primary call to action"],
            "status": "SANDBOX_READY",
        }
        self.assertEqual(self.baseline_v2(payload), "PASS")
        codes = candidate_semantic_codes(payload)
        self.assertIn("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE", codes)
        self.assertIn("UI_FOCUSED_SELECTED_TREATMENT_NON_CONCRETE", codes)
        self.assertIn("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE", codes)
        self.assertIn("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3", codes)

    def test_observed_few_shot_false_positive_is_rejected_for_duplication(self) -> None:
        payload = {
            "decision_subject": "horizontal overflow in operational table",
            "selected_visual_type": "1px accent border on the table header",
            "base_color_or_surface": "existing white table surface",
            "size_or_coverage": "1px accent border on the table header",
            "density_limits": "1px accent border on the table header",
            "depth_style": "no added elevation; preserve the existing table shadow token",
            "visual_weight": "secondary to the table data and primary actions",
            "relationship_to_main_element": "displays horizontal scroll bar without hiding row actions",
            "implementation_format": "CSS border token on the table header",
            "hard_exclusions": ["no new business rules", "no extra primary actions"],
            "status": "SANDBOX_READY",
        }
        self.assertEqual(self.baseline_v2(payload), "PASS")
        self.assertIn(
            "UI_FOCUSED_CROSS_FIELD_DUPLICATION", candidate_semantic_codes(payload)
        )

    def test_numeric_only_density_is_rejected(self) -> None:
        payload = good_overflow()
        payload["density_limits"] = "100"
        self.assertIn(
            "UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY", candidate_semantic_codes(payload)
        )

    def test_generic_depth_and_weight_are_rejected(self) -> None:
        payload = good_overflow()
        payload["depth_style"] = "Elevation"
        payload["visual_weight"] = "Secondary"
        codes = candidate_semantic_codes(payload)
        self.assertIn("UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE", codes)
        self.assertIn("UI_FOCUSED_VISUAL_WEIGHT_NON_CONCRETE", codes)

    def test_non_surface_base_is_rejected(self) -> None:
        payload = good_overflow()
        payload["base_color_or_surface"] = "wide operational table"
        self.assertIn("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE", candidate_semantic_codes(payload))

    def test_relationship_without_ui_target_is_rejected(self) -> None:
        payload = good_overflow()
        payload["relationship_to_main_element"] = "without adding business rules"
        self.assertIn("UI_FOCUSED_RELATIONSHIP_NON_CONCRETE", candidate_semantic_codes(payload))

    def test_non_ui_implementation_format_is_rejected(self) -> None:
        payload = good_overflow()
        payload["implementation_format"] = "JSON object"
        self.assertIn(
            "UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3",
            candidate_semantic_codes(payload),
        )

    def test_exact_cross_field_copy_is_rejected(self) -> None:
        payload = good_overflow()
        payload["size_or_coverage"] = payload["selected_visual_type"]
        payload["density_limits"] = payload["selected_visual_type"]
        self.assertIn("UI_FOCUSED_CROSS_FIELD_DUPLICATION", candidate_semantic_codes(payload))

    def test_current_good_fixture_still_passes_existing_v2_and_v3(self) -> None:
        payload = good_overflow()
        self.assertEqual(self.baseline_v2(payload), "PASS")
        self.assertEqual(candidate_semantic_codes(payload), [])


if __name__ == "__main__":
    unittest.main()
