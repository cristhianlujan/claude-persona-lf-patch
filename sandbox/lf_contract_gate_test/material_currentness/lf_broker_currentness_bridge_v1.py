#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from lf_material_currentness_v1 import evaluate

HEX40 = re.compile(r"^[0-9a-f]{40}$")


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
    if authority.get("bound_revision") != base_revision:
        return {
            "ready": False,
            "decision": "BLOCK_BROKER_BINDING_BASE_MISMATCH",
            "expected_base_revision": base_revision,
            "binding_bound_revision": authority.get("bound_revision"),
        }

    hydrated = json.loads(json.dumps(binding))
    hydrated.setdefault("authority", {})["current_revision"] = current_revision
    result = evaluate(hydrated, repo)

    common = {
        "base_revision": base_revision,
        "current_revision": current_revision,
        "material_currentness_required": True,
        "material_currentness": result,
    }

    if result.get("decision") == "CURRENT_REBOUND" and result.get("ready") and result.get("rebind_allowed"):
        return {
            **common,
            "ready": True,
            "decision": "BROKER_REBIND_CURRENT",
            "effective_base_revision": current_revision,
        }

    if result.get("decision") == "STALE_AFFECTED":
        return {
            **common,
            "ready": False,
            "decision": "BLOCK_BROKER_STALE_AFFECTED",
            "affected_material_ids": result.get("affected_material_ids") or [],
            "affected_root_material_ids": result.get("affected_root_material_ids") or [],
        }

    return {
        **common,
        "ready": False,
        "decision": "BLOCK_BROKER_CURRENTNESS_UNPROVEN",
        "reason": result.get("reason"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Compatibility bridge for S30 Git Broker stale-main handling.")
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--binding", type=Path, required=True)
    ap.add_argument("--base-revision", required=True)
    ap.add_argument("--current-revision", required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()

    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    result = bridge_decision(
        repo=ns.repo,
        binding=binding,
        base_revision=ns.base_revision,
        current_revision=ns.current_revision,
    )
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
