#!/usr/bin/env python3
from __future__ import annotations

import json
from s28_ci_feedback_tier import classify

CASES = [
    ("D11", "F11_MIXED_SURFACE", ("profiles/ui/profile.yaml", "cards/example/card.yaml", "supabase/functions/runtime/index.ts"), False, "DEEP", "three-surface mix with runtime must escalate"),
    ("D12", "F12_UNKNOWN_FINAL", ("profiles_safe/ui/profile.yaml",), False, "DEEP", "lookalike safe prefix must remain unknown and fail closed"),
]


def main() -> int:
    rows = []
    false_fast = 0
    nondeterministic = 0
    for case_id, family, paths, final_evidence, expected, note in CASES:
        observed = [classify(paths, final_evidence=final_evidence) for _ in range(100)]
        deterministic = len({(d.tier, d.reason, d.deep_required) for d in observed}) == 1
        decision = observed[0]
        if not deterministic:
            nondeterministic += 1
        if decision.tier == "FAST" and expected == "DEEP":
            false_fast += 1
        passed = deterministic and decision.tier == expected
        rows.append({
            "case_id": case_id,
            "family": family,
            "expected": expected,
            "observed": decision.tier,
            "reason": decision.reason,
            "deterministic": deterministic,
            "pass": passed,
            "note": note,
        })
    summary = {
        "cases": len(CASES),
        "false_fast": false_fast,
        "nondeterministic": nondeterministic,
        "hard_gate_pass": false_fast == 0 and nondeterministic == 0 and all(r["pass"] for r in rows),
    }
    print("S28_FIRE_TEST_LOT_D_RESIDUAL_REPORT=" + json.dumps({"rows": rows, "summary": summary}, sort_keys=True))
    if not summary["hard_gate_pass"]:
        raise SystemExit("FAIL_S28_FIRE_TEST_LOT_D_RESIDUAL")
    print(f"PASS_S28_FIRE_TEST_LOT_D_RESIDUAL={len(CASES)}/{len(CASES)} FALSE_FAST={false_fast} NONDETERMINISTIC={nondeterministic}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
