# PASE_MERGE_ROUTE_V1

## Purpose

Materialize the canonical `lf-pase-merge-route/v1` packet that `PASE_MERGE_GATE_V1` consumes.

Authority stays with `CHANGESET_GOVERNANCE_LF_V1`. This component does **not** classify control applicability and does not execute controls.

```text
Changeset Governance / lf-ci-execution-plan/v2
                    |
                    +--> PASE_CONTROL_REPAIR_QUARANTINE_V1
                    |        ACTIVE_BLOCKING / REPAIR_OBSERVE_ONLY
                    |
                    v
            PASE_MERGE_ROUTE_V1
                    |
                    +--> EXECUTION_PLAN
                    |        or
                    +--> CONTROL_SYSTEM_QUALIFICATION
                    |
                    v
             PASE_MERGE_GATE_V1
```

## Route semantics

`required_control_ids` is always exactly the canonical repair-enforcement `blocking_controls` set. The route cannot add or remove applicable controls and cannot reintroduce an observe-only validator as a blocker.

Normal changes emit:

- `mode = EXECUTION_PLAN`;
- `candidate_id = null`.

Known control-system changes emit:

- `mode = CONTROL_SYSTEM_QUALIFICATION`;
- exactly one canonical `candidate_id` from the Changeset Governance route registry.

The registry uses longest-specific-match semantics so a specific PASE solution can live under the broader s28 Changeset Governance tree without being collapsed into the generic `CHANGESET_GOVERNANCE_LF_V1` identity.

If one changeset touches more than one independently registered control-system candidate, route production blocks fail-closed. That preserves the one-solution-per-PR boundary.

## Current control-system identities

The initial registry covers the currently material PASE governance surfaces:

- `PASE_MERGE_ROUTE_V1`;
- `PASE_MERGE_GATE_V1`;
- `PASE_ORCHESTRATOR_V1`;
- `PASE_CONTROL_QUALIFICATION_V1`;
- `LF_GOVERNANCE_SUPER_ADMIN_V1`;
- `PASE_GITHUB_ENTRYPOINT_V1`;
- generic s28 authority changes as `CHANGESET_GOVERNANCE_LF_V1`.

This registry is route authority only. It is not an owner-runner registry, carrier registry, or second applicability engine.

## Fail-closed invariants

The producer requires:

- exact 40-hex candidate head;
- canonical `lf-ci-execution-plan/v2` with complete coverage and plan digest;
- canonical `lf-pase-control-enforcement/v1` from `CHANGESET_GOVERNANCE_LF_V1` / `PASE_CONTROL_REPAIR_QUARANTINE_V1`;
- exact plan/enforcement digest binding;
- complete blocking/observe-only partition;
- valid route registry authority and matcher shape;
- one or zero control-system candidate identities per changeset.

## Non-goals

This solution does not:

- run Contract Check, Migration Parity, Assurance, P0, Runtime, DB Regression or another domain control;
- qualify a candidate;
- mutate GitHub rulesets;
- mutate Supabase;
- activate owner-runners;
- merge or deploy by itself.

## Deterministic test

```bash
python3 sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_pase_merge_route_v1.py
```

Expected marker:

```text
PASS_PASE_MERGE_ROUTE_V1 checks=20
```
