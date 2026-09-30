# Contract Check Execution Chain V1

Status: `SHADOW_CANDIDATE`

## Purpose

Close the development gap between an already-resolved caller operation context and the existing Contract Check implementation without moving routing, applicability, authority lookup, fact production, or contract semantics into Contract Check.

```text
explicit caller operation context
  operation_code
  public.lf_operation_contracts snapshot
        |
        v
Contract Resolution carrier
        |
        v
resolved_contracts
        |
        + explicit source bindings: TYPED | LEGACY_TRANSLATION
        + explicit evidence-backed facts
        |
        v
Contract Check Final Thin Carrier
        |
        v
Semantic Integration
        |
        + Legacy Normalization when explicitly bound
        + Predicate Semantics
        + Contract Check Core
        |
        v
PASS / BLOCK
```

## Input

Schema: `lf-contract-check-execution-request/v1`.

Required:

- `phase`: `ENTRY | CLOSURE`;
- `operation_context.operation_code`: already decided by the caller;
- `operation_context.authority_source = public.lf_operation_contracts`;
- `operation_context.authority_contracts`: caller-provided authority snapshot;
- `bindings`: one explicit `TYPED | LEGACY_TRANSLATION` binding per resolved contract;
- `facts`: explicit evidence-backed observations consumed by Predicate Semantics.

## Boundary

This composition does **not**:

- decide whether Contract Check applies;
- infer, route, or select `operation_code`;
- query or mutate Supabase;
- rank/select one contract from N;
- infer whether a contract is typed or legacy;
- infer legacy contract meaning;
- manufacture facts or evidence;
- accept upstream contractual verdicts;
- execute sibling controls;
- mutate contracts, operations, runtime, lifecycle, workflows, or rulesets.

The composition calls the existing Contract Resolution carrier and then the existing Final Thin Carrier. It introduces no second Contract Check evaluator and no parallel contract authority.

## Failure semantics

- malformed execution/context input: invalid transport (`3`);
- zero active contracts from Contract Resolution: governed block (`2`);
- semantic/core contractual block: governed block (`2`);
- final Contract Check PASS: success (`0`).

## Evidence

Candidate self-test target:

`PASS_CONTRACT_CHECK_EXECUTION_CHAIN_V1=18/18`

The test proves:

- exact operation context is preserved;
- inactive/other-operation contracts are filtered by Contract Resolution;
- all active contracts are retained;
- source mode remains explicit;
- missing bindings block;
- missing evidence-backed facts block;
- contractual PASS/BLOCK reaches the existing Core;
- zero active contracts fail closed.

## Remaining work after this candidate

This candidate does not claim live contract readiness. The current active authority remains legacy-shaped and still requires explicit live `LEGACY_TRANSLATION` coverage (or canonical TYPED contract migration) before a real live E2E Contract Check can close.
