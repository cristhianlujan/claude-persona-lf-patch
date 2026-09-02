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

## Adapter factory composition

`ACT-0045` also provides the reusable factory core when the resolved target capability is an Adapter. This is composition, not permission to make Profile Creator a second Adapter authority.

For an Adapter request:

1. reuse the common factory concerns already owned here: authority/context resolution, duplicate check, research when applicable, generic-vs-specific boundary, candidate design, evidence, sandbox/reviewability and governed handoff;
2. resolve `CREACION_ADAPTER_LF` as the Adapter specialization through Router;
3. apply `skills/profile_creator/adapters/adapter_factory_binding.md` plus the canonical Adapter contract/procedure;
4. keep the resulting Adapter Router-bound and explicitly mapped to its consumer(s);
5. never create an Adapter as an alternate worker, never let it choose workers independently, and never require a second Adapter-specific LLM call;
6. do not copy the common factory lifecycle into another parallel creation pipeline.

`ACT-0045` is the factory core, not the owner/parent authority of the resulting Adapter. Adapter invocation authority remains the Router and its explicit binding.

Input Governance is not called directly by the Profile because an Adapter exists. When governance is needed, the Profile declares the need; the governed Adapter mediation contract decides applicability, selects only required governance sections and returns the governed receipt. Direct Profile → `INPUT_GOVERNANCE_AGENT` invocation is forbidden.

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
- Adapter creation bypasses `CREACION_ADAPTER_LF` specialization or duplicates the common factory lifecycle.
- A Profile directly invokes `INPUT_GOVERNANCE_AGENT` instead of declaring governance need for Adapter mediation.

## Expected statuses

- PROFILE_PACK_CREATED
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
