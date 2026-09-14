from __future__ import annotations

import json

import test_s26_commit_readback_binding as subject


def _expect_block(name: str, fn, expected: str) -> str:
    try:
        fn()
    except AssertionError as exc:
        message = str(exc)
        if expected not in message:
            raise AssertionError(f"S26_PR_BASE_DRIFT_WRONG_BLOCK:{name}:{message}") from exc
        return message
    raise AssertionError(f"S26_PR_BASE_DRIFT_FALSE_PASS:{name}")


def main() -> int:
    event_base = "1" * 40
    candidate = "2" * 40
    advanced_base = "3" * 40
    unrelated_base = "4" * 40

    original_is_ancestor = subject._is_ancestor
    results = {}
    try:
        subject._is_ancestor = lambda ancestor, descendant: (
            ancestor == event_base and descendant == advanced_base
        )
        resolved = subject._resolve_pr_checkout_base(
            candidate,
            event_base,
            [advanced_base, candidate],
        )
        if resolved != advanced_base:
            raise AssertionError("S26_PR_BASE_DRIFT_FORWARD_RESOLUTION_WRONG")
        results["historical_forward_main_drift"] = "PASS"

        subject._is_ancestor = lambda ancestor, descendant: False
        resolved_exact = subject._resolve_pr_checkout_base(
            candidate,
            event_base,
            [event_base, candidate],
        )
        if resolved_exact != event_base:
            raise AssertionError("S26_PR_BASE_DRIFT_EXACT_RESOLUTION_WRONG")
        results["exact_event_base"] = "PASS"

        results["candidate_parent_mismatch"] = _expect_block(
            "candidate_parent_mismatch",
            lambda: subject._resolve_pr_checkout_base(
                candidate,
                event_base,
                [advanced_base, unrelated_base],
            ),
            "S26_SHA_BINDING_PR_EVENT_CANDIDATE_PARENT_MISMATCH",
        )

        results["divergent_base"] = _expect_block(
            "divergent_base",
            lambda: subject._resolve_pr_checkout_base(
                candidate,
                event_base,
                [unrelated_base, candidate],
            ),
            "S26_SHA_BINDING_PR_EVENT_BASE_NOT_ANCESTOR_OF_CHECKOUT_BASE",
        )

        results["parent_count"] = _expect_block(
            "parent_count",
            lambda: subject._resolve_pr_checkout_base(
                candidate,
                event_base,
                [candidate],
            ),
            "S26_SHA_BINDING_PR_MERGE_PARENT_COUNT_INVALID:1",
        )
    finally:
        subject._is_ancestor = original_is_ancestor

    print(
        json.dumps(
            {
                "gate": "S26_PR_MERGE_BASE_DRIFT_REGRESSION_V1",
                "result": "PASS",
                "historical_case": {
                    "event_base": "63cb72970aa7f24fcf7ee61d4544b7dc38099847",
                    "checkout_base": "a38d7d145a5ba110051911a19f91ac866eab8743",
                    "candidate": "e682b292c1b23e15833b7c42364e12e8875bfa93",
                    "expected": "ALLOW_FORWARD_ONLY_BASE_DRIFT_WITH_EXACT_CANDIDATE_PARENT",
                },
                "positive_controls": 2,
                "negative_controls": 3,
                "results": results,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
