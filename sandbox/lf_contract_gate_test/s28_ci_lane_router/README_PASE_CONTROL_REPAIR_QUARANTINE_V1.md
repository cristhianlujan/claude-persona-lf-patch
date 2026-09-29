# PASE_CONTROL_REPAIR_QUARANTINE_V1

## Purpose

Temporarily remove legacy validators that are under repair from **merge-blocking authority** without deleting them, disabling diagnostics, or changing Changeset Governance applicability.

Canonical flow during the repair window:

`Changeset Governance -> lf-ci-execution-plan/v2 -> repair enforcement projection -> PASE merge decision`

The execution plan continues to declare which controls are applicable. This solution only projects each applicable control into one of two enforcement states:

- `REPAIR_OBSERVE_ONLY`: may execute for diagnosis/evidence, but its result cannot block merge.
- `ACTIVE_BLOCKING`: may block merge only after the complete re-entry contract is present.

## Current transition state

All 25 controls in `lf-ci-control-impact-registry/v2` are `REPAIR_OBSERVE_ONLY` while the validator estate is being decomposed and requalified.

This does **not** disable structural governance. The following remain fail-closed and are outside the quarantine:

- repository path admission;
- execution-plan schema and complete control-universe coverage;
- exact control-policy coverage and digest binding;
- exact-head `PASE_CONTROL_QUALIFICATION_V1` for control-system candidates;
- pull-request / non-fast-forward / deletion repository rules.

## Re-entry contract

A control returns to `ACTIVE_BLOCKING` one at a time. Silent reactivation is forbidden. Re-entry requires all of:

1. `CANDIDATE_QUALIFIED`;
2. owner-runner binding readback `PASS`;
3. equivalent replay `PASS`;
4. exact-head readback `PASS`.

Returning one control must not reactivate any other control.

## Non-goals

This solution does not:

- classify repository paths;
- recalculate applicability;
- execute domain controls;
- delete or rewrite legacy validators;
- create owner-runners;
- activate, cut over, rebind, or retire any control;
- mutate Supabase;
- mutate GitHub rulesets;
- authorize merge by itself.

## Deterministic evidence

`test_lf_pase_control_repair_quarantine_v1.py` verifies the live 25-control universe, all-observe-only transition behavior, diagnostic allowance, no second-router behavior, deterministic digests, fail-closed policy coverage, and the mandatory four-part re-entry contract.

Expected marker:

`PASS_PASE_CONTROL_REPAIR_QUARANTINE_V1 checks=20`
