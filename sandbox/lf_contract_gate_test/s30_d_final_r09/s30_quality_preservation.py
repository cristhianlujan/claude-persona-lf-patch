from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

INPUT_CONTRACT = "S30_QUALITY_OBLIGATION_INPUT_V1"
MANIFEST_CONTRACT = "S30_SEMANTIC_OBLIGATION_MANIFEST_V1"
DELTA_CONTRACT = "S30_SEMANTIC_DELTA_V2"
FINAL_EVAL_CONTRACT = "S30_FINAL_SEMANTIC_QUALITY_EVALUATION_V1"
PASS = "PASS"
BLOCKED = "BLOCKED"
CHECK_MODES = {"DETERMINISTIC_READBACK", "SEMANTIC_DELTA", "FINAL_SEMANTIC_EVALUATION"}


def canonical_sha256(value: Any) -> str:
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def validate_readiness_projection(projection: Any) -> dict:
    if not isinstance(projection, Mapping):
        return _block("BLOCK_PROFILE_CARD_READINESS_PROJECTION_INVALID")
    required = {
        "contract_version", "execution_id", "profile_code", "readiness_receipt_sha256",
        "readiness_status", "card_coverage_status", "coverage_reason", "coverage_evidence_refs",
        "quality_obligations",
    }
    if set(projection) != required:
        return _block("BLOCK_PROFILE_CARD_READINESS_PROJECTION_SHAPE")
    if projection.get("contract_version") != INPUT_CONTRACT:
        return _block("BLOCK_PROFILE_CARD_READINESS_CONTRACT")
    if projection.get("readiness_status") != "EXECUTION_READY" or projection.get("card_coverage_status") != "PASS":
        return _block("BLOCK_PROFILE_NOT_EXECUTION_READY")
    if not _sha(projection.get("readiness_receipt_sha256")):
        return _block("BLOCK_PROFILE_READINESS_SHA256")
    if not _text(projection.get("execution_id")) or not _text(projection.get("profile_code")):
        return _block("BLOCK_PROFILE_READINESS_IDENTITY")
    if not _text(projection.get("coverage_reason")):
        return _block("BLOCK_PROFILE_CARD_COVERAGE_REASON_MISSING")
    refs = projection.get("coverage_evidence_refs")
    if not isinstance(refs, list) or not refs or any(not _text(x) for x in refs):
        return _block("BLOCK_PROFILE_CARD_COVERAGE_EVIDENCE_MISSING")
    obs = projection.get("quality_obligations")
    if not isinstance(obs, list):
        return _block("BLOCK_PROFILE_QUALITY_OBLIGATIONS_NOT_ARRAY")
    seen = set()
    normalized = []
    for item in obs:
        if not isinstance(item, Mapping) or set(item) != {
            "obligation_id", "statement", "criticality", "source_ref", "verification_mode"
        }:
            return _block("BLOCK_PROFILE_QUALITY_OBLIGATION_SHAPE")
        oid = item.get("obligation_id")
        if not _text(oid) or oid in seen:
            return _block("BLOCK_PROFILE_QUALITY_OBLIGATION_ID")
        seen.add(oid)
        if item.get("criticality") not in {"CRITICAL", "REQUIRED"}:
            return _block("BLOCK_PROFILE_QUALITY_OBLIGATION_FIELDS")
        if item.get("verification_mode") not in CHECK_MODES:
            return _block("BLOCK_PROFILE_QUALITY_VERIFICATION_MODE")
        if not _text(item.get("statement")) or not _text(item.get("source_ref")):
            return _block("BLOCK_PROFILE_QUALITY_OBLIGATION_FIELDS")
        normalized.append(dict(item))
    return {
        "status": PASS,
        "code": "PASS_PROFILE_CARD_READINESS_PROJECTION",
        "projection": dict(projection),
        "quality_obligations": normalized,
    }


