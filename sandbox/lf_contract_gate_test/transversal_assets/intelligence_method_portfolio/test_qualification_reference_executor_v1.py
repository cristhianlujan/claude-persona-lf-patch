#!/usr/bin/env python3
from qualification_reference_executor_v1 import (
    adaptive_evidence_escalation,
    claim_method_constraint_selector,
    constraint_elimination,
    dependency_constraint_partition_selector,
    deterministic_invariant_veto,
    deterministic_signal_rule_classifier,
    hybrid_rule_first_semantic_classifier,
    obligation_preserving_budget,
)


def main() -> int:
    checks = 0

    out = deterministic_signal_rule_classifier({
        "changed_paths": ["supabase/migrations/x.sql", "docs/a.md"],
        "governed_constraint_change": True,
    })
    assert out["selected_options"] == ["DB_MIGRATION"] and out["execution_permission"] is False
    checks += 1

    out = deterministic_signal_rule_classifier({
        "changed_paths": ["supabase/migrations/x.sql"],
        "runtime_surface": True,
        "api_contract_change": True,
    })
    assert set(out["selected_options"]) == {"DB_MIGRATION", "RUNTIME", "API"}
    checks += 1

    assert deterministic_signal_rule_classifier({"changed_paths": ["docs/a.md"]})["selected_options"] == ["DOCS"]
    checks += 1

    out = deterministic_signal_rule_classifier({"changed_paths": ["unknown.bin"]})
    assert out["selected_options"] == [] and out["fallback"] == "TARGETED_EVIDENCE"
    checks += 1

    out = hybrid_rule_first_semantic_classifier(
        {"changed_paths": ["supabase/migrations/x.sql"]}, semantic_labels=["DOCS"]
    )
    assert out["selected_options"][0] == "DB_MIGRATION"
    checks += 1

    out = deterministic_invariant_veto(
        [{"id": "A", "violated_invariants": ["I1"]}, {"id": "B", "violated_invariants": []}],
        [{"id": "I1", "state": "PROVEN", "material": True}],
    )
    assert out["selected_options"] == ["B"]
    checks += 1

    out = deterministic_invariant_veto(
        [{"id": "A"}], [{"id": "I1", "state": "UNKNOWN", "material": True}]
    )
    assert out["fallback"] == "TARGETED_EVIDENCE"
    checks += 1

    out = constraint_elimination(
        [{"id": "TDD", "violates": ["COMPAT"]}, {"id": "COMPAT_FIRST", "violates": []}],
        [{"id": "COMPAT", "state": "PROVEN", "material": True}],
    )
    assert out["selected_options"] == ["COMPAT_FIRST"]
    checks += 1

    out = constraint_elimination(
        [{"id": "A", "violates": []}, {"id": "B", "violates": []}],
        [{"id": "C", "state": "PROVEN", "material": True}],
    )
    assert out["fallback"] == "BOUNDED_ALTERNATIVES" and set(out["selected_options"]) == {"A", "B"}
    checks += 1

    out = dependency_constraint_partition_selector([
        {"id": "layer_split", "breaks_atomicity": True},
        {"id": "vertical", "reuses_shared_capability": True},
    ])
    assert out["selected_options"] == ["vertical"]
    checks += 1

    out = dependency_constraint_partition_selector([
        {"id": "p1", "write_conflict": True},
        {"id": "p2", "context_budget_ok": False},
    ])
    assert out["fallback"] == "REPARTITION_REQUIRED"
    checks += 1

    out = claim_method_constraint_selector(
        [{"required_observations": ["state", "latency"]}],
        [{"id": "state_machine", "observes": ["state"]}, {"id": "load", "observes": ["latency"]}],
    )
    assert out["selected_options"] == ["state_machine", "load"]
    checks += 1

    out = claim_method_constraint_selector(
        [{"required_observations": ["state", "latency"]}],
        [{"id": "state_machine", "observes": ["state"]}],
    )
    assert out["fallback"] == "BLOCK_CLAIM_UNTESTABLE" and out["unknowns"] == ["latency"]
    checks += 1

    out = obligation_preserving_budget(
        [{"id": "I1"}, {"id": "I2"}],
        [
            {"id": "LOW", "covers": ["I1"], "within_budget": True},
            {"id": "MED", "covers": ["I1", "I2"], "within_budget": True},
        ],
    )
    assert out["selected_options"] == ["MED"]
    checks += 1

    out = obligation_preserving_budget(
        [{"id": "I1"}, {"id": "I2"}],
        [{"id": "LOW", "covers": ["I1"], "within_budget": True}],
    )
    assert out["fallback"] == "ESCALATE_BUDGET_OR_BLOCK"
    checks += 1

    out = adaptive_evidence_escalation(
        {"current_tier": "LOW", "sufficient": False, "material_uncertainty": True},
        [{"id": "LOW"}, {"id": "MED"}],
    )
    assert out["selected_options"] == ["MED"] and out["fallback"] == "ESCALATE"
    checks += 1

    out = adaptive_evidence_escalation(
        {"current_tier": "MED", "sufficient": True, "material_uncertainty": False, "contradiction": False},
        [{"id": "LOW"}, {"id": "MED"}],
    )
    assert out["selected_options"] == ["MED"] and out["fallback"] == "STOP_SUFFICIENT"
    checks += 1

    for output in [
        deterministic_signal_rule_classifier({"changed_paths": ["docs/a.md"]}),
        deterministic_invariant_veto([{"id": "A"}], []),
        constraint_elimination([{"id": "A"}], []),
        dependency_constraint_partition_selector([{"id": "A"}]),
        claim_method_constraint_selector([{"required_observations": ["x"]}], [{"id": "M", "observes": ["x"]}]),
        obligation_preserving_budget([{"id": "x"}], [{"id": "T", "covers": ["x"], "within_budget": True}]),
        adaptive_evidence_escalation({"current_tier": "T", "sufficient": True}, [{"id": "T"}]),
    ]:
        assert output["execution_permission"] is False
        checks += 1

    print(f"PASS_QUALIFICATION_REFERENCE_EXECUTOR checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
