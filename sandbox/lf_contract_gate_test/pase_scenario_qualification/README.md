# PASE_SCENARIO_QUALIFICATION_MATRIX_V1

## Purpose

Prevent realistic reachable PASE states from being discovered for the first time during production or normal post-merge operation, without turning qualification into an unbounded mega-suite.

This is a qualification overlay. It is **not** a second Changeset Governance/applicability authority.

## Contract

Scenario selection is deterministic:

`control maturity + declared traits + catalog predicates -> selected scenario set`

For every catalog scenario:

- selected -> `TESTED` or `BLOCKED_EXPLICITLY`, with exact-head/bounded evidence;
- unselected -> `NOT_APPLICABLE`, with a machine-derived predicate reason;
- selected + no assertion/evidence -> `BLOCK_SCENARIO_SELECTED_UNKNOWN`.

`UNKNOWN` is never a terminal state for a selected scenario.

Evidence commands are deduplicated and run with `shell=False`; only repository-local Python tests under `sandbox/lf_contract_gate_test/` are admitted.

## Maturity behavior

A scenario may be `NOT_APPLICABLE` during CUTOVER and become mandatory at ACTIVE. This is intentional.

Example: `MIGRATION_SOURCE_PARITY` does not declare `ORCHESTRATOR_ENTRY` during the current CUTOVER because receipt enforcement is deliberately deferred. F06 must re-resolve the matrix at ACTIVE maturity; then valid dispatch, missing receipt BLOCK and direct-call BLOCK become selected.

## Relationship to existing qualification

`PASE_CONTROL_QUALIFICATION_V1` remains the candidate qualification/verdict authority. The scenario matrix supplies reusable evidence for Q06 (negative/adversarial coverage), Q10 (coverage preserved), and the activation gate. It does not change the existing qualification receipt schema.

F04-Q99 requires terminal scenario coverage. F06 re-runs scenario resolution for ACTIVE_BLOCKING transition.

## First consumer

`MIGRATION_SOURCE_PARITY` uses `profiles/migration_source_parity_v1.json`.

The profile covers Git lifecycle/currentness, Changeset Governance N/A behavior, authority, canonical carrier/decontamination, exact-head evidence, retry/concurrency, historical causal/non-causal behavior, migration add/modify/delete/rename/version/content states, external dependency failure and post-merge readback.

Historical broad scan remains outside the current PASE critical path unless causal/material binding is demonstrated.

## Evidence

Runtime output is written to the control's existing bounded evidence directory as `scenario-qualification.json`, so the normal no-ZIP exact-head evidence path remains intact.
