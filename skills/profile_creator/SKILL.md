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
- Fixtures.
- Executable validators.
- Positive and negative evals with assertions.
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

When returning `PROFILE_PACK_CREATED`, the output must deliver the created candidate through an exact `deliverable_artifact_ref`. The receiver must be able to inspect that artifact directly; a pack ID, a list of intended filenames or a prose description is not evidence that the pack exists.

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

A substantive Quality Pack rejection is still a valid handoff execution if the relevant receiver layer actually received and reviewed the candidate; an inability to locate the candidate is a producer handoff failure.

## Existing-profile S26 upgrade route

`ACTUALIZACION_PERFIL_LF` is the governed maintenance path for an existing profile. Before any profile-source write, the updater must evaluate the target against `contracts/s26_profile_baseline_v1.json` using `validators/evaluate_s26_profile_baseline.py` (or the planning wrapper `validators/plan_s26_profile_update.py`).

Rules:

- `NO_UPDATE_REQUIRED` means the profile already satisfies all 10 S26 architectural dimensions; do not rewrite it merely to create activity.
- `UPDATE_REQUIRED` means apply only the reported `repair_actions`, preserving the profile's domain semantics and authority.
- `BLOCKED_AUTHORITY_REQUIRED` means a canonical choice cannot be derived safely (for example, multiple schemas exist and no exact runtime schema is bound). Resolve authority before writing; filename similarity is not authority.
- A profile update cannot close until the baseline is rerun on the post-write exact head and returns 10/10, in addition to the existing operation contract, validator, evidence, readback and semantic gates.
- The standard runtime integration surface is `profiles/<slug>/contracts/runtime_binding.json` (`LF_PROFILE_RUNTIME_BINDING_V1`). It binds exact profile identity, canonical runtime schema, canonical validator, profile-local deterministic semantic utility, source-first/no-invention, fail-closed, exact-head evidence and post-update baseline requirements.
- Profile-local specializations belong behind this common interface. Do not add new slug-specific branches to the shared runtime when the behavior can be expressed by the runtime binding.
- The update route never activates runtime, production, automatic promotion or business effects. Those remain separate governed operations.

This makes the updater differential: measure -> repair only the demonstrated delta -> rerun -> close only at the common S26 compatibility floor.

## CI profile-validator discovery contract

The repository's existing `Validate LF Packs` workflow invokes `skills/profile_creator/validators/validate_pack.py`. That validator is therefore the reusable discovery boundary for profile-local deterministic pack validation; no profile slug may be hardcoded as a privileged canary.

Rules:

- A governed profile opts into this CI boundary by materializing `profiles/<slug>/validators/validate_pack.py`.
- Profile Creator discovers every such entrypoint under `profiles/`, excluding template/private underscore directories.
- Each discovered validator executes exactly once and its stdout/stderr remains visible in CI evidence.
- A discovered validator failure fails Profile Creator validation; a later PASS cannot mask it.
- A profile without the entrypoint is not silently treated as validated; it is simply outside this deterministic CI contract until the profile publishes the entrypoint through its own governed update.
- Symlinked or out-of-tree validators are rejected.
- Discovery must remain generic: a future profile that publishes the contract is picked up without changing `.github/workflows/**` or adding its slug to Profile Creator.

This boundary proves only deterministic/profile-local validation at the exact checkout. It does not replace semantic judge execution, Router/direct behavioral evidence, runtime receipts, post-merge smoke, independent audit, runtime authorization or promotion.

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
