#!/usr/bin/env python3
"""F04-Q99 terminal scenario qualification over the complete CUTOVER control set.

Qualification-only. No activation, cutover, deploy, DB mutation, or legacy retirement.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CATALOG_PATH = HERE / "pase_scenario_catalog_v1.json"
QUALIFIER_PATH = HERE / "pase_scenario_qualification_v1.py"
PROFILE_DIR = HERE / "profiles"
HEX40 = re.compile(r"^[0-9a-f]{40}$")

PROFILES = [
    ("PASE-ATOM-F04-Q01", "contract_validation_v1.json"),
    ("PASE-ATOM-F04-Q02", "pack_validation_harness_v1.json"),
    ("PASE-ATOM-F04-Q03", "visual_evidence_gate_v1.json"),
    ("PASE-ATOM-F04-Q04", "assurance_evaluator_v1.json"),
    ("PASE-ATOM-F04-Q05", "runtime_deploy_verification_v1.json"),
    ("PASE-ATOM-F04-Q06", "full_regression_v1.json"),
    ("PASE-ATOM-F04-Q07", "migration_source_parity_v1.json"),
    ("PASE-ATOM-F04-Q08", "currentness_authority_v1.json"),
    ("PASE-ATOM-F04-Q09", "evidence_stack_v1.json"),
    ("PASE-ATOM-F04-Q10", "gate_check_observability_v1.json"),
    ("PASE-ATOM-F04-Q11", "source_fidelity_exact_head_v1.json"),
]

EXPECTED_CHANGED_PATHS = {
    ".github/workflows/lf-f04-q99-terminal-scenario-profiles.yml",
    "sandbox/lf_contract_gate_test/pase_scenario_qualification/run_f04_terminal_scenario_profiles_v1.py",
    *{
        f"sandbox/lf_contract_gate_test/pase_scenario_qualification/profiles/{name}"
        for _, name in PROFILES
        if name not in {"contract_validation_v1.json", "migration_source_parity_v1.json"}
    },
}


def fail(code: str, detail: str = "") -> None:
    raise RuntimeError(f"{code}:{detail}" if detail else code)


def git(*args: str) -> str:
    p = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)
    if p.returncode != 0:
        fail("FAIL_F04_Q99_GIT", f"{args!r}:{p.stderr[-1200:]}")
    return p.stdout.strip()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail("FAIL_F04_Q99_MODULE_LOAD", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def require_sha(value: str, label: str) -> str:
    value = value.strip().lower()
    if not HEX40.fullmatch(value):
        fail(f"FAIL_F04_Q99_{label}_SHA", value)
    return value


def write_runtime(runtime: Path, *, base_sha: str, head_sha: str) -> None:
    runtime.mkdir(parents=True, exist_ok=True)
    (runtime / "scope-manifest.json").write_text(
        json.dumps(
            {
                "schema_version": "lf-pase-evaluation-scope-manifest/v1",
                "policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
                "control_maturity": "CUTOVER",
                "evaluation_scope": "CHANGESET_SCOPED",
                "historical_debt_disposition": "RECONCILIATION_WORK_ITEM",
                "base_sha": base_sha,
                "head_sha": head_sha,
                "unbounded_historical_scan": False,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    (runtime / "run-summary.json").write_text(
        json.dumps(
            {
                "schema_version": "lf-f04-terminal-scenario-scope-run/v1",
                "policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
                "control_maturity": "CUTOVER",
                "evaluation_scope": "CHANGESET_SCOPED",
                "historical_debt_disposition": "RECONCILIATION_WORK_ITEM",
                "unbounded_historical_scan": False,
                "status": "PASS",
                "returncode": 0,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def verify_exact_candidate(base_sha: str, head_sha: str) -> list[str]:
    actual = require_sha(git("rev-parse", "HEAD"), "ACTUAL_HEAD")
    if actual != head_sha:
        fail("FAIL_F04_Q99_EXACT_HEAD", f"expected={head_sha} actual={actual}")
    git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
    live_main = require_sha(git("rev-parse", "refs/remotes/origin/main"), "LIVE_MAIN")
    if live_main != base_sha:
        fail("FAIL_F04_Q99_BASE_CURRENTNESS", f"expected={base_sha} live={live_main}")
    merge_base = require_sha(git("merge-base", base_sha, head_sha), "MERGE_BASE")
    if merge_base != base_sha:
        fail("FAIL_F04_Q99_BASE_NOT_ANCESTOR", f"base={base_sha} merge_base={merge_base}")
    changed = sorted(
        line.strip()
        for line in git("diff", "--name-only", base_sha, head_sha).splitlines()
        if line.strip()
    )
    unexpected = sorted(set(changed) - EXPECTED_CHANGED_PATHS)
    missing = sorted(EXPECTED_CHANGED_PATHS - set(changed))
    if unexpected:
        fail("FAIL_F04_Q99_OUT_OF_SCOPE_DIFF", ",".join(unexpected))
    if missing:
        fail("FAIL_F04_Q99_SCOPE_INCOMPLETE", ",".join(missing))
    return changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-sha", required=True)
    ap.add_argument("--head-sha", required=True)
    ap.add_argument("--output-dir", default=".f04-q99-scenario-results")
    args = ap.parse_args()

    base_sha = require_sha(args.base_sha, "BASE")
    head_sha = require_sha(args.head_sha, "HEAD")
    if base_sha == head_sha:
        fail("FAIL_F04_Q99_EMPTY_RANGE")

    changed = verify_exact_candidate(base_sha, head_sha)
    qualifier = load_module(QUALIFIER_PATH, "f04_q99_scenario_qualifier")
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    out_root = (ROOT / args.output_dir).resolve()
    try:
        out_root.relative_to(ROOT)
    except ValueError as exc:
        raise RuntimeError("FAIL_F04_Q99_OUTPUT_OUTSIDE_REPO") from exc

    results = []
    total_selected = 0
    total_na = 0
    for unit_code, profile_name in PROFILES:
        profile = json.loads((PROFILE_DIR / profile_name).read_text(encoding="utf-8"))
        runtime = out_root / unit_code
        write_runtime(runtime, base_sha=base_sha, head_sha=head_sha)
        result = qualifier.qualify(
            root=ROOT,
            catalog=catalog,
            profile=profile,
            maturity="CUTOVER",
            base_sha=base_sha,
            head_sha=head_sha,
            runtime_dir=runtime,
        )
        if result["verdict"] != "PASS":
            fail("BLOCK_F04_Q99_PROFILE_VERDICT", f"{unit_code}:{result['verdict']}")
        if result["unknown_selected_count"] != 0:
            fail("BLOCK_F04_Q99_UNKNOWN_SELECTED", f"{unit_code}:{result['unknown_selected_count']}")
        if result["selected_count"] <= 0:
            fail("BLOCK_F04_Q99_EMPTY_SELECTED_SET", unit_code)
        (runtime / "scenario-qualification.json").write_text(
            json.dumps(result, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        total_selected += result["selected_count"]
        total_na += result["not_applicable_count"]
        results.append(
            {
                "unit_code": unit_code,
                "control_id": result["control_id"],
                "selected_count": result["selected_count"],
                "not_applicable_count": result["not_applicable_count"],
                "unknown_selected_count": result["unknown_selected_count"],
                "verdict": result["verdict"],
                "profile_sha256": result["profile_sha256"],
            }
        )
        print(
            f"PASS_F04_TERMINAL_PROFILE unit={unit_code} "
            f"control={result['control_id']} selected={result['selected_count']} "
            f"not_applicable={result['not_applicable_count']} unknown=0"
        )

    summary = {
        "schema_version": "lf-f04-terminal-scenario-qualification-summary/v1",
        "policy_id": "PASE_SCENARIO_QUALIFICATION_MATRIX_V1",
        "scope_policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
        "maturity": "CUTOVER",
        "evaluation_scope": "CHANGESET_SCOPED",
        "historical_debt_disposition": "RECONCILIATION_WORK_ITEM",
        "base_sha": base_sha,
        "head_sha": head_sha,
        "changed_paths": changed,
        "control_count": len(results),
        "selected_count": total_selected,
        "not_applicable_count": total_na,
        "unknown_selected_count": 0,
        "zip_used_as_authority": False,
        "activation_authorized": False,
        "runtime_or_production_touched": False,
        "results": results,
        "verdict": "PASS",
    }
    out_root.mkdir(parents=True, exist_ok=True)
    (out_root / "summary.json").write_text(
        json.dumps(summary, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"PASS_F04_TERMINAL_SCENARIO_PROFILES={len(results)}/{len(PROFILES)} "
        f"selected={total_selected} not_applicable={total_na} unknown=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
