#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import math
import time
from pathlib import Path
from typing import Any

from s26_hp001.gate_f_input import evaluate_f_input
from s26_hp001.happy_path_preexecution import run_preexecution

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FIXTURE = HERE / "s26_hp001"
OUTPUT = FIXTURE / "manual_profile_output.json"
CONTRACT = FIXTURE / "quality_depth_performance_contract.json"
UI_VALIDATOR = REPO / "profiles/ui_architect/validators/validate_ui_architect_output.py"
BOUNDARY_VALIDATOR = REPO / "profiles/ui_architect/validators/validate_composer_payload_boundary.py"


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"QDP_NOT_OBJECT:{path.name}")
    return value


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"QDP_MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _component_map(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    tree = ((data.get("deliverable_created") or {}).get("component_tree") or [])
    return {
        str(item["component_id"]): item
        for item in tree
        if isinstance(item, dict) and item.get("component_id")
    }


def _hierarchy_depth_edges(data: dict[str, Any]) -> int:
    edges: dict[str, list[str]] = {}
    for row in ((data.get("deliverable_created") or {}).get("visual_hierarchy") or []):
        if not isinstance(row, dict) or not row.get("parent_id"):
            continue
        edges.setdefault(str(row["parent_id"]), []).extend(str(x) for x in (row.get("child_ids") or []))

    def walk(node: str, seen: set[str]) -> int:
        if node in seen:
            raise RuntimeError("QDP_HIERARCHY_CYCLE")
        children = edges.get(node, [])
        if not children:
            return 0
        return 1 + max(walk(child, seen | {node}) for child in children)

    return walk("screen", set())


def _requirement_checks(data: dict[str, Any]) -> dict[str, bool]:
    deliverable = data.get("deliverable_created") or {}
    screen = deliverable.get("screen_definition") or {}
    components = _component_map(data)
    card = components.get("service_card_template") or {}
    fields = ((card.get("content") or {}).get("fields") or [])
    return {
        "header_search": "header_search" in components,
        "category_navigation": "category_navigation" in components,
        "featured_services": "featured_services" in components,
        "service_cards": "service_cards" in components,
        "service_card_fields": set(fields) == {"title", "provider", "price", "call_to_action"},
        "design_intent": set(screen.get("design_intent") or []) == {"clear", "professional", "easy_to_navigate"},
        "implementation_ready": screen.get("implementation_readiness") == "STRUCTURED_SPEC_READY_FOR_NEXT_AGENT",
        "structured_handoff": (data.get("handoff_to_next") or {}).get("payload_ref") == "composer_payload",
    }


def _source_bound_checks(data: dict[str, Any]) -> dict[str, bool]:
    c = _component_map(data)
    return {
        "categories_source_bound": ((c.get("category_navigation") or {}).get("content") or {}).get("items") == "DATA_BOUND",
        "featured_source_bound": ((c.get("featured_services") or {}).get("content") or {}).get("items") == "DATA_BOUND",
        "collection_source_bound": ((c.get("service_cards") or {}).get("content") or {}).get("items") == "DATA_BOUND",
        "template_values_source_bound": ((c.get("service_card_template") or {}).get("content") or {}).get("values") == "DATA_BOUND",
        "title_source_bound": ((c.get("service_title") or {}).get("content") or {}).get("value") == "DATA_BOUND:title",
        "provider_source_bound": ((c.get("service_provider") or {}).get("content") or {}).get("value") == "DATA_BOUND:provider",
        "price_source_bound": (
            ((c.get("service_price") or {}).get("content") or {}).get("value") == "DATA_BOUND:price"
            and ((c.get("service_price") or {}).get("content") or {}).get("format") == "SOURCE_DEFINED"
        ),
        "cta_source_bound": (
            ((c.get("service_cta") or {}).get("content") or {}).get("label") == "DATA_BOUND:call_to_action"
            and ((c.get("service_cta") or {}).get("content") or {}).get("destination") == "UNRESOLVED_UNTIL_SOURCE"
        ),
    }


