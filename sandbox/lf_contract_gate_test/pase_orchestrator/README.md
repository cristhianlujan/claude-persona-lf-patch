# PASE Orchestrator V1

## Purpose

Provide the neutral orchestration boundary that sits **after** Changeset Governance / the canonical CI applicability plan and **before** individual pass controls.

```text
Changeset Governance / Router
        |
        v
lf-ci-execution-plan/v2
        |
        |-- plan.governance_admin
        v
PASE_ORCHESTRATOR_V1
        |
        +--> current carrier A / applicable controls only
        +--> current carrier B / applicable controls only
        +--> ...
```

This candidate does not replace or duplicate the Router. It consumes the existing
`required_controls`, `carrier_controls`, dependency graph, plan identity and the
plan-level governance administrator identity already produced upstream.

## Governance administrator contract

`PASE_ORCHESTRATOR_V1` requires `plan.governance_admin` with schema
`lf-ci-governance-admin-identity/v1`.

The identity is plan-level, not one owner per control:

- `super_admin = LF_GOVERNANCE`;
- source contract schema is `lf-governance-super-admin/v1`;
- `source_revision` is a SHA-256 readback handle for the source contract;
- `binding_materialized` and `supabase_registered` are booleans;
- `orchestrator_consumer = PASE_ORCHESTRATOR_V1`.

PASE validates this identity and propagates it unchanged into the dispatch packet.
It does **not** load the source contract, recalculate ownership, invent per-control
owners, or resolve owner-runners.

While `binding_materialized=false`, current carrier delegation remains authoritative.
An `INTERNAL_CI_CHECK` therefore does not need an independent owner-runner merely to
be dispatched. A standalone capability may move to an owner-runner only through its
separate canonical binding + qualified cutover.

If `binding_materialized=true` reaches this V1 before that later binding-aware cutover
is implemented, the orchestrator blocks fail-closed instead of silently continuing
with stale carrier semantics.

## Exact responsibility

`pase_orchestrator_v1.py`:

1. accepts an already-authoritative `lf-ci-execution-plan/v2`;
2. requires and validates `plan.governance_admin`;
3. requires `coverage_complete=true`;
4. proves every required control is delegated exactly once;
5. checks carrier assignment against the existing `lf_ci_control_impact_registry_v2.json`;
6. derives deterministic carrier order from the **existing dependency graph**;
7. emits `lf-pase-dispatch-plan/v1` while preserving the governance-admin identity unchanged.

It never decides whether a control applies.

## Boundaries

The orchestrator does **not**:

- classify changed paths or material;
- resolve Change Families;
- select or evaluate contracts;
- calculate or assign a separate owner for each control;
- require one owner-runner per internal CI check;
- load or reinterpret `LF_GOVERNANCE_SUPER_ADMIN_V1`;
- execute Contract Check semantics;
- execute Migration Source Parity, Assurance, P0, Runtime, DB Regression or another domain control;
- create a second gate-group engine;
- invoke subprocesses, GitHub APIs, Supabase or network services;
- mutate assets, operation registry, lifecycle, runtime or production state;
- change the current workflow cutover.

Execution remains delegated to the carriers named by the canonical plan while
`binding_materialized=false`. A later binding-aware change must be separately
qualified before any standalone capability is dispatched through an owner-runner.

## Why this is needed

The current `lf-contract-check.yml` is both a Contract Check carrier and a historical host for unrelated controls. Removing those controls before a neutral pass orchestration boundary exists would disable them. This module introduces the missing neutral boundary without changing current live execution.

The current plan still names the historical carriers. That is deliberate: carrier migration is a separate, evidence-backed step. The orchestrator must not invent a destination.

## Dependency order

Ordering is derived from `lf_ci_control_impact_registry_v2.json`; there is no second dependency registry.

If control `B` depends on control `A` and they are assigned to different carriers:

```text
carrier(A) -> carrier(B)
```

A cross-carrier cycle blocks fail-closed.

## Staging status

`PASE_ORCHESTRATOR_V1` is a repository candidate only in this PR.

No `.github/workflows/*` cutover is performed here. No Supabase/live authority is mutated. The later cutover must prove exact-head E2E before replacing historical carrier wiring.

## Test

```bash
python3 sandbox/lf_contract_gate_test/pase_orchestrator/test_pase_orchestrator_v1.py
```

Expected marker:

```text
PASS_PASE_ORCHESTRATOR_V1 checks=15
```
