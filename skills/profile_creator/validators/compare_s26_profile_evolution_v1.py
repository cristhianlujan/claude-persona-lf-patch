#!/usr/bin/env python3
"""Deterministic before/after proof for a Profile update (structural S26 dimensions).

The trusted evaluator and baseline contract come from --trusted-root. Only the profile directory is
taken from the base and candidate trees, so a candidate cannot change the rules it is judged by.
Never imports or executes profile code.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

SCHEMA = "S26_PROFILE_EVOLUTION_PROOF_V1"
EVALUATOR_REL = Path("skills/profile_creator/validators/evaluate_s26_profile_baseline.py")
BASELINE_REL = Path("skills/profile_creator/contracts/s26_profile_baseline_v1.json")


def _load_evaluator(trusted_root: Path):
    path = trusted_root / EVALUATOR_REL
    spec = importlib.util.spec_from_file_location("trusted_s26_evaluator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # trusted code from the trusted root only
    return module


def _has_symlink(root: Path) -> bool:
    return any(p.is_symlink() for p in [root, *root.rglob("*")])


def _evaluate(evaluator, trusted_root: Path, slug: str, profile_dir: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="s26-proof-") as tmp:
        root = Path(tmp)
        (root / BASELINE_REL).parent.mkdir(parents=True)
        shutil.copyfile(trusted_root / BASELINE_REL, root / BASELINE_REL)
        (root / "profiles").mkdir()
        shutil.copytree(profile_dir, root / "profiles" / slug, symlinks=False)
        return evaluator.evaluate(root, slug)


def compare(trusted_root: Path, slug: str, base_dir: Path, candidate_dir: Path) -> dict[str, Any]:
    trusted_root = trusted_root.resolve()
    result: dict[str, Any] = {"schema": SCHEMA, "profile_slug": slug, "verdict": "BLOCKED",
                              "blocking_codes": [], "improved_dimensions": [], "regressed_dimensions": []}
    for label, directory in (("BASE", base_dir), ("CANDIDATE", candidate_dir)):
        if not directory.is_dir():
            result["blocking_codes"].append(f"{label}_PROFILE_DIR_MISSING")
        elif _has_symlink(directory):
            result["blocking_codes"].append(f"{label}_PROFILE_SYMLINK_FORBIDDEN")
    if result["blocking_codes"]:
        return _seal(result)
    evaluator = _load_evaluator(trusted_root)
    base = _evaluate(evaluator, trusted_root, slug, base_dir)
    cand = _evaluate(evaluator, trusted_root, slug, candidate_dir)
    for label, ev in (("BASE", base), ("CANDIDATE", cand)):
        if ev.get("blocking_codes") and not ev.get("dimensions"):
            result["blocking_codes"].extend(f"{label}_{c}" for c in ev["blocking_codes"])
    if result["blocking_codes"] or set(base["dimensions"]) != set(cand["dimensions"]):
        if not result["blocking_codes"]:
            result["blocking_codes"].append("DIMENSION_SET_MISMATCH")
        return _seal(result)
    improved = sorted(d for d in base["dimensions"] if not base["dimensions"][d]["pass"] and cand["dimensions"][d]["pass"])
    regressed = sorted(d for d in base["dimensions"] if base["dimensions"][d]["pass"] and not cand["dimensions"][d]["pass"])
    result.update({
        "base_score": base["score"], "candidate_score": cand["score"], "required": base["required"],
        "improved_dimensions": improved, "regressed_dimensions": regressed,
        "structural_ceiling_reached": base["score"] == base["required"],
    })
    if regressed:
        result["verdict"] = "REGRESSION"
    elif improved:
        result["verdict"] = "EVOLUTION_DEMONSTRATED"
    else:
        result["verdict"] = "NO_DEMONSTRATED_IMPROVEMENT"
    return _seal(result)


def _seal(result: dict[str, Any]) -> dict[str, Any]:
    body = json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
    result["proof_sha256"] = hashlib.sha256(body).hexdigest()
    return result


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: compare_s26_profile_evolution_v1.py <slug> <trusted_root> <base_profile_dir> <candidate_profile_dir>", file=sys.stderr)
        return 2
    out = compare(Path(sys.argv[2]), sys.argv[1], Path(sys.argv[3]), Path(sys.argv[4]))
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["verdict"] == "EVOLUTION_DEMONSTRATED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
