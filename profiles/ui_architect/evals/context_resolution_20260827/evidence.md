# UI Architect Context Resolution V5 — Evidence

Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260827-004`
Target: `PERFIL-UI-ARCHITECT`
Baseline main: `2e451cfbddf52c819290da2e9490c4936fc78fef`
Scope: `profiles/ui_architect/**`
Status: candidate evidence only; no runtime enablement or automatic promotion.

## Reconciliation note
During PR #250 validation, `main` advanced with a separate governed UI Architect directionality hardening. The candidate was rebuilt on the new `main` before merge. The new runtime-critical directionality gate is preserved verbatim and the context-resolution invariant is layered beneath it.

## Problem demonstrated
The profile already had executable remediation and defect-direction protections, but implementation precision could still fail in three ways:

1. canonical context exists but the output degrades it to vague language such as `dar más aire`;
2. no canonical token exists and exploratory work is blocked or false precision is presented as authority;
3. a materially unresolved interaction/business rule is silently invented or asked directly from the end user instead of routed through the orchestrator.

## Runtime-source correction
`SKILL.md` now carries both runtime protections:

`DEFECT -> CORRECTION -> POSTCONDITION`

followed by:

`CANONICAL -> UPSTREAM -> EXPLORATORY/RELATIVE -> RETURN_TO_ORCHESTRATOR_IF_MATERIAL`

The first prevents semantic direction inversion; the second prevents vague precision, false authority and unnecessary blocking.

## Deterministic context-resolution matrix
Runner:
`profiles/ui_architect/evals/context_resolution_20260827/run_context_resolution_cases.py`

Expected/observed contract result: `CONTEXT_RESOLUTION_MATRIX_PASS=11/11`.

Covered cases:
- canonical `space_24` used and source-bound: PASS;
- canonical token degraded to vague wording: rejected;
- no-token concrete exploratory proposal labeled non-canonical: PASS;
- no-token relative guidance: PASS;
- exploratory case blocked only because token is missing: rejected;
- invented DS token represented as canonical: rejected;
- material interaction ambiguity returned to orchestrator: PASS;
- material interaction silently assumed: rejected;
- recoverable canonical context escalated again: rejected;
- worker asks final user directly: rejected;
- partial-context holdout uses known `space_16`: PASS.

## Semantic judge expectations
The semantic judge must additionally reject:
- a supplied/resolved canonical token that materially applies but is omitted from the handoff;
- a proposal represented as canonical/upstream authority;
- unnecessary blocking caused solely by absence of a visual token;
- materially unresolved CTA/state behavior invented without source;
- any regression of the runtime-critical defect-direction invariant.

## Compact-report expectation
Precision must not create an oversized visible audit. Each material finding should communicate only:

`Observation -> selected correction -> exact canonical/upstream value OR labeled proposal/relative rule`

Internal EKB, schema and governance metadata remain outside the normal user-facing UI review.