def _normalize_graph(graph: Any) -> dict:
    if not isinstance(graph, Mapping):
        raise ValueError("GRAPH_NOT_OBJECT")
    ids = graph.get("ids")
    if not isinstance(ids, list) or not ids or any(not _text(x) for x in ids) or len(set(ids)) != len(ids):
        raise ValueError("GRAPH_IDS_INVALID")
    relations = graph.get("relations", [])
    if not isinstance(relations, list):
        raise ValueError("GRAPH_RELATIONS_INVALID")
    norm_rel = []
    relation_ids = set()
    for i, rel in enumerate(relations):
        if not isinstance(rel, Mapping):
            raise ValueError("GRAPH_RELATION_NOT_OBJECT")
        rid = rel.get("relation_id") or f"rel-{i+1}"
        members = rel.get("member_ids")
        if not _text(rid) or rid in relation_ids:
            raise ValueError("GRAPH_RELATION_ID_INVALID")
        if not isinstance(members, list) or len(members) < 2 or any(x not in ids for x in members) or len(set(members)) != len(members):
            raise ValueError("GRAPH_RELATION_MEMBERS_INVALID")
        relation_ids.add(rid)
        norm_rel.append({
            "relation_id": rid,
            "relation_type": rel.get("relation_type", "ASSOCIATION"),
            "member_ids": list(members),
        })
    return {
        "contract_version": graph.get("contract_version", "S30_CANONICAL_WORKING_GRAPH_V1"),
        "ids": list(ids),
        "relations": norm_rel,
    }


def build_semantic_obligation_manifest(projection: Any, canonical_working_graph: Any) -> dict:
    checked = validate_readiness_projection(projection)
    if checked["status"] != PASS:
        return checked
    try:
        graph = _normalize_graph(canonical_working_graph)
    except ValueError as exc:
        return _block("BLOCK_CANONICAL_WORKING_GRAPH_INVALID", detail=str(exc))

    obligations = []
    for cid in graph["ids"]:
        obligations.append({
            "obligation_id": f"CMP::{cid}", "kind": "COMPONENT_PRESERVATION",
            "criticality": "CRITICAL", "statement": f"Preserve required component {cid}",
            "component_id": cid, "source_ref": "CANONICAL_WORKING_GRAPH",
            "check_mode": "DETERMINISTIC_READBACK",
        })
    for rel in graph["relations"]:
        obligations.append({
            "obligation_id": f"REL::{rel['relation_id']}", "kind": "RELATION_PRESERVATION",
            "criticality": "CRITICAL",
            "statement": f"Preserve relation {rel['relation_id']} {rel['relation_type']} over {','.join(rel['member_ids'])}",
            "relation_id": rel["relation_id"], "member_ids": rel["member_ids"],
            "source_ref": "CANONICAL_WORKING_GRAPH", "check_mode": "DETERMINISTIC_READBACK",
        })
    for item in checked["quality_obligations"]:
        obligations.append({
            "obligation_id": f"QLT::{item['obligation_id']}", "kind": "PROFILE_QUALITY",
            "criticality": item["criticality"], "statement": item["statement"],
            "source_ref": item["source_ref"], "check_mode": item["verification_mode"],
        })

    ids = [x["obligation_id"] for x in obligations]
    if len(ids) != len(set(ids)):
        return _block("BLOCK_SEMANTIC_OBLIGATION_ID_COLLISION")
    graph_digest = canonical_sha256(graph)
    invariant_payload = {
        "profile_code": projection["profile_code"],
        "graph_sha256": graph_digest,
        "obligations": obligations,
        "coverage_reason": projection["coverage_reason"],
    }
    invariant_digest = canonical_sha256(invariant_payload)
    semantic_ids = [o["obligation_id"] for o in obligations if o["check_mode"] == "SEMANTIC_DELTA"]
    deterministic_ids = [o["obligation_id"] for o in obligations if o["check_mode"] == "DETERMINISTIC_READBACK"]
    final_semantic_ids = [o["obligation_id"] for o in obligations if o["check_mode"] == "FINAL_SEMANTIC_EVALUATION"]
    manifest = {
        "contract_version": MANIFEST_CONTRACT,
        "execution_id": projection["execution_id"],
        "profile_code": projection["profile_code"],
        "readiness_receipt_sha256": projection["readiness_receipt_sha256"],
        "coverage_evidence_refs": list(projection["coverage_evidence_refs"]),
        "canonical_working_graph_sha256": graph_digest,
        "semantic_invariant_sha256": invariant_digest,
        "required_obligation_ids": ids,
        "semantic_delta_obligation_ids": semantic_ids,
        "deterministic_readback_obligation_ids": deterministic_ids,
        "final_semantic_evaluation_obligation_ids": final_semantic_ids,
        "obligations": obligations,
        "bound_before_model": True,
    }
    manifest["manifest_sha256"] = canonical_sha256(manifest)
    return {"status": PASS, "code": "PASS_SEMANTIC_OBLIGATION_MANIFEST_BUILT", "manifest": manifest}


