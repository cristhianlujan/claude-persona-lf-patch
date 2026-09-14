#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from lf_material_currentness_v1 import affected_closure, canonical_sha256, evaluate

HEX64 = re.compile(r"^[0-9a-f]{64}$")
_ALLOWED_CHANGE_CLASSES = {
    "IMPLEMENTATION_ONLY_COMPATIBLE",
    "CONTRACT_COMPATIBLE",
    "BREAKING",
    "UNKNOWN",
}


def compatibility_proof_sha256(*, material_id: str, change_class: str, bound_fingerprint: str, current_fingerprint: str, contract_identity: str, implementation_binding: str) -> str:
    if change_class not in _ALLOWED_CHANGE_CLASSES:
        raise ValueError("COMPATIBILITY_CLASS_INVALID")
    if not all(isinstance(v, str) and v for v in (material_id, contract_identity, implementation_binding)):
        raise ValueError("COMPATIBILITY_CONTEXT_IDENTITY_MISSING")
    if not HEX64.fullmatch(bound_fingerprint or "") or not HEX64.fullmatch(current_fingerprint or ""):
        raise ValueError("COMPATIBILITY_FINGERPRINT_INVALID")
    return canonical_sha256({
        "schema_version": "LF_COMPATIBILITY_PROOF_CONTEXT_V1",
        "material_id": material_id,
        "change_class": change_class,
        "bound_fingerprint": bound_fingerprint,
        "current_fingerprint": current_fingerprint,
        "contract_identity": contract_identity,
        "implementation_binding": implementation_binding,
    })


def _assessment_map(binding: dict[str, Any], material_fingerprints: dict[str, dict[str, Any]]) -> tuple[dict[str, dict[str, Any]], str | None]:
    block = binding.get("compatibility_contract") or {}
    assessments = block.get("assessments") or []
    if not isinstance(assessments, list):
        return {}, "COMPATIBILITY_ASSESSMENTS_INVALID"
    contract_identity = binding.get("contract_identity")
    implementation_binding = binding.get("implementation_binding")
    if assessments and (not isinstance(contract_identity, str) or not contract_identity or not isinstance(implementation_binding, str) or not implementation_binding):
        return {}, "COMPATIBILITY_CONTEXT_IDENTITY_MISSING"
    out: dict[str, dict[str, Any]] = {}
    for row in assessments:
        if not isinstance(row, dict):
            return {}, "COMPATIBILITY_ASSESSMENT_INVALID"
        mid = row.get("material_id")
        klass = row.get("change_class")
        proof = row.get("proof_sha256")
        if not isinstance(mid, str) or not mid or mid in out:
            return {}, "COMPATIBILITY_MATERIAL_ID_INVALID_OR_DUPLICATE"
        if mid not in material_fingerprints:
            return {}, f"COMPATIBILITY_MATERIAL_UNKNOWN:{mid}"
        if klass not in _ALLOWED_CHANGE_CLASSES:
            return {}, f"COMPATIBILITY_CLASS_INVALID:{mid}"
        if not isinstance(proof, str) or not HEX64.fullmatch(proof):
            return {}, f"COMPATIBILITY_PROOF_INVALID:{mid}"
        fps = material_fingerprints[mid]
        expected = compatibility_proof_sha256(material_id=mid, change_class=klass, bound_fingerprint=fps.get("bound_fingerprint"), current_fingerprint=fps.get("current_fingerprint"), contract_identity=contract_identity, implementation_binding=implementation_binding)
        if proof != expected:
            return {}, f"COMPATIBILITY_PROOF_CONTEXT_MISMATCH:{mid}"
        out[mid] = row
    return out, None


def _gates_for(material_ids: list[str], materials: dict[str, dict[str, Any]]) -> list[str]:
    gates: set[str] = set()
    for mid in material_ids:
        spec = materials.get(mid) or {}
        for gate in spec.get("consumer_gates") or []:
            if isinstance(gate, str) and gate:
                gates.add(gate)
    return sorted(gates)


def _fail_closed(base: dict[str, Any], reason: str, **extra: Any) -> dict[str, Any]:
    return {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": "UNKNOWN_FAIL_CLOSED",
        "ready": False,
        "reason": reason,
        "evidence_revision": base.get("evidence_revision"),
        "bound_revision": base.get("bound_revision"),
        "current_revision": base.get("current_revision"),
        **extra,
    }


