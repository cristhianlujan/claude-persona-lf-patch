from __future__ import annotations

import copy
from typing import Any


class UISemanticQualityError(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


_LAYOUT_REFINEMENTS: dict[str, tuple[str, str]] = {
    "STANDARD_GRID_STACK": (
        "source-designated featured services remain visually distinct before a responsive 2-3 column service-card grid; category navigation stays visible and columns collapse when card readability would be lost",
        "single-column stack preserving search, category navigation, the distinct featured-services section, and service-card field order",
    ),
    "DENSE_GRID_STACK": (
        "compact responsive 2-3 column service-card grid with wrapping cards, persistent category navigation, and a distinct source-designated featured-services section",
        "single-column stack with compact spacing while preserving every required card field and keeping featured services distinct",
    ),
    "FEATURED_FIRST_GRID_STACK": (
        "source-designated featured services lead as a visually distinct section before a responsive 2-3 column service-card grid with visible navigation",
        "featured services remain visually distinct before a single-column service-card stack preserving information order",
    ),
    "NAVIGATION_FIRST_GRID_STACK": (
        "search and category navigation stay prominent above a distinct source-designated featured-services section and responsive 2-3 column service-card grid",
        "search and category navigation stay first, followed by distinct featured services and a single-column service-card stack",
    ),
    "MOBILE_PRIORITY_STACK": (
        "responsive 2-3 column service-card grid keeps search and navigation visible, preserves a distinct featured-services section, and collapses by available card width",
        "mobile-first single-column stack preserves required sections, distinct featured services, and card information order",
    ),
}


def _require_dict(value: Any, code: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise UISemanticQualityError(code)
    return value


def _component_map(deliverable: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = deliverable.get("component_tree")
    if not isinstance(rows, list):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_COMPONENT_TREE_INVALID")
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("component_id"), str):
            raise UISemanticQualityError("UI_SEMANTIC_QUALITY_COMPONENT_INVALID")
        out[row["component_id"]] = row
    return out


def _top_level_flow(deliverable: dict[str, Any], required_ids: list[str]) -> list[str]:
    relations = deliverable.get("visual_hierarchy")
    if not isinstance(relations, list):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_HIERARCHY_INVALID")
    nested_children = {
        child
        for relation in relations
        if isinstance(relation, dict) and relation.get("parent_id") != "screen"
        for child in (relation.get("child_ids") or [])
        if isinstance(child, str)
    }
    return [cid for cid in required_ids if cid not in nested_children]


def _ensure_search_states(state_map: dict[str, Any], required_ids: list[str]) -> None:
    for cid in required_ids:
        if "search" not in cid.casefold():
            continue
        states = state_map.get(cid)
        if not isinstance(states, dict):
            raise UISemanticQualityError("UI_SEMANTIC_QUALITY_SEARCH_STATE_MISSING", cid)
        states.update(
            {
                "default": states.get("default") or "enabled",
                "query_entered": states.get("query_entered") or "preserve_user_query",
                "results_available": "render_source_results_only",
                "no_results": "render_empty_result_without_invented_items",
                "error": "render_non_fabricated_error_state",
            }
        )


def _ensure_component_states(
    state_map: dict[str, Any], components: dict[str, dict[str, Any]]
) -> None:
    """Give every material component an explicit safe state contract."""
    for cid, component in components.items():
        if cid in state_map:
            continue
        current_state = component.get("state")
        if not isinstance(current_state, str) or not current_state:
            current_state = "default"
            component["state"] = current_state
        if cid == "service_card_template":
            state_map[cid] = {
                current_state: "apply_template_to_source_bound_fields",
                "missing_required_field": "preserve_missing_field_without_inventing_value",
            }
        elif cid == "service_price":
            state_map[cid] = {
                current_state: "render_source_price_with_source_defined_format",
                "missing_source_value": "omit_price_or_render_neutral_unavailable_state_without_inventing_amount",
                "missing_source_format": "preserve_source_value_without_inventing_price_format",
            }
        elif cid in {"service_title", "service_provider"}:
            field = cid.removeprefix("service_")
            state_map[cid] = {
                current_state: f"render_source_{field}",
                "missing_source_value": f"omit_{field}_or_render_neutral_missing_state_without_invention",
            }
        else:
            state_map[cid] = {
                current_state: "preserve_source_bound_state_without_invention"
            }


def _apply_spacing_roles(components: dict[str, dict[str, Any]]) -> None:
    """Ensure every declared spacing role has an observable component consumer."""
    for cid in ("featured_services", "service_cards"):
        if cid in components:
            components[cid]["spacing"] = "section"


def _enrich_known_marketplace_structure(components: dict[str, dict[str, Any]]) -> None:
    category = components.get("category_navigation")
    if category is not None:
        content = _require_dict(category.get("content"), "UI_SEMANTIC_QUALITY_CATEGORY_CONTENT_INVALID")
        content["item_structure"] = {"label": "DATA_BOUND", "selection_state": "SOURCE_DEFINED"}
        category["role"] = (
            "Present source-bound category items as navigable labels while preserving source selection state."
        )

    featured = components.get("featured_services")
    if featured is not None:
        content = _require_dict(featured.get("content"), "UI_SEMANTIC_QUALITY_FEATURED_CONTENT_INVALID")
        content["selection_rule"] = "SOURCE_DESIGNATED_ONLY"
        content["selection_binding"] = {
            "membership_source": "featured_services.items",
            "membership_mode": "SOURCE_DEFINED_ONLY",
            "fallback_when_absent": "NO_FEATURED_INFERENCE",
        }
        content["item_template_ref"] = "service_card_template"
        featured["role"] = (
            "Present only source-designated featured services as a visually distinct section; never infer featured status."
        )

    cards = components.get("service_cards")
    if cards is not None:
        content = _require_dict(cards.get("content"), "UI_SEMANTIC_QUALITY_SERVICE_CARDS_CONTENT_INVALID")
        content["item_template_ref"] = "service_card_template"
        content["collection_binding"] = "service_cards.items"
        content["featured_membership_rule"] = "DO_NOT_INFER_FROM_GENERAL_COLLECTION"
        cards["role"] = (
            "Present the source-bound service collection using service_card_template for every repeated item."
        )

    template = components.get("service_card_template")
    if template is not None:
        template["role"] = (
            "Define the repeated source-bound service item structure consumed by both regular and featured service presentation."
        )


def _prune_unused_tokens(deliverable: dict[str, Any], components: dict[str, dict[str, Any]]) -> None:
    token_map = _require_dict(deliverable.get("token_map"), "UI_SEMANTIC_QUALITY_TOKEN_MAP_INVALID")
    used = {
        token
        for component in components.values()
        for token in (component.get("color_tokens") or [])
        if isinstance(token, str)
    }
    for group in ("surface", "text", "action", "border"):
        values = token_map.get(group)
        if isinstance(values, list):
            kept = [token for token in values if isinstance(token, str) and token in used]
            if kept:
                token_map[group] = kept


def _validate_semantic_quality_output(
    deliverable: dict[str, Any], components: dict[str, dict[str, Any]]
) -> None:
    state_map = _require_dict(
        deliverable.get("state_map"), "UI_SEMANTIC_QUALITY_STATE_MAP_INVALID"
    )
    missing_state_components = [cid for cid in components if cid not in state_map]
    if missing_state_components:
        raise UISemanticQualityError(
            "UI_SEMANTIC_QUALITY_COMPONENT_STATE_MISSING",
            ",".join(missing_state_components),
        )
    required_state_keys = {
        "service_card_template": {"default", "missing_required_field"},
        "service_title": {"default", "missing_source_value"},
        "service_provider": {"default", "missing_source_value"},
        "service_price": {"default", "missing_source_value", "missing_source_format"},
    }
    for cid, required in required_state_keys.items():
        if cid not in components:
            continue
        states = state_map.get(cid)
        if not isinstance(states, dict) or not required.issubset(states):
            raise UISemanticQualityError(
                "UI_SEMANTIC_QUALITY_COMPONENT_STATE_INCOMPLETE", cid
            )

    spacing = _require_dict(
        deliverable.get("spacing_typography"), "UI_SEMANTIC_QUALITY_SPACING_TYPOGRAPHY_INVALID"
    )
    spacing_rule = spacing.get("spacing")
    if not isinstance(spacing_rule, str):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_SPACING_RULE_INVALID")
    declared = {part.split("=", 1)[0].strip() for part in spacing_rule.split(";") if "=" in part}
    used = {
        component.get("spacing")
        for component in components.values()
        if isinstance(component.get("spacing"), str)
    }
    if declared and not declared.issubset(used):
        raise UISemanticQualityError(
            "UI_SEMANTIC_QUALITY_UNUSED_SPACING_ROLE",
            ",".join(sorted(declared - used)),
        )

    featured = components.get("featured_services")
    if featured is not None:
        content = _require_dict(
            featured.get("content"), "UI_SEMANTIC_QUALITY_FEATURED_CONTENT_INVALID"
        )
        binding = content.get("selection_binding")
        if not isinstance(binding, dict) or binding.get("membership_mode") != "SOURCE_DEFINED_ONLY" or binding.get("fallback_when_absent") != "NO_FEATURED_INFERENCE":
            raise UISemanticQualityError("UI_SEMANTIC_QUALITY_FEATURED_BINDING_INCOMPLETE")


def _append_risk_controls(deliverable: dict[str, Any], components: dict[str, dict[str, Any]]) -> None:
    controls = deliverable.get("risk_controls")
    if not isinstance(controls, list) or any(not isinstance(item, str) for item in controls):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_RISK_CONTROLS_INVALID")
    additions: list[str] = []
    if "featured_services" in components:
        additions.append(
            "For featured_services, use only source-designated featured membership; never infer or promote an item as featured."
        )
    additions.extend(
        [
            "Do not introduce pressure, shame, urgency, scarcity, countdowns, guaranteed outcomes, or eligibility claims.",
            "Keep internal governance, provenance, scores, hashes, routing, and execution metadata out of user-visible UI.",
        ]
    )
    for item in additions:
        if item not in controls:
            controls.append(item)


def apply_ui_production_semantic_quality_v1(
    deliverable: dict[str, Any],
    acceptance: dict[str, Any],
    *,
    layout_choice: str,
) -> dict[str, Any]:
    """Refine UICT5 deterministic materialization without changing source-bound domain truth."""
    if layout_choice not in _LAYOUT_REFINEMENTS:
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_LAYOUT_CHOICE_INVALID", str(layout_choice))
    required_ids = acceptance.get("required_component_ids")
    if not isinstance(required_ids, list) or any(not isinstance(cid, str) for cid in required_ids):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_REQUIRED_IDS_INVALID")

    out = copy.deepcopy(deliverable)
    components = _component_map(out)
    missing = [cid for cid in required_ids if cid not in components]
    if missing:
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_REQUIRED_COMPONENT_MISSING", ",".join(missing))

    layout = _require_dict(out.get("layout_grid"), "UI_SEMANTIC_QUALITY_LAYOUT_INVALID")
    layout["flow"] = _top_level_flow(out, required_ids)
    layout["desktop"], layout["mobile"] = _LAYOUT_REFINEMENTS[layout_choice]

    state_map = _require_dict(out.get("state_map"), "UI_SEMANTIC_QUALITY_STATE_MAP_INVALID")
    _ensure_search_states(state_map, required_ids)
    _ensure_component_states(state_map, components)
    _enrich_known_marketplace_structure(components)
    _apply_spacing_roles(components)
    _prune_unused_tokens(out, components)

    spacing = _require_dict(
        out.get("spacing_typography"), "UI_SEMANTIC_QUALITY_SPACING_TYPOGRAPHY_INVALID"
    )
    spacing["spacing"] = (
        "compact=1u within component;regular=2u between related components;section=4u between major sections"
    )
    spacing["precision_mode"] = "RELATIVE_GUIDANCE"

    _append_risk_controls(out, components)
    _validate_semantic_quality_output(out, components)
    return out