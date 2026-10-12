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


## Runtime payload conformance finding

The sweep found a deeper gap than the original B2B blocker classification: the generic DECISION_CONTEXT_ASOF payload validator validates the outer immutable context envelope, but it does not validate the semantic shape of extensions.programming_context_snapshot.

The persisted B2B shell context therefore passed the generic store even though its snapshot is structurally incomplete against the current Analysis contracts: scope_front_matrix is empty, material fronts are skeletal, and implementability/decision artifacts are summaries rather than the full typed contracts.

Candidate repair:

- programacion.fn_programming_context_snapshot_validate_v1
- programacion.fn_programming_context_record_v1
- programacion.fn_programming_context_resolve_v1

These wrappers reuse the existing DECISION_CONTEXT_ASOF store and block Programming admission when the typed snapshot is incomplete. No new store is introduced.

Rollback-only Supabase probe:
- 7/7 PASS: 1 valid positive + 6 negative/systemic cases;
- historical B2B snapshot: BLOCKED as expected;
- implementation-absence false blocker: rejected;
- REQUIRES_DECISION without owner packet: rejected;
- REQUIRES_DECISION despite current authority: rejected;
- missing scope-front matrix: rejected;
- incomplete A6 implementability requirement: rejected;
- synthetic structurally complete snapshot: VALID as expected;
- candidate functions after rollback: 0.

Evidence: programming_context_runtime_guard_probe_v1.json.

## Human decision queue

PROGRAMMING_CONTEXT_SNAPSHOT_V1 now requires human_decision_queue[] even when empty. Every REQUIRES_DECISION scope must have a matching pending SUPER_ADMIN packet; a READY scope may not carry a pending owner decision. This prevents human decisions from disappearing inside generic blockers.


### Exact source sealing

The completeness manifest now binds each covered A1–A9 / PG contract to its exact SHA-256 and validator symbol. The runtime payload guard migration is also SHA-bound. A plan-only declaration, missing validator symbol, source drift, or migration-source drift fails the source self-test.
