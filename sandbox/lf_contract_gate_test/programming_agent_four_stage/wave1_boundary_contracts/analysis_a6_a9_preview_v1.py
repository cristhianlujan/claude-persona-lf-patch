"""Opt-in A6 -> A9 draft preview; no persistence, activation or admission.

Preserves a complete upstream A6 artifact and delegates A7 matrix generation to
the existing assembler. Does not fabricate missing evidence or repair history.
The supplied artifact digest is an identity check, not a source attestation.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import sys

from validate_wave1_boundary_contracts_v1 import (
    ContractError, assemble_scope_front_matrix_v1,
    validate_programming_snapshot_payload_v1,
)

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[3] / "sandbox/lf_contract_gate_test/material_currentness"))
from lf_material_currentness_v1 import canonical_sha256

A6_CONTRACT = json.loads((HERE / "analysis_implementability_contract_v1.json").read_text())
ENTRY_BYTES = (HERE / "programming_entry_contract_v1.json").read_bytes()
ENTRY = json.loads(ENTRY_BYTES)
ENTRY_DIGEST = hashlib.sha256(ENTRY_BYTES).hexdigest()
HEX64 = re.compile(r"[0-9a-f]{64}")


def _text(v):
    return isinstance(v, str) and bool(v.strip())


def _strings(v, nonempty=False):
    return (isinstance(v, list) and (bool(v) or not nonempty)
            and all(_text(x) for x in v) and len(v) == len(set(v)))


def _json_value(value):
    if value is None or type(value) in (str, bool, int):
        return True
    if type(value) is float:
        return value == value and abs(value) != float("inf")
    if isinstance(value, list):
        return all(_json_value(x) for x in value)
    if isinstance(value, dict):
        return all(isinstance(k, str) and _json_value(v) for k, v in value.items())
    return False


def validate_a6_payload_v1(artifact, scope_ids):
    """Contract-derived structural diagnostics, not canonical truth/currentness."""
    issues = []

    def reject(path, code):
        issues.append({"path": path, "code": code})

    if not isinstance(artifact, dict) or not _json_value(artifact):
        return [{"path": "implementability_schema", "code": "A6_JSON_OBJECT_REQUIRED"}]
    if artifact.get("schema_version") != "IMPLEMENTABILITY_SCHEMA_V1":
        reject("schema_version", "A6_SCHEMA_MISMATCH")
    if not _strings(scope_ids, nonempty=True):
        return [{"path": "scope_ids", "code": "A9_SCOPE_IDENTITIES_INVALID"}]
    known = set(scope_ids)
    for field in A6_CONTRACT["output_requirements"]:
        key = field.removesuffix("[]")
        if key not in artifact:
            reject(key, "A6_REQUIRED_FIELD_MISSING")
        elif field.endswith("[]") and not isinstance(artifact[key], list):
            reject(key, "A6_ARRAY_REQUIRED")
    fp = artifact.get("implementability_fingerprint_sha256")
    if not isinstance(fp, str) or not HEX64.fullmatch(fp):
        reject("implementability_fingerprint_sha256", "A6_FINGERPRINT_MISSING_OR_INVALID")
    for key in ("source_refs", "currentness_refs"):
        if key in artifact and not _strings(artifact[key]):
            reject(key, "A6_REFERENCE_LIST_INVALID")
    for collection, contract_key, identity in (
        ("requirements", "requirement_contract", "requirement_id"),
        ("canonical_implementation_bindings", "binding_contract", "binding_id"),
    ):
        rows = artifact.get(collection)
        if not isinstance(rows, list):
            continue
        seen = set()
        fields = A6_CONTRACT[contract_key]["required_fields"]
        for i, row in enumerate(rows):
            path = collection + "[" + str(i) + "]"
            if not isinstance(row, dict):
                reject(path, "A6_ROW_OBJECT_REQUIRED")
                continue
            for field in fields:
                key = field.removesuffix("[]")
                if key not in row:
                    reject(path + "." + key, "A6_REQUIRED_FIELD_MISSING")
                elif field.endswith("[]") and not _strings(row[key]):
                    reject(path + "." + key, "A6_REFERENCE_LIST_INVALID")
            rid = row.get(identity)
            if not _text(rid) or rid in seen:
                reject(path + "." + identity, "A6_IDENTITY_INVALID_OR_DUPLICATE")
            else:
                seen.add(rid)
            refs = row.get("scope_refs")
            if not _strings(refs, nonempty=True) or not set(refs).issubset(known):
                reject(path + ".scope_refs", "A6_UNKNOWN_OR_MISSING_SCOPE")
            if collection == "requirements":
                for key in ("outcome", "obligation_mode", "side_effect_class"):
                    if not _text(row.get(key)):
                        reject(path + "." + key, "A6_VALUE_REQUIRED")
                if row.get("obligation_mode") not in A6_CONTRACT["requirement_contract"]["obligation_modes"]:
                    reject(path + ".obligation_mode", "A6_OBLIGATION_INVALID")
                if row.get("side_effect_class") not in A6_CONTRACT["requirement_contract"]["side_effect_classes"]:
                    reject(path + ".side_effect_class", "A6_SIDE_EFFECT_INVALID")
                if (not row.get("authority_refs") or row.get("side_effect_class") == "UNKNOWN") and not row.get("blockers"):
                    reject(path, "A6_UNKNOWN_MATERIAL_WITHOUT_BLOCKER")
            else:
                for key in ("binding_kind", "canonical_ref", "currentness_ref", "implementation_obligation"):
                    if not _text(row.get(key)):
                        reject(path + "." + key, "A6_VALUE_REQUIRED")
                if row.get("implementation_obligation") not in A6_CONTRACT["requirement_contract"]["obligation_modes"]:
                    reject(path + ".implementation_obligation", "A6_OBLIGATION_INVALID")
                transport = row.get("value_transport")
                if transport not in A6_CONTRACT["binding_contract"]["value_transport_values"]:
                    reject(path + ".value_transport", "A6_TRANSPORT_INVALID")
                if transport == "INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF" and row.get("resolved_current_value") is None:
                    reject(path, "A6_INLINE_VALUE_REQUIRED")
                if transport in ("EXACT_REF_ONLY", "EXACT_REF_PLUS_TYPED_RESOLVER") and not _text(row.get("resolver_ref")):
                    reject(path, "A6_TYPED_RESOLVER_REQUIRED")
                if not row.get("evidence_refs") and not row.get("blockers"):
                    reject(path, "A6_BINDING_EVIDENCE_OR_BLOCKER_REQUIRED")
    forbidden = set(A6_CONTRACT["strategy_boundary"]["forbidden_fields"])

    def walk(v, path):
        if isinstance(v, dict):
            for k, child in v.items():
                if k in forbidden:
                    reject(path + "." + k, "A6_TECHNICAL_STRATEGY_FORBIDDEN")
                walk(child, path + "." + k)
        elif isinstance(v, list):
            for i, child in enumerate(v):
                walk(child, path + "[" + str(i) + "]")
    walk(artifact, "implementability_schema")
    return issues


def assemble_a6_a9_preview_v1(draft, a6_output, expected_a6_sha256):
    """Return a separate unpersisted snapshot candidate; never alter inputs.

    Call only with an A9 draft. Recorded contexts are diagnostic inputs, not
    candidates to rewrite. No status, source currentness or scope is promoted.
    """
    out = {"schema_version": "A6_A9_ASSEMBLY_PREVIEW_V1",
           "status": "RETURN_TO_ANALYSIS", "issues": [], "candidate_snapshot": None,
           "planning_allowed": False, "execution_allowed": False,
           "operational_admission": False, "persistence_allowed": False,
           "pending_gates": ["A9_PRODUCER_AGREEMENT", "SOURCE_AND_AUTHORITY_CURRENTNESS",
                             "INDEPENDENT_REVIEW", "PG01_ADMISSION", "D5_D7_PERSISTENCE"]}

    def fail(path, code):
        out["issues"].append({"path": path, "code": code})
        return out

    if not isinstance(draft, dict) or not _json_value(draft):
        return fail("draft", "A9_DRAFT_JSON_OBJECT_REQUIRED")
    if "context_id" in draft or "context_sha256" in draft or "extensions" in draft:
        return fail("draft", "RECORDED_CONTEXT_REWRITE_FORBIDDEN")
    if draft.get("schema_version") != "PROGRAMMING_CONTEXT_SNAPSHOT_V1":
        return fail("draft.schema_version", "A9_SNAPSHOT_SCHEMA_MISMATCH")
    if draft.get("snapshot_schema_digest_sha256") != ENTRY_DIGEST:
        return fail("draft.snapshot_schema_digest_sha256", "A9_ENTRY_DIGEST_MISMATCH")
    scopes = draft.get("scope_readiness")
    scope_ids = [s.get("scope_id") for s in scopes] if isinstance(scopes, list) and all(isinstance(s, dict) for s in scopes) else []
    out["issues"] = validate_a6_payload_v1(a6_output, scope_ids)
    if out["issues"]:
        return out
    digest = canonical_sha256(a6_output)
    if not isinstance(expected_a6_sha256, str) or not HEX64.fullmatch(expected_a6_sha256) or digest != expected_a6_sha256:
        return fail("a6_output", "A6_EXPECTED_ARTIFACT_DIGEST_MISMATCH")
    previous = draft.get("implementability_schema")
    if previous not in (None, {}) and previous != a6_output:
        return fail("implementability_schema", "A6_EXISTING_ARTIFACT_CONFLICT")
    candidate = deepcopy(draft)
    candidate["implementability_schema"] = deepcopy(a6_output)
    missing = [f.removesuffix("[]") for f in ENTRY["programming_context_snapshot"]["required_fields"]
               if f.removesuffix("[]") not in candidate and f != "scope_front_matrix[]"]
    if missing:
        out["issues"] = [{"path": p, "code": "A9_REQUIRED_FIELD_MISSING"} for p in missing]
        return out
    requirements = a6_output["requirements"]
    root = candidate["requirements"]
    root_ids = [r if isinstance(r, str) else r.get("requirement_id") if isinstance(r, dict) else None for r in root] if isinstance(root, list) else []
    ids = [r["requirement_id"] for r in requirements]
    if not _strings(root_ids, nonempty=True) or set(root_ids) != set(ids):
        return fail("requirements", "A6_A9_REQUIREMENT_IDENTITY_MISMATCH")
    for scope in scopes:
        if scope.get("status") != "READY":
            continue
        sid = scope["scope_id"]
        bound = [r for r in requirements if sid in r["scope_refs"]]
        bindings = [b for b in a6_output["canonical_implementation_bindings"] if sid in b["scope_refs"]]
        if not bound or any(r["blockers"] or not r["authority_refs"] or not r["evidence_refs"] or not r["currentness_refs"] or r["side_effect_class"] == "UNKNOWN" for r in bound) or any(b["blockers"] for b in bindings) or any(not isinstance(item, dict) or not _strings(item.get("scope_refs"), nonempty=True) or not set(item["scope_refs"]).issubset(set(scope_ids)) or sid in item["scope_refs"] for item in a6_output["unresolved_material_items"]):
            return fail("scope_readiness." + sid, "A6_MATERIAL_NOT_CLEARED_FOR_READY_SCOPE")
    try:
        matrix = assemble_scope_front_matrix_v1(candidate)
        if candidate.get("scope_front_matrix") in (None, []):
            candidate["scope_front_matrix"] = matrix
        validate_programming_snapshot_payload_v1(candidate)
    except (ContractError, KeyError, TypeError, ValueError, AttributeError) as exc:
        return fail("scope_front_matrix", "A9_MATRIX_VALIDATION:" + str(exc))
    out.update(status="CANDIDATE_ASSEMBLED", candidate_snapshot=candidate,
               a6_artifact_sha256=digest, ready_scope_ids=[s["scope_id"] for s in scopes if s.get("status") == "READY"],
               source_attestation_verified=False, fingerprint_semantics_verified=False)
    return out
