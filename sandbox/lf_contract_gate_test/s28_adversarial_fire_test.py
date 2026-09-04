#!/usr/bin/env python3
from __future__ import annotations

import json
from s28_ci_feedback_tier import classify

CASES = [
    ("E01", ("profilesx/ui/profile.yaml",), False, False, tuple(), "DEEP", "lookalike FAST prefix"),
    ("E02", ("profiles/../supabase/migrations/escape.sql",), False, False, tuple(), "DEEP", "path traversal into migration surface"),
    ("E03", ("profiles\\..\\.github\\workflows\\escape.yml",), False, False, tuple(), "DEEP", "backslash traversal into control surface"),
    ("E04", ("profiles/ui/profile.yaml", "supabase/functions/runtime/index.ts"), False, True, tuple(), "DEEP", "mixed safe plus runtime"),
    ("E05", ("docs/runbook.md", ".github/workflows/required.yml"), False, False, tuple(), "DEEP", "mixed docs plus CI control"),
    ("E06", ("profiles/ui/profile.yaml",), True, True, tuple(), "DEEP", "final evidence override"),
    ("E07", tuple(), False, False, tuple(), "DEEP", "no changed paths"),
    ("E08", ("/profiles/ui/profile.yaml",), False, False, tuple(), "DEEP", "absolute path"),
    ("E09", ("skills/story_creator/skill.yaml",), False, False, tuple(), "DEEP", "unmapped skill surface"),
    ("E10", ("cards/example/card.yaml",), False, False, tuple(), "DEEP", "unmapped card surface"),
    ("E11", ("workers/runtime/config.yaml",), False, False, tuple(), "DEEP", "unmapped worker surface"),
    ("E12", ("profiles/ui/profile.yaml",), False, True, ("SOURCE_RUNTIME_MISMATCH",), "DEEP", "profile-only path with server-derived source/runtime mismatch"),
]


def main() -> int:
    rows = []
    false_fast = 0
    nondeterministic = 0
    for case_id, paths, final_evidence, server_context_resolved, server_risks, expected, note in CASES:
        observed = [classify(
            paths,
            final_evidence=final_evidence,
            server_context_resolved=server_context_resolved,
            server_risk_signals=server_risks,
        ) for _ in range(100)]
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
            "server_context_resolved": server_context_resolved,
            "server_risks": list(server_risks),
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
