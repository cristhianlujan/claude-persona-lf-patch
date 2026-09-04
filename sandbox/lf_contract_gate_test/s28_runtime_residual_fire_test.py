#!/usr/bin/env python3
from __future__ import annotations

import json
import time
from s28_ci_feedback_tier import classify

CASES = [
    # F07 Runtime / Worker / Edge — deep assurance is mandatory.
    ("C01", "F07_RUNTIME_WORKER_EDGE", ("supabase/functions/profile-runtime/index.ts",), False, "DEEP", "runtime edge function"),
    ("C02", "F07_RUNTIME_WORKER_EDGE", ("scripts/runtime/profile_worker.py",), False, "DEEP", "runtime worker script"),
    ("C03", "F07_RUNTIME_WORKER_EDGE", ("supabase/migrations/20260904000000_programacion_worker_spec_probe.sql",), False, "DEEP", "worker specification migration"),
    ("C04", "F07_RUNTIME_WORKER_EDGE", ("workers/profile-runtime/config.yaml",), False, "DEEP", "unmapped worker surface must fail closed"),
    ("C05", "F07_RUNTIME_WORKER_EDGE", ("profiles/ui_architect/profile.yaml", "supabase/functions/profile-runtime/index.ts"), False, "DEEP", "profile plus runtime"),
    ("C06", "F07_RUNTIME_WORKER_EDGE", ("docs/runtime/runbook.md", "scripts/runtime/profile_worker.py"), False, "DEEP", "docs plus runtime script"),

    # F02 remaining domain-boundary cases. These remain DEEP until a domain contract proves FAST safety.
    ("C13", "F02_CARD_SKILL_ADAPTER", ("cards/payment/card.yaml", "profiles/payment/profile.yaml"), False, "DEEP", "card plus profile remains unmapped/domain-bound"),
    ("C14", "F02_CARD_SKILL_ADAPTER", ("skills/story_creator/skill.yaml", "docs/story_creator.md"), False, "DEEP", "skill plus docs remains unmapped/domain-bound"),

    # F11 remaining mixed surfaces.
    ("C15", "F11_MIXED_SURFACE", ("profiles/profile_creator/profile.yaml", "scripts/runtime/worker.py"), False, "DEEP", "safe plus runtime must escalate"),
    ("C16", "F11_MIXED_SURFACE", ("docs/ekb/note.md", "cards/example/card.yaml"), False, "DEEP", "safe plus unmapped must fail closed"),

    # F12 remaining malformed/unsafe paths.
    ("C17", "F12_UNKNOWN_FINAL", ("../supabase/migrations/escape.sql",), False, "DEEP", "path traversal must fail closed"),
    ("C18", "F12_UNKNOWN_FINAL", ("/absolute/runtime/config.yaml",), False, "DEEP", "absolute path must fail closed"),
]


def main() -> int:
    rows = []
    false_fast = 0
    mismatch = 0
    nondeterministic = 0
    samples_ns: list[int] = []

    for case_id, family, paths, final_evidence, expected, note in CASES:
        observed = []
        reason = None
        for _ in range(100):
            started = time.perf_counter_ns()
            decision = classify(paths, final_evidence=final_evidence)
            samples_ns.append(time.perf_counter_ns() - started)
            observed.append((decision.tier, decision.reason, decision.deep_required))
            reason = decision.reason
        deterministic = len(set(observed)) == 1
        if not deterministic:
            nondeterministic += 1
        tier = observed[0][0]
        passed = tier == expected and deterministic
        if tier == "FAST" and expected == "DEEP":
            false_fast += 1
        if tier != expected:
            mismatch += 1
        rows.append({
            "case_id": case_id,
            "family": family,
            "expected": expected,
            "observed": tier,
            "reason": reason,
            "deterministic": deterministic,
            "pass": passed,
            "note": note,
        })

    sorted_ns = sorted(samples_ns)
    median_us = sorted_ns[len(sorted_ns)//2] / 1000
    p95_us = sorted_ns[int(len(sorted_ns)*0.95)-1] / 1000
    summary = {
        "cases": len(CASES),
        "false_fast": false_fast,
        "decision_mismatch": mismatch,
        "nondeterministic": nondeterministic,
        "hard_gate_pass": false_fast == 0 and mismatch == 0 and nondeterministic == 0,
        "classifier_benchmark": {
            "samples": len(samples_ns),
            "median_us": round(median_us, 3),
            "p95_us": round(p95_us, 3),
            "scope": "classifier-only; excludes runner/network/external validators",
        },
    }
    print("S28_FIRE_TEST_LOT_C_ROUTING_REPORT=" + json.dumps({"rows": rows, "summary": summary}, sort_keys=True))
    if not summary["hard_gate_pass"]:
        raise SystemExit("FAIL_S28_FIRE_TEST_LOT_C_ROUTING")
    print(f"PASS_S28_FIRE_TEST_LOT_C_ROUTING={len(CASES)}/{len(CASES)} FALSE_FAST={false_fast} NONDETERMINISTIC={nondeterministic}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
