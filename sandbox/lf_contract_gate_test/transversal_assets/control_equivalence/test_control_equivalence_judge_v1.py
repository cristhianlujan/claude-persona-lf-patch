from control_equivalence_judge_v1 import evaluate

BASE = {"summary": {"story_ready_status": "BLOCKED", "severity": "HIGH", "family_count": 47}}

IG_POLICY = {
    "schema_version": "lf-control-equivalence-policy/v1",
    "consumer_ref": "IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8",
    "field_levels": {},
}

FALSE_PASS_POLICY = {
    "schema_version": "lf-control-equivalence-policy/v1",
    "consumer_ref": "IG_CURATOR_VALIDATOR_REFACTOR_V2:T-EQUIV:NEGATIVE_FIXTURE",
    "field_levels": {
        "summary.story_ready_status": {
            "level": "D4",
            "meaning": "candidate claims readiness where baseline remains blocked; false-PASS risk",
            "blocking": True,
        }
    },
}

NON_IG_POLICY = {
    "schema_version": "lf-control-equivalence-policy/v1",
    "consumer_ref": "NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE",
    "field_levels": {
        "config.retry_limit": {
            "level": "D2",
            "meaning": "consumer-declared operational configuration difference",
            "blocking": False,
        }
    },
}


def main() -> None:
    # 1: exact equality is D0.
    result = evaluate(BASE, BASE, IG_POLICY)
    assert result["result"] == "PASS_EQUIVALENT"
    assert result["comparison_level"] == "D0"
    assert result["divergence_count"] == 0

    # 2: M7.8 is exact-only. Any changed cached/non-cached field blocks unclassified.
    cached = {"visual": {"source_refs": ["SCREEN_CANONICAL_GRAPH"]}}
    uncached = {"visual": {"source_refs": ["SCREEN_CANONICAL_GRAPH", "CURRENT_VISUAL_ARTIFACT"]}}
    result = evaluate(cached, uncached, IG_POLICY)
    assert result["result"] == "BLOCKED_UNCLASSIFIED_DIVERGENCE"
    assert result["blocking"] is True

    # 3: known false-PASS is D4 and blocks.
    candidate = {"summary": {"story_ready_status": "READY", "severity": "HIGH", "family_count": 47}}
    result = evaluate(BASE, candidate, FALSE_PASS_POLICY)
    assert result["result"] == "BLOCKED_DIVERGENCE"
    assert result["comparison_level"] == "D4"
    assert result["blocking"] is True

    # 4: unmapped field always fails closed.
    candidate2 = {"summary": {"story_ready_status": "BLOCKED", "severity": "HIGH", "family_count": 46}}
    result = evaluate(BASE, candidate2, FALSE_PASS_POLICY)
    assert result["result"] == "BLOCKED_UNCLASSIFIED_DIVERGENCE"
    assert "summary.family_count" in result["unclassified_fields"]

    # 5: consumer cannot downgrade D4 to non-blocking.
    bad_policy = {
        **FALSE_PASS_POLICY,
        "field_levels": {
            "summary.story_ready_status": {
                "level": "D4",
                "meaning": "false pass",
                "blocking": False,
            }
        },
    }
    result = evaluate(BASE, candidate, bad_policy)
    assert result["result"] == "BLOCKED"
    assert result["reason_code"].startswith("D4_MUST_BLOCK")

    # 6: non-IG consumer supplies its own D2 meaning; provider needs no branch.
    left = {"config": {"retry_limit": 3, "mode": "SAFE"}}
    right = {"config": {"retry_limit": 4, "mode": "SAFE"}}
    result = evaluate(left, right, NON_IG_POLICY)
    assert result["result"] == "DIVERGENCE_CLASSIFIED"
    assert result["comparison_level"] == "D2"
    assert result["blocking"] is False
    assert result["consumer_ref"] == "NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE"

    print("PASS_CONTROL_EQUIVALENCE_JUDGE_V1 checks=6 consumers=2")


if __name__ == "__main__":
    main()
