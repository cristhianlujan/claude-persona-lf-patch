#!/usr/bin/env python3
"""Deterministic ASSET_COMPOSITION_V1 validator/projector.

This module does not write Supabase or GitHub. It validates a normalized composition
payload against a supplied inventory snapshot and emits the derived component/dependency
projection that LF_GLOBAL_TECHNICAL_INVENTORY_V1 may materialize.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "ASSET_COMPOSITION_V1"
CODE_RE = re.compile(r"^[A-Z0-9][A-Z0-9_-]{1,127}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
AUTHORITY_CLASSES = {"CANONICAL_ARTIFACT", "CANONICAL_REGISTRY", "CANONICAL_METADATA"}
SCOPE_MODES = {"COMPLETE_ASSET", "COMPONENT_SET"}
MEMBERSHIP_CLASSES = {"CANONICAL_ARTIFACT", "PHYSICAL_OBJECT", "CANDIDATE_OBJECT", "SUPPORTING_OBJECT"}


class CompositionError(ValueError):
    pass


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise CompositionError(code)


def _object_refs(inventory_snapshot: Any) -> set[str]:
    if isinstance(inventory_snapshot, dict):
        rows = inventory_snapshot.get("objects", [])
    else:
        rows = inventory_snapshot
    _require(isinstance(rows, list), "INVENTORY_OBJECTS_NOT_LIST")
    refs: set[str] = set()
    for row in rows:
        if isinstance(row, str):
            refs.add(row)
        elif isinstance(row, dict) and isinstance(row.get("object_ref"), str):
            if row.get("active", True):
                refs.add(row["object_ref"])
        else:
            raise CompositionError("INVENTORY_OBJECT_INVALID")
    return refs


def validate_and_project(payload: dict[str, Any], inventory_snapshot: Any) -> dict[str, Any]:
    refs = _object_refs(inventory_snapshot)
    _require(isinstance(payload, dict), "PAYLOAD_NOT_OBJECT")
    _require(payload.get("schema_version") == SCHEMA_VERSION, "SCHEMA_VERSION_MISMATCH")

    allowed_root = {"schema_version", "asset_ref", "authority", "scope", "components"}
    _require(set(payload) == allowed_root, "ROOT_KEYS_MISMATCH")

    asset_ref = payload.get("asset_ref")
    _require(isinstance(asset_ref, str) and asset_ref.startswith("asset://"), "ASSET_REF_INVALID")
    _require(asset_ref in refs, "ASSET_REF_NOT_IN_INVENTORY")
    asset_code = asset_ref.removeprefix("asset://")

    authority = payload.get("authority")
    _require(isinstance(authority, dict), "AUTHORITY_INVALID")
    _require(set(authority) == {"source_ref", "source_sha256", "source_version", "authority_class"}, "AUTHORITY_KEYS_MISMATCH")
    _require(isinstance(authority.get("source_ref"), str) and len(authority["source_ref"]) >= 5, "AUTHORITY_SOURCE_REF_INVALID")
    _require(isinstance(authority.get("source_version"), str) and authority["source_version"], "AUTHORITY_SOURCE_VERSION_INVALID")
    _require(authority.get("authority_class") in AUTHORITY_CLASSES, "AUTHORITY_CLASS_INVALID")
    _require(isinstance(authority.get("source_sha256"), str) and SHA_RE.fullmatch(authority["source_sha256"]) is not None, "AUTHORITY_SHA256_INVALID")
    _require(authority["source_ref"] in refs, "AUTHORITY_SOURCE_REF_NOT_IN_INVENTORY")

    scope = payload.get("scope")
    _require(isinstance(scope, dict), "SCOPE_INVALID")
    _require(set(scope) == {"mode", "component_codes"}, "SCOPE_KEYS_MISMATCH")
    _require(scope.get("mode") in SCOPE_MODES, "SCOPE_MODE_INVALID")
    scope_codes = scope.get("component_codes")
    _require(isinstance(scope_codes, list), "SCOPE_COMPONENT_CODES_NOT_LIST")
    _require(all(isinstance(code, str) and CODE_RE.fullmatch(code) for code in scope_codes), "SCOPE_COMPONENT_CODE_INVALID")
    _require(len(scope_codes) == len(set(scope_codes)), "SCOPE_COMPONENT_CODE_DUPLICATE")

    components = payload.get("components")
    _require(isinstance(components, list), "COMPONENTS_NOT_LIST")
    codes = [c.get("component_code") for c in components if isinstance(c, dict)]
    _require(len(codes) == len(components), "COMPONENT_INVALID")
    _require(len(codes) == len(set(codes)), "COMPONENT_CODE_DUPLICATE")
    _require(all(isinstance(code, str) and CODE_RE.fullmatch(code) for code in codes), "COMPONENT_CODE_INVALID")

    if scope["mode"] == "COMPONENT_SET":
        _require(scope_codes, "COMPONENT_SET_EMPTY")
        _require(set(scope_codes) == set(codes), "COMPONENT_SET_SCOPE_MISMATCH")
    else:
        _require(scope_codes == [], "COMPLETE_ASSET_SCOPE_CODES_MUST_BE_EMPTY")

    out_objects: list[dict[str, Any]] = []
    out_edges: list[dict[str, Any]] = []
    for component in components:
        _require(set(component) == {"component_code", "component_type", "order", "status", "members"}, "COMPONENT_KEYS_MISMATCH")
        code = component["component_code"]
        _require(isinstance(component.get("component_type"), str) and CODE_RE.fullmatch(component["component_type"]) is not None, "COMPONENT_TYPE_INVALID")
        _require(isinstance(component.get("order"), int) and component["order"] >= 0, "COMPONENT_ORDER_INVALID")
        _require(isinstance(component.get("status"), str) and component["status"], "COMPONENT_STATUS_INVALID")
        members = component.get("members")
        _require(isinstance(members, list), "COMPONENT_MEMBERS_NOT_LIST")

        component_ref = f"component://{asset_code}/{code}"
        out_objects.append({
            "object_ref": component_ref,
            "object_type": "COMPONENT",
            "parent_ref": asset_ref,
            "source_system": "ASSET_COMPOSITION_PROJECTION",
            "source_of_truth": False,
            "status": component["status"],
            "metadata": {
                "component_code": code,
                "component_type": component["component_type"],
                "order": component["order"],
                "authority_source_ref": authority["source_ref"],
                "authority_source_sha256": authority["source_sha256"],
                "authority_source_version": authority["source_version"],
                "projection_scope_mode": scope["mode"],
            },
        })
        out_edges.append({
            "source_ref": asset_ref,
            "target_ref": component_ref,
            "relation_type": "HAS_COMPONENT",
            "evidence_type": SCHEMA_VERSION,
        })

        seen_member_refs: set[str] = set()
        for member in members:
            _require(isinstance(member, dict), "MEMBER_INVALID")
            _require(set(member) == {"member_ref", "role", "membership_class", "required"}, "MEMBER_KEYS_MISMATCH")
            member_ref = member.get("member_ref")
            _require(isinstance(member_ref, str) and len(member_ref) >= 5, "MEMBER_REF_INVALID")
            _require(member_ref not in seen_member_refs, "MEMBER_REF_DUPLICATE")
            seen_member_refs.add(member_ref)
            _require(member_ref in refs, "MEMBER_REF_NOT_IN_INVENTORY")
            _require(isinstance(member.get("role"), str) and CODE_RE.fullmatch(member["role"]) is not None, "MEMBER_ROLE_INVALID")
            klass = member.get("membership_class")
            _require(klass in MEMBERSHIP_CLASSES, "MEMBERSHIP_CLASS_INVALID")
            _require(isinstance(member.get("required"), bool), "MEMBER_REQUIRED_INVALID")
            if klass == "CANONICAL_ARTIFACT":
                _require(member_ref.startswith("artifact://"), "CANONICAL_ARTIFACT_REF_INVALID")
            if klass == "CANDIDATE_OBJECT":
                _require(not member_ref.startswith("artifact://"), "CANDIDATE_OBJECT_MUST_NOT_USE_CANONICAL_ARTIFACT_REF")
            out_edges.append({
                "source_ref": component_ref,
                "target_ref": member_ref,
                "relation_type": "COMPOSED_OF",
                "evidence_type": SCHEMA_VERSION,
                "metadata": {
                    "role": member["role"],
                    "membership_class": klass,
                    "required": member["required"],
                },
            })

    return {
        "schema_version": SCHEMA_VERSION,
        "asset_ref": asset_ref,
        "authority": authority,
        "scope": scope,
        "objects": sorted(out_objects, key=lambda item: item["object_ref"]),
        "dependencies": sorted(out_edges, key=lambda item: (item["source_ref"], item["relation_type"], item["target_ref"])),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    payload = json.loads(args.payload.read_text(encoding="utf-8"))
    inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
    try:
        result = validate_and_project(payload, inventory)
    except CompositionError as exc:
        print(json.dumps({"valid": False, "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps({"valid": True, "projection": result}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
