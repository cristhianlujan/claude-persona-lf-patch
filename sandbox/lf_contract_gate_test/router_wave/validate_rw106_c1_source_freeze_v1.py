#!/usr/bin/env python3
"""Validate RW1-06 C1 preregistered source, policy, and three local negative controls.

This is deterministic source-policy assurance only: it does not create hidden
holdouts, execute a provider, attest reviewer independence, or close RW1-06_C1.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOC = ROOT / "docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json"
EXPECTED_SNAPSHOT = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
EXPECTED_PLAN = "LF_ROUTER_ARCHITECTURE_WAVE_V1"
SOURCE_PATHS = {
    "docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md",
    "docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md",
    "docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json",
    "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
    "docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md",
    "docs/programming-agent/router_wave/RW1_05_C3_REVIEW_CAPTURE_V1.json",
}


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)


def git_tree_blob(path: str) -> str:
    return subprocess.check_output(
        ["git", "rev-parse", f"HEAD:{path}"], cwd=ROOT, text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def validate(d: dict, *, source_check: bool = True) -> None:
    require(d.get("schema_version") == "RW106_C1_SOURCE_POLICY_FREEZE_V1", "WRONG_SCHEMA")
    require(d.get("plan_code") == EXPECTED_PLAN, "CROSS_PROJECT")
    require(d.get("unit_code") == "RW1-06" and d.get("checkpoint_code") == "RW1-06_C1", "WRONG_CP")
    require(d.get("source_snapshot_commit") == EXPECTED_SNAPSHOT, "STALE_SOURCE_SNAPSHOT")
    require(d.get("status") == "CANDIDATE_FOR_GOVERNED_BINDING_NOT_C1_DONE", "FALSE_READY")
    require(d.get("no_lifecycle_transition_in_this_artifact") is True, "EARLY_CLOSE")
    blobs = d.get("source_blobs")
    require(isinstance(blobs, dict) and set(blobs) == SOURCE_PATHS, "MISSING_SOURCE")
    for path, sha in blobs.items():
        require(bool(re.fullmatch(r"[0-9a-f]{40}", sha)), "BAD_BLOB_SHA")
        if source_check:
            try:
                found = git_tree_blob(path)
            except subprocess.CalledProcessError as ex:
                raise ValueError("MISSING_GIT_SOURCE") from ex
            require(found == sha, "STALE_SOURCE_BLOB")
    fam = d.get("test_families", [])
    require(len(fam) == 13 and {x.get("id") for x in fam} == {f"F{i:02d}" for i in range(1, 14)}, "FAMILY_SCOPE")
    h = d.get("holdout_protocol", {})
    require(h.get("status") == "NOT_GENERATED_NOT_COMMITTED", "FALSE_HOLDOUT_CLAIM")
    require(h.get("minimum") == {"valid": 12, "invalid": 24, "novel_falsifiers": 2}, "HOLDOUT_THRESHOLDS")
    require(h.get("reviewer_role") == "not implementer or checker author", "NONINDEPENDENT_REVIEW")
    limits = d.get("limitations", {})
    for key in ("provider_attested", "independent_review", "independent_holdout_frozen",
                "production_activation", "runtime_activation", "golden_promoted",
                "c1_checkpoint_done"):
        require(limits.get(key) is False, "UNSUPPORTED_COMPLETION_CLAIM")
    negatives = d.get("required_negative_controls", {})
    require(negatives.get("C1") == ["missing_source", "stale_source", "cross_project"], "MISSING_NEGATIVES")
    gates = d.get("decision_gates", {})
    require(gates.get("verdicts") == ["PASS", "FAIL", "GAP"], "VERDICT_ENUM")
    require(gates.get("overhead", {}).get("numeric_budget") == "UNDEFINED_BY_CURRENT_AUTHORITY_GAP_NOT_PASS",
            "FABRICATED_SLO")


def self_test(good: dict) -> None:
    validate(good)
    failures = {}
    for test in ("missing_source", "stale_source", "cross_project"):
        bad = copy.deepcopy(good)
        if test == "missing_source":
            bad["source_blobs"].pop(sorted(SOURCE_PATHS)[0])
        elif test == "stale_source":
            bad["source_blobs"][sorted(SOURCE_PATHS)[0]] = "0" * 40
        else:
            bad["plan_code"] = "SALY_ROUTER_WAVE_V1"
        try:
            validate(bad)
        except ValueError as ex:
            failures[test] = str(ex)
        else:
            raise AssertionError(f"NEGATIVE_FALSE_ACCEPT:{test}")
    require(len(failures) == 3, "NEGATIVE_COVERAGE_INCOMPLETE")
    print(json.dumps({"local_freeze": "PASS", "negatives_rejected": failures,
                      "provider_attested": False, "independent_holdout": "PENDING",
                      "checkpoint_done": False}, sort_keys=True))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    good = json.loads(DOC.read_text(encoding="utf-8"))
    if args.self_test:
        self_test(good)
    else:
        validate(good)
        print("RW106_C1_SOURCE_POLICY_LOCAL_PASS_NOT_CHECKPOINT_DONE")


if __name__ == "__main__":
    main()
