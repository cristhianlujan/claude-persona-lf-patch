#!/usr/bin/env python3
"""Strategy 28 fire-test harness for the sandbox CI tier router.

This harness evaluates safety and optimization separately:
- false FAST is a hard failure;
- false DEEP is recorded as an optimization gap, not promoted automatically.
It never replaces the existing contract/parity/bootstrap gates.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import time
from dataclasses import dataclass

from s28_ci_feedback_tier import classify


@dataclass(frozen=True)
class Case:
    case_id: str
    family: str
    paths: tuple[str, ...]
    final_evidence: bool
    safety: str
    target_tier: str
    note: str


LOT_A = (
    Case("A01","F01_PROFILE_ONLY",("profiles/ui_architect/profile.yaml",),False,"FAST_ALLOWED","FAST","single profile yaml"),
    Case("A02","F01_PROFILE_ONLY",("profiles/story_creator/profile.yaml",),False,"FAST_ALLOWED","FAST","single profile contract source"),
    Case("A03","F01_PROFILE_ONLY",("profiles/ui_architect/README.md",),False,"FAST_ALLOWED","FAST","profile documentation inside governed package"),
    Case("A04","F01_PROFILE_ONLY",("profiles/a/profile.yaml","profiles/b/profile.yaml"),False,"FAST_ALLOWED","FAST","two profile packages"),
    Case("A05","F01_PROFILE_ONLY",("profiles/a/tests/case.yaml",),False,"FAST_ALLOWED","FAST","profile-local deterministic test data"),
    Case("A06","F01_PROFILE_ONLY",("profiles/a/profile.yaml","profiles/a/README.md"),False,"FAST_ALLOWED","FAST","profile source plus local documentation"),
    Case("A07","F02_CARD_SKILL_ADAPTER",("cards/client_screen/card.yaml",),False,"FAST_ALLOWED","FAST","card-only iterative source candidate"),
    Case("A08","F02_CARD_SKILL_ADAPTER",("skills/story_creator/skill.md",),False,"FAST_ALLOWED","FAST","skill-only iterative source candidate"),
    Case("A09","F02_CARD_SKILL_ADAPTER",("adapters/router/profile_binding.yaml",),False,"DEEP_REQUIRED","DEEP","adapter binding can alter routing/runtime behavior"),
    Case("A10","F02_CARD_SKILL_ADAPTER",("adapters/input_governance/adapter.yaml","profiles/a/profile.yaml"),False,"DEEP_REQUIRED","DEEP","adapter plus profile mixed behavior"),
    Case("A11","F03_DOCS_EKB",("docs/audits/strategy28.md",),False,"FAST_ALLOWED","FAST","documentation-only"),
    Case("A12","F03_DOCS_EKB",("docs/ekb/ci-fast-deep-feedback.md",),False,"FAST_ALLOWED","FAST","EKB documentation-only Git source"),
    Case("A13","F08_CI_WORKFLOW",(".github/workflows/lf-contract-check.yml",),False,"DEEP_REQUIRED","DEEP","required CI workflow"),
    Case("A14","F08_CI_WORKFLOW",(".github/workflows/lf-bootstrap-reproducibility.yml",),False,"DEEP_REQUIRED","DEEP","bootstrap workflow"),
    Case("A15","F08_CI_WORKFLOW",(".github/actions/lf-helper/action.yml",),False,"DEEP_REQUIRED","DEEP","composite action control surface"),
    Case("A16","F08_CI_WORKFLOW",(".github/workflows/new-fast-gate.yml","profiles/a/profile.yaml"),False,"DEEP_REQUIRED","DEEP","workflow plus profile"),
    Case("A17","F08_CI_WORKFLOW",(".github/dependabot.yml",),False,"DEEP_REQUIRED","DEEP","automation configuration"),
    Case("A18","F08_CI_WORKFLOW",(".github/CODEOWNERS",),False,"DEEP_REQUIRED","DEEP","governance/control configuration"),
    Case("A19","F11_MIXED_SURFACE",("profiles/a/profile.yaml","docs/audits/a.md"),False,"FAST_ALLOWED","FAST","two explicitly low-impact surfaces"),
    Case("A20","F11_MIXED_SURFACE",("profiles/a/profile.yaml","supabase/migrations/20260904000000_x.sql"),False,"DEEP_REQUIRED","DEEP","profile plus schema"),
    Case("A21","F11_MIXED_SURFACE",("docs/audits/a.md",".github/workflows/x.yml"),False,"DEEP_REQUIRED","DEEP","docs plus CI control"),
    Case("A22","F12_UNKNOWN_FINAL",("unmapped/new-area/file.txt",),False,"DEEP_REQUIRED","DEEP","unknown surface"),
    Case("A23","F12_UNKNOWN_FINAL",tuple(),False,"DEEP_REQUIRED","DEEP","no changed paths fail closed"),
    Case("A24","F12_UNKNOWN_FINAL",("docs/audits/final.md",),True,"DEEP_REQUIRED","DEEP","final evidence override"),
)


def run_lot(cases: tuple[Case, ...]) -> dict[str, object]:
    rows = []
    false_fast = 0
    false_deep = 0
    decision_mismatch = 0
    nondeterministic = 0
    timings_ns: list[int] = []

    for case in cases:
        decisions = [classify(case.paths, final_evidence=case.final_evidence) for _ in range(3)]
        if len({json.dumps(d.as_dict(), sort_keys=True) for d in decisions}) != 1:
            nondeterministic += 1
        decision = decisions[0]
        if case.safety == "DEEP_REQUIRED" and decision.tier == "FAST":
            false_fast += 1
        if case.target_tier == "FAST" and decision.tier == "DEEP":
            false_deep += 1
        if decision.tier != case.target_tier:
            decision_mismatch += 1
        for _ in range(100):
            start = time.perf_counter_ns()
            classify(case.paths, final_evidence=case.final_evidence)
            timings_ns.append(time.perf_counter_ns() - start)
        rows.append({"case_id":case.case_id,"family":case.family,"safety":case.safety,"target_tier":case.target_tier,"actual_tier":decision.tier,"reason":decision.reason,"note":case.note})

    sorted_ns = sorted(timings_ns)
    p95_idx = max(0, min(len(sorted_ns)-1, int(len(sorted_ns)*0.95)-1))
    summary = {
        "cases":len(cases),"false_fast":false_fast,"false_deep":false_deep,"decision_mismatch":decision_mismatch,
        "nondeterministic":nondeterministic,"hard_gate_pass":false_fast == 0 and nondeterministic == 0,
        "classifier_benchmark":{"samples":len(timings_ns),"median_us":round(statistics.median(timings_ns)/1000,3),"p95_us":round(sorted_ns[p95_idx]/1000,3),"scope":"classifier-only; excludes checkout/runner/network/external validators"},
    }
    return {"summary":summary,"rows":rows}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lot", default="A")
    args = parser.parse_args()
    if args.lot != "A":
        raise SystemExit("ONLY_LOT_A_MATERIALIZED_IN_THIS_INCREMENT")
    report = run_lot(LOT_A)
    print("S28_FIRE_TEST_REPORT=" + json.dumps(report, sort_keys=True))
    s = report["summary"]
    print(f"PASS_S28_FIRE_TEST_LOT_A={s['cases'] - s['false_fast']}/{s['cases']} FALSE_FAST={s['false_fast']} FALSE_DEEP={s['false_deep']} NONDETERMINISTIC={s['nondeterministic']}")
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path,"a",encoding="utf-8") as handle:
            handle.write("### Strategy 28 — Fire Test Lot A\n")
            handle.write(f"- cases: `{s['cases']}`\n- false FAST: `{s['false_fast']}`\n- false DEEP / optimization gaps: `{s['false_deep']}`\n- nondeterministic: `{s['nondeterministic']}`\n")
            handle.write(f"- classifier median: `{s['classifier_benchmark']['median_us']} us`\n- classifier p95: `{s['classifier_benchmark']['p95_us']} us`\n")
            handle.write("- false DEEP does not fail safety; it identifies candidates requiring domain evidence before FAST promotion.\n")
    return 0 if s["hard_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
