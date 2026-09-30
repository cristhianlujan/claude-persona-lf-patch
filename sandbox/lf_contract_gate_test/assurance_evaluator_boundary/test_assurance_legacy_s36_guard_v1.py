#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
GUARD = HERE / "assurance_legacy_s36_guard_v1.py"

spec = importlib.util.spec_from_file_location("assurance_legacy_s36_guard_v1", GUARD)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def packet(**overrides):
    value = {
        "schema_version": "lf-assurance-evaluator-review-reference/v1",
        "mode": "NEW_REVIEW_REFERENCE",
        "review_type": "INDEPENDENT_REVIEW",
        "judge_source": "public.lf_test_judge_results",
        "judge_result_id": "00000000-0000-0000-0000-000000000001",
        "judge_write_requested": False,
    }
    value.update(overrides)
    return value


def main() -> None:
    checks = 0

    out = mod.validate_review_reference(packet())
    assert out["status"] == "ACCEPTED_NEW_REVIEW_REFERENCE", out
    assert out["judge_write_allowed"] is False
    checks += 1

    out = mod.validate_review_reference(packet(review_type="INDEPENDENT_HOLDOUT"))
    assert out["status"] == "ACCEPTED_NEW_REVIEW_REFERENCE", out
    checks += 1

    out = mod.validate_review_reference(packet(review_type="S36_ASSURANCE"))
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_LEGACY_S36_NEW_WRITE_SEMANTICS"
    checks += 1

    out = mod.validate_review_reference(
        packet(
            mode="HISTORICAL_LEGACY_READBACK",
            review_type="S36_ASSURANCE",
        )
    )
    assert out["status"] == "ACCEPTED_HISTORICAL_LEGACY_READBACK", out
    assert out["legacy_readback_only"] is True
    assert out["judge_write_allowed"] is False
    checks += 1

    out = mod.validate_review_reference(
        packet(
            mode="HISTORICAL_LEGACY_READBACK",
            review_type="INDEPENDENT_REVIEW",
        )
    )
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_HISTORICAL_READBACK_TYPE"
    checks += 1

    out = mod.validate_review_reference(packet(judge_write_requested=True))
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_EVALUATOR_JUDGE_WRITE_ATTEMPT"
    checks += 1

    out = mod.validate_review_reference(packet(judge_source="public.some_parallel_judges"))
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_NON_CANONICAL_JUDGE_SOURCE"
    checks += 1

    out = mod.validate_review_reference(packet(review_type="QUALITY_PACK"))
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_NEW_REVIEW_TYPE"
    checks += 1

    out = mod.validate_review_reference(packet(judge_result_id=""))
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_JUDGE_RESULT_ID"
    checks += 1

    print(f"ASSURANCE_LEGACY_S36_GUARD_V1=PASS checks={checks}")


if __name__ == "__main__":
    main()
