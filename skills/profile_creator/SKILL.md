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

## Transversal generated-output parity — creation and update

This is a **common prevention rule** for both `CREACION_PERFIL_LF` and
`ACTUALIZACION_PERFIL_LF`: a candidate must not repeat the PE10_C3 failure of
publishing `PASS` with a required output field absent or with an unrecognized
enum. Never copy Product/UI-specific rules into the Profile Creator/Updater.

**At creation (new profiles)**, `validate_candidate_depth.py` must inspect
the materialized positive output sample against the candidate's exact
`schemas/output.schema.json` using
`validators/profile_output_shape_preflight_v1.py`.
A missing nested required key, mistyped key, unsupported enum/const, invalid
root shape or unsupported schema applicator is a producer self-repair failure,
not `DEPTH_READY_FOR_SEMANTIC_REVIEW`. Preserve the complete source schema and
the valid positive/negative examples and the original ownership of independent
semantic review. This structural preflight is deliberately NOT a complete JSON
Schema validator and never authorizes runtime/cutover.

**At evolution (existing profiles)**, `plan_profile_evolution.py` emits
`candidate_output_contract_gate` in addition to the existing advisory
method/decision steps. When it says `REQUIRED_BEFORE_ADMISSION`, the updater
must materialize *real candidate outputs* and use the **current profile's
bound canonical schema and existing profile-local validator**, plus the shared
shape preflight where applicable, BEFORE requesting semantic/admission PASS.
A new local validator or an unqualified schema file cannot override the
authoritative runtime contract. Resolve conflicting or missing binding to
`RETURN_TO_EVIDENCE_OR_AUTHORITY`, never invent a PASS. Evidence includes:
source revision, candidate revision, output file SHA-256, exact schema/validator
references, executed validation return code and error codes, and a negative
counterexample for the material change. The profile-local validator is invoked
only by the governed execution consumer, NOT by the read-only S26 source
assessment or generic baseline AST scanner.

The executable post-generation adapter is
`validators/run_bound_profile_output_validator_v1.py --root <repo> --binding <packet.json>`.
The binding is a typed `PROFILE_OUTPUT_VALIDATION_BINDING_V1` with
`operation_code`, `profile_slug`, `expected_valid`, exact source-relative
`schema_ref`, `validator_ref`, `raw_output_ref`, their three SHA-256
digests, and a declared `validator_transport` of `STDIN_JSON` or
`JSON_FILE_ARGUMENT`. The canonical owner must resolve this binding from
current authority, not guess a path from filenames. Only the governed
post-generation consumer invokes the exact profile validator; the shared
Updater planner remains read-only and records the obligation as **unexecuted**.
Require a valid positive output and an intentional negative counterexample
using the same canonical validator. Neither an expected negative rejection
nor a local positive result is an independent acceptance or runtime receipt.

When a validator fails, allow **one bounded candidate self-repair** for the
proved defect, preserving the raw failure for comparison. Then report
`NO_QUALIFIED_GAIN` or `BLOCKED` and stop that optimization attempt; do
not create further benchmark rounds just to increase evidence counts. A
semantic tie with structural uplift is still a semantic tie. Unavailable
independent or provider attestation is a provenance blocker, not a reason
to replay all cases. In all outcomes, producer depth, deterministic parity,
functional execution and independent review remain separate, and no
candidate is auto-merged or activated.

## Transversal preventive gap review and bounded repair (Profile Updater)

This applies to **every governed profile update**, not only UI Architect or
Product Director. It complements the S26 structural compatibility baseline;
**13/13 means structural compatibility, not proven task quality**. Do not
insert new required steps into frozen v0.1 runs or create a second repair engine.
Consume `candidate_output_contract_gate.preventive_gap_review` during v0.2
planning; it is explicitly unexecuted until the existing governed consumer
materializes evidence.

At existing stage boundaries, perform only the checks relevant to the actual
task, resolved authority, frozen update outcome and material gap:

