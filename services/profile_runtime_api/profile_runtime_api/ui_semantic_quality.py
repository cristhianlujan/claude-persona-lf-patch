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
        "single-column stack preserving search, category navigation, the distinct source-designated featured section, and stable service-card field order for comparison",
    ),
    "DENSE_GRID_STACK": (
        "compact multi-column grid using a responsive 2-3 column service-card layout with wrapping cards, persistent category navigation, and a distinct source-designated featured-services section",
        "single-column stack with compact spacing while preserving every required card field and keeping featured services source-conditional",
    ),
    "FEATURED_FIRST_GRID_STACK": (
        "source-designated featured services lead as a visually distinct optional section before a responsive 2-3 column service-card grid with visible navigation",
        "source-designated featured services remain distinct before a single-column service-card stack preserving comparison field order",
    ),
    "NAVIGATION_FIRST_GRID_STACK": (
        "search and category navigation stay prominent above an optional source-designated featured-services section and responsive 2-3 column service-card grid",
        "search and category navigation stay first, followed by source-conditional featured services and a single-column service-card stack",
    ),
    "MOBILE_PRIORITY_STACK": (
        "responsive 2-3 column service-card grid keeps search and navigation visible, preserves a source-conditional featured-services section, and collapses by available card width",
        "mobile-first single-column stack preserves required sections, source-conditional featured services, and stable card information order",
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


def _ensure_states(state_map: dict[str, Any], required_ids: list[str]) -> None:
    for cid in required_ids:
        states = state_map.get(cid)
        if not isinstance(states, dict):
            continue
        folded = cid.casefold()
        if "search" in folded:
            states.update(
                {
                    "default": states.get("default") or "enabled",
                    "query_entered": states.get("query_entered") or "preserve_user_query",
                    "results_available": "render_source_results_only",
                    "no_results": "render_empty_result_without_invented_items",
                    "error": "render_non_fabricated_error_state",
                }
            )
        if "featured" in folded:
            states.update(
                {
                    "source_designated": "render_only_source_marked_featured_items",
                    "not_source_designated": "omit_or_render_empty_state_without_invented_items",
                }
            )


def _enrich_marketplace_structure(components: dict[str, dict[str, Any]]) -> None:
    search = components.get("header_search")
    if search is not None:
        search["role"] = (
            "Support service comparison by narrowing only source-bound services; preserve the query and show source-backed results, empty, or error states without inventing items."
        )

    category = components.get("category_navigation")
    if category is not None:
        content = _require_dict(category.get("content"), "UI_SEMANTIC_QUALITY_CATEGORY_CONTENT_INVALID")
        content["item_structure"] = {"label": "DATA_BOUND", "selection_state": "SOURCE_DEFINED"}
        content["comparison_affordance"] = "SOURCE_DRIVEN_CATEGORY_FILTER_ONLY"
        category["role"] = (
            "Filter or navigate the source-bound service set by source-defined categories so users can compare relevant services without invented classification."
        )

    featured = components.get("featured_services")
    if featured is not None:
        content = _require_dict(featured.get("content"), "UI_SEMANTIC_QUALITY_FEATURED_CONTENT_INVALID")
        content["selection_rule"] = "SOURCE_DESIGNATED_ONLY"
        content["item_template_ref"] = "service_card_template"
        content["overlap_policy"] = "SOURCE_DESIGNATED_SUBSET_MAY_REPEAT_FROM_SERVICE_CARDS"
        featured["state"] = "source_conditional"
        featured["role"] = (
            "Present an optional source-designated subset of services using the same comparison card template; never infer featured status or create a separate service record."
        )

    cards = components.get("service_cards")
    if cards is not None:
        content = _require_dict(cards.get("content"), "UI_SEMANTIC_QUALITY_SERVICE_CARDS_CONTENT_INVALID")
        content["item_template_ref"] = "service_card_template"
        content["comparison_affordance"] = "CONSISTENT_FIELD_ORDER_WITH_SOURCE_DRIVEN_FILTERING_OR_ORDERING_ONLY"
        cards["role"] = (
            "Present the primary source-bound service collection in a stable card field order so title, provider, price, and action can be scanned and compared consistently."
        )

    template = components.get("service_card_template")
    if template is not None:
        template["role"] = (
            "Define the repeated comparison structure for every service card; preserve the same title, provider, price, and action field order across regular and featured presentation."
        )

    roles = {
        "service_title": "Expose the source-bound service title in the same card position so users can compare service identity consistently.",
        "service_provider": "Expose the source-bound provider in the same card position so users can compare who offers each service.",
        "service_price": "Expose only source-bound price data with SOURCE_DEFINED formatting in a consistent card position; never invent precision or discounts.",
        "service_cta": "Expose the source-bound action label only when its source-backed destination exists; otherwise disable or omit the action without inventing a route.",
    }
    for cid, role in roles.items():
        if cid in components:
            components[cid]["role"] = role


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


def _append_risk_controls(deliverable: dict[str, Any], components: dict[str, dict[str, Any]]) -> None:
    controls = deliverable.get("risk_controls")
    if not isinstance(controls, list) or any(not isinstance(item, str) for item in controls):
        raise UISemanticQualityError("UI_SEMANTIC_QUALITY_RISK_CONTROLS_INVALID")
    additions: list[str] = []
    if "featured_services" in components:
        additions.extend(
            [
                "For featured_services, render items only when the source explicitly marks them featured; otherwise omit the section or use its empty state without inventing membership.",
                "featured_services is a presentation subset of service_cards: the same source item may appear in both only when source-designated featured, and must not be duplicated as a new domain record.",
            ]
        )
    additions.extend(
        [
            "Any service ordering, filtering, or comparison grouping must remain source-driven or explicit user interaction; do not invent rankings, recommendations, or domain fields.",
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
    _ensure_states(state_map, required_ids)
    _enrich_marketplace_structure(components)
    _prune_unused_tokens(out, components)

    spacing = _require_dict(
        out.get("spacing_typography"), "UI_SEMANTIC_QUALITY_SPACING_TYPOGRAPHY_INVALID"
    )
    spacing["spacing"] = (
        "compact=1u within component;regular=2u between related components;section=4u between major sections"
    )
    spacing["precision_mode"] = "RELATIVE_GUIDANCE"

    _append_risk_controls(out, components)
    return out
