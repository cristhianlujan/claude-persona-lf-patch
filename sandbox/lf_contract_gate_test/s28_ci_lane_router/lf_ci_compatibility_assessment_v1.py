#!/usr/bin/env python3
"""Bounded producer for CI Currentness compatibility assessments.

This producer is deliberately separate from CURRENTNESS_AUTHORITY. It proves
consumer-specific semantic equivalence by replaying the same changeset against
the bound and current CI authority revisions. Only then does it emit a
CONTRACT_COMPATIBLE assessment whose proof is recomputed from material
fingerprints by the canonical Currentness contract.

It never activates runtime, mutates authority, or treats path similarity as
compatibility evidence.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CURRENTNESS_DIR = HERE.parent / "material_currentness"
CURRENTNESS_IMPL = CURRENTNESS_DIR / "lf_currentness_authority_v1.py"
EMITTER_REL = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py")
MATERIAL_ID = "ci_applicability_authority"


def _load_currentness():
    if str(CURRENTNESS_DIR) not in sys.path:
        sys.path.insert(0, str(CURRENTNESS_DIR))
    spec = importlib.util.spec_from_file_location(
        "lf_currentness_authority_v1_ci_compatibility_producer", CURRENTNESS_IMPL
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_CI_COMPAT_CURRENTNESS_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


CURRENTNESS = _load_currentness()


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _observable_projection(plan: dict[str, Any]) -> dict[str, Any]:
    enforcement = plan.get("pase_control_enforcement") or {}
    handoff = plan.get("contract_check_resolution_request") or {}
    return {
        "lane_mode": plan.get("lane_mode"),
        "full_regression": bool(plan.get("full_regression")),
        "required_controls": plan.get("required_controls") or [],
        "carrier_controls": plan.get("carrier_controls") or {},
        "coverage_complete": bool(plan.get("coverage_complete")),
        "contract_check_handoff_state": handoff.get("handoff_state"),
        "pase_blocking_controls": enforcement.get("blocking_controls") or [],
        "pase_observe_only_controls": enforcement.get("observe_only_controls") or [],
    }


def _run_projection(
    *,
    repo: Path,
    authority_revision: str,
    diff_base_revision: str,
    candidate_head_revision: str,
) -> dict[str, Any]:
    """Replay one changeset with authority=current to avoid recursive currentness."""
    with tempfile.TemporaryDirectory(prefix="lf-ci-compat-") as td:
        worktree = Path(td) / "wt"
        add = subprocess.run(
            ["git", "-C", str(repo), "worktree", "add", "--detach", "--force", str(worktree), authority_revision],
            text=True,
            capture_output=True,
        )
        if add.returncode != 0:
            raise RuntimeError(f"FAIL_CI_COMPAT_WORKTREE_ADD:{authority_revision}:{add.stderr.strip()}")
        try:
            emitter = worktree / EMITTER_REL
            if not emitter.is_file():
                raise RuntimeError(f"FAIL_CI_COMPAT_EMITTER_MISSING:{authority_revision}")
            output = Path(td) / "plan.json"
            cmd = [
                sys.executable,
                str(emitter),
                "--repo-root", str(worktree),
                "--base", diff_base_revision,
                "--head", candidate_head_revision,
                "--authority-current-revision", authority_revision,
                "--event-name", "compatibility_replay",
                "--ref-name", "compatibility-replay",
                "--output-json", str(output),
            ]
            cp = subprocess.run(cmd, text=True, capture_output=True)
            if cp.returncode != 0:
                raise RuntimeError(
                    f"FAIL_CI_COMPAT_REPLAY:{authority_revision}:"
                    f"{cp.stderr.strip() or cp.stdout.strip()}"
                )
            plan = json.loads(output.read_text(encoding="utf-8"))
            return _observable_projection(plan)
        finally:
            subprocess.run(
                ["git", "-C", str(repo), "worktree", "remove", "--force", str(worktree)],
                text=True,
                capture_output=True,
            )


def assess_ci_compatibility(
    *,
    repo: Path,
    binding_without_assessments: dict[str, Any],
    diff_base_revision: str | None,
    candidate_head_revision: str | None,
) -> dict[str, Any]:
    """Return a source-bound assessment plus its bounded replay receipt."""
    base = CURRENTNESS.evaluate(binding_without_assessments, repo)
    if base.get("decision") == "UNKNOWN_FAIL_CLOSED":
        return {
            "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
            "ready": False,
            "reason": f"CURRENTNESS_PROBE_FAILED:{base.get('reason') or 'UNKNOWN'}",
            "assessment": None,
        }

    changed = list(base.get("changed_material_ids") or [])
    if not changed:
        return {
            "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
            "ready": True,
            "reason": "NO_CHANGED_CI_AUTHORITY_MATERIAL",
            "assessment": None,
            "bounded_validation": {"required": False, "verdict": "NOT_REQUIRED"},
        }
    if changed != [MATERIAL_ID]:
        return {
            "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
            "ready": False,
            "reason": "UNEXPECTED_CHANGED_MATERIAL_SET",
            "changed_material_ids": changed,
            "assessment": None,
        }
    if not diff_base_revision or not candidate_head_revision:
        return {
            "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
            "ready": False,
            "reason": "BOUNDED_REPLAY_CONTEXT_MISSING",
            "assessment": None,
        }

    authority = binding_without_assessments.get("authority") or {}
    bound_revision = authority.get("bound_revision")
    current_revision = authority.get("current_revision")
    old_projection = _run_projection(
        repo=repo,
        authority_revision=bound_revision,
        diff_base_revision=diff_base_revision,
        candidate_head_revision=candidate_head_revision,
    )
    new_projection = _run_projection(
        repo=repo,
        authority_revision=current_revision,
        diff_base_revision=diff_base_revision,
        candidate_head_revision=candidate_head_revision,
    )
    old_sha = _sha(old_projection)
    new_sha = _sha(new_projection)
    if old_sha != new_sha:
        return {
            "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
            "ready": False,
            "reason": "BOUNDED_REPLAY_SEMANTIC_DRIFT",
            "assessment": None,
            "bounded_validation": {
                "required": True,
                "verdict": "FAIL",
                "diff_base_revision": diff_base_revision,
                "candidate_head_revision": candidate_head_revision,
                "bound_authority_revision": bound_revision,
                "current_authority_revision": current_revision,
                "bound_projection_sha256": old_sha,
                "current_projection_sha256": new_sha,
            },
        }

    material = (base.get("materials") or {}).get(MATERIAL_ID) or {}
    change_class = "CONTRACT_COMPATIBLE"
    proof = CURRENTNESS.compatibility_proof_sha256(
        material_id=MATERIAL_ID,
        change_class=change_class,
        bound_fingerprint=material.get("bound_fingerprint"),
        current_fingerprint=material.get("current_fingerprint"),
        contract_identity=binding_without_assessments.get("contract_identity"),
        implementation_binding=binding_without_assessments.get("implementation_binding"),
    )
    replay_receipt = {
        "schema_version": "LF_CI_COMPATIBILITY_BOUNDED_REPLAY_V1",
        "required": True,
        "verdict": "PASS",
        "material_id": MATERIAL_ID,
        "diff_base_revision": diff_base_revision,
        "candidate_head_revision": candidate_head_revision,
        "bound_authority_revision": bound_revision,
        "current_authority_revision": current_revision,
        "bound_projection_sha256": old_sha,
        "current_projection_sha256": new_sha,
        "projection_fields": sorted(old_projection),
    }
    replay_receipt["receipt_sha256"] = _sha(replay_receipt)
    return {
        "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
        "ready": True,
        "reason": "BOUNDED_REPLAY_EQUIVALENT",
        "assessment": {
            "material_id": MATERIAL_ID,
            "change_class": change_class,
            "proof_sha256": proof,
        },
        "bounded_validation": replay_receipt,
    }
