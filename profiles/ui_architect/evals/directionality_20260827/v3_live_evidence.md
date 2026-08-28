# UI Architect directionality remediation V3 — live evidence

Status: SUPERSEDED_BY_MISSING_INPUT_POLICY_V2 / RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Current closure execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Historical V3 baseline main: `a8e82a9941db479775a2c78a25b590d4431fa6e6`
- Current remediation branch: `lf/ui-runtime-closure-v8-20260828`

## Historical V3 evidence preserved
Runtime request `8fdd51e7-3422-4324-b433-cce7d6b22d99` executed from historical `main@a8e82a9941db479775a2c78a25b590d4431fa6e6` with the pinned zero-cost Qwen2.5-VL 3B runtime.

That run reproduced a duplicate-amplification defect. The historical V3 remediation therefore made directionality salient and treated unresolved survivor authority as an exact `BLOCK_PIPELINE` case.

This historical observation remains valid evidence of the old defect. What is superseded is the assumption that every unresolved material input must serialize to `BLOCK_PIPELINE`.

## Missing Input Policy V2 reconciliation
The current governed Missing Input Policy distinguishes two fail-closed routes:
- `RETURN_TO_ORCHESTRATOR` when a material input can still be resolved from a governed upstream/orchestrator source;
- `BLOCK_PIPELINE` only when no safe source can resolve the material input and execution would be unsafe.

Accordingly, the V3 static assertion that required an exact `BLOCK_PIPELINE` literal in the first 25 lines is superseded by the current structured policy. The current salience test must prove both branches are explicit and that the complete Missing Input State is serialized instead of a bare action token.

## P1 closure canaries on main@5079a3f8fbb6edd4cbdfdcfa092da887479cb0e7
Two fresh zero-cost MODEL_RUNTIME executions exposed the remaining live defects before V8 remediation:

1. Resolved authority — request `5ea5c0c5-315b-4f83-b177-e64baa10e7cd`, run `33183201945`:
   - input explicitly established `Resumen` as canonical survivor and `top strip` as redundant;
   - RAW removed `top strip` but also hid `Resumen`;
   - semantic result: FAIL because the canonical survivor was destructively targeted and the output was not a complete Production UI Spec.

2. Unresolved authority — request `5ad2bde5-8d4e-438a-a55d-99cfedf51a80`, run `33183212795`:
   - RAW was only `RETURN_TO_ORCHESTRATOR`;
   - directionality was fail-closed, but the current contract requires a complete JSON Missing Input State;
   - schema result: FAIL.

Both runs were attested `MODEL_RUNTIME`, `ZERO_COST_ONLY`, on exact `main@5079a3f8fbb6edd4cbdfdcfa092da887479cb0e7`.

## V8 minimal remediation
The current branch strengthens only `profiles/ui_architect/**` behavior/evidence:
- resolved duplicate authority short-circuits to exactly one destructive remediation action against the redundant presentation;
- the survivor is retained as visible/preserved state/evidence, never a destructive target;
- existing-screen execution must serialize the complete Production UI Spec instead of an abbreviated findings fragment;
- unresolved authority must serialize the complete Missing Input State JSON;
- `RETURN_TO_ORCHESTRATOR` and `BLOCK_PIPELINE` remain distinct according to Missing Input Policy V2;
- the V3 salience test is reconciled to the current policy rather than forcing every unresolved case to BLOCK.

## Verification boundary
This file does not claim behavioral closure. Closure still requires exact-head CI, merge/readback, and two fresh post-merge MODEL_RUNTIME canaries from merged `main` proving:
1. resolved authority preserves `Resumen`, destroys only `top strip`, leaves exactly one primary amount presentation, and returns a structurally valid executable UI artifact;
2. unresolved authority does not guess and returns a schema-valid complete Missing Input State with the governed pipeline action.
