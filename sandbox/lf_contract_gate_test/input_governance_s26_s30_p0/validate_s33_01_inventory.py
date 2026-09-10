#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

VERSION = "S33_01_INVENTORY_VALIDATOR_V1"
EXPECTED_OBSERVATION_COMMIT = "7fab0a830b62700ba742d824362fb1acdac8b2b5"
EXPECTED_OBSERVATION_BLOB = "9836aff1bccbc4bc97d4a54a40d55ff92e9db030"
EXPECTED_EXTERNAL_CAPABILITIES = {
    "INPUT_GOVERNANCE_ORCHESTRATE",
    "INPUT_GOVERNANCE_DISPATCH",
    "INPUT_GOVERNANCE_CURATE",
    "INPUT_GOVERNANCE_CURATE_RPC",
    "INPUT_GOVERNANCE_VALIDATE",
    "INPUT_GOVERNANCE_VALIDATE_RPC",
    "INPUT_GOVERNANCE_SAFE_AUTOFIX",
    "INPUT_VALIDATOR_RESUME_CONTEXT",
}
EXPECTED_RESOURCE_BINDINGS = {
    "LF_TYPED_DATA_ACCESS": {"blob_sha": "0fc3792e2f75fd5befc6fb22eb6d8e53ccd16965"},
    "LF_SCHEMA_CONTRACT_RESOLUTION": {"blob_sha": "0fc3792e2f75fd5befc6fb22eb6d8e53ccd16965"},
    "LF_BUDGETED_DATA_ACCESS": {"blob_sha": "466751dc09990414c0e0aa6b5d1aaecf99c54ff3"},
    "LF_EXECUTION_AUTHORITY": {
        "policy_blob_sha": "4107e31ad8eb145cb80474de0ba135a164715c00",
        "code_blob_sha": "933e6d597dcffc720854a23ed0ee6ae9002c8a14",
    },
    "LF_HISTORICAL_REPLAY": {"blob_sha": "77369851dce6b0f6fdc0fb1167a43e721152ab57"},
}
EXPECTED_WORKER_PLAN = {
    "SCREEN", "SCREEN_RULE_SET", "SCREEN_STATE_SET", "SCREEN_CANONICAL_GRAPH",
    "DESIGN_BINDING_GRAPH_V4", "API_CONTRACT_RESOLUTION_V1", "EKB_DECISION_SET",
    "EKB_PREVENTION_SET",
}


