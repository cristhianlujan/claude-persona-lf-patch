# PASE_MERGE_GATE_V1 — repair enforcement integration

## Purpose

`PASE_MERGE_GATE_V1` remains the neutral merge-policy evaluator between Changeset Governance and the repository required-status rule. This refactor adds the explicitly approved repair-window contract without creating a second router or a second merge gate.

```text
Changeset Governance / lf-ci-execution-plan/v2
                  |
                  | applicability (all applicable controls)
                  v
PASE_CONTROL_REPAIR_QUARANTINE_V1
                  |
                  | ACTIVE_BLOCKING / REPAIR_OBSERVE_ONLY
                  v
        authoritative merge route
                  |
                  v
          PASE_MERGE_GATE_V1
          /                \
CONTROL_SYSTEM_QUALIFICATION  EXECUTION_PLAN
```

## Authority boundary

Applicability remains entirely owned by Changeset Governance / `lf-ci-execution-plan/v2`.

The gate requires three mutually bound governance surfaces:

1. canonical plan `lf-ci-execution-plan/v2` with complete coverage and plan digest;
2. repair enforcement `lf-pase-control-enforcement/v1` produced under `CHANGESET_GOVERNANCE_LF_V1` / `PASE_CONTROL_REPAIR_QUARANTINE_V1` and bound to the exact plan digest;
3. merge route `lf-pase-merge-route/v1` under `CHANGESET_GOVERNANCE_LF_V1`.

The repair projection must partition every `plan.required_controls` entry exactly once into:

- `ACTIVE_BLOCKING` → appears in `blocking_controls` and must have exact-head PASS evidence;
- `REPAIR_OBSERVE_ONLY` → appears in `observe_only_controls`; diagnostic execution is allowed and its PASS/FAIL result cannot block merge.

The merge route must name exactly the `blocking_controls` set. It cannot silently suppress an active blocker or reintroduce an observe-only validator as a blocker.

## Control-system candidates

`CONTROL_SYSTEM_QUALIFICATION` still requires independent exact-head `PASE_CONTROL_QUALIFICATION_V1` evidence with:

- exact candidate identity/head;
- `verdict = CANDIDATE_QUALIFIED`;
- independent + validated evidence envelope;
- matching result digest;
- `qualified_only = true`;
- activation/cutover/rebind/legacy-retirement flags all false.

This requirement remains fail-closed even if every legacy validator is temporarily `REPAIR_OBSERVE_ONLY`.

## Normal changes

For `EXECUTION_PLAN` changes:

- canonical applicability is preserved in `plan.required_controls`;
- the quarantine projection decides enforcement state, not applicability;
- only `ACTIVE_BLOCKING` controls require PASS evidence;
- `REPAIR_OBSERVE_ONLY` controls may report diagnostics independently;
- missing/extra/duplicate blocking evidence, head drift, failed blockers, malformed policy binding, or plan/enforcement drift blocks.

## Structural governance that is never quarantined

The repair window does not relax:

- repository path admission;
- execution-plan schema and coverage;
- plan/enforcement digest binding;
- exact policy partition coverage;
- exact-head control-system qualification;
- pull-request, deletion, and non-fast-forward repository protections.

## Re-entry

The gate does not reactivate controls. Re-entry is owned by the repair policy and remains one-control-at-a-time after `CANDIDATE_QUALIFIED`, owner-runner binding PASS, equivalent replay PASS, and exact-head readback PASS.

## Trust boundary

The pure evaluator validates deterministic shape/identity/digests. The eventual trusted carrier must obtain plan, repair enforcement, merge route, qualification evidence, and blocking-control evidence from their canonical protected producers. Candidate-owned lookalike JSON is not authority.

## Non-scope

This refactor does not classify paths, recalculate applicability, execute domain controls, qualify a candidate itself, create owner-runners, modify rulesets, merge PRs, mutate Supabase, activate/cut over/rebind controls, or retire legacy validators.

## Test

```bash
python3 sandbox/lf_contract_gate_test/pase_merge_gate/test_pase_merge_gate_v1.py
```

Expected marker:

```text
PASS_PASE_MERGE_GATE_REPAIR_ENFORCEMENT_V1 checks=26
```