def build_semantic_gap_request_v2(task: Mapping[str, Any], manifest: Mapping[str, Any]) -> dict:
    if manifest.get("contract_version") != MANIFEST_CONTRACT or manifest.get("bound_before_model") is not True:
        return _block("BLOCK_SEMANTIC_MANIFEST_REQUIRED_BEFORE_MODEL")
    allowed = {k: task[k] for k in (
        "semantic_context", "unresolved_semantic_gap", "candidate_alternatives", "semantic_constraints"
    ) if k in task}
    by_id = {o["obligation_id"]: o for o in manifest["obligations"]}
    compact = [
        {"obligation_id": oid, "kind": by_id[oid]["kind"], "criticality": by_id[oid]["criticality"], "statement": by_id[oid]["statement"]}
        for oid in manifest["semantic_delta_obligation_ids"]
    ]
    deterministic_constraints = [
        {"obligation_id": oid, "statement": by_id[oid]["statement"]}
        for oid in manifest["deterministic_readback_obligation_ids"]
    ]
    return {"status": PASS, "code": "PASS_SEMANTIC_GAP_REQUEST_V2_BUILT", "request": {
        "request_contract": "S30_MODEL_SEMANTIC_GAP_REQUEST_V2",
        "manifest_sha256": manifest["manifest_sha256"],
        "semantic_invariant_sha256": manifest["semantic_invariant_sha256"],
        "semantic_context": allowed,
        "required_semantic_obligations": compact,
        "deterministic_preservation_constraints": deterministic_constraints,
        "output_contract": {
            "contract_version": DELTA_CONTRACT,
            "required_fields": ["decisions", "proposals", "rationale", "unresolved", "obligation_evidence"],
        },
    }}


def _resolve_pointer(delta: Mapping[str, Any], pointer: Any) -> bool:
    if not isinstance(pointer, Mapping) or set(pointer) != {"field", "index"}:
        return False
    field = pointer.get("field")
    idx = pointer.get("index")
    if field not in {"decisions", "proposals", "rationale"} or not isinstance(idx, int) or idx < 0:
        return False
    arr = delta.get(field)
    return isinstance(arr, list) and idx < len(arr) and arr[idx] not in (None, "", {}, [])


def validate_semantic_delta_v2(model_output: Any, manifest: Mapping[str, Any]) -> dict:
    if not isinstance(model_output, Mapping) or set(model_output) != {"semantic_delta"}:
        return _block("BLOCK_MODEL_SEMANTIC_DELTA_V2_CONTRACT")
    delta = model_output.get("semantic_delta")
    required_fields = {"decisions", "proposals", "rationale", "unresolved", "obligation_evidence"}
    if not isinstance(delta, Mapping) or set(delta) != required_fields or any(not isinstance(delta[f], list) for f in required_fields):
        return _block("BLOCK_MODEL_SEMANTIC_DELTA_V2_CONTRACT")
    if delta["unresolved"]:
        return _block("BLOCK_SEMANTIC_UNRESOLVED", unresolved=delta["unresolved"])
    required = list(manifest.get("semantic_delta_obligation_ids") or [])
    evidence = delta["obligation_evidence"]
    seen = []
    for item in evidence:
        if not isinstance(item, Mapping) or set(item) != {"obligation_id", "evidence_pointer"}:
            return _block("BLOCK_SEMANTIC_OBLIGATION_EVIDENCE_SHAPE")
        oid = item.get("obligation_id")
        if oid not in required:
            return _block("BLOCK_SEMANTIC_OBLIGATION_UNKNOWN", obligation_id=oid)
        if oid in seen:
            return _block("BLOCK_SEMANTIC_OBLIGATION_DUPLICATE", obligation_id=oid)
        if not _resolve_pointer(delta, item.get("evidence_pointer")):
            return _block("BLOCK_SEMANTIC_OBLIGATION_EVIDENCE_POINTER", obligation_id=oid)
        seen.append(oid)
    missing = [x for x in required if x not in seen]
    if missing:
        return _block("BLOCK_SEMANTIC_OBLIGATION_COVERAGE_MISSING", missing_obligation_ids=missing)
    return {
        "status": PASS, "code": "PASS_SEMANTIC_OBLIGATION_COVERAGE_COMPLETE",
        "semantic_delta": dict(delta), "covered_obligation_ids": seen, "coverage_count": len(seen),
    }