1. `baseline_read`: inspect the origin of the defect (profile generation
   instructions/template, canonical binding, current policy and matched EKB),
   not only its symptom. If an upstream shared method is wrong, repair that
   shared owner through its own governed route; profile-local fixes cannot
   substitute for the origin repair.
2. `method_selection`: resolve a real structural, functional, causal,
   uncertainty, semantic or evidence gap and qualify the smallest applicable
   method. Do not require all 13 dimensions or all capability families on
   each output; the 13-dimensional baseline remains the compatibility floor.
3. `deterministic_validation`: bind the exact current profile schema and
   canonical local validator to the generated candidate; check valid output
   and a relevant invalid counterexample. The shared runner reports exact
   errors. If source/validator authority is missing, stop: do not change the
   schema or silently waive a validator failure.
4. **Single bounded producer repair**: on a verified output defect,
   return the defect and pre-repair RAW SHA to the existing producer once.
   Correct only the candidate output or deliberate negative fixture, not the
   schema, authority, test oracle or historical RAW. The corrected output must
   be a **different bound file**, with its own SHA; the original file must be
   byte-for-byte unchanged after producer and validator execution. A local SHA
   snapshot is not a durable provider-bound RAW receipt. The governed consumer
   must separately preserve and verify both immutable outputs before admission.
   Preserve failed and corrected versions; rerun the same bound validator on the new exact head.
   The runner only **requests** remediation; the authorized producer must
   actually perform and attest it. The consumer must enforce the model/process
   timeout and budget; a synchronous local test callback does NOT provide that
   protection. No uncontrolled retry chain.
5. `regression_after` and `semantic_judge`: test material behavior
   (including critical negatives and relevant causality) against a frozen
   baseline. Mechanical shape repair does not prove functional improvement.
   An independent reviewer resolves meaningful semantic value. TIE, FAIL,
   regression or `NO_QUALIFIED_GAIN` stops the update attempt; provenance
   missing blocks admission but does not trigger more benchmark rounds.
6. `report_output`: reconcile origin correction, candidate repair, positive
   and negative validator evidence, semantic verdict, provider-bound receipts
   where required, and EKB cause/prevention readback. Record new learnings
   through the existing governed EKB/Train route, never an unapproved direct
   profile-runtime database write. Nothing auto-activates.

**Repair scope:** one bounded correction cycle **per evidenced defect in
the active candidate pass**, with a finite batch and a single post-repair
revalidation. Multiple defects can be corrected together before that rerun.
If the same defect remains or a new material gap cannot be solved safely,
stop/return to source; never silently mark a check executed or passed.
When the method itself is deficient, correct the Updater/Creator shared
origin once and preserve specialization only where a domain-owned profile
actually needs it. A reviewer MUST differ from the producer. The explicit
producer repair receipt and semantic/assurance receipts are not interchangeable.

## Handoff outcome rule

For outputs routed to Quality Pack, the evidence layers remain distinct:

1. `PRODUCER_DEPTH`: the created candidate passes `validate_candidate_depth.py`.
2. `DETERMINISTIC_INTAKE`: Quality Pack receives explicit context and the exact observable artifact.
3. `SEMANTIC_REVIEW`: an independent reviewer evaluates evidence quality, governance, safety, leakage/scope and the Quality Pack rubric.
4. `FULL_HANDOFF_OUTCOME`: only after all required layers and observable next state are complete.

Neither producer depth nor deterministic intake may be promoted to `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS`, `BEHAVIORAL_EVAL_PASS` or general semantic PASS.

A substantive Quality Pack rejection is still a valid handoff execution if the relevant receiver layer actually received and reviewed the candidate; an inability to locate the candidate is a producer handoff failure.

## Existing-profile S26 upgrade route

`ACTUALIZACION_PERFIL_LF` is the governed maintenance path for an existing profile. The updater is differential, but structural compatibility alone never authorizes a write.

Before any profile-source write, execute these gates in order:

