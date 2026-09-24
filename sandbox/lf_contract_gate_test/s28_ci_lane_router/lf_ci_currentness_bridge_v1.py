#!/usr/bin/env python3
"""CURRENTNESS_AUTHORITY adapter for the unified CI applicability authority.

This module does not implement a second currentness engine. It builds the
material binding for CI_FAST_DEEP_LANE_ROUTER + FULL_REGRESSION and delegates
the decision to the existing material_currentness/CURRENTNESS_AUTHORITY.
"""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
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
        ".github/workflows/lf-db-regression.yml",
    ],
    "prefixes": [
        "sandbox/lf_contract_gate_test/s28_ci_lane_router/",
        "sandbox/lf_contract_gate_test/gate_check_observability/",
        "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/",
        "sandbox/lf_contract_gate_test/transversal_assets/full_regression/",
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


def resolve_authority_evidence_revision(
    *,
    repo: Path,
    event_name: str,
    ref_name: str,
    diff_base_revision: str | None,
    candidate_head_revision: str | None,
    current_revision: str,
) -> str:
    """Resolve the historical authority revision for currentness."""
    if not HEX40.fullmatch(current_revision or ""):
        raise ValueError("FAIL_CI_CURRENTNESS_CURRENT_REVISION")
    event_name = (event_name or "").strip()
    ref_name = (ref_name or "").strip()

    if event_name == "pull_request":
        if not HEX40.fullmatch(diff_base_revision or ""):
            raise ValueError("FAIL_CI_CURRENTNESS_PR_DIFF_BASE")
        if not HEX40.fullmatch(candidate_head_revision or ""):
            raise ValueError("FAIL_CI_CURRENTNESS_PR_HEAD")
        try:
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "merge-base",
                    "--is-ancestor",
                    current_revision,
                    str(candidate_head_revision),
                ],
                check=True,
                text=True,
                capture_output=True,
            )
            return current_revision
        except subprocess.CalledProcessError:
            merge_base = subprocess.check_output(
                [
                    "git",
                    "-C",
                    str(repo),
                    "merge-base",
                    str(candidate_head_revision),
                    current_revision,
                ],
                text=True,
            ).strip()
            if not HEX40.fullmatch(merge_base):
                raise ValueError("FAIL_CI_CURRENTNESS_PR_MERGE_BASE")
            return merge_base

    if event_name == "push" and ref_name == "main":
        return current_revision

    if event_name == "push":
        if not HEX40.fullmatch(candidate_head_revision or ""):
            raise ValueError("FAIL_CI_CURRENTNESS_PUSH_HEAD")
        value = subprocess.check_output(
            [
                "git",
                "-C",
                str(repo),
                "merge-base",
                str(candidate_head_revision),
                current_revision,
            ],
            text=True,
        ).strip()
        if not HEX40.fullmatch(value):
            raise ValueError("FAIL_CI_CURRENTNESS_MERGE_BASE")
        return value

    return current_revision


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
        "implementation_binding": "LF_CI_APPLICABILITY_AUTHORITY_V2+FULL_REGRESSION_V1",
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
    binding = build_binding(
        bound_revision=bound_revision,
        current_revision=current_revision,
    )
    result = CURRENTNESS.evaluate_authority(binding, repo)
    return {
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
