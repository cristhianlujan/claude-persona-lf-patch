#!/usr/bin/env python3
"""CI source-attestation runner for the Analysis A1Q..A15Q C1 checkpoints.

Runs inside GitHub Actions on the exact main SHA. For each unit it
  1. recomputes the sha256 of the canonical source bytes by itself (not through the adapter),
  2. compares it with the sha256 committed earlier in ANALYSIS_QUALIFICATION_JUDGE_DOSSIER_V1.json,
  3. runs the unit adapter (receipt mechanics + stage structural validator + negative controls),
  4. checks the checkout is the exact commit the workflow was started on.
It prints one JSON document with the observed facts and the Actions run context. It never
touches a database, never reads a secret and never transitions a checkpoint.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DOSSIER = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_JUDGE_DOSSIER_V1.json"
UNITS = [f"A{n}" for n in range(1, 16)]
sys.path.insert(0, str(HERE))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def head_sha() -> str:
    return subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()


def attest_unit(unit: str, dossier: dict, main_sha: str, expected_sha: str | None) -> dict:
    n = int(unit[1:])
    entry = next(e for e in dossier["checkpoints"] if e["checkpoint_code"] == f"{unit}Q_C1")
    source = REPO / entry["canonical_source"]["path"]
    module = importlib.import_module(f"analysis_qualification_a{n}q_c1_source_attestation_v1")
    ci_sha = sha256_file(source)
    out = {"checkpoint_code": f"{unit}Q_C1", "canonical_source": entry["canonical_source"]["path"],
           "ci_computed_sha256": ci_sha, "dossier_sha256": entry["canonical_source"]["sha256"],
           "source_sha256_matches": ci_sha == entry["canonical_source"]["sha256"],
           "run_on_exact_main_sha": bool(expected_sha) and expected_sha == main_sha}
    if hasattr(module, "SPEC"):
        common = importlib.import_module("analysis_qualification_c1_source_attestation_common_v1")
        verdict = common.attest(module.SPEC, common.candidate_receipt(module.SPEC, main_sha), main_sha)
        selftest = common.selftest(module.SPEC, main_sha)
    else:  # A1 keeps its standalone adapter
        verdict = module.attest(module.candidate_receipt(main_sha), main_sha)
        buf = subprocess.run([sys.executable, "-I", module.__file__, "--main-sha", main_sha],
                             capture_output=True, text=True)
        selftest = buf.stdout.strip().splitlines()[-1] if buf.returncode == 0 and buf.stdout.strip() else "FAIL"
    out["stage_structure_validator_passed"] = verdict == "PASS_SOURCE_ATTESTATION_MECHANICS"
    out["selftest_negatives_passed"] = selftest.startswith("PASS_") and "negatives=" in selftest
    out["adapter_selftest"] = selftest
    out["all_passed"] = all(out[k] for k in ("source_sha256_matches", "run_on_exact_main_sha",
                                              "stage_structure_validator_passed",
                                              "selftest_negatives_passed"))
    return out


def run(units: list[str], dossier_path: Path, expected_sha: str | None) -> dict:
    dossier = json.loads(dossier_path.read_text(encoding="utf-8"))
    main_sha = head_sha()
    results = [attest_unit(u, dossier, main_sha, expected_sha) for u in units]
    return {"schema": "ANALYSIS_C1_CI_SOURCE_ATTESTATION_V1", "main_sha": main_sha,
            "ci_context": {k: os.environ.get(k) for k in (
                "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA", "GITHUB_WORKFLOW",
                "GITHUB_REPOSITORY", "GITHUB_EVENT_NAME", "GITHUB_ACTOR", "GITHUB_REF")},
            "results": results, "all_passed": all(r["all_passed"] for r in results),
            "boundary": "DETERMINISTIC_CI_RUN_NO_DB_NO_SECRETS_NO_TRANSITION"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--units", default=",".join(UNITS))
    parser.add_argument("--dossier", default=str(DOSSIER))
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run([u.strip() for u in args.units.split(",") if u.strip()], Path(args.dossier),
                 os.environ.get("GITHUB_SHA"))
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    print(text)
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
