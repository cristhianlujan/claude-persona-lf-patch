#!/usr/bin/env python3
"""M9.0 DRIFT_NEGATIVE: any drift (Edge != main, or a remote migration without Git) must block the freeze.

Re-runs the parity judge of ENG_M9_0_PARITY_GIT_RUNTIME (same directory) over mutated COPIES of the live authority snapshot.
The unmutated snapshot must pass; every mutation must be blocked with the expected problem code. No database or repository writes.
"""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path

TEST_CODE = "ENG_M9_0_DRIFT_NEGATIVE"


def load_judge():
    spec = importlib.util.spec_from_file_location("parity_git_runtime", Path(__file__).with_name("parity_git_runtime.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(authority: dict, repo: Path) -> dict:
    m = load_judge()
    files = m.index_repo(repo)
    ok0, _ = m.judge(authority, files, repo)
    cases = []

    def expect(name, auth, code, files_override=None):
        ok, detail = m.judge(auth, files_override if files_override is not None else files, repo)
        codes = {p[0] for p in detail.get("problems", [])} | ({detail["reason"]} if "reason" in detail else set())
        cases.append({"case": name, "blocked": (not ok) and code in codes, "expected": code, "got": sorted(codes)})

    # 1 Edge deployed index.ts differs from main (stale deploy, exactly the pre-v13 curator situation)
    a = copy.deepcopy(authority)
    a["edge_functions"][1]["deployed_index_sha256"] = "0" * 63 + "1"
    expect("EDGE_NE_MAIN_CURATOR", a, "EDGE_DEPLOYED_NOT_EQUAL_GIT")
    # 2 Edge function missing from the inventory
    a = copy.deepcopy(authority)
    a["edge_functions"] = a["edge_functions"][:2]
    expect("EDGE_INVENTORY_MISSING_VALIDATOR", a, "EDGE_INVENTORY_INCOMPLETE")
    # 3 remote migration without a Git file
    a = copy.deepcopy(authority)
    a["migrations"].insert(0, ["29991231235959", "ig_remote_only_unversioned_probe", "a" * 64, "b" * 64])
    expect("REMOTE_MIGRATION_WITHOUT_GIT", a, "REMOTE_WITHOUT_GIT")
    # 4 Git file removed for an applied remote migration
    files2 = {k: v for k, v in files.items() if k != "ig_cv_m1a1_contract_asset_registry_v1"}
    expect("GIT_FILE_REMOVED", authority, "REMOTE_WITHOUT_GIT", files2)
    # 5 remote content changed (exact row no longer matches Git, normalized sha also differs)
    a = copy.deepcopy(authority)
    a["migrations"][-1][2] = "c" * 64
    a["migrations"][-1][3] = "d" * 64
    expect("REMOTE_CONTENT_CHANGED", a, "UNADJUDICATED_FORMAT_DIVERGENCE")
    # 6 version skew without adjudication
    a = copy.deepcopy(authority)
    a["adjudicated"] = {"version_skew": []}
    expect("UNADJUDICATED_VERSION_SKEW", a, "UNADJUDICATED_VERSION_SKEW")
    # 7 runtime authority no longer current
    a = copy.deepcopy(authority)
    a["capabilities"] = [c for c in a["capabilities"] if c != "RUNTIME_DEPLOY_VERIFICATION"]
    expect("RUNTIME_DEPLOY_VERIFICATION_NOT_CURRENT", a, "RUNTIME_AUTHORITY_NOT_CURRENT")
    # 8 invalid / foreign authority
    a = copy.deepcopy(authority)
    a["source"] = "FIXTURE"
    expect("AUTHORITY_NOT_LIVE", a, "AUTHORITY_INVALID")
    return {"test": TEST_CODE, "baseline_passes": ok0, "cases": cases,
            "adversarial_case_executed": len(cases) == 8,
            "all_blocked": all(c["blocked"] for c in cases)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--authority-json", required=True)
    ap.add_argument("--repo", default=".")
    a = ap.parse_args()
    out = run(json.loads(Path(a.authority_json).read_text()), Path(a.repo))
    print(json.dumps(out, sort_keys=True))
    return 0 if (out["baseline_passes"] and out["all_blocked"] and out["adversarial_case_executed"]) else 1


if __name__ == "__main__":
    sys.exit(main())
