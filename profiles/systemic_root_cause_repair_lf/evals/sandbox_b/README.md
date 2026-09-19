# Sandbox B — SRCR semantic judge

This sandbox tests the minimal proposal B only:
- preserve the current SRCR producer architecture;
- preserve the current 12 omission dimensions and 8 falsification families;
- make the existing semantic-judge stage independently reconcile candidate changes against exact run scope.

## Holdout
Source execution: `EXEC-SRCR-PILOT-SPEC-R2-20260919-001`
Exact candidate SHA-256: `5f18b8c23bb439c3790c53c01099753f7f3d53cbe897b407f7da413b202827ff`.

The candidate contains D3 / deliverable CREATE FUNCTION `public.lf_operation_lifecycle_readiness_v1(text,text)`.
Backlog #186 exact footprint enumerates existing caller writes plus `lf_operation_steps` / `lf_operation_step_contracts`; the new pg_proc is outside that exact child footprint.

Expected B verdict: `RETURN_TO_WORKER_FOR_SELF_REPAIR` with `OUT_OF_SCOPE_DESIGN_DELTA`.

## Deterministic tests
`run_cases.py` validates:
1. the semantic RETURN result is structurally/coverage valid;
2. changing the same result to semantic PASS fails closed;
3. omitting JCHG-002 from scope reconciliation fails coverage.

The deterministic validator never decides that D3 is out of scope. That conclusion belongs to the semantic judge. The validator only proves the semantic result did not omit observed-change coverage or contradict its own findings.

## Evidence ceiling
This is sandbox evidence only. It does not alter Supabase, runtime activation, profile source promotion, the production operation judge, or the current producer architecture.
