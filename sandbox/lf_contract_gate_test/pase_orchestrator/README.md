# PASE Orchestrator V1

## Purpose

Provide the neutral orchestration boundary that sits **after** Changeset Governance / the canonical CI applicability plan and **before** individual pass controls.

```text
Changeset Governance / Router
        |
        v
lf-ci-execution-plan/v2
        |
        v
PASE_ORCHESTRATOR_V1
        |
        +--> carrier A / applicable controls only
        +--> carrier B / applicable controls only
        +--> ...
```

This candidate does not replace or duplicate the Router. It consumes the existing `required_controls`, `carrier_controls`, dependency graph and plan identity already produced by `CI_FAST_DEEP_LANE_ROUTER`.

## Exact responsibility

`pase_orchestrator_v1.py`:

1. accepts an already-authoritative `lf-ci-execution-plan/v2`;
2. requires `coverage_complete=true`;
3. proves every required control is delegated exactly once;
4. checks carrier assignment against the existing `lf_ci_control_impact_registry_v2.json`;
5. derives deterministic carrier order from the **existing dependency graph**;
6. emits `lf-pase-dispatch-plan/v1`.

It never decides whether a control applies.

## Boundaries

The orchestrator does **not**:

- classify changed paths or material;
- resolve Change Families;
- select or evaluate contracts;
- execute Contract Check semantics;
- execute Migration Source Parity, Assurance, P0, Runtime, DB Regression or another domain control;
- create a second gate-group engine;
- invoke subprocesses, GitHub APIs, Supabase or network services;
- mutate assets, operation registry, lifecycle, runtime or production state;
- change the current workflow cutover.

Execution remains delegated to the carriers named by the canonical plan until each domain control is migrated to its proven owner/carrier.

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
PASS_PASE_ORCHESTRATOR_V1 checks=8
```