def validate_materialization_readback(readback: Any, manifest: Mapping[str, Any]) -> dict:
    required_fields = {
        "readback_contract", "artifact_sha256", "producer_is_materializer", "readback_source",
        "observed_component_ids", "observed_relation_ids", "observed_quality_obligation_ids",
    }
    if not isinstance(readback, Mapping) or set(readback) != required_fields:
        return _block("BLOCK_MATERIALIZATION_PRESERVATION_READBACK_SHAPE")
    if readback.get("readback_contract") != "S30_MATERIALIZATION_PRESERVATION_READBACK_V1" or not _sha(readback.get("artifact_sha256")):
        return _block("BLOCK_MATERIALIZATION_PRESERVATION_READBACK_BINDING")
    if readback.get("producer_is_materializer") is not False or not _text(readback.get("readback_source")):
        return _block("BLOCK_MATERIALIZATION_SELF_ATTESTATION_FORBIDDEN")
    required_components = [o["component_id"] for o in manifest["obligations"] if o["kind"] == "COMPONENT_PRESERVATION"]
    required_relations = [o["relation_id"] for o in manifest["obligations"] if o["kind"] == "RELATION_PRESERVATION"]
    deterministic_quality = [o["obligation_id"] for o in manifest["obligations"] if o["kind"] == "PROFILE_QUALITY" and o["check_mode"] == "DETERMINISTIC_READBACK"]
    observed_components = readback.get("observed_component_ids")
    observed_relations = readback.get("observed_relation_ids")
    observed_quality = readback.get("observed_quality_obligation_ids")
    if not all(isinstance(x, list) for x in (observed_components, observed_relations, observed_quality)):
        return _block("BLOCK_MATERIALIZATION_PRESERVATION_READBACK_SHAPE")
    missing_components = [x for x in required_components if x not in observed_components]
    missing_relations = [x for x in required_relations if x not in observed_relations]
    missing_quality = [x for x in deterministic_quality if x not in observed_quality]
    if missing_components or missing_relations or missing_quality:
        return _block(
            "BLOCK_MATERIALIZATION_QUALITY_LOSS",
            missing_components=missing_components,
            missing_relations=missing_relations,
            missing_quality_obligations=missing_quality,
        )
    return {"status": PASS, "code": "PASS_MATERIALIZATION_QUALITY_PRESERVED"}


def validate_final_semantic_evaluation(receipt: Any, manifest: Mapping[str, Any], *, artifact_sha256: str) -> dict:
    required_ids = list(manifest.get("final_semantic_evaluation_obligation_ids") or [])
    if not required_ids:
        return {"status": PASS, "code": "PASS_FINAL_SEMANTIC_EVALUATION_NOT_REQUIRED", "evaluated": 0}
    if not isinstance(receipt, Mapping) or set(receipt) != {
        "contract_version", "artifact_sha256", "manifest_sha256", "evaluator_role",
        "producer_is_materializer", "results",
    }:
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_RECEIPT_SHAPE")
    if receipt.get("contract_version") != FINAL_EVAL_CONTRACT:
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_CONTRACT")
    if receipt.get("artifact_sha256") != artifact_sha256 or not _sha(artifact_sha256):
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_ARTIFACT_BINDING")
    if receipt.get("manifest_sha256") != manifest.get("manifest_sha256"):
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_MANIFEST_BINDING")
    if receipt.get("evaluator_role") != "INDEPENDENT_EVALUATION_ONLY" or receipt.get("producer_is_materializer") is not False:
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATOR_INDEPENDENCE")
    results = receipt.get("results")
    if not isinstance(results, list):
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_RESULTS")
    seen = set()
    for item in results:
        if not isinstance(item, Mapping) or set(item) != {"obligation_id", "verdict", "evidence_ref"}:
            return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_RESULT_SHAPE")
        oid = item.get("obligation_id")
        if oid not in required_ids or oid in seen:
            return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_COVERAGE")
        if item.get("verdict") not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"} or not _text(item.get("evidence_ref")):
            return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_RESULT_FIELDS")
        if item.get("verdict") != "COMPLIES":
            return _block("BLOCK_FINAL_SEMANTIC_QUALITY_NOT_COMPLIANT", obligation_id=oid, verdict=item.get("verdict"))
        seen.add(oid)
    missing = [x for x in required_ids if x not in seen]
    if missing:
        return _block("BLOCK_FINAL_SEMANTIC_EVALUATION_COVERAGE", missing_obligation_ids=missing)
    return {"status": PASS, "code": "PASS_FINAL_SEMANTIC_QUALITY_COMPLETE", "evaluated": len(seen)}


def compare_cross_route_invariants(direct_manifest: Mapping[str, Any], router_manifest: Mapping[str, Any]) -> dict:
    a = direct_manifest.get("semantic_invariant_sha256")
    b = router_manifest.get("semantic_invariant_sha256")
    if not _text(a) or not _text(b) or a != b:
        return _block("BLOCK_CROSS_ROUTE_SEMANTIC_INVARIANT_MISMATCH", direct=a, router=b)
    return {"status": PASS, "code": "PASS_CROSS_ROUTE_SEMANTIC_INVARIANT"}