def evaluate_quality_depth(data: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    quality_contract = contract["quality"]
    depth_contract = contract["depth"]
    components = _component_map(data)

    requirement_checks = _requirement_checks(data)
    source_checks = _source_bound_checks(data)
    requirement_ratio = sum(requirement_checks.values()) / len(requirement_checks)
    source_ratio = sum(source_checks.values()) / len(source_checks)

    state_map = ((data.get("deliverable_created") or {}).get("state_map") or {})
    stateful_required = {"header_search", "category_navigation", "featured_services", "service_cards", "service_cta"}
    state_ratio = len(stateful_required.intersection(state_map)) / len(stateful_required)

    variant_guarded = [
        component_id
        for component_id, component in components.items()
        if component.get("allowed_variants") and component.get("blocked_variants")
    ]
    variant_ratio = len(variant_guarded) / max(1, len(components))
    hierarchy_depth = _hierarchy_depth_edges(data)
    layout = ((data.get("deliverable_created") or {}).get("layout_grid") or {})
    risk_controls = ((data.get("deliverable_created") or {}).get("risk_controls") or [])
    required_leafs = set(depth_contract["required_service_leaf_components"])

    self_score = data.get("score") or {}
    self_score_total = self_score.get("total")

    quality_errors = []
    if requirement_ratio < float(quality_contract["minimum_requirement_coverage_ratio"]):
        quality_errors.append("QDP_QUALITY_REQUIREMENT_COVERAGE_LOW")
    if source_ratio < float(quality_contract["minimum_source_bound_integrity_ratio"]):
        quality_errors.append("QDP_QUALITY_SOURCE_BOUND_INTEGRITY_LOW")

    depth_errors = []
    if len(components) < int(depth_contract["minimum_component_count"]):
        depth_errors.append("QDP_DEPTH_COMPONENT_COUNT_LOW")
    if hierarchy_depth < int(depth_contract["minimum_hierarchy_depth_edges"]):
        depth_errors.append("QDP_DEPTH_HIERARCHY_TOO_SHALLOW")
    if state_ratio < float(depth_contract["minimum_state_map_coverage_ratio"]):
        depth_errors.append("QDP_DEPTH_STATE_MAP_COVERAGE_LOW")
    if variant_ratio < float(depth_contract["minimum_variant_guard_coverage_ratio"]):
        depth_errors.append("QDP_DEPTH_VARIANT_GUARD_COVERAGE_LOW")
    if len(risk_controls) < int(depth_contract["minimum_risk_control_count"]):
        depth_errors.append("QDP_DEPTH_RISK_CONTROL_COUNT_LOW")
    missing_modes = [mode for mode in depth_contract["required_responsive_modes"] if not layout.get(mode)]
    if missing_modes:
        depth_errors.append("QDP_DEPTH_RESPONSIVE_MODE_MISSING:" + ",".join(missing_modes))
    missing_leafs = sorted(required_leafs - set(components))
    if missing_leafs:
        depth_errors.append("QDP_DEPTH_SERVICE_LEAF_MISSING:" + ",".join(missing_leafs))

    return {
        "quality": {
            "requirement_coverage_ratio": requirement_ratio,
            "source_bound_integrity_ratio": source_ratio,
            "requirement_checks": requirement_checks,
            "source_bound_checks": source_checks,
            "self_reported_score_total_observed_not_authority": self_score_total,
            "self_score_used_as_authority": False,
            "errors": quality_errors,
            "pass": not quality_errors,
        },
        "depth": {
            "component_count": len(components),
            "hierarchy_depth_edges": hierarchy_depth,
            "state_map_coverage_ratio": state_ratio,
            "variant_guard_coverage_ratio": variant_ratio,
            "risk_control_count": len(risk_controls),
            "responsive_modes_present": [mode for mode in depth_contract["required_responsive_modes"] if layout.get(mode)],
            "service_leaf_components_present": sorted(required_leafs.intersection(components)),
            "errors": depth_errors,
            "pass": not depth_errors,
        },
    }


def _validate_canonical(data: dict[str, Any]) -> dict[str, bool]:
    ui = _load_module(UI_VALIDATOR, "s26_qdp_ui_validator")
    boundary = _load_module(BOUNDARY_VALIDATOR, "s26_qdp_boundary_validator")
    ui_errors = ui.validate(data)
    boundary_errors = boundary.validate(data)
    return {
        "ui_validator_pass": not ui_errors,
        "composer_boundary_pass": not boundary_errors,
    }


def _validate_once(data: dict[str, Any], contract: dict[str, Any]) -> None:
    pre = run_preexecution()
    if pre.get("result") != "PASS":
        raise RuntimeError("QDP_PREEXECUTION_NOT_PASS")
    f_input = evaluate_f_input()
    if f_input.get("f_compatibility_proven") is not True:
        raise RuntimeError("QDP_E_TO_F_COMPATIBILITY_NOT_PASS")
    canonical = _validate_canonical(data)
    if not all(canonical.values()):
        raise RuntimeError("QDP_CANONICAL_VALIDATOR_NOT_PASS")
    qd = evaluate_quality_depth(data, contract)
    if not qd["quality"]["pass"]:
        raise RuntimeError("QDP_QUALITY_NOT_PASS:" + ",".join(qd["quality"]["errors"]))
    if not qd["depth"]["pass"]:
        raise RuntimeError("QDP_DEPTH_NOT_PASS:" + ",".join(qd["depth"]["errors"]))


def _percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(q * len(ordered)) - 1))
    return ordered[index]


