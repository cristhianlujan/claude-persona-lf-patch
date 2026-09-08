#!/usr/bin/env python3
"""Deterministic Strategy 26 routing matrix for the hybrid semantic candidate."""

from __future__ import annotations

from semantic_authority_router import (
    LOCAL_3B_SOURCE_GROUNDED,
    NOVEL_SEMANTIC_KINDS,
    SOURCE_GROUNDED_KINDS,
    STRONG_SEMANTIC_AUTHORITY,
    select_semantic_authority,
)


def main() -> None:
    cases: list[tuple[str, str | None, bool, str | None, bool, str]] = []

    for kind in sorted(SOURCE_GROUNDED_KINDS):
        for index in range(3):
            cases.append(
                (
                    f"local_{kind}_{index}",
                    kind,
                    True,
                    f"supabase://authority/{kind}/{index}",
                    False,
                    LOCAL_3B_SOURCE_GROUNDED,
                )
            )

    for kind in sorted(NOVEL_SEMANTIC_KINDS):
        for index in range(2):
            cases.append(
                (
                    f"novel_{kind}_{index}",
                    kind,
                    False,
                    None,
                    True,
                    STRONG_SEMANTIC_AUTHORITY,
                )
            )

    for kind in sorted(SOURCE_GROUNDED_KINDS):
        cases.append(
            (
                f"ungrounded_{kind}",
                kind,
                False,
                None,
                False,
                STRONG_SEMANTIC_AUTHORITY,
            )
        )

    cases.extend(
        [
            ("missing", None, False, None, False, STRONG_SEMANTIC_AUTHORITY),
            ("empty", "", True, "supabase://x", False, STRONG_SEMANTIC_AUTHORITY),
            ("unknown", "MAKE_IT_GOOD", True, "supabase://x", False, STRONG_SEMANTIC_AUTHORITY),
            (
                "conflict_source_plus_novel",
                "EXTRACT_EXISTING",
                True,
                "supabase://x",
                True,
                STRONG_SEMANTIC_AUTHORITY,
            ),
            (
                "s26_golden_novel_overflow",
                "NOVEL_DECISION",
                False,
                None,
                True,
                STRONG_SEMANTIC_AUTHORITY,
            ),
            (
                "s26_source_grounded_control",
                "REPRODUCE_EXISTING",
                True,
                "supabase://ACT-0024/exact-visual-decision",
                False,
                LOCAL_3B_SOURCE_GROUNDED,
            ),
        ]
    )

    if len(cases) != 30:
        raise AssertionError(f"expected 30 cases, got {len(cases)}")

    passed = 0
    for name, kind, grounded, ref, novel, expected in cases:
        decision = select_semantic_authority(
            task_kind=kind,
            source_grounding_ready=grounded,
            authority_ref=ref,
            requires_novel_judgment=novel,
        )
        if decision.route != expected:
            raise AssertionError(
                f"{name}: expected={expected} actual={decision.route} reason={decision.reason_code}"
            )
        passed += 1
        print(f"PASS {name}: {decision.route} {decision.reason_code}")

    print(f"SEMANTIC_AUTHORITY_ROUTER_MATRIX_PASS {passed}/{len(cases)}")


if __name__ == "__main__":
    main()
