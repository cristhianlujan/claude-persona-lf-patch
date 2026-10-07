# Programming Agent control sweep — 2026-10-07

Base: faf71e4c700af201c74537e392dfdca0394d19b7

## Scope

Systemic sweep over Analysis A1–A9 and the Programming controls that own the two exposed downstream risks: PG-01 admission, PG-04 partitioning, PG-07 context budget and PG-10 human decision routing.

## Findings

| Family | Baseline | Candidate repair |
|---|---|---|
| Existing decision reuse | A5 checked current ADRs but did not require general current-decision reuse before a new human question | A5 now checks DECISION_CONTEXT_ASOF + public/transversal decision logs and forbids duplicate owner questions |
| Human decision visibility | REQUIRES_DECISION could remain a generic blocker | Explicit owner packet and dedicated A9 presentation required |
| Missing implementation semantics | A7 could classify absence of code/table/binding as BLOCKED | Missing implementation alone is BUILD_REQUIRED, not Analysis blocker |
| A9 package materialization | Canonical package existed in plan metadata but no dedicated source contract | analysis_implementation_package_contract_v1.json |
| Partitioning | PG-04 contract existed only in plan metadata | programming_solution_partition_contract_v1.json |
| Context budget | PG-07 had a strong plan contract but no boundary source contract/receipt | programming_context_budget_contract_v1.json, reusing CONTEXT_BUDGET_GOVERNANCE |
| Programming conflict routing | PG-10 mapped human_decisions but had no source routing contract | programming_human_decision_routing_contract_v1.json |
| Completeness | Wave1 validator could PASS while some later plan controls existed only as metadata | programming_agent_control_completeness_manifest_v1.json |

## Context partition ownership

- A9: one canonical Analysis spec.
- PG-04: semantic/risk/dependency partitioning.
- PG-07: runtime context-budget enforcement per worker projection.
- PG-07 RED: repair edge back to PG-04; this is not a prerequisite dependency cycle.
- PG-10: owner routing only for true human decisions.

## Validation

Current candidate self-test:
PASS ... human_decision_routing=PASS implementation_absence_semantics=PASS a9_package=PASS solution_partition=PASS context_budget=PASS control_completeness=PASS negatives=122

No runtime or production activation. No merge.
