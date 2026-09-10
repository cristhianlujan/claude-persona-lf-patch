#!/usr/bin/env python3
"""Bind immutable source-semantic entities to concrete JSON locations in a render-facing artifact.

The source-fidelity contract says WHAT is immutable. This validator proves that each
immutable entity is materially present at a declared artifact pointer; a copied
semantic projection alone cannot manufacture PASS.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path
from typing import Any

SCHEMA = "LF_SEMANTIC_BINDING_CONTRACT_V1"
SOURCE_SCHEMA = "LF_SOURCE_FIDELITY_CONTRACT_V1"
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
COMPARISONS = {"EXACT", "LIST_EXACT", "LIST_CONTAINS", "DICT_SUBSET"}


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _pointer_get(doc: Any, pointer: str) -> Any:
    if pointer == "":
        return doc
    if not isinstance(pointer, str) or not pointer.startswith("/"):
        raise ValueError("POINTER_INVALID")
    cur = doc
    for raw in pointer[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(cur, list):
            if not token.isdigit():
                raise ValueError("POINTER_LIST_INDEX_INVALID")
            idx = int(token)
            if idx < 0 or idx >= len(cur):
                raise ValueError("POINTER_NOT_FOUND")
            cur = cur[idx]
        elif isinstance(cur, dict):
            if token not in cur:
                raise ValueError("POINTER_NOT_FOUND")
            cur = cur[token]
        else:
            raise ValueError("POINTER_TRAVERSES_SCALAR")
    return cur


def _pointer_exists(doc: Any, pointer: str) -> tuple[bool, Any]:
    try:
        return True, _pointer_get(doc, pointer)
    except ValueError as exc:
        if str(exc) == "POINTER_NOT_FOUND":
            return False, None
        raise


def _compare(expected: Any, observed: Any, mode: str) -> bool:
    if mode in {"EXACT", "LIST_EXACT"}:
        return observed == expected
    if mode == "LIST_CONTAINS":
        return isinstance(expected, list) and isinstance(observed, list) and all(item in observed for item in expected)
    if mode == "DICT_SUBSET":
        return isinstance(expected, dict) and isinstance(observed, dict) and all(k in observed and observed[k] == v for k, v in expected.items())
    return False


def validate(source: Any, artifact: Any, binding: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(source, dict) or source.get("schema") != SOURCE_SCHEMA:
        return ["SOURCE_FIDELITY_CONTRACT_INVALID"]
    if not isinstance(artifact, dict):
        return ["ARTIFACT_NOT_OBJECT"]
    if not isinstance(binding, dict) or binding.get("schema") != SCHEMA:
        return ["SEMANTIC_BINDING_CONTRACT_INVALID"]

    claimed_artifact = binding.get("artifact_canonical_sha256")
    actual_artifact = canonical_sha(artifact)
    if claimed_artifact != actual_artifact:
        errors.append("ARTIFACT_CANONICAL_SHA256_MISMATCH")
    if binding.get("source_fidelity_contract_sha256") != source.get("contract_sha256"):
        errors.append("SOURCE_FIDELITY_BINDING_SHA256_MISMATCH")

    entities = source.get("immutable_entities")
    if not isinstance(entities, list) or not entities:
        return sorted(set(errors + ["SOURCE_IMMUTABLE_ENTITIES_INVALID"]))
    source_by_id = {e.get("entity_id"): e for e in entities if isinstance(e, dict) and isinstance(e.get("entity_id"), str)}
    if len(source_by_id) != len(entities):
        errors.append("SOURCE_ENTITY_IDS_INVALID_OR_DUPLICATE")

    bindings = binding.get("bindings")
    if not isinstance(bindings, list) or not bindings:
        return sorted(set(errors + ["BINDINGS_INVALID"]))
    seen: set[str] = set()
    for i, item in enumerate(bindings):
        prefix = f"BINDING_{i}"
        if not isinstance(item, dict):
            errors.append(prefix + "_NOT_OBJECT"); continue
        eid = item.get("entity_id")
        if not isinstance(eid, str) or not eid:
            errors.append(prefix + "_ENTITY_ID_INVALID"); continue
        if eid in seen:
            errors.append("BINDING_ENTITY_ID_DUPLICATE:" + eid)
        seen.add(eid)
        source_entity = source_by_id.get(eid)
        if source_entity is None:
            errors.append("BINDING_ENTITY_INVENTED:" + eid); continue
        sig = source_entity.get("semantic_signature")
        key = item.get("signature_key")
        if not isinstance(sig, dict) or not isinstance(key, str) or key not in sig:
            errors.append("BINDING_SIGNATURE_KEY_INVALID:" + eid); continue
        mode = item.get("comparison")
        if mode not in COMPARISONS:
            errors.append("BINDING_COMPARISON_INVALID:" + eid); continue
        try:
            observed = _pointer_get(artifact, item.get("artifact_pointer"))
        except ValueError as exc:
            errors.append(f"BINDING_POINTER_ERROR:{eid}:{exc}"); continue
        expected = sig[key]
        if not _compare(expected, observed, mode):
            errors.append("SEMANTIC_BINDING_MISMATCH:" + eid)

    missing = sorted(set(source_by_id) - seen)
    for eid in missing:
        errors.append("SEMANTIC_BINDING_MISSING:" + eid)

    dynamic = binding.get("dynamic_bindings", [])
    if not isinstance(dynamic, list):
        errors.append("DYNAMIC_BINDINGS_INVALID")
    else:
        seen_dynamic: set[str] = set()
        for i, item in enumerate(dynamic):
            prefix = f"DYNAMIC_BINDING_{i}"
            if not isinstance(item, dict):
                errors.append(prefix + "_NOT_OBJECT"); continue
            bid = item.get("binding_id")
            if not isinstance(bid, str) or not bid:
                errors.append(prefix + "_ID_INVALID"); continue
            if bid in seen_dynamic:
                errors.append("DYNAMIC_BINDING_ID_DUPLICATE:" + bid)
            seen_dynamic.add(bid)
            expected_binding = item.get("expected_binding")
            if not isinstance(expected_binding, str) or not expected_binding:
                errors.append("DYNAMIC_BINDING_EXPECTED_INVALID:" + bid); continue
            try:
                observed = _pointer_get(artifact, item.get("artifact_pointer"))
            except ValueError as exc:
                errors.append(f"DYNAMIC_BINDING_POINTER_ERROR:{bid}:{exc}"); continue
            if observed != expected_binding:
                errors.append("DYNAMIC_BINDING_MISMATCH:" + bid)

    forbidden = binding.get("forbidden_render_literals", [])
    if not isinstance(forbidden, list):
        errors.append("FORBIDDEN_RENDER_LITERALS_INVALID")
    else:
        seen_forbidden: set[str] = set()
        for i, item in enumerate(forbidden):
            prefix = f"FORBIDDEN_RENDER_LITERAL_{i}"
            if not isinstance(item, dict):
                errors.append(prefix + "_NOT_OBJECT"); continue
            fid = item.get("literal_id")
            if not isinstance(fid, str) or not fid:
                errors.append(prefix + "_ID_INVALID"); continue
            if fid in seen_forbidden:
                errors.append("FORBIDDEN_RENDER_LITERAL_ID_DUPLICATE:" + fid)
            seen_forbidden.add(fid)
            pointer = item.get("artifact_pointer")
            try:
                exists, observed = _pointer_exists(artifact, pointer)
            except ValueError as exc:
                errors.append(f"FORBIDDEN_RENDER_LITERAL_POINTER_ERROR:{fid}:{exc}"); continue
            if exists:
                if item.get("must_be_absent") is True:
                    errors.append("FORBIDDEN_RENDER_POINTER_PRESENT:" + fid)
                elif "forbidden_value" in item and observed == item.get("forbidden_value"):
                    errors.append("FORBIDDEN_RENDER_LITERAL_PRESENT:" + fid)

    claimed = binding.get("binding_sha256")
    if not isinstance(claimed, str) or not SHA_RE.fullmatch(claimed):
        errors.append("BINDING_SHA256_INVALID")
    else:
        expected = canonical_sha({k: v for k, v in binding.items() if k != "binding_sha256"})
        if claimed != expected:
            errors.append("BINDING_SHA256_MISMATCH")
    return sorted(set(errors))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--artifact", required=True, type=Path)
    ap.add_argument("--binding", required=True, type=Path)
    args = ap.parse_args()
    source = json.loads(args.source.read_text(encoding="utf-8"))
    artifact = json.loads(args.artifact.read_text(encoding="utf-8"))
    binding = json.loads(args.binding.read_text(encoding="utf-8"))
    errors = validate(source, artifact, binding)
    print(json.dumps({"valid": not errors, "errors": errors}, ensure_ascii=False, indent=2))
    return 0 if not errors else 1

if __name__ == "__main__":
    raise SystemExit(main())