def evaluate_authority(binding: dict[str, Any], repo: Path) -> dict[str, Any]:
    base = evaluate(binding, repo)
    if base.get("decision") == "UNKNOWN_FAIL_CLOSED":
        base["authority_layer"] = "CURRENTNESS_AUTHORITY"
        return base
    raw_materials = binding.get("materials") or []
    materials = {m.get("material_id"): m for m in raw_materials if isinstance(m, dict) and m.get("material_id")}
    changed = list(base.get("changed_material_ids") or [])
    if not changed:
        out = dict(base)
        out.update({
            "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
            "authority_layer": "CURRENTNESS_AUTHORITY",
            "contract_identity": binding.get("contract_identity"),
            "implementation_binding": binding.get("implementation_binding"),
            "compatibility_contract": binding.get("compatibility_contract") or {"assessments": []},
            "bounded_validation_required": False,
            "bounded_validation_material_ids": [],
            "bounded_validation_gate_ids": [],
            "affected_gate_ids": [],
        })
        out.pop("receipt_sha256", None)
        out["receipt_sha256"] = canonical_sha256(out)
        return out
    assessments, error = _assessment_map(binding, base.get("materials") or {})
    if error:
        return _fail_closed(base, error)
    missing = sorted(mid for mid in changed if mid not in assessments)
    if missing:
        return _fail_closed(base, "COMPATIBILITY_ASSESSMENT_MISSING", unknown_material_ids=missing)
    compatible_impl: set[str] = set()
    compatible_contract: set[str] = set()
    breaking: set[str] = set()
    unknown: set[str] = set()
    for mid in changed:
        klass = assessments[mid]["change_class"]
        if klass == "IMPLEMENTATION_ONLY_COMPATIBLE":
            compatible_impl.add(mid)
        elif klass == "CONTRACT_COMPATIBLE":
            compatible_contract.add(mid)
        elif klass == "BREAKING":
            breaking.add(mid)
        else:
            unknown.add(mid)
    if unknown:
        return _fail_closed(base, "COMPATIBILITY_UNKNOWN", unknown_material_ids=sorted(unknown))
    breaking_closure = affected_closure(breaking, materials) if breaking else []
    bounded_closure = affected_closure(compatible_contract, materials) if compatible_contract else []
    roots = set(binding.get("root_material_ids") or sorted(materials))
    affected_roots = sorted(roots.intersection(breaking_closure))
    if affected_roots:
        decision = "STALE_AFFECTED"
        ready = False
        rebind_allowed = False
    else:
        decision = "CURRENT_REBOUND" if base.get("bound_revision") != base.get("current_revision") or changed else "CURRENT"
        ready = True
        rebind_allowed = base.get("bound_revision") != base.get("current_revision")
    out = dict(base)
    out.update({
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": decision,
        "ready": ready,
        "rebind_allowed": rebind_allowed,
        "contract_identity": binding.get("contract_identity"),
        "implementation_binding": binding.get("implementation_binding"),
        "compatibility_contract": binding.get("compatibility_contract") or {"assessments": []},
        "implementation_compatible_material_ids": sorted(compatible_impl),
        "contract_compatible_material_ids": sorted(compatible_contract),
        "breaking_material_ids": sorted(breaking),
        "affected_material_ids": breaking_closure,
        "affected_root_material_ids": affected_roots,
        "affected_gate_ids": _gates_for(breaking_closure, materials),
        "bounded_validation_required": bool(compatible_contract),
        "bounded_validation_material_ids": bounded_closure,
        "bounded_validation_gate_ids": _gates_for(bounded_closure, materials),
    })
    out.pop("receipt_sha256", None)
    out["receipt_sha256"] = canonical_sha256(out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="S31 CURRENTNESS_AUTHORITY over the read-only material-currentness engine.")
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--binding", type=Path, required=True)
    ap.add_argument("--current-revision")
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    if ns.current_revision:
        binding.setdefault("authority", {})["current_revision"] = ns.current_revision
    result = evaluate_authority(binding, ns.repo)
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
