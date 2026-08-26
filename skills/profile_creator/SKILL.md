# SKILL — LF Profile Creator

## Role

Create complete LF profile pack candidates under governance control.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → Active governing asset → Adapter when applicable → Operation → Verification → Closure.

## Inputs

- Requested profile purpose.
- Scope and target user/task.
- Source authority.
- Allowed and blocked impacts.
- Required gates.
- Existing assets to avoid duplication.

## Outputs

A structured profile pack candidate containing:

- Profile definition.
- Contracts.
- Schemas.
- Judges.
- Checklists.
- Examples.
- Fixtures.
- Validators.
- Evals.
- Handoffs.
- Adapters.
- `manifest.json` when the resolved `PROFILE_PACK` destination requires it. The manifest must preserve profile identity, operation, file inventory and the candidate/read-only/runtime/automatic-impact boundaries from governing authority.

When returning `PROFILE_PACK_CREATED`, the output must also deliver the created candidate through an exact `deliverable_artifact_ref`. The receiver must be able to inspect that artifact directly; a pack ID, a list of intended filenames or a prose description is not evidence that the pack exists.

## Handoff outcome rule

For outputs routed to Quality Pack, success is not that Profile Creator says the pack was created. The created candidate must be observable and Quality Pack must be able to continue from that delivered artifact without inventing missing structure, content or intent.

Receiver evidence is evaluated in separate layers:

1. `DETERMINISTIC_INTAKE`: proves that Quality Pack received explicit context and an observable artifact with consistent identity.
2. `SEMANTIC_REVIEW`: evaluates evidence quality, governance, safety, leakage/scope and the Quality Pack rubric.
3. `FULL_HANDOFF_OUTCOME`: is proven only after all required receiver layers and observable next state are complete.

A deterministic intake PASS is valid receiver execution evidence for the intake layer, but it is not a semantic Quality Pack PASS and must never be promoted to `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS` or a general behavioral PASS. When intake is executed successfully but semantic review has not run, the current blocker is `SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED`. The older `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER` may remain only as historical evidence for runs made before an executable intake target existed.

A substantive Quality Pack rejection is still a valid handoff execution if the relevant receiver layer actually received and reviewed the candidate; an inability to locate the candidate is a producer handoff failure.

## Blocking rules

Block or return to orchestrator when:

- Source authority is missing.
- ACT-0045 or applicable asset is not verified.
- The request tries to create a final operational profile directly.
- The request enables runtime or production general.
- The output is only prose or prompt text.
- `PROFILE_PACK_CREATED` is claimed without a resolvable created candidate artifact.
- The resolved `PROFILE_PACK` destination requires `manifest.json` and the created candidate does not materialize it.
- The manifest contradicts the governing profile identity, operation, candidate/read-only status, runtime boundary or automatic-impact boundary.
- Deterministic intake evidence is presented as semantic Quality Pack approval.
- A full handoff outcome is claimed while a required receiver layer remains unexecuted.
- The request creates narrow one-off rules instead of reusable mother rules.

## Expected statuses

- PROFILE_PACK_CREATED
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
