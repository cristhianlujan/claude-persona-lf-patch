# UI Architect directionality remediation — live evidence

Status: RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Current closure execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Historical V3 baseline main: `a8e82a9941db479775a2c78a25b590d4431fa6e6`
- Current remediation branch: `lf/ui-v10-no-fence-action-binding-20260828`

## Historical V3 evidence preserved
Runtime request `8fdd51e7-3422-4324-b433-cce7d6b22d99` executed from historical `main@a8e82a9941db479775a2c78a25b590d4431fa6e6` with the pinned zero-cost Qwen2.5-VL 3B runtime.

That run reproduced a duplicate-amplification defect. The historical V3 remediation therefore made directionality salient and treated unresolved survivor authority as an exact `BLOCK_PIPELINE` case.

This historical observation remains valid evidence of the old defect. What is superseded is the assumption that every unresolved material input must serialize to `BLOCK_PIPELINE`.

## Missing Input Policy V2 reconciliation
The current governed Missing Input Policy distinguishes two fail-closed routes:
- `RETURN_TO_ORCHESTRATOR` when a material input can still be resolved from a governed upstream/orchestrator source;
- `BLOCK_PIPELINE` only when no safe source can resolve the material input and execution would be unsafe.

Accordingly, the V3 static assertion that required an exact `BLOCK_PIPELINE` literal is superseded by the current structured policy. The current salience test must prove both branches are explicit and that the complete Missing Input State is serialized instead of a bare action token.

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
V8 strengthened only `profiles/ui_architect/**` behavior/evidence:
- resolved duplicate authority short-circuits to exactly one destructive remediation action against the redundant presentation;
- the survivor is retained as visible/preserved state/evidence, never a destructive target;
- existing-screen execution must serialize the complete Production UI Spec instead of an abbreviated findings fragment;
- unresolved authority must serialize the complete Missing Input State JSON;
- `RETURN_TO_ORCHESTRATOR` and `BLOCK_PIPELINE` remain distinct according to Missing Input Policy V2.

## Post-V8 canaries on main@b97234d2c87f0c0211c290f668b195b577002787
Two fresh zero-cost `MODEL_RUNTIME` runs evaluated merged PR #289:

1. Unresolved authority — request `f383677a-0e3b-44ea-a991-5b68f79fcc2d`, run `33185648132`:
   - returned one complete Missing Input State;
   - did not guess the survivor;
   - used `pipeline_action=RETURN_TO_ORCHESTRATOR`;
   - structural and semantic result: PASS.

2. Resolved authority — request `337fd41d-a86d-428a-9441-10c119173582`, run `33185638102`:
   - preserved `payment_summary` and removed only `top_amount_strip`;
   - satisfied semantic direction and survivor invariant;
   - repeated the top-level `score`, `handoff_to_next`, and `self_verdict` tail after an early root close;
   - omitted mandatory `evidence_component_ids` from the remediation action;
   - structural result: FAIL because RAW was not one valid contract-complete JSON object.

Both runs are attested `MODEL_RUNTIME`, `ZERO_COST_ONLY`, on exact merged `main@b97234d2c87f0c0211c290f668b195b577002787`.

## V9 remediation and post-merge evidence
PRs #290 and #291 added a single-envelope guard and made `evidence_component_ids` mandatory in the runtime-critical gate. PR #291 merged as exact `main@27849cf7ff743ff232375fcb7629c873c6916a67`.

Fresh resolved-authority Canary A — request `7c126b8b-5077-4b22-90e0-18c3973c964e`, run `33188587221`:
- execution origin: `MODEL_RUNTIME`;
- zero-cost provider: `local_llama_cpp_github_standard_public`;
- exact runtime SHA: `27849cf7ff743ff232375fcb7629c873c6916a67`;
- semantic direction: PASS — `payment_summary` remained canonical/visible and only `top_amount_strip` was targeted for removal;
- structural result: FAIL — assistant output was wrapped in Markdown JSON fences and the emitted remediation action still omitted `evidence_component_ids`;
- closure impact: P1 remains open; execution 007 must not be completed from this run.

This run demonstrates that declarative prohibition alone was insufficient for the pinned small runtime because the nearby positive examples themselves still rehearsed fenced JSON and the action-binding field was not salient enough during serialization.

## V10 minimal remediation
V10 remains strictly profile-local and does not change Router, Shell, adapter, runtime infrastructure, policy, Supabase schema, production state, `VALIDATED`, or automatic promotion.

It adds only serialization salience:
- the first non-whitespace output byte must be `{` and the last must be `}`;
- zero backticks / zero Markdown fences / zero surrounding prose;
- positive JSON examples are presented unfenced so the runtime is not primed to copy a forbidden wrapper;
- every existing-screen remediation action must write `evidence_component_ids` before `evidence_anchor` and include both the redundant execution target and canonical survivor;
- pre-output self-repair explicitly rejects fenced or missing-binding artifacts.

## Verification boundary
This file does not claim behavioral closure. Closure still requires exact-head CI, merge/readback, and two fresh post-merge `MODEL_RUNTIME` canaries from merged `main` proving:
1. resolved authority preserves `payment_summary`, destroys only `top_amount_strip`, leaves exactly one primary amount presentation, emits no Markdown wrapper, includes valid `evidence_component_ids`, and returns a structurally valid executable UI artifact;
2. unresolved authority does not guess and returns an unfenced schema-valid complete Missing Input State with the governed pipeline action.
