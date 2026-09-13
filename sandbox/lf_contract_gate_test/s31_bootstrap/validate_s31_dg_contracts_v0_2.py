#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft7Validator

PASS = "PASS"
BLOCKED = "BLOCKED"
CARD_MODES = {"EXACT", "COMPATIBLE", "COMPOSED", "GENERIC_SAFE"}
from s31_trusted_resolution_v0_1 import (
    PASS as TRUST_PASS,
    TRUSTED_RESOLVER_ID,
    TrustedRefResolver,
    resolve_json_binding,
    resolve_source,
)
EvidenceResolver = TrustedRefResolver
ROOT = Path(__file__).resolve().parent
D_SCHEMA_PATH = ROOT / "lf_shared_authority_typed_context_v0_2_candidate.schema.json"

FORBIDDEN_AUTHORITY_EFFECTS = {
    "AUTHORIZE_DOWNSTREAM",
    "PROMOTE_GOLDEN",
    "ENABLE_PRODUCTION",
    "ALTER_AUTHORITY",
}
FORBIDDEN_AUTHORITY_FLAGS = {
    "downstream_authorized",
    "golden_authorized",
    "production_authorized",
}
REQUIRED_RUNTIME_OUTPUT_FIELDS = {
    "raw_output",
    "runtime_receipt",
    "transport_diagnostics",
    "resource_usage",
    "failure_code",
}


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def _canonical_digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolve_binding(
    binding: Mapping[str, Any] | None,
    expected_type: str,
    resolver: EvidenceResolver | None,
    producer_id: str,
    label: str,
    *,
    require_current_content: bool = True,
) -> tuple[dict[str, Any], Mapping[str, Any] | None, Mapping[str, Any] | None]:
    resolved, record, provider = resolve_json_binding(
        resolver, binding, expected_type, label, require_current_content=require_current_content
    )
    if resolved.get("status") != TRUST_PASS:
        return _block(resolved.get("code", "BLOCK_TRUSTED_EVIDENCE"), **{k:v for k,v in resolved.items() if k not in {"status","code"}}), None, provider
    # Resolver authority comes from the canonical resolver object, not candidate/record strings.
    if producer_id == TRUSTED_RESOLVER_ID:
        return _block("BLOCK_EVIDENCE_SELF_RESOLVER", binding=label), None, provider
    return {"status": PASS, "code": "PASS_RESOLVED_EVIDENCE", "binding": label}, record, provider

