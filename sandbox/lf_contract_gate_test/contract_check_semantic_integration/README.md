# Contract Check Semantic Integration V1

Status: `SHADOW_CANDIDATE`

## Purpose

Compose the already-closed Contract Check semantic pieces without moving ownership upstream:

```text
Contract Resolution result
        |
        v
explicit per-contract source binding
  TYPED | LEGACY_TRANSLATION
        |
        +-- LEGACY_TRANSLATION -> Legacy Contract Normalization V1
        |
        v
Typed contracts
        |
        v
Contract Predicate Semantics V1
        |
        v
Contract Check Core V1
        |
        v
PASS / BLOCK
```

## Boundary

This integration MUST NOT:

- decide whether Contract Check applies;
- resolve, rank, select, or infer contracts;
- infer `operation_code`;
- accept upstream `SATISFIED`, `FAILED`, `CLEAR`, `TRIGGERED`, or `evaluations`;
- infer whether a contract is typed vs legacy; the source mode is explicit per contract;
- translate legacy free-form terms without an exact translation binding;
- create facts or evidence; it consumes explicit observations with evidence refs;
- mutate Supabase, runtime, workflows, contracts, or lifecycle state;
- call sibling controls.

## Integrity rules

- Input consumes the exact `lf-contract-resolution-result/v1` packet.
- The resolution SHA-256 is recomputed before any semantic work.
- Every resolved contract must have exactly one source binding.
- `TYPED` contracts bypass legacy normalization but still pass through Predicate Semantics and Contract Check Core.
- `LEGACY_TRANSLATION` contracts must normalize `FULL` and `ready_for_contract_check=true`; partial shadow normalization blocks.
- Any missing fact/evidence blocks in Predicate Semantics.
- Predicate verdicts are generated inside Contract Check and passed directly to Contract Check Core; they cannot arrive from PASE or another upstream caller.

## Evidence

Candidate self-test marker:

`PASS_CONTRACT_CHECK_SEMANTIC_INTEGRATION_V1=18/18`

No live authority, production runtime, workflow cutover, Contract Resolution selector, PASE applicability rule, or sibling control implementation is changed by this candidate.
