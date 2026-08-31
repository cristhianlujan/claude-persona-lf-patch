#!/usr/bin/env python3
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "gobernanza/benchmarks/learning_consumer_50_cases_v1.yaml"
CONTRACT = ROOT / "gobernanza/contratos/contrato_learning_consumer_binding_benchmark_lf.yaml"

EXPECTED_FAMILIES = {
    "COMPETITIVE_OFFER_INSIGHT",
    "DEBT_EDUCATION",
    "PAYMENT_NO_ADEUDO",
    "DIGITAL_SELF_SERVICE",
    "FINANCIAL_ALTERNATIVES",
    "NEGOTIATION",
    "OUT_OF_SCOPE_NO_INVOKE",
    "CONFLICT_PRECEDENCE",
    "STALE_LOW_GROUNDING",
    "MULTI_DOMAIN_COMPLEX",
}
REQUIRED_CONTRACT_TERMS = {
    "consumer_id",
    "consumer_type",
    "capability_id",
    "invoke_when",
    "must_not_invoke_when",
    "minimum_context",
    "selected_evidence_refs",
    "policy_capsule_ref",
    "output_schema_ref",
    "champion_id",
    "challenger_id",
    "READY_FOR_BINDING",
    "DETERMINISTIC_FIRST",
    "authority_pass_pct: 100",
    "critical_must_not_invoke_false_positives: 0",
    "automatic_impact: BLOQUEADO",
    "production: BLOQUEADO",
}


def fail(msg: str) -> None:
    raise SystemExit(f"FAIL learning-consumer-benchmark: {msg}")


def main() -> int:
    matrix = MATRIX.read_text(encoding="utf-8")
    contract = CONTRACT.read_text(encoding="utf-8")

    case_lines = [line.strip() for line in matrix.splitlines() if line.strip().startswith("- {id:")]
    if len(case_lines) != 50:
        fail(f"expected 50 cases, found {len(case_lines)}")

    ids: list[str] = []
    families: list[str] = []
    invokes = Counter()
    for line in case_lines:
        m = re.search(r"id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)", line)
        if not m:
            fail(f"malformed case line: {line}")
        case_id, family, invoke, expect, prohibit = [v.strip() for v in m.groups()]
        if not expect or not prohibit:
            fail(f"case {case_id} missing expectation/prohibition")
        ids.append(case_id)
        families.append(family)
        invokes[invoke] += 1

    if len(set(ids)) != 50:
        fail("case IDs are not unique")

    counts = Counter(families)
    if set(counts) != EXPECTED_FAMILIES:
        fail(f"family set mismatch: {sorted(counts)}")
    if any(count != 5 for count in counts.values()):
        fail(f"each family must have exactly 5 cases: {dict(sorted(counts.items()))}")
    if invokes["true"] == 0 or invokes["false"] == 0:
        fail("benchmark must contain positive and should-not-invoke cases")

    missing = sorted(term for term in REQUIRED_CONTRACT_TERMS if term not in contract)
    if missing:
        fail(f"contract missing required terms: {missing}")

    if "same_inputs: true" not in matrix or "same_model_runtime: true" not in matrix or "same_judges: true" not in matrix:
        fail("champion/challenger comparison invariants missing")

    print("LEARNING_CONSUMER_BENCHMARK_VERDICT=PASS")
    print(f"cases=50 families=10 positive={invokes['true']} negative={invokes['false']}")
    for family, count in sorted(counts.items()):
        print(f"family={family} cases={count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