def validate_shared_typed_context(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    producer_id = str(value.get("producer_id") or "")
    current_run_id = value.get("current_run_id")
    card = value.get("card_resolution") or {}
    status = card.get("status")
    mode = card.get("mode")
    if status == "RESOLVED" and mode not in CARD_MODES:
        return _block("BLOCK_D_RESOLVED_CARD_MODE_INVALID", mode=mode)
    if status in {"NO_DIRECT_CARD", "AMBIGUOUS", "BLOCKED"} and mode is not None:
        return _block("BLOCK_D_NONRESOLVED_CARD_HAS_MODE", status=status, mode=mode)
    if card.get("schema_invention_allowed") is not False:
        return _block("BLOCK_D_SCHEMA_INVENTION_ALLOWED")

    authorities = value.get("authority_resolution") or []
    for index, authority in enumerate(authorities):
        if not isinstance(authority, Mapping):
            return _block("BLOCK_D_AUTHORITY_SHAPE", index=index)
        run_id = authority.get("run_id")
        if run_id != current_run_id and authority.get("cross_run_declared") is not True:
            return _block("BLOCK_D_UNDECLARED_CROSS_RUN_AUTHORITY", index=index, run_id=run_id)
        refs = list(authority.get("source_refs") or [])
        if len(refs) != 1:
            return _block("BLOCK_D_SOURCE_DIGEST_MODEL_AMBIGUOUS", index=index)
        src_status, src = resolve_source(resolver, refs[0], authority.get("source_sha256"), f"authority_resolution[{index}].source", require_current_content=True)
        if src_status.get("status") != TRUST_PASS:
            return _block(src_status.get("code"), **{k:v for k,v in src_status.items() if k not in {"status","code"}})
        resolved, receipt, provider = _resolve_binding(authority.get("currentness_evidence"), "SOURCE_CURRENTNESS_RECEIPT", resolver, producer_id, f"authority_resolution[{index}].currentness_evidence")
        if resolved.get("status") != PASS:
            return resolved
        if receipt.get("run_id") != current_run_id:
            return _block("BLOCK_D_AUTHORITY_CURRENTNESS_MISMATCH", index=index, mismatches={"run_id":{"expected":current_run_id,"observed":receipt.get("run_id")}})

    runtime_schema = value.get("runtime_schema") or {}
    if runtime_schema.get("schema_invention_allowed") is not False:
        return _block("BLOCK_D_RUNTIME_SCHEMA_INVENTION_ALLOWED")
    src_status, src = resolve_source(resolver, runtime_schema.get("source_ref"), runtime_schema.get("sha256"), "runtime_schema.source", require_current_content=True)
    if src_status.get("status") != TRUST_PASS:
        return _block(src_status.get("code"), **{k:v for k,v in src_status.items() if k not in {"status","code"}})
    resolved, receipt, provider = _resolve_binding(runtime_schema.get("currentness_evidence"), "SOURCE_CURRENTNESS_RECEIPT", resolver, producer_id, "runtime_schema.currentness_evidence")
    if resolved.get("status") != PASS:
        return resolved
    if receipt.get("run_id") != current_run_id:
        return _block("BLOCK_D_RUNTIME_SCHEMA_CURRENTNESS_MISMATCH", mismatches={"run_id":{"expected":current_run_id,"observed":receipt.get("run_id")}})
    if value.get("provenance_reconstructible") is not True:
        return _block("BLOCK_D_PROVENANCE_NOT_RECONSTRUCTIBLE")
    return {"status": PASS, "code": "PASS_D_SHARED_TYPED_CONTEXT"}

def validate_registry_inventory_schema(inventory: Mapping[str, Any], schema: Mapping[str, Any]) -> dict[str, Any]:
    declared = inventory.get("required_capability_manifest_fields") or []
    target = schema.get("required") or []
    if len(declared) != len(set(declared)):
        return _block("BLOCK_E_INVENTORY_DUPLICATE_REQUIRED_FIELD")
    if set(declared) != set(target):
        return _block(
            "BLOCK_E_SOURCE_MODEL_REQUIRED_FIELDS_MISMATCH",
            inventory_only=sorted(set(declared) - set(target)),
            schema_only=sorted(set(target) - set(declared)),
        )
    if "lifecycle_state" in declared or "lifecycle" not in declared:
        return _block("BLOCK_E_LIFECYCLE_FIELD_CONTRACT_MISMATCH")
    return {"status": PASS, "code": "PASS_E_SOURCE_MODEL_CONSISTENT"}


def validate_capability_manifest(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    lifecycle = value.get("lifecycle") or {}
    if lifecycle.get("self_certification_allowed") is not False:
        return _block("BLOCK_E_SELF_CERTIFICATION")
    if lifecycle.get("canonical_vocabulary_status") != "UNRESOLVED":
        return _block("BLOCK_E_LIFECYCLE_VOCABULARY_OVERCLAIM")
    currentness = value.get("currentness_binding") or {}
    if currentness.get("stale_action") != "FAIL_CLOSED":
        return _block("BLOCK_E_STALE_NOT_FAIL_CLOSED")
    refs = list(value.get("source_refs") or [])
    digests = list(value.get("source_digests") or [])
    if len(refs) != len(digests):
        return _block("BLOCK_E_SOURCE_BINDING_CARDINALITY", refs=len(refs), digests=len(digests))
    dependencies = value.get("dependencies") or []
    dep_ids = [d.get("capability_id") for d in dependencies if isinstance(d, Mapping)]
    if len(dep_ids) != len(set(dep_ids)):
        return _block("BLOCK_E_DUPLICATE_DEPENDENCY")
    for index,(ref,digest) in enumerate(zip(refs,digests)):
        status, observed = resolve_source(resolver, ref, digest, f"source_refs[{index}]", require_current_content=True)
        if status.get("status") != TRUST_PASS:
            return _block(status.get("code"), **{k:v for k,v in status.items() if k not in {"status","code"}})
    binding = {"ref": currentness.get("evidence_ref"), "sha256": currentness.get("evidence_sha256"), "resolver_id": currentness.get("resolver_id")}
    resolved, receipt, provider = _resolve_binding(binding, "CAPABILITY_CURRENTNESS_RECEIPT", resolver, str(value.get("owner") or ""), "currentness_binding")
    if resolved.get("status") != PASS:
        return resolved
    return {"status": PASS, "code": "PASS_E_CAPABILITY_MANIFEST"}

def validate_evidence_envelope(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    level = value.get("evidence_level")
    ceiling = value.get("claim_ceiling")
    order = {"STRUCTURAL": 0, "PROVENANCE_EXECUTION": 1, "SEMANTIC": 2, "BEHAVIORAL": 3}
    if level not in order or ceiling not in order:
        return _block("BLOCK_F_EVIDENCE_LEVEL_UNKNOWN")
    if order[ceiling] > order[level]:
        return _block("BLOCK_F_CLAIM_EXCEEDS_EVIDENCE", level=level, ceiling=ceiling)
    owner = value.get("owner_receipt") or {}
    if owner.get("preserved_without_rewrite") is not True:
        return _block("BLOCK_F_OWNER_RECEIPT_NOT_PRESERVED")
    producer_id = str(value.get("producer_id") or "")
    resolved, owner_record, owner_provider = _resolve_binding(owner, "OWNER_RECEIPT", resolver, producer_id, "owner_receipt", require_current_content=True)
    if resolved.get("status") != PASS:
        return resolved
    owner_expected = {"owner_capability_id": owner.get("owner_capability_id"), "run_id": value.get("run_id")}
    mismatches = {k:{"expected":v,"observed":owner_record.get(k)} for k,v in owner_expected.items() if owner_record.get(k)!=v}
    if mismatches:
        return _block("BLOCK_F_OWNER_RECEIPT_MISMATCH", mismatches=mismatches)

    input_obj=value.get("input") or {}; output_obj=value.get("output") or {}
    if _canonical_digest(input_obj.get("exact")) != input_obj.get("digest"):
        return _block("BLOCK_F_INPUT_DIGEST_MISMATCH")
    if _canonical_digest(output_obj.get("exact")) != output_obj.get("digest"):
        return _block("BLOCK_F_OUTPUT_DIGEST_MISMATCH")
    input_refs=list(input_obj.get("source_refs") or []); input_digests=list(input_obj.get("source_digests") or [])
    if len(input_refs)!=len(input_digests):
        return _block("BLOCK_F_INPUT_SOURCE_BINDING_CARDINALITY")
    for index,(ref,digest) in enumerate(zip(input_refs,input_digests)):
        status, observed=resolve_source(resolver,ref,digest,f"input.source_refs[{index}]",require_current_content=True)
        if status.get("status") != TRUST_PASS:
            return _block(status.get("code"), **{k:v for k,v in status.items() if k not in {"status","code"}})
    if level == "STRUCTURAL":
        return {"status": PASS, "code": "PASS_F_STRUCTURAL_EVIDENCE_ENVELOPE"}

    execution = value.get("execution_identity") or {}; authority = value.get("authority") or {}; provenance = value.get("provenance") or {}
    if execution.get("executed") is not True:
        return _block("BLOCK_F_NONSTRUCTURAL_NOT_EXECUTED")
    if authority.get("currentness") != "CURRENT":
        return _block("BLOCK_F_NONSTRUCTURAL_AUTHORITY_NOT_CURRENT")
    if provenance.get("reconstructible") is not True:
        return _block("BLOCK_F_NONSTRUCTURAL_PROVENANCE_NOT_RECONSTRUCTIBLE")
    auth_status, auth_source = resolve_source(resolver, authority.get("source_ref"), authority.get("source_digest"), "authority.source_ref", require_current_content=True)
    if auth_status.get("status") != TRUST_PASS:
        return _block(auth_status.get("code"), **{k:v for k,v in auth_status.items() if k not in {"status","code"}})
    if auth_source.get("revision") != authority.get("source_revision"):
        return _block("BLOCK_F_AUTHORITY_SOURCE_REVISION_MISMATCH", expected=authority.get("source_revision"), observed=auth_source.get("revision"))
    prov_refs=list(provenance.get("refs") or []); prov_digests=list(provenance.get("digests") or [])
    if len(prov_refs)!=len(prov_digests):
        return _block("BLOCK_F_PROVENANCE_BINDING_CARDINALITY")
    for index,(ref,digest) in enumerate(zip(prov_refs,prov_digests)):
        status, observed=resolve_source(resolver,ref,digest,f"provenance.refs[{index}]",require_current_content=True)
        if status.get("status") != TRUST_PASS:
            return _block(status.get("code"), **{k:v for k,v in status.items() if k not in {"status","code"}})

    bindings = value.get("resolved_evidence") or {}; receipts={}; providers={}
    for key,expected_type in [("execution_receipt","EXECUTION_RECEIPT"),("authority_currentness_receipt","AUTHORITY_CURRENTNESS_RECEIPT"),("provenance_receipt","PROVENANCE_RECEIPT")]:
        resolved, receipt, provider = _resolve_binding(bindings.get(key), expected_type, resolver, producer_id, key, require_current_content=True)
        if resolved.get("status") != PASS:
            return resolved
        receipts[key]=receipt; providers[key]=provider
    exec_expected={"run_id":value.get("run_id"),"capability_or_gate_id":value.get("capability_or_gate_id"),"executed":True,"execution_id":execution.get("execution_id"),"input_digest":input_obj.get("digest"),"output_digest":output_obj.get("digest")}
    mismatches={k:{"expected":v,"observed":receipts["execution_receipt"].get(k)} for k,v in exec_expected.items() if receipts["execution_receipt"].get(k)!=v}
    if mismatches:
        return _block("BLOCK_F_EXECUTION_RECEIPT_MISMATCH",mismatches=mismatches)
    if providers["execution_receipt"].get("revision") != execution.get("executed_sha"):
        return _block("BLOCK_F_EXECUTION_RECEIPT_REVISION_MISMATCH")
    auth_expected={"run_id":value.get("run_id"),"capability_or_gate_id":value.get("capability_or_gate_id"),"authority_source":authority.get("source"),"authority_source_digest":authority.get("source_digest"),"currentness":"CURRENT"}
    mismatches={k:{"expected":v,"observed":receipts["authority_currentness_receipt"].get(k)} for k,v in auth_expected.items() if receipts["authority_currentness_receipt"].get(k)!=v}
    if mismatches:
        return _block("BLOCK_F_AUTHORITY_CURRENTNESS_RECEIPT_MISMATCH",mismatches=mismatches)
    prov_expected={"run_id":value.get("run_id"),"capability_or_gate_id":value.get("capability_or_gate_id"),"execution_id":execution.get("execution_id"),"reconstructible":True,"provenance_digests":prov_digests}
    mismatches={k:{"expected":v,"observed":receipts["provenance_receipt"].get(k)} for k,v in prov_expected.items() if receipts["provenance_receipt"].get(k)!=v}
    if mismatches:
        return _block("BLOCK_F_PROVENANCE_RECEIPT_MISMATCH",mismatches=mismatches)
    return {"status": PASS, "code": "PASS_F_EVIDENCE_ENVELOPE_RESOLVED"}

def validate_runtime_port_request(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    runtime_policy = value.get("runtime_policy") or {}
    if runtime_policy.get("silent_fallback_allowed") is not False:
        return _block("BLOCK_G_SILENT_FALLBACK_ALLOWED")
    forbidden = value.get("authority_decisions_forbidden") or []
    expected = {"AUTHORITY", "CURRENTNESS", "CARD_APPLICABILITY", "PROMOTION", "GOLDEN", "PRODUCTION"}
    if set(forbidden) != expected:
        return _block("BLOCK_G_AUTHORITY_FORBIDDEN_SET_INCOMPLETE", observed=sorted(set(forbidden)))
    if value.get("typed_context_resolver_id") != TRUSTED_RESOLVER_ID:
        return _block("BLOCK_G_UNTRUSTED_TYPED_CONTEXT_RESOLVER")
    status, observed = resolve_source(resolver, value.get("typed_context_ref"), value.get("typed_context_sha256"), "typed_context_ref", require_current_content=True)
    if status.get("status") != TRUST_PASS:
        return _block(status.get("code"), **{k:v for k,v in status.items() if k not in {"status","code"}})
    try:
        context=json.loads(observed["raw"].decode("utf-8"))
    except Exception:
        return _block("BLOCK_G_TYPED_CONTEXT_NOT_JSON")
    schema=json.loads(D_SCHEMA_PATH.read_text(encoding="utf-8"))
    errors=sorted(Draft7Validator(schema).iter_errors(context),key=lambda e:list(e.path))
    if errors:
        return _block("BLOCK_G_TYPED_CONTEXT_SCHEMA_INVALID", errors=[{"path":"/".join(map(str,e.path)),"message":e.message} for e in errors[:12]])
    if context.get("current_run_id") != value.get("request_id"):
        return _block("BLOCK_G_TYPED_CONTEXT_REQUEST_ID_MISMATCH")
    ctx_input=((context.get("input") or {}).get("input_fields"))
    if ctx_input != value.get("governed_input"):
        return _block("BLOCK_G_TYPED_CONTEXT_GOVERNED_INPUT_MISMATCH")
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_REQUEST"}

def _scan_runtime_receipt(node: Any, path: str = "runtime_receipt") -> dict[str, Any] | None:
    if isinstance(node, Mapping):
        for key, val in node.items():
            current_path = f"{path}.{key}"
            if key in FORBIDDEN_AUTHORITY_FLAGS and val is True:
                return _block("BLOCK_G_NESTED_AUTHORITY_FLAG", path=current_path)
            if key == "authority_grants_allowed" and val is not False:
                return _block("BLOCK_G_NESTED_AUTHORITY_GRANT_ALLOWED", path=current_path)
            if key == "authority_effects":
                if not isinstance(val, list):
                    return _block("BLOCK_G_NESTED_AUTHORITY_EFFECT_SHAPE", path=current_path)
                forbidden = sorted(set(val) & FORBIDDEN_AUTHORITY_EFFECTS)
                if forbidden:
                    return _block("BLOCK_G_NESTED_AUTHORITY_EFFECT", path=current_path, effects=forbidden)
                if val:
                    return _block("BLOCK_G_UNDECLARED_AUTHORITY_EFFECT", path=current_path)
            nested = _scan_runtime_receipt(val, current_path)
            if nested:
                return nested
    elif isinstance(node, list):
        for index, val in enumerate(node):
            nested = _scan_runtime_receipt(val, f"{path}[{index}]")
            if nested:
                return nested
    return None


def validate_runtime_port_output(value: Mapping[str, Any]) -> dict[str, Any]:
    missing = sorted(REQUIRED_RUNTIME_OUTPUT_FIELDS - set(value))
    if missing:
        return _block("BLOCK_G_RUNTIME_OUTPUT_FIELDS_MISSING", missing=missing)
    receipt = value.get("runtime_receipt")
    if not isinstance(receipt, Mapping):
        return _block("BLOCK_G_RUNTIME_RECEIPT_SHAPE")
    nested = _scan_runtime_receipt(receipt)
    if nested:
        return nested
    if receipt.get("authority_grants_allowed") is not False:
        return _block("BLOCK_G_RUNTIME_RECEIPT_AUTHORITY_BOUNDARY_MISSING")
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_OUTPUT"}
