#!/usr/bin/env python3
"""Verify exact inventory, hashes and executable gates for the P0 integration candidate."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "manifest.candidate.json"
ARCHITECTURE_SHA256 = "a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531"
CANONICALIZER_SHA256 = "99952f4a1c0819bfc6a7488bea595b43ff31697a0c5ffe034c3e7ea76cde930f"
GATES = [
    ["validate_p0_contracts.py", "--self-test"],
    ["admit_p0_image.py", "--self-test"],
    ["validate_p0_security.py", "--self-test"],
    ["validate_p0_visual_output.py", "--self-test"],
    ["validate_p0_judge.py", "--self-test"],
    ["validate_p0_human_binding.py", "--self-test"],
    ["validate_p0_j02_handoff.py", "--self-test"],
    ["adapt_p0_to_screen_decomposer.py", "--self-test"],
    ["smoke_p0_j02.py"],
    ["run_p0_visual_worker.py", "--self-test"],
    ["build_p0_review_evidence_packet.py", "--self-test"],
    ["report_p0_metric_denominators.py", "--self-test"],
    ["report_p0_metric_denominators.py"],
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    rows = manifest.get("files", [])
    declared = {row["path"]: row for row in rows if isinstance(row, dict) and isinstance(row.get("path"), str)}
    actual_paths = []
    symlinks = []
    for path in ROOT.rglob("*"):
        if path == MANIFEST or path.is_dir():
            continue
        rel = path.relative_to(ROOT).as_posix()
        if path.is_symlink():
            symlinks.append(rel)
        elif "__pycache__" not in path.parts and not path.name.endswith(".pyc"):
            actual_paths.append(rel)
    actual = set(actual_paths)
    declared_set = set(declared)
    mismatches = []
    for rel in sorted(actual & declared_set):
        path = ROOT / rel
        row = declared[rel]
        if path.stat().st_size != row.get("bytes") or sha256(path) != row.get("sha256"):
            mismatches.append(rel)
    canonicalizer = ROOT / "P0_RFC8785_CANONICALIZER_v1.1.mjs"
    gate_results = []
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    for script, *args in GATES:
        proc = subprocess.run([sys.executable, str(ROOT / "scripts" / script), *args], text=True, capture_output=True, env=env)
        gate_results.append({"gate": script, "exit_code": proc.returncode, "last_line": proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else proc.stderr.strip()[-500:]})
    checks = {
        "inventory_exact": actual == declared_set,
        "hashes_exact": not mismatches,
        "symlink_count_zero": not symlinks,
        "architecture_source_pinned": manifest.get("architecture_source_sha256") == ARCHITECTURE_SHA256,
        "canonicalizer_identity_exact": canonicalizer.is_file() and sha256(canonicalizer) == CANONICALIZER_SHA256,
        "all_gates_pass": all(row["exit_code"] == 0 for row in gate_results),
    }
    passed = all(checks.values())
    report = {
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
        "checks": checks,
        "declared_file_count": len(declared_set),
        "actual_file_count": len(actual),
        "missing": sorted(declared_set - actual),
        "unexpected": sorted(actual - declared_set),
        "hash_mismatches": mismatches,
        "symlinks": symlinks,
        "gate_results": gate_results,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
