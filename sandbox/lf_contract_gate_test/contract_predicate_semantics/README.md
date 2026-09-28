# Contract Predicate Semantics V1

Status: `SHADOW_CANDIDATE`

## Purpose

Complete the semantic responsibility of the single Contract Check capability without moving contractual judgment into PASE, Contract Resolution, or another orchestrator.

The evaluator receives already-resolved contracts plus explicit evidence-backed facts and derives the per-term verdicts consumed by `contract_check_core_v1.py`.

```text
PASE / applicability
        |
        v
Contract Resolution
        | exact resolved contracts
        v
Contract Predicate Semantics V1
        | typed predicates + evidence-backed facts
        | -> SATISFIED / FAILED / CLEAR / TRIGGERED / NOT_APPLICABLE
        v
Contract Check Core V1
        | exact coverage + term digests + aggregate verdict
        v
      PASS / BLOCK
```

## Boundary

This component is an internal semantic stage of Contract Check. It is not a second Contract Check and not a new orchestration capability.

It MUST NOT:

- decide whether Contract Check applies;
- resolve or rank contracts;
- infer `operation_code`;
- call PASE, GitHub, Supabase, sibling controls, or lifecycle actions;
- persist receipts or EKB records;
- execute arbitrary code or interpret free-form natural-language contract strings.

## Typed term contract

Each evaluated section must be an array of terms shaped as:

```json
{
  "id": "production_disabled",
  "predicate": {
    "op": "FALSE",
    "fact": "production.allowed"
  }
}
```

An optional `applies_when` predicate may be supplied. When it evaluates to false, the term is emitted as `NOT_APPLICABLE` with a deterministic rationale and the evidence used for that applicability decision.

Supported operators in V1:

- leaf: `EXISTS`, `ABSENT`, `EQ`, `NEQ`, `IN`, `NOT_IN`, `TRUE`, `FALSE`;
- composition: `ALL`, `ANY`, `NOT`.

Unknown operators, undeclared fields, empty compound predicates, malformed terms, or unsupported section shapes fail closed.

## Evidence-backed facts

Facts are explicit observations keyed by stable fact name:

```json
{
  "runtime.enable_requested": {
    "present": true,
    "value": false,
    "evidence_refs": ["evidence://runtime/request"]
  }
}
```

Absence is never inferred from a missing observation. If absence matters, it must be stated explicitly with `present=false` and at least one evidence reference. A missing fact observation or missing evidence blocks semantic readiness.

This prevents the evaluator from inventing context or treating unknown data as a clean result.

## Section semantics

For `required_before_write`, `allowed`, and `required_after_write`:

- predicate true -> `SATISFIED`;
- predicate false -> `FAILED`.

For `blocked`:

- predicate true -> `TRIGGERED`;
- predicate false -> `CLEAR`.

`NOT_APPLICABLE` is produced only by an explicit `applies_when` predicate evaluating false.

The semantic result uses `READY` only to mean that every term was deterministically evaluated. A valid `FAILED` or `TRIGGERED` term still leaves semantic evaluation `READY`; `contract_check_core_v1` is the component that aggregates those term verdicts into final `PASS` or `BLOCK`.

## Compatibility with Contract Check Core V1

The evaluator emits the exact `evaluations` shape already consumed by `contract_check_core_v1.py`, including the canonical term digest and current core term identity (`section[index]`). Tests prove that the semantic output is accepted unchanged by the existing core.

The explicit semantic `id` is validated for uniqueness within each section. The current core identity remains index-based until a separately governed core-schema evolution is justified.

## Legacy contracts

This V1 does not reinterpret the current heterogeneous live strings/objects and does not mutate any live contract.

Legacy compatibility and contract normalization are deliberately separate later work. A legacy term that has not been explicitly translated to the typed predicate schema must not be guessed by this evaluator.

## Rollout

This PR is shadow-only. It adds the deterministic evaluator, regression tests, and CI self-test wiring. It does not change the active LF contract authority, production workflow semantics, required-check behavior, runtime activation, or Supabase state.
