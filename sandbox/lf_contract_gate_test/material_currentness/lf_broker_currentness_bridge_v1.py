#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from lf_currentness_authority_v1 import evaluate_authority

HEX40 = re.compile(r"^[0-9a-f]{40}$")


def _hydrate_template(binding: dict, base_revision: str, current_revision: str) -> dict:
    hydrated = json.loads(json.dumps(binding))
    authority = hydrated.setdefault("authority", {})
    template_mode = authority.get("bound_revision") == "__BOUND_REVISION__" and hydrated.get("evidence_revision") == "__BOUND_REVISION__"
    if template_mode:
        authority["bound_revision"] = base_revision
        hydrated["evidence_revision"] = base_revision
    authority["current_revision"] = current_revision
    return hydrated


def bridge_decision(*, repo: Path, binding: dict, base_revision: str, current_revision: str) -> dict:
    if not HEX40.fullmatch(base_revision or "") or not HEX40.fullmatch(current_revision or ""):
        return {"ready": False, "decision": "BLOCK_BROKER_REVISION_FORMAT_INVALID"}

    if base_revision == current_revision:
        return {
            "ready": True,
            "decision": "BROKER_BASE_CURRENT",
            "base_revision": base_revision,
            "current_revision": current_revision,
            "effective_base_revision": base_revision,
            "material_currentness_required": False,
        }

    authority = dict(binding.get("authority") or {})
    declared_bound = authority.get("bound_revision")
    if declared_bound not in (base_revision, "__BOUND_REVISION__"):
        return {
            "ready": False,
            "decision": "BLOCK_BROKER_BINDING_BASE_MISMATCH",
            "expected_base_revision": base_revision,
            "binding_bound_revision": declared_bound,
        }

    hydrated = _hydrate_template(binding, base_revision, current_revision)
    result = evaluate_authority(hydrated, repo)

    common = {
        "base_revision": base_revision,
        "current_revision": current_revision,
        "material_currentness_required": True,
        "material_currentness": result,
    }

    if result.get("decision") == "CURRENT_REBOUND" and result.get("ready") and result.get("bounded_validation_required"):
        return {
            **common,
            "ready": False,
            "decision": "BLOCK_BROKER_BOUNDED_VALIDATION_REQUIRED",
            "bounded_validation_material_ids": result.get("bounded_validation_material_ids") or [],
            "bounded_validation_gate_ids": result.get("bounded_validation_gate_ids") or [],
        }

    if result.get("decision") == "CURRENT_REBOUND" and result.get("ready") and result.get("rebind_allowed"):
        return {
            **common,
            "ready": True,
            "decision": "BROKER_REBIND_CURRENT",
            "effective_base_revision": current_revision,
            "evidence_revision": result.get("evidence_revision"),
        }

    if result.get("decision") == "STALE_AFFECTED":
        return {
            **common,
            "ready": False,
            "decision": "BLOCK_BROKER_STALE_AFFECTED",
            "affected_material_ids": result.get("affected_material_ids") or [],
            "affected_root_material_ids": result.get("affected_root_material_ids") or [],
            "affected_gate_ids": result.get("affected_gate_ids") or [],
        }

    return {
        **common,
        "ready": False,
        "decision": "BLOCK_BROKER_CURRENTNESS_UNPROVEN",
        "reason": result.get("reason"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="S31 material-aware compatibility bridge for Git Broker stale-main handling.")
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--binding", type=Path, required=True)
    ap.add_argument("--base-revision", required=True)
    ap.add_argument("--current-revision", required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()

    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    result = bridge_decision(repo=ns.repo, binding=binding, base_revision=ns.base_revision, current_revision=ns.current_revision)
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
