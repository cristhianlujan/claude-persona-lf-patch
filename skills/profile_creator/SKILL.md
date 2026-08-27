# SKILL — LF Profile Creator

## Role

Create complete LF profile pack candidates under governance control. A pack is not complete merely because its files exist: the producer must prove that the candidate is sufficiently developed for independent semantic review.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → Active governing asset → Adapter when applicable → Operation → Verification → Closure.

If two live authorities disagree, or a required destination/contract cannot be resolved, block and report the conflict. Never choose a structural identifier or requirement because it matches the observed repository state or a translated handoff.

## Inputs

- Requested profile purpose.
- Scope and target user/task.
- Source authority with exact references.
- Allowed and blocked impacts.
- Required gates.
- Existing assets to avoid duplication.
- Whether the profile exposes user-facing output.

## Outputs

A structured profile pack candidate containing developed:

- Profile/skill definition.
- Contracts and failure routing.
- Typed schemas.
- Judges/rubrics.
- Checklists.
- Positive and negative examples.
- Positive and negative evals with assertions.
- Fixtures.
- Executable validators.
- Actionable handoffs.
- Adapters.
- `manifest.json` when the resolved destination requires it.

The candidate artifact must also declare:

- `artifact_type=PROFILE_PACK_CANDIDATE`;
- `profile_pack_id`;
- `source_authority`;
- candidate/read-only/runtime/automatic-impact boundaries;
- `exposes_user_facing_output` as a boolean;
- an `evidence_map` with explicit `source_ref` and supported claims;
- the materialized `files` map.

When `exposes_user_facing_output=true`, the generated profile must separate user-facing content from orchestration metadata through an explicit contract boundary such as `user_payload` / `internal_envelope`. When false, the candidate must not invent that boundary merely to satisfy a template.

## Deterministic depth gate

Before returning `PROFILE_PACK_CREATED`, execute:

`skills/profile_creator/validators/validate_candidate_depth.py <deliverable_artifact_ref>`

The required result is:

`DEPTH_READY_FOR_SEMANTIC_REVIEW`

The validator checks deterministic reviewability invariants: developed core contracts, typed output schema, traceable evidence, positive and negative evals with assertions, actionable Quality Pack handoff, governance boundaries, and conditional user/internal output separation.

This depth gate is **not** semantic Quality Pack approval. It must return `semantic_quality_review=NOT_EXECUTED`. A candidate that fails the gate returns to the worker for self-repair.

The outer Profile Creator result must include a `depth_gate` receipt bound to the exact same `deliverable_artifact_ref`.

## Handoff outcome rule

For outputs routed to Quality Pack, the evidence layers remain distinct:

1. `PRODUCER_DEPTH`: the created candidate passes `validate_candidate_depth.py`.
2. `DETERMINISTIC_INTAKE`: Quality Pack receives explicit context and the exact observable artifact.
3. `SEMANTIC_REVIEW`: an independent reviewer evaluates evidence quality, governance, safety, leakage/scope and the Quality Pack rubric.
4. `FULL_HANDOFF_OUTCOME`: only after all required layers and observable next state are complete.

Neither producer depth nor deterministic intake may be promoted to `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS`, `BEHAVIORAL_EVAL_PASS` or general semantic PASS.

## Blocking rules

Block or return when:

- Source authority is missing, contradictory or unresolved.
- ACT-0045 or the applicable asset is not verified.
- A required destination contract cannot be resolved.
- The request tries to create a final operational profile directly.
- The request enables runtime or production general.
- The output is only prose, filenames or prompt text.
- `PROFILE_PACK_CREATED` is claimed without a resolvable created candidate artifact.
- The resolved destination requires `manifest.json` and the candidate does not materialize it.
- The manifest contradicts profile identity, operation, candidate/read-only status, runtime or automatic-impact boundaries.
- The candidate lacks developed contract/schema/judge/evals/handoff/evidence required by the deterministic depth gate.
- A user-facing profile exposes internal orchestration metadata without a protected output boundary.
- `depth_gate.candidate_ref` differs from `deliverable_artifact_ref`.
- Producer depth or deterministic intake is presented as semantic Quality Pack approval.
- A full handoff outcome is claimed while a required receiver layer remains unexecuted.
- The request creates narrow one-off rules instead of reusable mother rules.

## Expected statuses

- PROFILE_PACK_CREATED
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
