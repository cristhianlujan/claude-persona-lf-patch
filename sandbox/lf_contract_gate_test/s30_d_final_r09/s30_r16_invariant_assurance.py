from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"
DELTA_V3 = "S30_SEMANTIC_DELTA_V3"
SUBSTANCE_EVAL_V1 = "S30_SEMANTIC_EVIDENCE_SUBSTANCE_EVALUATION_V1"
READBACK_V2 = "S30_MATERIALIZATION_PRESERVATION_READBACK_V2"
CATALOG_V1 = "S30_INVARIANT_ASSURANCE_CATALOG_V1"

ATOM_FIELDS = ("decisions", "proposals", "rationale")
ALLOWED_VERDICTS = {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}
ALLOWED_GATE_TYPES = {"CONTRACT_INVARIANT", "SIGNAL_ONLY"}
ALLOWED_VALIDATORS = {
    "NO_FINDING_QUOTA",
    "SEMANTIC_ATOM_ALLOWLIST",
    "SEMANTIC_EVIDENCE_BINDING",
    "INDEPENDENT_SEMANTIC_SUBSTANCE",
    "HANDOFF_RECURSIVE_ALLOWLIST",
    "MATERIALIZATION_RELATION_BINDING",
    "READBACK_INDEPENDENCE",
    "GENERATOR_FIRST_REMEDIATION",
    "DUPLICATE_EVIDENCE_SIGNAL",
}
FORBIDDEN_QUOTA_KEYS = {
    "minimum_findings",
    "target_findings",
    "required_finding_count",
    "finding_quota",
    "find_n_more",
}


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _find_forbidden_quota_key(value: Any) -> str | None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if str(key) in FORBIDDEN_QUOTA_KEYS:
                return str(key)
            hit = _find_forbidden_quota_key(child)
            if hit:
                return hit
    elif isinstance(value, list):
        for child in value:
            hit = _find_forbidden_quota_key(child)
            if hit:
                return hit
    return None


def validate_invariant_catalog(catalog: Any) -> dict:
    if not isinstance(catalog, Mapping) or set(catalog) != {"contract_version", "principles", "invariants"}:
        return _block("BLOCK_R16_INVARIANT_CATALOG_SHAPE")
    if catalog.get("contract_version") != CATALOG_V1:
        return _block("BLOCK_R16_INVARIANT_CATALOG_VERSION")
    quota_key = _find_forbidden_quota_key(catalog)
    if quota_key:
        return _block("BLOCK_R16_FINDING_QUOTA_FORBIDDEN", field=quota_key)
    principles = catalog.get("principles")
    required_principles = {
        "NO_FINDING_QUOTAS",
        "NO_UNVALIDATED_INVARIANTS",
        "NO_HEURISTIC_AS_GATE",
        "FIX_GENERATOR_BEFORE_GENERATED_ARTIFACT_FOR_SYSTEMATIC_DEFECTS",
    }
    if not isinstance(principles, list) or not required_principles.issubset(set(principles)):
        return _block("BLOCK_R16_PRINCIPLES_INCOMPLETE")
    invariants = catalog.get("invariants")
    if not isinstance(invariants, list) or not invariants:
        return _block("BLOCK_R16_INVARIANTS_MISSING")
    seen: set[str] = set()
    blocking = 0
    signals = 0
    for item in invariants:
        required = {"invariant_id", "class", "gate_type", "blocking", "source_ref", "validator_id", "verification"}
        if not isinstance(item, Mapping) or set(item) != required:
            return _block("BLOCK_R16_INVARIANT_SHAPE")
        iid = item.get("invariant_id")
        if not _text(iid) or iid in seen:
            return _block("BLOCK_R16_INVARIANT_ID")
        seen.add(iid)
        gate_type = item.get("gate_type")
        if gate_type not in ALLOWED_GATE_TYPES or not isinstance(item.get("blocking"), bool):
            return _block("BLOCK_R16_INVARIANT_GATE_TYPE", invariant_id=iid)
        if item.get("validator_id") not in ALLOWED_VALIDATORS:
            return _block("BLOCK_R16_INVARIANT_VALIDATOR_UNKNOWN", invariant_id=iid)
        if gate_type == "CONTRACT_INVARIANT":
            if item.get("blocking") is not True or not _text(item.get("source_ref")):
                return _block("BLOCK_R16_CONTRACT_INVARIANT_NOT_AUTHORIZED", invariant_id=iid)
            blocking += 1
        else:
            if item.get("blocking") is not False:
                return _block("BLOCK_R16_SIGNAL_CANNOT_BLOCK", invariant_id=iid)
            signals += 1
        verification = item.get("verification")
        if not isinstance(verification, Mapping) or set(verification) != {"positive_case", "negative_case", "mutation_case"}:
            return _block("BLOCK_R16_INVARIANT_VERIFICATION_SHAPE", invariant_id=iid)
        if gate_type == "CONTRACT_INVARIANT" and any(verification.get(k) is not True for k in verification):
            return _block("BLOCK_R16_UNVALIDATED_INVARIANT", invariant_id=iid)
    return {
        "status": PASS,
        "code": "PASS_R16_INVARIANT_CATALOG_VALID",
        "invariant_count": len(invariants),
        "blocking_invariant_count": blocking,
        "signal_only_count": signals,
        "finding_quota": None,
    }


