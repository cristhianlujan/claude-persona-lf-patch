# PASE_MERGE_GATE_CARRIER_V1

## Purpose

Run `PASE_MERGE_GATE_V1` from trusted base-branch code, independently of candidate code, before any external required-status enforcement is activated.

```text
pull_request_target
      |
      v
trusted PR base checkout
      |
      +-- resolve current main == event base
      +-- fetch candidate Git objects only
      +-- do NOT checkout/import/execute candidate code
      |
      v
CHANGESET_GOVERNANCE_LF_V1
  emit lf-ci-execution-plan/v2
      |
      v
PASE_MERGE_ROUTE_V1
      |
      v
PASE_MERGE_GATE_V1
```

## Shadow behavior

The carrier is intentionally fail-closed and does not invent missing evidence:

- ordinary `EXECUTION_PLAN` changes pass only when the repair-enforcement projection has no active blocker requiring missing evidence;
- a control-system change routes to `CONTROL_SYSTEM_QUALIFICATION` and blocks until independent canonical `PASE_CONTROL_QUALIFICATION_V1` evidence is available;
- an active blocker without canonical exact-head PASS evidence blocks;
- stale base, repository drift, head drift or malformed canonical plan blocks.

## Trust boundary

The workflow checks out exactly `github.event.pull_request.base.sha`. Candidate objects are fetched only so trusted base code can compute the Git diff. Candidate workflows, Python modules, build hooks and package code are never executed by this carrier.

The carrier does not depend on a candidate-declared PASS and does not mutate GitHub rulesets, Supabase, the repository, owner-runners, bindings, controls or production state.

## Activation boundary

This solution is **shadow only**. `external_enforcement_active=false` is emitted in the result. Adding `pase-merge-gate` as a required status in `protect-main` is a later, separate activation step and requires explicit authorization plus live-fire evidence.

## Self-test

```bash
python3 sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_carrier_v1.py self-test
```

The self-test proves:

1. normal no-blocker route can PASS;
2. control-system change without independent qualification blocks;
3. active blocker without canonical PASS evidence blocks;
4. stale base blocks.