1. Materialize a fresh `S26_PROFILE_UPDATE_LEARNING_PREFLIGHT_V1` from the live EKB/control plane and the canonical `pre_write_execution_binding_gate`.
2. Validate it with `validators/evaluate_s26_learning_preflight.py`.
3. Evaluate the target against `contracts/s26_profile_baseline_v1.json` using `validators/evaluate_s26_profile_baseline.py`.
4. Build the bounded write plan with `validators/plan_s26_profile_update.py <profile_slug> <preflight_json> [repo_root]`.

Learning Preflight rules:

- `EKB_PREFLIGHT_COMPLETED` must come from `public.lf_error_knowledge` for the current run; snapshots are not reusable across runs.
- Every matched EKB code must record exactly one `matched_prevention_rule` and exactly one prevention check. A declarative PASS without `executed=true`, `exit_code=0`, a test ID, evidence SHA and source ref is not execution evidence.
- The preflight must contain the active `ACTUALIZACION_PERFIL_LF` execution with canonical `target_type=PERFIL`, a target path inside `profiles/<slug>`, a PASS `pre_write_execution_binding_gate`, server-derived GitHub trust context, and a bound revision equal to the current repository HEAD.
- If main advances, the preflight is stale: re-read/rebind before the next write.
- Allowed write scope is only `profiles/<slug>/**`; runtime activation and production change remain false.
- `write_allowed=true` can only be emitted when Learning Preflight passes and the structural baseline says `UPDATE_REQUIRED` without authority blockers.
- The baseline evaluator is read-only by construction: callable discovery uses static AST and never imports or executes target profile validators or semantic utilities.

Structural baseline rules:

- `NO_UPDATE_REQUIRED` means the profile already satisfies all 13 S26 architectural dimensions; do not rewrite it merely to create activity.
- `UPDATE_REQUIRED` means apply only the reported `repair_actions`, preserving the profile's domain semantics and authority.
- `BLOCKED_AUTHORITY_REQUIRED` means a canonical choice cannot be derived safely (for example, multiple schemas exist and no exact runtime schema is bound). Resolve authority before writing; filename similarity is not authority.
- A profile update cannot close until the baseline is rerun on the post-write exact head and returns 13/13, in addition to the existing operation contract, validator, evidence, readback and semantic gates.
- The standard runtime integration surface is `profiles/<slug>/contracts/runtime_binding.json` (`LF_PROFILE_RUNTIME_BINDING_V1`). It binds exact profile identity, canonical runtime schema, canonical validator, profile-local deterministic semantic utility, source-first/no-invention, fail-closed, exact-head evidence and post-update baseline requirements.
- Every created or updated runtime-bound profile must also declare `model_context`, `execution_partition` and `execution_budget`. The profile owns the semantic classification; the shared Profile Runtime owns projection, transport, deterministic materialization and resource preflight.
- `model_context.full_source_to_model` must be `false`; canonical full source remains authority/receipt evidence while the model sees only the declared bounded projection.
- `execution_partition` must classify every canonical root output field as `DETERMINISTIC`, `SEMANTIC` or `HYBRID`. Every deterministic root field must have a declarative materialization source; callers and canaries must never reconstruct this split.
- `execution_budget` must declare the bounded model input/output budget and resource class. Heavy semantic inference must fail closed before model invocation when the runtime host cannot satisfy its declared resource preflight.
- Profile-local specializations belong behind this common interface. Do not add new slug-specific branches to the shared runtime when the behavior can be expressed by the runtime binding.
- The update route never activates runtime, production, automatic promotion or business effects. Those remain separate governed operations.

This flow is: live learnings -> executable prevention checks -> canonical binding -> measure -> repair only the demonstrated delta -> rerun -> close only at the common S26 compatibility floor.

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
- A profile update lacks a fresh Learning Preflight or canonical pre-write execution binding.
- A matched EKB prevention is unmapped, unexecuted, duplicated, stale or outside the exact target scope.
- Read-only profile evaluation would require importing or executing target profile code.
- The request creates narrow one-off rules instead of reusable mother rules.

## Expected statuses

- PROFILE_PACK_CREATED
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
