#!/usr/bin/env python3
from __future__ import annotations

import json
from s28_ci_feedback_tier import classify

CASES = [
    ("E01", ("profilesx/ui/profile.yaml",), False, "DEEP", None, "lookalike FAST prefix"),
    ("E02", ("profiles/../supabase/migrations/escape.sql",), False, "DEEP", None, "path traversal into migration surface"),
    ("E03", ("profiles\\..\\.github\\workflows\\escape.yml",), False, "DEEP", None, "backslash traversal into control surface"),
    ("E04", ("profiles/ui/profile.yaml", "supabase/functions/runtime/index.ts"), False, "DEEP", None, "mixed safe plus runtime"),
    ("E05", ("docs/runbook.md", ".github/workflows/required.yml"), False, "DEEP", None, "mixed docs plus CI control"),
    ("E06", ("profiles/ui/profile.yaml",), True, "DEEP", None, "final evidence override"),
    ("E07", tuple(), False, "DEEP", None, "no changed paths"),
    ("E08", ("/profiles/ui/profile.yaml",), False, "DEEP", None, "absolute path"),
    ("E09", ("skills/story_creator/skill.yaml",), False, "DEEP", None, "unmapped skill surface"),
    ("E10", ("cards/example/card.yaml",), False, "DEEP", None, "unmapped card surface"),
    ("E11", ("workers/runtime/config.yaml",), False, "DEEP", None, "unmapped worker surface"),
    # Critical adversarial case: path is normally FAST, but an external currentness signal says source/runtime mismatch.
    # The current classifier has no context input for that signal; expected DEEP proves whether path-only routing is sufficient.
    ("E12", ("profiles/ui/profile.yaml",), False, "DEEP", "SOURCE_RUNTIME_MISMATCH", "profile-only path with external source/runtime mismatch"),
]


def main() -> int:
    rows = []
    false_fast = 0
    nondeterministic = 0
    for case_id, paths, final_evidence, expected, external_risk, note in CASES:
        observed = [classify(paths, final_evidence=final_evidence) for _ in range(100)]
        deterministic = len({(d.tier, d.reason, d.deep_required) for d in observed}) == 1
        decision = observed[0]
        if not deterministic:
            nondeterministic += 1
        if decision.tier == "FAST" and expected == "DEEP":
            false_fast += 1
        rows.append({
            "case_id": case_id,
            "expected": expected,
            "observed": decision.tier,
            "reason": decision.reason,
            "external_risk": external_risk,
            "deterministic": deterministic,
            "pass": deterministic and decision.tier == expected,
            "note": note,
        })

    summary = {
        "cases": len(CASES),
        "false_fast": false_fast,
        "nondeterministic": nondeterministic,
        "hard_gate_pass": false_fast == 0 and nondeterministic == 0 and all(row["pass"] for row in rows),
    }
    print("S28_FIRE_TEST_LOT_E_ADVERSARIAL_REPORT=" + json.dumps({"rows": rows, "summary": summary}, sort_keys=True))
    if not summary["hard_gate_pass"]:
        print(f"FAIL_S28_FIRE_TEST_LOT_E FALSE_FAST={false_fast} NONDETERMINISTIC={nondeterministic}")
        return 1
    print(f"PASS_S28_FIRE_TEST_LOT_E={len(CASES)}/{len(CASES)} FALSE_FAST={false_fast}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
