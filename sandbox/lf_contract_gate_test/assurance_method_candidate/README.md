# LF_ASSURANCE_METHOD_V1 — candidate methodology boundary

`LF_ASSURANCE_METHOD_V1` is a **candidate evaluation methodology/catalog**, not an active PASE control and not an owner of the domains represented by its claims.

## Live readback frozen for this boundary

Observed on 2026-09-26:

- claims: 36 total / 0 ACTIVE / 36 CANDIDATO;
- obligations: 48 total / 0 ACTIVE / 48 CANDIDATO;
- defeaters: 34 total / 0 ACTIVE / 34 CANDIDATO;
- subject bindings: 4 total / 0 ACTIVE / 4 CANDIDATO;
- direct function references located: only `public.lf_eval_strategy_matrix_probe_v1` reads claims/obligations/bindings;
- its located consumer `TS-STRATEGY-OP-EXECUTE-V1 / E20 / ROUTE_GUARD_CLAIM_SURFACES` is itself `CANDIDATO`.

These counts are evidence for the current boundary, not a permanent lifecycle assertion. Promotion decisions require fresh readback.

## Purpose

The method may model structured claims, obligations, defeaters, evidence expectations and evaluation records for explicitly bound candidate evaluations.

It may be useful as a methodology for qualification/evaluation design. That does not make it a pass gate by itself.

## Not a PASE owner

`LF_ASSURANCE_METHOD_V1` must not own or replace:

- `OPERATION_TEST_COVERAGE`;
- `TEST_COVERAGE_DEBT_GUARD`;
- `INDEPENDENT_REVIEW`;
- `QUALIFICATION_FRAMEWORK`;
- Contract Check;
- Changeset Governance / applicability;
- lifecycle/stateful regressions;
- Card E2E;
- Router or policy authority;
- runtime or production authorization.

Claims whose subjects belong to those domains remain specifications/evaluation assertions; domain behavior stays with each canonical owner.

## Activation rule

No global activation by method name.

A future promotion, if justified, must be **subject/binding specific** and independently prove:

1. exact subject and claim set;
2. applicability/activation condition;
3. canonical domain owner remains unchanged;
4. no duplicate runner/store/router/qualification engine is created;
5. required evidence and defeaters are executable/current;
6. pass semantics do not exceed the bound claim;
7. consumer readback is explicit;
8. the candidate binding is promoted through its own governed lifecycle.

Until then, method/catalog rows and bindings remain candidate-only and out of the normal PASE critical path.

## Existing candidate integration

`ROUTE_GUARD_CLAIM_SURFACES` in `lf_eval_strategy_matrix_probe_v1` is a structural candidate probe. It checks presence/count/binding of the Strategy Router claim surfaces; it does not activate `LF_ASSURANCE_METHOD_V1` globally and does not transfer Router ownership to this method.

## No retirement required now

The catalog is not deleted because it has a bounded candidate consumer and can retain design/evaluation value. The cleanup is semantic/governance containment:

- keep candidate;
- keep outside PASE critical path;
- do not promote all rows together;
- promote only exact bindings if independently justified later;
- preserve domain ownership.

## EKB

- `ASSURANCE-METHOD-CANDIDATE-NOT-PASE-CONTROL-001`
- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`

## Safety

This boundary package creates no active capability, DB object, workflow, policy, router, runner, binding or production behavior.