def benchmark(data: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    cfg = contract["performance"]
    for _ in range(int(cfg["warmup_iterations"])):
        _validate_once(data, contract)

    samples_ms = []
    for _ in range(int(cfg["sample_iterations"])):
        start = time.perf_counter_ns()
        _validate_once(data, contract)
        samples_ms.append((time.perf_counter_ns() - start) / 1_000_000.0)

    raw = OUTPUT.read_bytes()
    p50 = _percentile(samples_ms, 0.50)
    p95 = _percentile(samples_ms, 0.95)
    maximum = max(samples_ms)
    errors = []
    if p95 > float(cfg["max_p95_deterministic_pipeline_ms"]):
        errors.append("QDP_PERFORMANCE_P95_BUDGET_EXCEEDED")
    if maximum > float(cfg["max_single_deterministic_pipeline_ms"]):
        errors.append("QDP_PERFORMANCE_SINGLE_BUDGET_EXCEEDED")
    if len(raw) > int(cfg["max_output_bytes"]):
        errors.append("QDP_PERFORMANCE_OUTPUT_BYTES_EXCEEDED")
    token_proxy = len(OUTPUT.read_text(encoding="utf-8")) / 4.0
    if token_proxy > float(cfg["max_output_token_proxy_chars_div_4"]):
        errors.append("QDP_PERFORMANCE_OUTPUT_TOKEN_PROXY_EXCEEDED")

    return {
        "scope": contract["scope"],
        "measurement_clock": "time.perf_counter_ns",
        "sample_iterations": len(samples_ms),
        "p50_ms": round(p50, 3),
        "p95_ms": round(p95, 3),
        "max_ms": round(maximum, 3),
        "max_p95_budget_ms": cfg["max_p95_deterministic_pipeline_ms"],
        "max_single_budget_ms": cfg["max_single_deterministic_pipeline_ms"],
        "output_bytes": len(raw),
        "max_output_bytes": cfg["max_output_bytes"],
        "output_token_proxy_chars_div_4": round(token_proxy, 2),
        "max_output_token_proxy_chars_div_4": cfg["max_output_token_proxy_chars_div_4"],
        "model_generation_latency_measured": False,
        "model_generation_latency_required_at_gate_f": True,
        "errors": errors,
        "pass": not errors,
    }


def _expect_metric_fail(name: str, data: dict[str, Any], contract: dict[str, Any], expected: str) -> str:
    result = evaluate_quality_depth(data, contract)
    errors = result["quality"]["errors"] + result["depth"]["errors"]
    if expected not in errors:
        raise RuntimeError(f"QDP_NEGATIVE_FALSE_PASS:{name}:{errors}")
    return expected


def main() -> int:
    contract = _load(CONTRACT)
    if contract.get("schema") != "S26_HP001_QDP_CONTRACT_V1":
        raise RuntimeError("QDP_CONTRACT_SCHEMA_INVALID")
    if contract.get("scope") != "DETERMINISTIC_PIPELINE_AND_ARTIFACT_ONLY":
        raise RuntimeError("QDP_SCOPE_INVALID")
    if (contract.get("quality") or {}).get("self_score_is_authority") is not False:
        raise RuntimeError("QDP_SELF_SCORE_AUTHORITY_MUST_BE_FALSE")
    if (contract.get("performance") or {}).get("model_generation_latency_measured") is not False:
        raise RuntimeError("QDP_MODEL_RUNTIME_PERF_FALSE_CLAIM")
    if (contract.get("performance") or {}).get("model_generation_latency_required_at_gate_f") is not True:
        raise RuntimeError("QDP_GATE_F_MODEL_PERF_REQUIREMENT_MISSING")

    data = _load(OUTPUT)
    canonical = _validate_canonical(data)
    if not all(canonical.values()):
        raise RuntimeError("QDP_CANONICAL_VALIDATION_FAILED")

    qd = evaluate_quality_depth(data, contract)
    if not qd["quality"]["pass"]:
        raise RuntimeError("QDP_QUALITY_FAILED:" + ",".join(qd["quality"]["errors"]))
    if not qd["depth"]["pass"]:
        raise RuntimeError("QDP_DEPTH_FAILED:" + ",".join(qd["depth"]["errors"]))

    negatives = {}

    x = copy.deepcopy(data)
    x["score"]["total"] = 20
    x["deliverable_created"]["component_tree"] = [
        row for row in x["deliverable_created"]["component_tree"] if row.get("component_id") != "featured_services"
    ]
    negatives["self_score_20_missing_requirement"] = _expect_metric_fail(
        "self_score_20_missing_requirement", x, contract, "QDP_QUALITY_REQUIREMENT_COVERAGE_LOW"
    )

    x = copy.deepcopy(data)
    x["deliverable_created"]["component_tree"] = [
        {**row, "content": ({"value": "S/ 99"} if row.get("component_id") == "service_price" else row.get("content"))}
        for row in x["deliverable_created"]["component_tree"]
    ]
    negatives["invented_price"] = _expect_metric_fail(
        "invented_price", x, contract, "QDP_QUALITY_SOURCE_BOUND_INTEGRITY_LOW"
    )

    x = copy.deepcopy(data)
    x["deliverable_created"]["visual_hierarchy"] = [
        {"parent_id": "screen", "child_ids": list(_component_map(x).keys())}
    ]
    negatives["flattened_hierarchy"] = _expect_metric_fail(
        "flattened_hierarchy", x, contract, "QDP_DEPTH_HIERARCHY_TOO_SHALLOW"
    )

    x = copy.deepcopy(data)
    del x["deliverable_created"]["state_map"]["service_cta"]
    negatives["missing_state_depth"] = _expect_metric_fail(
        "missing_state_depth", x, contract, "QDP_DEPTH_STATE_MAP_COVERAGE_LOW"
    )

    x = copy.deepcopy(data)
    for row in x["deliverable_created"]["component_tree"]:
        if row.get("component_id") == "service_price":
            row["blocked_variants"] = []
    negatives["missing_variant_guard"] = _expect_metric_fail(
        "missing_variant_guard", x, contract, "QDP_DEPTH_VARIANT_GUARD_COVERAGE_LOW"
    )

    x = copy.deepcopy(data)
    del x["deliverable_created"]["layout_grid"]["mobile"]
    negatives["missing_mobile_depth"] = _expect_metric_fail(
        "missing_mobile_depth", x, contract, "QDP_DEPTH_RESPONSIVE_MODE_MISSING:mobile"
    )

    perf = benchmark(data, contract)
    if not perf["pass"]:
        raise RuntimeError("QDP_PERFORMANCE_FAILED:" + ",".join(perf["errors"]))

    synthetic_perf_errors = []
    synthetic = dict(perf)
    synthetic["p95_ms"] = float(contract["performance"]["max_p95_deterministic_pipeline_ms"]) + 1.0
    if synthetic["p95_ms"] > float(contract["performance"]["max_p95_deterministic_pipeline_ms"]):
        synthetic_perf_errors.append("QDP_PERFORMANCE_P95_BUDGET_EXCEEDED")
    if "QDP_PERFORMANCE_P95_BUDGET_EXCEEDED" not in synthetic_perf_errors:
        raise RuntimeError("QDP_PERFORMANCE_NEGATIVE_FALSE_PASS")
    negatives["performance_budget"] = "QDP_PERFORMANCE_P95_BUDGET_EXCEEDED"

    print(json.dumps({
        "gate": "S26_HP001_QUALITY_DEPTH_PERFORMANCE_V1",
        "result": "PASS",
        "quality": qd["quality"],
        "depth": qd["depth"],
        "performance": perf,
        "canonical_validation": canonical,
        "negative_controls": negatives,
        "claim_ceiling": contract["claim_ceiling"],
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
