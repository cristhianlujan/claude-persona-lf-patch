#!/usr/bin/env python3
"""Versioned dispatcher for the read-only A01-A62 continuous audit.

Preserves the historical auditor byte-for-byte in r8_continuous_audit_legacy_v01.py
and resolves J11 runtime validation from the candidate manifest instead of
hardcoding validate_package.py v1.2.
"""
from __future__ import annotations
from pathlib import Path
import sys
import yaml
import r8_continuous_audit_legacy_v01 as legacy

_orig_suite = legacy.suite


def suite(root: Path, tmp: Path):
    results = _orig_suite(root, tmp)
    manifest = yaml.safe_load((root / "manifest.yaml").read_text(encoding="utf-8")) or {}
    configured = (
        manifest.get("maturity_extension", {})
        .get("package_gate_candidate", {})
        .get("validator")
    )
    relative = str(configured or "scripts/validate_package.py")
    if not relative.startswith("scripts/"):
        raise SystemExit(f"FAIL_J11_VALIDATOR_PATH_OUTSIDE_SKILL_SCRIPTS: {relative}")
    validator = root / relative
    if not validator.is_file():
        raise SystemExit(f"FAIL_J11_VALIDATOR_MISSING: {relative}")
    env = {"LF_JUDGE_VERSION": "v0.6", "LF_EXECUTOR_IDENTITY": legacy.EXEC}
    results["j11"] = [
        legacy.run(
            "j11_selftest",
            [sys.executable, str(validator), "--self-test"],
            root,
            (0,),
            env,
        ),
        legacy.run(
            "j11_package",
            [sys.executable, str(validator), str(root), "--evidence-ref", "continuous"],
            root,
            (0,),
            env,
        ),
    ]
    results["all"] = [item for key, group in results.items() if key != "all" for item in group]
    return results


legacy.suite = suite

if __name__ == "__main__":
    raise SystemExit(legacy.main())
