"""A4: deterministic projection of the EXISTING shared impact core.

The authorized LF host reads the fixed S1-S5 source set. A4 does no
discovery, SQL, network, GitHub lookup, execution or attestation.
"""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts/deterministic_source_set_v1.json"
SCHEMA = "SHARED_CHANGE_IMPACT_ANALYSIS"
CORE = "SHARED_CHANGE_IMPACT_MAP_V1"
SIDECAR = "A4_EXISTING_IMPACT_CORE_READBACK_V1"


def _blocked(code: str, *, target: str | None = None) -> dict:
    return {
        "schema_version": SCHEMA, "status": "BLOCKED",
        "target_ref": target, "blocking_codes": [code],
        "direct_impacts": [], "indirect_impacts": [], "consumers": [],
        "dependency_paths": [], "evidence_refs": [],
        "unresolved_material_impacts": [{"code": code, "target_ref": target}],
        "source_attested": False, "impact_verified": False,
        "a5_allowed": False, "no_write_performed": True,
    }


def _gap(code: str, *, target: str, source: str) -> dict:
    return {"code": code, "target_ref": target, "source_id": source,
            "resolution": "TARGETED_RETURN_TO_A3_OR_EXACT_PROVIDER",
            "impact_state": "UNKNOWN"}


def run(a3: Any, a2: Any, readback: Any = None, *, business: str = "LF") -> dict:
    """Read supplied exact-source evidence, never search repositories or tables.

    The result is an UNATTESTED candidate even if every readback row looks
    consistent; source auth/currentness, judge and operation gates live in
    the existing governed host.
    """
    if business != "LF":
        return _blocked("A4_BUSINESS_NOT_ENABLED_FOR_LF_SKILL")
    policy = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if (policy.get("schema_version") != "A4_DETERMINISTIC_SOURCE_SET_V1"
            or [x.get("id") for x in policy.get("sources", [])] != [
                "S1_A3", "S2_A2", "S3_INV_OBJECT",
                "S4_IMPACT_CORE", "S5_DEPENDENCIES"
            ]):
        return _blocked("A4_SOURCE_SET_CONTRACT_DRIFT")
    if (not isinstance(a3, dict) or not isinstance(a2, dict)
            or a3.get("schema_version") != "TARGETED_EVIDENCE_SET_V1"
            or a2.get("schema_version") != "ANALYSIS_CHANGE_CLASSIFICATION_V1"):
        return _blocked("A4_EXACT_A3_A2_INPUTS_REQUIRED")
    target = a3.get("target_ref")
    classified = a2.get("target_ref")
    if (a3.get("business") != "LF" or not isinstance(target, str)
            or not target or not isinstance(classified, str)
            or classified not in (target, a3.get("declared_target_hint"))):
        return _blocked("A4_TARGET_OR_BUSINESS_BINDING_INVALID", target=target)
    if a3.get("status") != "SOURCE_READBACK_PROCESSED_UNATTESTED":
        return _blocked("A4_A3_NOT_ADMISSIBLE_EVIDENCE_CANDIDATE", target=target)
    if not isinstance(a3.get("source_refs"), list) or not a3["source_refs"]:
        return _blocked("A4_A3_EVIDENCE_REFS_REQUIRED", target=target)
    if not isinstance(readback, dict):
        return {
            **_blocked("A4_EXACT_HOST_SOURCE_READBACK_REQUIRED", target=target),
            "status": "NEED_MORE_EVIDENCE",
        }
    if (readback.get("schema_version") != SIDECAR
            or readback.get("business") != "LF"
            or readback.get("target_ref") != target
            or readback.get("source_attested") is not False):
        return _blocked("A4_HOST_SOURCE_IDENTITY_INVALID", target=target)
    inv = readback.get("inventory_object")
    binding = readback.get("identity_binding")
    if inv is None and binding is None:
        return {
            **_blocked("A4_TARGET_NOT_MAPPED_TO_INVENTORY_OBJECT", target=target),
            "status": "IMPACT_UNKNOWN",
            "unresolved_material_impacts": [
                _gap("A4_TARGET_NOT_MAPPED_TO_INVENTORY_OBJECT",
                     target=target, source="S3_INV_OBJECT")
            ],
        }
    if not isinstance(inv, dict) or not isinstance(binding, dict):
        return _blocked("A4_INVENTORY_IDENTITY_READBACK_INCOMPLETE", target=target)
    root = inv.get("object_ref")
    if (not isinstance(root, str) or not root or inv.get("active") is not True
            or not isinstance(inv.get("object_type"), str)
            or not inv["object_type"]):
        return _blocked("A4_INVENTORY_OBJECT_NOT_EXACT_ACTIVE", target=target)
    if (binding.get("target_ref") != target
            or binding.get("inventory_object_ref") != root
            or binding.get("source_ref") not in a3["source_refs"]
            or binding.get("source_attested") is not False):
        return _blocked("A4_INVENTORY_TARGET_BINDING_MISSING_OR_DRIFTED", target=target)
    impact = readback.get("impact_readback")
    deps = readback.get("dependency_readback")
    if not isinstance(impact, dict) or not isinstance(deps, dict):
        return {
            **_blocked("A4_DEPENDENCY_SOURCE_READBACK_MISSING", target=target),
            "status": "IMPACT_UNKNOWN",
        }
    expected = [
        (impact, "inventory.fn_impact_analysis_v1",
         {"p_object_ref": root, "p_max_depth": 3, "p_min_confidence": 0.8}),
        (deps, "inventory.fn_dependencies_v1",
         {"p_object_ref": root, "p_direction": "BOTH", "p_max_depth": 2}),
    ]
    for item, fn, params in expected:
        if (item.get("source_function") != fn
                or item.get("parameters") != params
                or item.get("source_attested") is not False
                or not isinstance(item.get("rows"), list)):
            return _blocked("A4_GRAPH_PROVIDER_OR_PARAMETERS_DRIFT", target=target)
    direct, indirect, consumers, paths = [], [], [], []
    for item in impact["rows"]:
        if (not isinstance(item, dict)
                or type(item.get("depth")) is not int
                or not 1 <= item["depth"] <= 3
                or not isinstance(item.get("affected_ref"), str)
                or not item["affected_ref"]
                or not isinstance(item.get("affected_type"), str)
                or not isinstance(item.get("via_relation"), str)
                or type(item.get("min_confidence")) not in (float, int)
                or not 0.8 <= item["min_confidence"] <= 1.0):
            return _blocked("A4_IMPACT_CORE_ROW_INVALID", target=target)
        projected = {
            "affected_ref": item["affected_ref"],
            "affected_type": item["affected_type"],
            "via_relation": item["via_relation"],
            "depth": item["depth"],
            "confidence": item["min_confidence"],
            "evidence_origin": "S4_IMPACT_CORE",
            "impact_class": "POTENTIAL_GRAPH_RELATION_NOT_BEHAVIOR_PROOF",
        }
        (direct if item["depth"] == 1 else indirect).append(projected)
    for item in deps["rows"]:
        if (not isinstance(item, dict)
                or type(item.get("depth")) is not int
                or not 1 <= item["depth"] <= 2
                or item.get("direction") not in ("IN", "OUT")
                or not isinstance(item.get("source_ref"), str)
                or not isinstance(item.get("target_ref"), str)
                or not isinstance(item.get("relation_type"), str)
                or type(item.get("confidence")) not in (float, int)
                or not 0 <= item["confidence"] <= 1.0):
            return _blocked("A4_DEPENDENCY_ROW_INVALID", target=target)
        projected = {
            "depth": item["depth"], "direction": item["direction"],
            "source_ref": item["source_ref"],
            "target_ref": item["target_ref"],
            "relation_type": item["relation_type"],
            "confidence": item["confidence"],
            "evidence_type": item.get("evidence_type"),
            "evidence_origin": "S5_DEPENDENCIES",
        }
        paths.append(projected)
        if item["direction"] == "IN":
            consumers.append(deepcopy(projected))
    unresolved = []
    if inv.get("currentness") != "CURRENT":
        unresolved.append(_gap("A4_INVENTORY_OBJECT_CURRENTNESS_NOT_VERIFIED",
                               target=target, source="S3_INV_OBJECT"))
    if not isinstance(a3.get("as_is_baseline_or_new_implementation_evidence"), dict):
        unresolved.append(_gap("A4_AS_IS_IMPLEMENTATION_EVIDENCE_MISSING",
                               target=target, source="S1_A3"))
    if not impact["rows"] and not deps["rows"]:
        unresolved.append(_gap("A4_EMPTY_GRAPH_DOES_NOT_ESTABLISH_NO_IMPACT",
                               target=target, source="S4_IMPACT_CORE"))
    for code in a3.get("unresolved_material_gaps", []):
        if isinstance(code, str) and code:
            unresolved.append(_gap(code, target=target, source="S1_A3"))
    refs = list(dict.fromkeys(
        [r for r in a3["source_refs"] if isinstance(r, str)]
        + [root]
    ))
    return {
        "schema_version": SCHEMA,
        "core_output_contract": CORE,
        "status": "PROJECTED_UNATTESTED" if not unresolved else "IMPACT_UNKNOWN",
        "business": "LF", "target_ref": target,
        "requested_change_type": a2.get("change_type"),
        "technical_root_ref": root,
        "direct_impacts": direct, "indirect_impacts": indirect,
        "consumers": consumers, "dependency_paths": paths,
        "evidence_refs": refs,
        "unresolved_material_impacts": unresolved,
        "counts": {"direct": len(direct), "indirect": len(indirect),
                   "consumers": len(consumers), "dependency_paths": len(paths)},
        "source_set_ref": "steps/a4/contracts/deterministic_source_set_v1.json",
        "source_attested": False, "impact_verified": False,
        "a5_allowed": False, "no_write_performed": True,
    }