def stable_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def validate(data: dict[str, Any]) -> dict[str, Any]:
    errors: list[dict[str, str]] = []

    def require(condition: bool, code: str, path: str, detail: str) -> None:
        if not condition:
            errors.append({"code": code, "path": path, "detail": detail})

    require(data.get("inventory_contract") == "S33_CAPABILITY_INVENTORY_V1", "CONTRACT_MISMATCH", "inventory_contract", "unexpected inventory contract")
    require(data.get("strategy_id") == "S33", "STRATEGY_MISMATCH", "strategy_id", "inventory must bind S33")
    require(data.get("stage") == "S33-01", "STAGE_MISMATCH", "stage", "inventory must bind S33-01")
    source = data.get("source_observation") if isinstance(data.get("source_observation"), dict) else {}
    require(source.get("commit_sha") == EXPECTED_OBSERVATION_COMMIT, "SOURCE_COMMIT_MISMATCH", "source_observation.commit_sha", "observation commit drift")
    require(source.get("git_blob_sha") == EXPECTED_OBSERVATION_BLOB, "SOURCE_BLOB_MISMATCH", "source_observation.git_blob_sha", "observation blob drift")
    require(data.get("selection_principle") == "CONSUMER_REQUESTS_CAPABILITY_ID_NEVER_RAW_FUNCTION_NAME", "SELECTION_PRINCIPLE_MISMATCH", "selection_principle", "consumer must request capability id")

    external = data.get("external_surfaces")
    require(isinstance(external, list), "EXTERNAL_SURFACES_INVALID", "external_surfaces", "must be array")
    external = external if isinstance(external, list) else []
    surfaces = [x.get("surface") for x in external if isinstance(x, dict)]
    capability_ids = [x.get("capability_id") for x in external if isinstance(x, dict)]
    require(len(external) == 8, "EXTERNAL_SURFACE_COUNT", "external_surfaces", "expected 8 observed external surfaces")
    require(len(surfaces) == len(set(surfaces)), "DUPLICATE_EXTERNAL_SURFACE", "external_surfaces", "surface must be unique")
    require(len(capability_ids) == len(set(capability_ids)), "DUPLICATE_EXTERNAL_CAPABILITY", "external_surfaces", "capability id must be unique")
    require(set(capability_ids) == EXPECTED_EXTERNAL_CAPABILITIES, "EXTERNAL_CAPABILITY_COVERAGE", "external_surfaces.capability_id", "external capability set mismatch")
    for idx, item in enumerate(external):
        if not isinstance(item, dict):
            continue
        require(item.get("direct_model_selection") is False, "DIRECT_MODEL_SELECTION_FORBIDDEN", f"external_surfaces[{idx}].direct_model_selection", "resource selection must be deterministic")
        require(isinstance(item.get("allowed_consumers"), list) and bool(item.get("allowed_consumers")), "ALLOWED_CONSUMERS_MISSING", f"external_surfaces[{idx}].allowed_consumers", "consumer boundary required")
        require(isinstance(item.get("side_effect_class"), str) and bool(item.get("side_effect_class")), "SIDE_EFFECT_CLASS_MISSING", f"external_surfaces[{idx}].side_effect_class", "side-effect class required")

    internal = data.get("internal_programacion_policy") if isinstance(data.get("internal_programacion_policy"), dict) else {}
    require(internal.get("observed_function_count") == 93, "INTERNAL_FUNCTION_COUNT", "internal_programacion_policy.observed_function_count", "must equal frozen observation")
    require(internal.get("consumer_direct_selection") == "DENY", "INTERNAL_DIRECT_SELECTION_NOT_DENIED", "internal_programacion_policy.consumer_direct_selection", "internal helpers cannot be consumer-selected")
    require(internal.get("versioned_or_cached_direct_selection") == "DENY", "VERSIONED_DIRECT_SELECTION_NOT_DENIED", "internal_programacion_policy.versioned_or_cached_direct_selection", "versioned/cached helpers cannot be consumer-selected")
    require(internal.get("unclassified_external_count") == 0, "UNCLASSIFIED_EXTERNAL_SURFACE", "internal_programacion_policy.unclassified_external_count", "all external surfaces must be classified")
    groups = internal.get("groups") if isinstance(internal.get("groups"), dict) else {}
    require(sum(v for v in groups.values() if isinstance(v, int)) == 93, "INTERNAL_GROUP_DENOMINATOR", "internal_programacion_policy.groups", "group counts must cover all 93 programacion functions")

    resources = data.get("resource_capabilities")
    require(isinstance(resources, list), "RESOURCE_CAPABILITIES_INVALID", "resource_capabilities", "must be array")
    resources = resources if isinstance(resources, list) else []
    by_id = {x.get("capability_id"): x for x in resources if isinstance(x, dict) and isinstance(x.get("capability_id"), str)}
    require(len(by_id) == len(resources), "RESOURCE_CAPABILITY_DUPLICATE", "resource_capabilities", "capability ids must be unique and present")
    for capability_id, fields in EXPECTED_RESOURCE_BINDINGS.items():
        item = by_id.get(capability_id, {})
        require(bool(item), "REQUIRED_REUSE_CAPABILITY_MISSING", f"resource_capabilities.{capability_id}", "required S30 reuse capability absent")
        require(item.get("disposition") == "REUSE_EXACT_SHA", "REUSE_DISPOSITION_MISMATCH", f"resource_capabilities.{capability_id}.disposition", "must reuse exact SHA")
        for field, expected in fields.items():
            require(item.get(field) == expected, "REUSE_SHA_MISMATCH", f"resource_capabilities.{capability_id}.{field}", "exact reusable resource SHA mismatch")

    context_jit = by_id.get("INPUT_CONTEXT_JIT", {})
    require(context_jit.get("disposition") == "BLOCK_NEW_CONSUMPTION_UNTIL_V3_V4_RECONCILIATION", "CONTEXT_JIT_NOT_BLOCKED", "resource_capabilities.INPUT_CONTEXT_JIT", "known V3/V4 drift must block new consumption")
    design = by_id.get("INPUT_DESIGN_BINDING_GRAPH", {})
    require("DO_NOT_EXPOSE_DIRECTLY" in str(design.get("disposition", "")), "DESIGN_DIRECT_EXPOSURE", "resource_capabilities.INPUT_DESIGN_BINDING_GRAPH", "drifted design implementation cannot be direct consumer surface")

    plan = data.get("current_worker_resource_plan")
    require(isinstance(plan, list) and set(plan) == EXPECTED_WORKER_PLAN, "WORKER_PLAN_MISMATCH", "current_worker_resource_plan", "worker resource plan drift")

    model = data.get("model_boundary") if isinstance(data.get("model_boundary"), dict) else {}
    require(model.get("planning_for_known_data_source") == "DENY", "MODEL_KNOWN_DATA_PLAN_ALLOWED", "model_boundary.planning_for_known_data_source", "known data planning must remain deterministic")
    require(model.get("request_mode") == "COMPACT_SEMANTIC_GAP_ONLY", "MODEL_REQUEST_MODE_MISMATCH", "model_boundary.request_mode", "semantic capsule must remain compact")
    require(model.get("output_contract") == "S30_SEMANTIC_DELTA_V1", "MODEL_OUTPUT_CONTRACT_MISMATCH", "model_boundary.output_contract", "semantic delta contract mismatch")
    require(model.get("system_owned_fields") == "DENY", "MODEL_SYSTEM_FIELDS_ALLOWED", "model_boundary.system_owned_fields", "model cannot own system fields")
    require(model.get("post_model_materialization") == "DETERMINISTIC", "POST_MODEL_AUTHORITY_MISMATCH", "model_boundary.post_model_materialization", "post-model materialization must be deterministic")

    checks = data.get("stage_exit_checks") if isinstance(data.get("stage_exit_checks"), dict) else {}
    require(checks.get("runtime_resources_observed") is True, "RUNTIME_OBSERVATION_MISSING", "stage_exit_checks.runtime_resources_observed", "runtime inventory evidence missing")
    require(checks.get("public_facades_observed") == 5, "PUBLIC_FACADE_COUNT", "stage_exit_checks.public_facades_observed", "expected 5 public facades")
    require(checks.get("input_edge_functions_observed") == 3, "EDGE_FUNCTION_COUNT", "stage_exit_checks.input_edge_functions_observed", "expected 3 Input Governance Edge functions")
    require(checks.get("programacion_functions_observed") == 93, "PROGRAMACION_FUNCTION_COUNT", "stage_exit_checks.programacion_functions_observed", "expected 93 programacion functions")
    require(checks.get("unclassified_external_count") == 0, "UNCLASSIFIED_EXTERNAL_EXIT", "stage_exit_checks.unclassified_external_count", "must be zero")
    require(checks.get("call_graph_evidence_bound_to_prior_commit") is True, "CALLGRAPH_LINEAGE_MISSING", "stage_exit_checks.call_graph_evidence_bound_to_prior_commit", "callgraph must bind prior frozen evidence")
    for field in ("foreign_lane_mutations", "supabase_mutations", "runtime_mutations"):
        require(checks.get(field) == 0, "UNAUTHORIZED_MUTATION", f"stage_exit_checks.{field}", "S33-01 must be read-only outside owned Git evidence")

    result = {
        "validator_version": VERSION,
        "valid": not errors,
        "error_count": len(errors),
        "blocking_codes": sorted({e["code"] for e in errors}),
        "errors": errors,
        "observed_external_surface_count": len(external),
        "observed_resource_capability_count": len(resources),
        "observed_internal_group_total": sum(v for v in groups.values() if isinstance(v, int)),
    }
    result["results_sha256"] = stable_sha(result)
    return result


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <inventory.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("inventory root must be object")
        result = validate(data)
    except Exception as exc:
        result = {
            "validator_version": VERSION,
            "valid": False,
            "error_count": 1,
            "blocking_codes": ["MALFORMED_INPUT"],
            "errors": [{"code": "MALFORMED_INPUT", "path": "$", "detail": str(exc)}],
        }
        result["results_sha256"] = stable_sha(result)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    raise SystemExit(main())
