#!/usr/bin/env python3
"""Bounded producer for CI Currentness compatibility assessments.

This producer is separate from CURRENTNESS_AUTHORITY. It replays the same
exact changeset against bound and current CI authority revisions. It accepts
only exact semantic equivalence or a narrow safe refinement where controls
removed by the newer authority were observe-only diagnostics, no blocking
control disappears, selected controls keep the same carrier, and coverage /
handoff semantics remain intact.

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
CI_AUTHORITY_EXACT = {
    ".github/workflows/lf-contract-check.yml",
    ".github/workflows/validate-lf-packs.yml",
    ".github/workflows/lf-db-regression.yml",
}
CI_AUTHORITY_PREFIXES = (
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/",
    "sandbox/lf_contract_gate_test/gate_check_observability/",
    "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/",
    "sandbox/lf_contract_gate_test/material_currentness/",
)


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


def _control_carriers(projection: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for carrier, controls in (projection.get("carrier_controls") or {}).items():
        if not isinstance(carrier, str) or not isinstance(controls, list):
            return {}
        for control in controls:
            if not isinstance(control, str) or control in result:
                return {}
            result[control] = carrier
    return result


def _safe_observe_only_refinement(
    old: dict[str, Any], new: dict[str, Any]
) -> tuple[bool, dict[str, Any]]:
    """Prove that a newer plan only removes non-blocking diagnostic work."""
    old_required = set(old.get("required_controls") or [])
    new_required = set(new.get("required_controls") or [])
    old_blocking = set(old.get("pase_blocking_controls") or [])
    new_blocking = set(new.get("pase_blocking_controls") or [])
    old_observe = set(old.get("pase_observe_only_controls") or [])
    new_observe = set(new.get("pase_observe_only_controls") or [])
    removed = old_required - new_required
    old_carriers = _control_carriers(old)
    new_carriers = _control_carriers(new)

    checks = {
        "same_lane_mode": old.get("lane_mode") == new.get("lane_mode"),
        "same_handoff_state": old.get("contract_check_handoff_state") == new.get("contract_check_handoff_state"),
        "coverage_complete": old.get("coverage_complete") is True and new.get("coverage_complete") is True,
        "historical_full_regression_only": old.get("full_regression") is True and new.get("full_regression") is False,
        "new_required_is_subset": bool(new_required) and new_required.issubset(old_required),
        "removed_controls_exist": bool(removed),
        "removed_are_observe_only": removed.issubset(old_observe),
        "no_blocking_control_removed": not bool(removed & old_blocking),
        "old_blocking_preserved": old_blocking.issubset(new_blocking),
        "new_required_carriers_stable": all(old_carriers.get(c) == new_carriers.get(c) for c in new_required),
        "new_observe_within_required": new_observe.issubset(new_required),
    }
    return all(checks.values()), {
        "checks": checks,
        "removed_observe_only_controls": sorted(removed),
        "preserved_required_controls": sorted(new_required),
    }


def _changed_paths(repo: Path, base: str, head: str) -> list[str]:
    raw = subprocess.check_output(
        ["git", "-C", str(repo), "diff", "--name-only", "--no-renames", base, head],
        text=True,
    )
    return sorted({line.strip() for line in raw.splitlines() if line.strip()})


def _touches_ci_authority(path: str) -> bool:
    return path in CI_AUTHORITY_EXACT or any(path.startswith(prefix) for prefix in CI_AUTHORITY_PREFIXES)


def _overlay_candidate_files(
    *, repo: Path, worktree: Path, candidate_head_revision: str, changed_paths: list[str]
) -> None:
    for rel in changed_paths:
        target = worktree / rel
        cp = subprocess.run(
            ["git", "-C", str(repo), "show", f"{candidate_head_revision}:{rel}"],
            capture_output=True,
        )
        if cp.returncode == 0:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(cp.stdout)
        elif target.exists():
            if target.is_file() or target.is_symlink():
                target.unlink()
            else:
                raise RuntimeError(f"FAIL_CI_COMPAT_OVERLAY_NONFILE:{rel}")


def _run_projection(
    *,
    repo: Path,
    authority_revision: str,
    diff_base_revision: str,
    candidate_head_revision: str,
    changed_paths: list[str],
) -> dict[str, Any]:
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
            _overlay_candidate_files(
                repo=repo,
                worktree=worktree,
                candidate_head_revision=candidate_head_revision,
                changed_paths=changed_paths,
            )
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
            cp = subprocess.run(cmd, text=True, capture_output=True, cwd=worktree)
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
    base = CURRENTNESS.evaluate(binding_without_assessments, repo)
    if base.get("decision") == "UNKNOWN_FAIL_CLOSED":
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": False, "reason": f"CURRENTNESS_PROBE_FAILED:{base.get('reason') or 'UNKNOWN'}", "assessment": None}

    changed = list(base.get("changed_material_ids") or [])
    if not changed:
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": True, "reason": "NO_CHANGED_CI_AUTHORITY_MATERIAL", "assessment": None, "bounded_validation": {"required": False, "verdict": "NOT_REQUIRED"}}
    if changed != [MATERIAL_ID]:
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": False, "reason": "UNEXPECTED_CHANGED_MATERIAL_SET", "changed_material_ids": changed, "assessment": None}
    if not diff_base_revision or not candidate_head_revision:
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": False, "reason": "BOUNDED_REPLAY_CONTEXT_MISSING", "assessment": None}

    candidate_paths = _changed_paths(repo, diff_base_revision, candidate_head_revision)
    authority_overlap = sorted(path for path in candidate_paths if _touches_ci_authority(path))
    if authority_overlap:
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": False, "reason": "CANDIDATE_TOUCHES_CI_AUTHORITY", "authority_overlap": authority_overlap, "assessment": None}

    authority = binding_without_assessments.get("authority") or {}
    bound_revision = authority.get("bound_revision")
    current_revision = authority.get("current_revision")
    try:
        old_projection = _run_projection(repo=repo, authority_revision=bound_revision, diff_base_revision=diff_base_revision, candidate_head_revision=candidate_head_revision, changed_paths=candidate_paths)
        new_projection = _run_projection(repo=repo, authority_revision=current_revision, diff_base_revision=diff_base_revision, candidate_head_revision=candidate_head_revision, changed_paths=candidate_paths)
    except RuntimeError as exc:
        return {"schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1", "ready": False, "reason": str(exc), "assessment": None}

    old_sha = _sha(old_projection)
    new_sha = _sha(new_projection)
    refinement_proof: dict[str, Any] | None = None
    if old_sha == new_sha:
        replay_mode = "EXACT_EQUIVALENCE"
    else:
        safe, refinement_proof = _safe_observe_only_refinement(old_projection, new_projection)
        if not safe:
            return {
                "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
                "ready": False,
                "reason": "BOUNDED_REPLAY_SEMANTIC_DRIFT",
                "assessment": None,
                "bounded_validation": {
                    "required": True, "verdict": "FAIL",
                    "diff_base_revision": diff_base_revision,
                    "candidate_head_revision": candidate_head_revision,
                    "bound_authority_revision": bound_revision,
                    "current_authority_revision": current_revision,
                    "bound_projection_sha256": old_sha,
                    "current_projection_sha256": new_sha,
                    "bound_projection": old_projection,
                    "current_projection": new_projection,
                    "refinement_proof": refinement_proof,
                },
            }
        replay_mode = "SAFE_OBSERVE_ONLY_REFINEMENT"

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
        "replay_mode": replay_mode,
        "material_id": MATERIAL_ID,
        "diff_base_revision": diff_base_revision,
        "candidate_head_revision": candidate_head_revision,
        "bound_authority_revision": bound_revision,
        "current_authority_revision": current_revision,
        "bound_projection_sha256": old_sha,
        "current_projection_sha256": new_sha,
        "candidate_changed_paths": candidate_paths,
        "projection_fields": sorted(old_projection),
        "refinement_proof": refinement_proof,
    }
    replay_receipt["receipt_sha256"] = _sha(replay_receipt)
    return {
        "schema_version": "LF_CI_COMPATIBILITY_ASSESSMENT_V1",
        "ready": True,
        "reason": "BOUNDED_REPLAY_COMPATIBLE",
        "assessment": {"material_id": MATERIAL_ID, "change_class": change_class, "proof_sha256": proof},
        "bounded_validation": replay_receipt,
    }
