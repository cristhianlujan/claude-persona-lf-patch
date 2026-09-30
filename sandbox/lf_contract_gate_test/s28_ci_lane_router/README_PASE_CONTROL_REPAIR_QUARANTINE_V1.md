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

A control returns to `ACTIVE_BLOCKING` one at a time. Silent reactivation is forbidden.

The single administrative owner for PASE controls is `LF_GOVERNANCE`. Carrier identity is transport only and must never be interpreted as owner identity.

Re-entry requires all of:

1. exact-head `CANDIDATE_QUALIFIED`;
2. `administrative_owner = LF_GOVERNANCE`;
3. classification-aware runner binding:
   - `INTERNAL_CI_CHECK -> runner_binding = NOT_REQUIRED`;
   - controls whose canonical destination requires its own runner -> `CANONICAL_RUNNER_REQUIRED -> runner_binding = PASS`;
4. equivalent replay `PASS`;
5. exact-head readback `PASS`.

This distinction prevents an internal CI check from being promoted into a fake standalone capability merely to satisfy quarantine re-entry. It also preserves fail-closed behavior for controls that really require a canonical runner.

Returning one control must not reactivate any other control.

## Non-goals

This solution does not:

- classify repository paths;
- recalculate applicability;
- execute domain controls;
- delete or rewrite legacy validators;
- create owner-runners;
- create capabilities from internal CI checks;
- activate, cut over, rebind, or retire any control;
- mutate Supabase;
- mutate GitHub rulesets;
- authorize merge by itself.

## Deterministic evidence

`test_lf_pase_control_repair_quarantine_v1.py` verifies the live 25-control universe, all-observe-only transition behavior, diagnostic allowance, no second-router behavior, deterministic digests, single-admin-owner enforcement, classification-aware runner binding, fail-closed negative cases, policy coverage, replay and exact-head requirements.

Expected marker:

`PASS_PASE_CONTROL_REPAIR_QUARANTINE_V1 checks=27`
