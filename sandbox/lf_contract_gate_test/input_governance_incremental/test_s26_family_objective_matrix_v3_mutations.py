from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
from types import SimpleNamespace

import test_s26_family_objective_matrix_v3 as v3

ROOT = Path(__file__).resolve().parent


class FakeResolver:
    def __init__(self, mapping):
        self.mapping = mapping

    def resolve_change_impact(self, family, mutation, runtime):
        return self.mapping[mutation]


def result(decision: str, impacts: set[str], *, uncertainty: str = "NONE", fail_closed: bool = False):
    return SimpleNamespace(
        decision=decision,
        impacted_families=tuple(sorted(impacts)),
        uncertainty=uncertainty,
        shared_dependency=len(impacts) > 1,
        fail_closed=fail_closed,
        rationale_code="MUTATION_AUDIT",
    )


def expect_system_exit(fn, expected_fragment: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        if expected_fragment not in str(exc):
            raise AssertionError(f"unexpected SystemExit: {exc}") from exc
        return
    raise AssertionError(f"expected SystemExit containing {expected_fragment}")


def main() -> None:
    matrix = json.loads((ROOT / "s26_family_objective_matrix_v3.json").read_text(encoding="utf-8"))
    metadata = v3.flatten_matrix(matrix)
    gold = v3.load_gold()
    gold_by_code = {row["case_code"]: row for row in gold}

    # Mutation 1: duplicate objective/evidence signature must be rejected structurally.
    duplicated = deepcopy(matrix)
    family = "COPY_RECONCILIATION"
    first = duplicated["families"][family][0]
    second = duplicated["families"][family][1]
    second["failure_mode"] = first["failure_mode"]
    second["functionality"] = first["functionality"]
    second["depth"] = first["depth"]
    expect_system_exit(lambda: v3.flatten_matrix(duplicated), "FAIL_S26_V3_DUPLICATE_EVIDENCE_SIGNATURE")

    # Mutation 2: wrong family binding cannot count as valid independent evidence.
    wrong_family = deepcopy(metadata["CI-COPY-01"])
    wrong_family["family"] = "ACTION_SEMANTICS"
    assert wrong_family["family"] != gold_by_code["CI-COPY-01"]["family"]

    # Mutations 3-4: metamorphic decision or impact divergence must break the relation gate.
    gold_row = {
        "family": "ACTION_SEMANTICS",
        "mutation": "gold-stable",
        "expected_decision": "SCOPED_CANDIDATE",
        "expected_impacts": {"ACTIONS"},
    }
    holdout_row = {
        "family": "ACTION_SEMANTICS",
        "mutation": "holdout-stable",
        "expected_decision": "SCOPED_CANDIDATE",
        "expected_impacts": {"ACTIONS"},
    }
    runtime = SimpleNamespace()

    baseline = FakeResolver({
        "gold-stable": result("SCOPED_CANDIDATE", {"ACTIONS"}),
        "holdout-stable": result("SCOPED_CANDIDATE", {"ACTIONS"}),
    })
    assert v3.relation_gate(gold_row, holdout_row, baseline, runtime)["pass"] is True

    decision_divergence = FakeResolver({
        "gold-stable": result("SCOPED_CANDIDATE", {"ACTIONS"}),
        "holdout-stable": result("GLOBAL_ESCALATE", {"ACTIONS"}, fail_closed=True),
    })
    assert v3.relation_gate(gold_row, holdout_row, decision_divergence, runtime)["pass"] is False

    impact_divergence = FakeResolver({
        "gold-stable": result("SCOPED_CANDIDATE", {"ACTIONS"}),
        "holdout-stable": result("SCOPED_CANDIDATE", {"ACTIONS", "SECURITY"}),
    })
    assert v3.relation_gate(gold_row, holdout_row, impact_divergence, runtime)["pass"] is False

    # Mutations 5-8: case-level hard dimensions must detect semantic/canonical corruption.
    sample = gold_by_code["CI-ERR-02"]
    sample_meta = metadata["CI-ERR-02"]
    correct = {
        "decision": sample["expected_decision"],
        "impacts": set(sample["expected_impacts"]),
        "uncertainty": "NONE",
        "fail_closed": True,
        "shared_dependency": True,
        "rationale_code": "AUDIT_BASELINE",
    }
    assert v3.case_dimensions(sample, sample_meta, correct, 1.0)["pass"] is True

    wrong_decision = dict(correct)
    wrong_decision["decision"] = "SCOPED_CANDIDATE"
    assert v3.case_dimensions(sample, sample_meta, wrong_decision, 1.0)["pass"] is False

    missing_impact = dict(correct)
    missing_impact["impacts"] = set()
    assert v3.case_dimensions(sample, sample_meta, missing_impact, 1.0)["pass"] is False

    spurious_impact = dict(correct)
    spurious_impact["impacts"] = set(correct["impacts"]) | {"SPURIOUS_MUTATION_FAMILY"}
    assert v3.case_dimensions(sample, sample_meta, spurious_impact, 1.0)["pass"] is False

    fail_open = dict(correct)
    fail_open["uncertainty"] = "UNKNOWN"
    fail_open["fail_closed"] = False
    assert v3.case_dimensions(sample, sample_meta, fail_open, 1.0)["pass"] is False

    # Mutations 9-10: removing source evidence or rationale must fail quality/evidence.
    no_anchor = dict(sample)
    no_anchor["source_anchor"] = ""
    assert v3.case_dimensions(no_anchor, sample_meta, correct, 1.0)["pass"] is False

    no_rationale = dict(sample)
    no_rationale["rationale"] = ""
    assert v3.case_dimensions(no_rationale, sample_meta, correct, 1.0)["pass"] is False

    required = set(matrix["mutation_operators"])
    verified = {
        "FLIP_BLOCK_TO_SCOPED_CANDIDATE",
        "DROP_REQUIRED_IMPACT_FAMILY",
        "ADD_SPURIOUS_IMPACT_FAMILY",
        "FAIL_OPEN_UNKNOWN_OR_MIXED",
        "WRONG_FAMILY_BINDING",
        "EMPTY_SOURCE_ANCHOR",
        "EMPTY_RATIONALE",
        "DUPLICATE_OBJECTIVE_SIGNATURE",
        "METAMORPHIC_DECISION_DIVERGENCE",
        "METAMORPHIC_IMPACT_DIVERGENCE",
    }
    assert required == verified, (sorted(required - verified), sorted(verified - required))
    print(f"PASS_S26_FAMILY_OBJECTIVE_MATRIX_V3_MUTATION_AUDIT={len(verified)}/{len(required)}")


if __name__ == "__main__":
    main()
