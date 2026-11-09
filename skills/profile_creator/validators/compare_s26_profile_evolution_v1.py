#!/usr/bin/env python3
"""Deterministic before/after proof for a Profile update (structural S26 dimensions).

The trusted evaluator and baseline contract come from --trusted-root. Only the profile directory is
taken from the base and candidate trees, so a candidate cannot change the rules it is judged by.
Profile code is never imported here; B14 runs the profile's validators only inside the evaluator's isolated child process.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import operational_coverage_v1 as opc  # trusted sibling module (same directory as this tool)

SCHEMA = "S26_PROFILE_EVOLUTION_PROOF_V1"
EVALUATOR_REL = Path("skills/profile_creator/validators/evaluate_s26_profile_baseline.py")
BASELINE_REL = Path("skills/profile_creator/contracts/s26_profile_baseline_v1.json")


def runtime_validator_binding_check(profile_dir: Path, expected_slug: str) -> dict[str, Any]:
    """Static check of the canonical native validator binding (not a model run)."""
    path = profile_dir / "contracts" / "runtime_binding.json"
    if not path.is_file():
        return {"status": "NOT_APPLICABLE", "valid": True, "issues": [],
                "check_source": "TRUSTED_RUNTIME_BINDING_STATIC_INSPECTION"}
    issues: list[str] = []
    try:
        binding = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        binding = None
        issues.append("BINDING_JSON_INVALID")
    if not isinstance(binding, dict):
        binding = {}
        if "BINDING_JSON_INVALID" not in issues:
            issues.append("BINDING_OBJECT_REQUIRED")
    if binding.get("schema") != "LF_PROFILE_RUNTIME_BINDING_V1":
        issues.append("BINDING_SCHEMA_MISMATCH")
    if binding.get("profile_slug") != expected_slug:
        issues.append("PROFILE_SLUG_MISMATCH")
    runtime = binding.get("runtime_schema")
    validator = binding.get("canonical_validator")
    if not isinstance(runtime, dict):
        runtime = {}
        issues.append("RUNTIME_SCHEMA_DECLARATION_REQUIRED")
    if not isinstance(validator, dict):
        validator = {}
        issues.append("CANONICAL_VALIDATOR_DECLARATION_REQUIRED")
    if validator.get("callable") != "validate":
        issues.append("VALIDATOR_CALLABLE_INVALID")
    if validator.get("transport") not in {"STDIN_JSON", "JSON_FILE_ARGUMENT"}:
        issues.append("VALIDATOR_TRANSPORT_MISSING_OR_INVALID")
    for field, candidate in (("SCHEMA", runtime.get("default")),
                             ("VALIDATOR", validator.get("path"))):
        if not isinstance(candidate, str) or not candidate:
            issues.append(f"{field}_PATH_INVALID")
            continue
        rel = Path(candidate)
        if rel.is_absolute() or ".." in rel.parts or "\\" in candidate:
            issues.append(f"{field}_PATH_UNSAFE")
            continue
        absolute = (profile_dir / rel).resolve()
        if not absolute.is_relative_to(profile_dir.resolve()) or not absolute.is_file():
            issues.append(f"{field}_SOURCE_UNRESOLVED")
    issues = sorted(set(issues))
    return {"status": "PASS" if not issues else "FAIL", "valid": not issues,
            "issues": issues, "check_source": "TRUSTED_RUNTIME_BINDING_STATIC_INSPECTION",
            "model_run_executed": False,
            "binding_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def _load_evaluator(trusted_root: Path):
    path = trusted_root / EVALUATOR_REL
    spec = importlib.util.spec_from_file_location("trusted_s26_evaluator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # trusted code from the trusted root only
    return module


def _has_symlink(root: Path) -> bool:
    return any(p.is_symlink() for p in [root, *root.rglob("*")])


def _tree_seed(directory: Path) -> str:
    """Seed derived from the candidate tree: base and candidate share it, and it is unknown before the change exists."""
    h = hashlib.sha256()
    for p in sorted(directory.rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(directory)).encode() + b"\0" + p.read_bytes() + b"\0")
    return h.hexdigest()


def _evaluate(evaluator, trusted_root: Path, slug: str, profile_dir: Path, seed: str | None = None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="s26-proof-") as tmp:
        root = Path(tmp)
        (root / BASELINE_REL).parent.mkdir(parents=True)
        shutil.copyfile(trusted_root / BASELINE_REL, root / BASELINE_REL)
        (root / "profiles").mkdir()
        shutil.copytree(profile_dir, root / "profiles" / slug, symlinks=False)
        return evaluator.evaluate(root, slug, seed=seed)


def compare(trusted_root: Path, slug: str, base_dir: Path, candidate_dir: Path,
            operational_root: Path | None = None) -> dict[str, Any]:
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
    seed = _tree_seed(candidate_dir)
    result["adversarial_seed_sha256"] = hashlib.sha256(seed.encode()).hexdigest()
    base = _evaluate(evaluator, trusted_root, slug, base_dir, seed)
    cand = _evaluate(evaluator, trusted_root, slug, candidate_dir, seed)
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
    # Group 2 (operational cases): trusted cases and runs from the trusted root, bound to the exact trees.
    operational = opc.evaluate(operational_root or trusted_root / opc.OPERATIONAL_REL, slug, base_dir, candidate_dir)
    result["operational"] = operational
    base_binding = runtime_validator_binding_check(base_dir, slug)
    candidate_binding = runtime_validator_binding_check(candidate_dir, slug)
    result["runtime_validator_binding"] = {"base": base_binding, "candidate": candidate_binding}
    binding_improved = base_binding["status"] == "FAIL" and candidate_binding["status"] == "PASS"
    basis = ((["STRUCTURAL_S26"] if improved else [])
             + (["OPERATIONAL_COVERAGE"] if operational["improved_checks"] else [])
             + (["RUNTIME_VALIDATOR_BINDING"] if binding_improved else []))
    if candidate_binding["status"] == "FAIL":
        result["blocking_codes"].append("CANDIDATE_RUNTIME_VALIDATOR_BINDING_INVALID")
        result["verdict"] = "BLOCKED"
    elif operational.get("candidate_validator_schema_contradictions"):
        result["blocking_codes"].append("CANDIDATE_VALIDATOR_SCHEMA_CONTRADICTION")
        result["verdict"] = "BLOCKED"
    elif regressed or operational["regressed_checks"]:
        result["verdict"] = "REGRESSION"
    elif basis:
        result["verdict"] = "EVOLUTION_DEMONSTRATED"
        result["evolution_basis"] = basis
    else:
        result["verdict"] = "NO_DEMONSTRATED_IMPROVEMENT"
    return _seal(result)


def measure(trusted_root: Path, slug: str, profile_dir: Path, operational_root: Path | None = None) -> dict[str, Any]:
    """Baseline measurement of one profile tree with the trusted evaluator (no comparison)."""
    trusted_root = trusted_root.resolve()
    result: dict[str, Any] = {"schema": "S26_PROFILE_MEASUREMENT_V1", "profile_slug": slug, "blocking_codes": []}
    if not profile_dir.is_dir():
        result["blocking_codes"].append("PROFILE_DIR_MISSING")
    elif _has_symlink(profile_dir):
        result["blocking_codes"].append("PROFILE_SYMLINK_FORBIDDEN")
    if result["blocking_codes"]:
        result["decision"] = "BLOCKED"
        return _seal(result)
    ev = _evaluate(_load_evaluator(trusted_root), trusted_root, slug, profile_dir, _tree_seed(profile_dir))
    if ev.get("blocking_codes") and not ev.get("dimensions"):
        result["blocking_codes"].extend(ev["blocking_codes"])
        result["decision"] = "BLOCKED"
        return _seal(result)
    result.update({
        "score": ev["score"], "required": ev["required"], "decision": ev["decision"],
        "failed_dimensions": sorted(d for d, v in ev["dimensions"].items() if not v["pass"]),
    })
    # Group 2: a structurally complete profile still needs an update while a trusted business-case check
    # recorded for this exact tree is unmet. Without bound runs nothing changes.
    operational = opc.unmet(operational_root or trusted_root / opc.OPERATIONAL_REL, slug, profile_dir)
    binding_check = runtime_validator_binding_check(profile_dir, slug)
    result["runtime_validator_binding"] = binding_check
    real_operational_unmet = bool(operational.get("unmet_checks"))
    if binding_check["status"] == "FAIL":
        operational = dict(operational)
        operational["unmet_checks"] = sorted(set(operational.get("unmet_checks", [])) | {
            "RUNTIME_VALIDATOR_BINDING:" + issue for issue in binding_check["issues"]
        })
        operational["runtime_binding_check_source"] = "TRUSTED_STATIC_CONTRACT_NOT_MODEL_EVAL"
    if operational["status"] != "NOT_APPLICABLE" or binding_check["status"] == "FAIL":
        result["operational"] = operational
        if result["decision"] == "NO_UPDATE_REQUIRED" and operational["unmet_checks"]:
            result["decision"] = "UPDATE_REQUIRED"
            result["update_basis"] = (["OPERATIONAL_COVERAGE"] if real_operational_unmet else []) + (
                ["RUNTIME_VALIDATOR_BINDING"] if binding_check["status"] == "FAIL" else [])
    return _seal(result)


def _seal(result: dict[str, Any]) -> dict[str, Any]:
    body = json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
    result["proof_sha256"] = hashlib.sha256(body).hexdigest()
    return result


def main() -> int:
    if len(sys.argv) == 5 and sys.argv[1] == "measure":
        out = measure(Path(sys.argv[3]), sys.argv[2], Path(sys.argv[4]))
        print(json.dumps(out, indent=2, sort_keys=True))
        return 0 if not out["blocking_codes"] else 1
    if len(sys.argv) != 5:
        print("usage: compare_s26_profile_evolution_v1.py <slug> <trusted_root> <base_profile_dir> <candidate_profile_dir> | measure <slug> <trusted_root> <profile_dir>", file=sys.stderr)
        return 2
    out = compare(Path(sys.argv[2]), sys.argv[1], Path(sys.argv[3]), Path(sys.argv[4]))
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["verdict"] == "EVOLUTION_DEMONSTRATED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
