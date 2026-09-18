#!/usr/bin/env python3
"""CURRENTNESS_AUTHORITY adapter for the unified CI applicability authority.

This module does not implement a second currentness engine. It builds the
material binding for CI_FAST_DEEP_LANE_ROUTER and delegates the decision to
the existing material_currentness/CURRENTNESS_AUTHORITY implementation.

The historical base SHA is evidence context only. The moving authority is
refs/heads/main, resolved at execution time.
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CURRENTNESS_DIR = HERE.parent / "material_currentness"
CURRENTNESS_IMPL = CURRENTNESS_DIR / "lf_currentness_authority_v1.py"

HEX40 = re.compile(r"^[0-9a-f]{40}$")

CI_AUTHORITY_SELECTORS = {
    "paths": [
        ".github/workflows/lf-contract-check.yml",
        ".github/workflows/validate-lf-packs.yml",
        ".github/workflows/lf-bootstrap-reproducibility.yml",
    ],
    "prefixes": [
        "sandbox/lf_contract_gate_test/s28_ci_lane_router/",
        "sandbox/lf_contract_gate_test/gate_check_observability/",
        "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/",
        "sandbox/lf_contract_gate_test/material_currentness/",
    ],
    "globs": [],
}


def _load_currentness():
    if str(CURRENTNESS_DIR) not in sys.path:
        sys.path.insert(0, str(CURRENTNESS_DIR))
    spec = importlib.util.spec_from_file_location(
        "lf_currentness_authority_v1_ci_adapter", CURRENTNESS_IMPL
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_CI_CURRENTNESS_AUTHORITY_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


CURRENTNESS = _load_currentness()


def build_binding(*, bound_revision: str, current_revision: str) -> dict[str, Any]:
    if not HEX40.fullmatch(bound_revision or ""):
        raise ValueError("FAIL_CI_CURRENTNESS_BOUND_REVISION")
    if not HEX40.fullmatch(current_revision or ""):
        raise ValueError("FAIL_CI_CURRENTNESS_CURRENT_REVISION")
    return {
        "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority": {
            "ref": "refs/heads/main",
            "bound_revision": bound_revision,
            "current_revision": current_revision,
        },
        "evidence_revision": bound_revision,
        "dependency_completeness": "COMPLETE",
        "require_ancestor": True,
        "contract_identity": "CI_FAST_DEEP_LANE_ROUTER",
        "implementation_binding": "LF_CI_APPLICABILITY_AUTHORITY_V2",
        "compatibility_contract": {"assessments": []},
        "materials": [
            {
                "material_id": "ci_applicability_authority",
                "kind": "GIT_TREE",
                "selectors": CI_AUTHORITY_SELECTORS,
                "required": True,
                "depends_on": [],
                "consumer_gates": ["CI_ROUTER_SELFTEST"],
            }
        ],
        "root_material_ids": ["ci_applicability_authority"],
    }


def evaluate_ci_authority_currentness(
    *,
    repo: Path,
    bound_revision: str,
    current_revision: str,
) -> dict[str, Any]:
    if bound_revision == current_revision:
        binding = build_binding(
            bound_revision=bound_revision,
            current_revision=current_revision,
        )
        result = CURRENTNESS.evaluate_authority(binding, repo)
    else:
        binding = build_binding(
            bound_revision=bound_revision,
            current_revision=current_revision,
        )
        result = CURRENTNESS.evaluate_authority(binding, repo)

    out = {
        "schema_version": "LF_CI_AUTHORITY_CURRENTNESS_RECEIPT_V1",
        "authority_ref": "refs/heads/main",
        "evidence_revision": bound_revision,
        "resolved_revision": current_revision,
        "decision": result.get("decision"),
        "ready": bool(result.get("ready")),
        "rebind_allowed": bool(result.get("rebind_allowed", False)),
        "reason": result.get("reason"),
        "changed_material_ids": result.get("changed_material_ids") or [],
        "affected_material_ids": result.get("affected_material_ids") or [],
        "affected_root_material_ids": result.get("affected_root_material_ids") or [],
        "authority_receipt_sha256": result.get("receipt_sha256"),
        "evidence_semantics": "HISTORICAL_IMMUTABLE_REFERENCE_NOT_MOVING_AUTHORITY",
    }
    return out


def require_ready(receipt: dict[str, Any]) -> None:
    if receipt.get("ready") is not True:
        decision = receipt.get("decision") or "UNKNOWN"
        reason = receipt.get("reason") or ""
        raise RuntimeError(
            f"BLOCK_CI_AUTHORITY_CURRENTNESS:{decision}:{reason}"
        )


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--bound-revision", required=True)
    ap.add_argument("--current-revision", required=True)
    ap.add_argument("--output")
    ns = ap.parse_args()

    receipt = evaluate_ci_authority_currentness(
        repo=ns.repo,
        bound_revision=ns.bound_revision,
        current_revision=ns.current_revision,
    )
    text = json.dumps(receipt, sort_keys=True, indent=2)
    if ns.output:
        Path(ns.output).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if receipt.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
