from control_equivalence_judge_v1 import evaluate

POLICY = {
    "schema_version": "lf-control-equivalence-policy/v1",
    "consumer_ref": "IG_CURATOR_VALIDATOR_REFACTOR_V2:T-EQUIV:NEGATIVE_FIXTURE",
    "field_levels": {
        "summary.story_ready_status": {
            "level": "D4",
            "meaning": "candidate can claim readiness where current evidence remains blocked; false-PASS risk",
            "blocking": True,
        },
        "summary.severity": {
            "level": "D2",
            "meaning": "fixture-only consumer-declared non-D4 severity difference",
            "blocking": False,
        },
    },
}
BASE = {"summary": {"story_ready_status": "BLOCKED", "severity": "HIGH", "family_count": 47}}


def main() -> None:
    result = evaluate(BASE, BASE, POLICY)
    assert result["result"] == "PASS_EQUIVALENT"
    assert result["comparison_level"] == "D0"
    assert result["divergence_count"] == 0

    candidate = {"summary": {"story_ready_status": "READY", "severity": "HIGH", "family_count": 47}}
    result = evaluate(BASE, candidate, POLICY)
    assert result["result"] == "BLOCKED_DIVERGENCE"
    assert result["comparison_level"] == "D4"
    assert result["blocking"] is True
    assert result["divergences"][0]["field"] == "summary.story_ready_status"
    assert result["divergences"][0]["level"] == "D4"

    candidate2 = {"summary": {"story_ready_status": "BLOCKED", "severity": "HIGH", "family_count": 46}}
    result = evaluate(BASE, candidate2, POLICY)
    assert result["result"] == "BLOCKED_UNCLASSIFIED_DIVERGENCE"
    assert result["unclassified_fields"] == ["summary.family_count"]

    bad_policy = {
        **POLICY,
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

    print("PASS_CONTROL_EQUIVALENCE_JUDGE_V1 checks=4")


if __name__ == "__main__":
    main()