def _manifest_obligations(manifest: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    obligations = manifest.get("obligations")
    if not isinstance(obligations, list):
        return {}
    return {
        item["obligation_id"]: item
        for item in obligations
        if isinstance(item, Mapping) and _text(item.get("obligation_id"))
    }


def validate_semantic_delta_v3(model_output: Any, manifest: Mapping[str, Any]) -> dict:
    if not isinstance(model_output, Mapping) or set(model_output) != {"semantic_delta"}:
        return _block("BLOCK_R16_SEMANTIC_DELTA_V3_ROOT")
    delta = model_output.get("semantic_delta")
    required_delta = {"contract_version", *ATOM_FIELDS, "unresolved", "obligation_evidence"}
    if not isinstance(delta, Mapping) or set(delta) != required_delta:
        return _block("BLOCK_R16_SEMANTIC_DELTA_V3_SHAPE")
    if delta.get("contract_version") != DELTA_V3:
        return _block("BLOCK_R16_SEMANTIC_DELTA_V3_VERSION")
    if any(not isinstance(delta.get(field), list) for field in (*ATOM_FIELDS, "unresolved", "obligation_evidence")):
        return _block("BLOCK_R16_SEMANTIC_DELTA_V3_ARRAYS")
    if delta["unresolved"]:
        for item in delta["unresolved"]:
            if not isinstance(item, Mapping) or set(item) != {"obligation_id", "reason"} or not _text(item.get("obligation_id")) or not _text(item.get("reason")):
                return _block("BLOCK_R16_UNRESOLVED_SHAPE")
        return _block("BLOCK_R16_SEMANTIC_UNRESOLVED", unresolved=delta["unresolved"])

    atoms: dict[str, dict[str, str]] = {}
    for field in ATOM_FIELDS:
        for item in delta[field]:
            if not isinstance(item, Mapping) or set(item) != {"atom_id", "text"}:
                return _block("BLOCK_R16_SEMANTIC_ATOM_ALLOWLIST", field=field)
            atom_id = item.get("atom_id")
            text = item.get("text")
            if not _text(atom_id) or not _text(text) or atom_id in atoms:
                return _block("BLOCK_R16_SEMANTIC_ATOM_INVALID", atom_id=atom_id)
            atoms[atom_id] = {"atom_id": atom_id, "text": text}

    required = list(manifest.get("semantic_delta_obligation_ids") or [])
    by_id = _manifest_obligations(manifest)
    if any(oid not in by_id for oid in required):
        return _block("BLOCK_R16_MANIFEST_SEMANTIC_OBLIGATION_INVALID")
    seen: set[str] = set()
    evidence_bindings: list[dict[str, Any]] = []
    for item in delta["obligation_evidence"]:
        required_evidence = {
            "obligation_id",
            "atom_id",
            "atom_sha256",
            "obligation_statement_sha256",
        }
        if not isinstance(item, Mapping) or set(item) != required_evidence:
            return _block("BLOCK_R16_SEMANTIC_EVIDENCE_ALLOWLIST")
        oid = item.get("obligation_id")
        atom_id = item.get("atom_id")
        if oid not in required:
            return _block("BLOCK_R16_SEMANTIC_OBLIGATION_UNKNOWN", obligation_id=oid)
        if oid in seen:
            return _block("BLOCK_R16_SEMANTIC_OBLIGATION_DUPLICATE", obligation_id=oid)
        if atom_id not in atoms:
            return _block("BLOCK_R16_SEMANTIC_EVIDENCE_ATOM_UNKNOWN", obligation_id=oid)
        if item.get("atom_sha256") != canonical_sha256(atoms[atom_id]):
            return _block("BLOCK_R16_SEMANTIC_EVIDENCE_ATOM_HASH", obligation_id=oid)
        statement = by_id[oid].get("statement")
        if item.get("obligation_statement_sha256") != canonical_sha256(statement):
            return _block("BLOCK_R16_SEMANTIC_EVIDENCE_OBLIGATION_HASH", obligation_id=oid)
        seen.add(oid)
        evidence_bindings.append({"obligation_id": oid, "atom_id": atom_id})
    missing = [oid for oid in required if oid not in seen]
    if missing:
        return _block("BLOCK_R16_SEMANTIC_OBLIGATION_COVERAGE_MISSING", missing_obligation_ids=missing)
    return {
        "status": PASS,
        "code": "PASS_R16_SEMANTIC_DELTA_V3_BOUND",
        "semantic_delta": dict(delta),
        "semantic_delta_sha256": canonical_sha256(delta),
        "evidence_bindings": evidence_bindings,
        "semantic_substance_status": "REQUIRES_INDEPENDENT_EVALUATION" if required else "NOT_REQUIRED",
    }


def validate_semantic_evidence_substance_evaluation(
    receipt: Any,
    manifest: Mapping[str, Any],
    *,
    semantic_delta_sha256: str,
) -> dict:
    required_fields = {
        "contract_version",
        "manifest_sha256",
        "semantic_delta_sha256",
        "evaluator_role",
        "producer_is_materializer",
        "results",
    }
    if not isinstance(receipt, Mapping) or set(receipt) != required_fields:
        return _block("BLOCK_R16_SUBSTANCE_EVALUATION_SHAPE")
    if receipt.get("contract_version") != SUBSTANCE_EVAL_V1:
        return _block("BLOCK_R16_SUBSTANCE_EVALUATION_VERSION")
    if receipt.get("manifest_sha256") != manifest.get("manifest_sha256") or receipt.get("semantic_delta_sha256") != semantic_delta_sha256:
        return _block("BLOCK_R16_SUBSTANCE_EVALUATION_BINDING")
    if receipt.get("producer_is_materializer") is not False or receipt.get("evaluator_role") != "INDEPENDENT_EVALUATION_ONLY":
        return _block("BLOCK_R16_SUBSTANCE_EVALUATOR_INDEPENDENCE")
    required = list(manifest.get("semantic_delta_obligation_ids") or [])
    results = receipt.get("results")
    if not isinstance(results, list):
        return _block("BLOCK_R16_SUBSTANCE_RESULTS_SHAPE")
    seen: set[str] = set()
    for item in results:
        if not isinstance(item, Mapping) or set(item) != {"obligation_id", "verdict", "evidence_ref", "reason"}:
            return _block("BLOCK_R16_SUBSTANCE_RESULT_SHAPE")
        oid = item.get("obligation_id")
        if oid not in required or oid in seen:
            return _block("BLOCK_R16_SUBSTANCE_COVERAGE", obligation_id=oid)
        if item.get("verdict") not in ALLOWED_VERDICTS or not _text(item.get("evidence_ref")) or not _text(item.get("reason")):
            return _block("BLOCK_R16_SUBSTANCE_RESULT_FIELDS", obligation_id=oid)
        if item.get("verdict") != "COMPLIES":
            return _block("BLOCK_R16_SEMANTIC_SUBSTANCE_NOT_COMPLIANT", obligation_id=oid, verdict=item.get("verdict"))
        seen.add(oid)
    missing = [oid for oid in required if oid not in seen]
    if missing:
        return _block("BLOCK_R16_SUBSTANCE_COVERAGE", missing_obligation_ids=missing)
    return {"status": PASS, "code": "PASS_R16_SEMANTIC_SUBSTANCE_COMPLETE", "evaluated": len(seen)}


def _project_by_schema(value: Any, schema: Mapping[str, Any], path: str) -> Any:
    stype = schema.get("type")
    if stype == "object":
        if not isinstance(value, Mapping):
            raise ValueError(f"{path}:OBJECT_REQUIRED")
        properties = schema.get("properties")
        required = schema.get("required", [])
        if not isinstance(properties, Mapping) or not isinstance(required, list):
            raise ValueError(f"{path}:SCHEMA_INVALID")
        missing = [key for key in required if key not in value]
        if missing:
            raise ValueError(f"{path}:REQUIRED_MISSING:{','.join(missing)}")
        return {
            key: _project_by_schema(value[key], child_schema, f"{path}.{key}")
            for key, child_schema in properties.items()
            if key in value
        }
    if stype == "array":
        if not isinstance(value, list):
            raise ValueError(f"{path}:ARRAY_REQUIRED")
        item_schema = schema.get("items")
        if not isinstance(item_schema, Mapping):
            raise ValueError(f"{path}:ITEM_SCHEMA_INVALID")
        return [_project_by_schema(item, item_schema, f"{path}[]") for item in value]
    if stype == "string":
        if not isinstance(value, str):
            raise ValueError(f"{path}:STRING_REQUIRED")
        return value
    if stype == "boolean":
        if not isinstance(value, bool):
            raise ValueError(f"{path}:BOOLEAN_REQUIRED")
        return value
    if stype == "integer":
        if not isinstance(value, int) or isinstance(value, bool):
            raise ValueError(f"{path}:INTEGER_REQUIRED")
        return value
    raise ValueError(f"{path}:UNSUPPORTED_SCHEMA_TYPE:{stype}")


def project_handoff_by_allowlist(source: Any, schema: Mapping[str, Any]) -> dict:
    try:
        payload = _project_by_schema(source, schema, "$")
    except ValueError as exc:
        return _block("BLOCK_R16_HANDOFF_ALLOWLIST_PROJECTION", detail=str(exc))
    return {
        "status": PASS,
        "code": "PASS_R16_HANDOFF_ALLOWLIST_PROJECTED",
        "payload": payload,
        "payload_sha256": canonical_sha256(payload),
    }


def _unique_by_id(rows: Any, key: str) -> tuple[dict[str, Mapping[str, Any]], str | None]:
    if not isinstance(rows, list):
        return {}, "NOT_ARRAY"
    out: dict[str, Mapping[str, Any]] = {}
    for item in rows:
        if not isinstance(item, Mapping) or not _text(item.get(key)) or item[key] in out:
            return {}, "INVALID_OR_DUPLICATE"
        out[item[key]] = item
    return out, None


def validate_materialization_readback_v2(readback: Any, manifest: Mapping[str, Any]) -> dict:
    required_fields = {
        "readback_contract",
        "artifact_sha256",
        "producer_is_materializer",
        "readback_source",
        "observed_components",
        "observed_relations",
        "deterministic_quality_evidence",
    }
    if not isinstance(readback, Mapping) or set(readback) != required_fields:
        return _block("BLOCK_R16_READBACK_V2_SHAPE")
    if readback.get("readback_contract") != READBACK_V2 or not _sha(readback.get("artifact_sha256")):
        return _block("BLOCK_R16_READBACK_V2_BINDING")
    if readback.get("producer_is_materializer") is not False or not _text(readback.get("readback_source")):
        return _block("BLOCK_R16_READBACK_SELF_ATTESTATION")
    components, cerr = _unique_by_id(readback.get("observed_components"), "component_id")
    relations, rerr = _unique_by_id(readback.get("observed_relations"), "relation_id")
    qev, qerr = _unique_by_id(readback.get("deterministic_quality_evidence"), "obligation_id")
    if cerr or rerr or qerr:
        return _block("BLOCK_R16_READBACK_V2_ROWS", component_error=cerr, relation_error=rerr, quality_error=qerr)
    for item in components.values():
        if set(item) != {"component_id", "content_sha256"} or not _sha(item.get("content_sha256")):
            return _block("BLOCK_R16_COMPONENT_EVIDENCE_SHAPE", component_id=item.get("component_id"))
    for item in relations.values():
        if set(item) != {"relation_id", "member_ids", "content_sha256"} or not isinstance(item.get("member_ids"), list) or not _sha(item.get("content_sha256")):
            return _block("BLOCK_R16_RELATION_EVIDENCE_SHAPE", relation_id=item.get("relation_id"))
    for item in qev.values():
        if set(item) != {"obligation_id", "evidence_ref", "evidence_sha256"} or not _text(item.get("evidence_ref")) or not _sha(item.get("evidence_sha256")):
            return _block("BLOCK_R16_QUALITY_EVIDENCE_SHAPE", obligation_id=item.get("obligation_id"))

    obligations = list(manifest.get("obligations") or [])
    required_components = [o["component_id"] for o in obligations if isinstance(o, Mapping) and o.get("kind") == "COMPONENT_PRESERVATION"]
    required_relations = {
        o["relation_id"]: list(o.get("member_ids") or [])
        for o in obligations
        if isinstance(o, Mapping) and o.get("kind") == "RELATION_PRESERVATION"
    }
    required_quality = [
        o["obligation_id"]
        for o in obligations
        if isinstance(o, Mapping) and o.get("kind") == "PROFILE_QUALITY" and o.get("check_mode") == "DETERMINISTIC_READBACK"
    ]
    missing_components = [cid for cid in required_components if cid not in components]
    missing_relations = [rid for rid in required_relations if rid not in relations]
    relation_mismatches = [
        rid for rid, members in required_relations.items()
        if rid in relations and relations[rid].get("member_ids") != members
    ]
    missing_quality = [oid for oid in required_quality if oid not in qev]
    if missing_components or missing_relations or relation_mismatches or missing_quality:
        return _block(
            "BLOCK_R16_MATERIALIZATION_SUBSTANCE_LOSS",
            missing_components=missing_components,
            missing_relations=missing_relations,
            relation_mismatches=relation_mismatches,
            missing_quality_obligations=missing_quality,
        )
    return {"status": PASS, "code": "PASS_R16_MATERIALIZATION_READBACK_V2"}


def classify_defect_remediation(defect: Any) -> dict:
    if not isinstance(defect, Mapping) or set(defect) != {"defect_class", "systematic", "producer_ref", "artifact_ref"}:
        return _block("BLOCK_R16_DEFECT_REMEDIATION_SHAPE")
    if not _text(defect.get("defect_class")) or not _text(defect.get("artifact_ref")) or not isinstance(defect.get("systematic"), bool):
        return _block("BLOCK_R16_DEFECT_REMEDIATION_FIELDS")
    if defect["systematic"]:
        if not _text(defect.get("producer_ref")):
            return _block("BLOCK_R16_SYSTEMATIC_DEFECT_PRODUCER_UNRESOLVED")
        return {"status": PASS, "code": "PASS_R16_FIX_PRODUCER_FIRST", "action": "FIX_PRODUCER_FIRST"}
    return {"status": PASS, "code": "PASS_R16_LOCAL_ARTIFACT_FIX_ALLOWED", "action": "ARTIFACT_LOCAL_FIX_ALLOWED"}
