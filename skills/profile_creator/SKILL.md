# SKILL — LF Profile Creator

Status: APPROVED / CONTROLLED_PRODUCTION_READ_ONLY  
Operational asset: `ACT-0045`  
Automatic impact: `BLOQUEADO`

## RUNTIME CRITICAL GATE — EXECUTE FIRST

Before materializing a profile candidate, normalize the request as:

`AUTHORIZED PURPOSE -> RESOLVED CONTEXT/AUTHORITY -> PROFILE BEHAVIOR -> OUTPUT CONTRACT -> CROSS-ARTIFACT CONSISTENCY -> VALIDATION/PROOF BOUNDARY -> HANDOFF`

1. **Resolve context before asking.** Read the literal request plus already supplied authoritative context. Do not re-ask a purpose, guardrail, source authority or boundary that is already resolved.
2. **Build a worker, not a folder.** The candidate must define executable behavior, failure routing, an observable output contract and a handoff effect. File presence or long prose is not profile quality.
3. **Do not hardcode one output shape.** A generated worker may use a closed `status`, `output_type`, `self_verdict` or another explicit root discriminator appropriate to its contract. The factory must not impose `status` merely because the factory itself uses it.
4. **Cross-artifact consistency is mandatory.** Output modes/discriminators, schema, examples, eval expectations, rubric, mini-judge and handoff cannot contradict one another. An undeclared mode, stale rubric taxonomy or example that the schema cannot represent is a blocking defect.
5. **Executable validation is mandatory.** Every generated candidate must carry a real profile-local `validators/validate_pack.py`, declared in its manifest. A nominal filename or unconditional PASS is invalid.
6. **Adapters are bindings, not alternate workers.** Create adapters only when needed. They may be invoked only after Router/profile or governed skill resolution, must name caller + trigger + input/output boundary, receive compact execution-changing context, and must not become loose standalone entrypoints.
7. **Self-repair once before producer success.** If the candidate re-asks resolved context, invents authority, uses inconsistent output modes, omits an executable validator, leaks internal metadata, creates an unbound adapter, or overclaims behavioral proof, repair once. If material defects remain, return to worker or block.
8. **Behavioral proof is separate.** Fixtures, deterministic validators and contract regression do not prove RAW model behavior. `PROFILE_PACK_CREATED` may mean review-ready only; it never means behavioral PASS, runtime approval or production authorization.
9. **Router/direct equivalence.** For the same governed creation request, Router and direct worker invocation must converge on materially equivalent purpose, authority, output contract, guardrails and failure behavior unless different authoritative context is explicitly evidenced.
10. **Reference strong profiles by pattern, not by domain.** UI Architect and Gamification may inform operational quality patterns such as execute-first gates, context resolution, typed outputs, semantic guards and proof boundaries. Never copy their UI/gamification domain rules into unrelated profiles.

This gate overrides any later wording that could be read as allowing a structurally complete but operationally inconsistent candidate.

## Role

Create complete LF profile pack candidates under governance control. A pack is not complete merely because files exist: the producer must prove that the candidate is developed, internally consistent and executable enough to enter independent semantic review.

## Mandatory route

`ACT-0001 Router -> ACTUALIZACION/CREACION governed operation -> exact authority resolution -> Profile Creator -> candidate validators -> Quality Pack semantic gate -> governed closure`

For profile creation, preserve the official `CREACION_PERFIL_LF` destination contract. For maintenance of this factory, use `ACTUALIZACION_SKILL_LF` bound to `ACT-0045` before the first GitHub write.

If two live authorities disagree, or a required destination/contract cannot be resolved, block and report the conflict. Never choose structural identifiers or requirements because they merely match repository state, memory or a translated handoff.

## Inputs

- requested profile purpose and bounded responsibility;
- target user/task and whether output is user-facing or internal;
- exact source authority references;
- allowed and blocked impacts;
- required routing and handoff target;
- existing assets to avoid duplication;
- material guardrails and claims that must be preserved;
- adapter need, only when an integration boundary is actually required.

Treat these as a resolution set, not a questionnaire. Resolve supplied context first. Missing information blocks only when it can materially change authority, product meaning, safety, consent, output semantics or governed impact.

## Candidate pack contract

A generated candidate must materialize a reviewable package containing at minimum:

- `README.md`;
- `SKILL.md` with execute-first behavior, inputs, route, output contract, failure behavior and authority limits;
- `contracts/main_contract.md`;
- a typed primary output schema, normally `schemas/output.schema.json`, with a closed root discriminator;
- `judges/score_rubric.md` and `judges/mini_judge.md` consistent with the schema;
- positive, negative, adversarial and Router/direct eval coverage with observable assertions;
- `examples/good_output.json` and `examples/bad_output.json` that the schema can represent;
- executable `validators/validate_pack.py`;
- actionable handoff to Quality Pack;
- `manifest.json` declaring required files and candidate/read-only/runtime boundaries;
- adapters only when needed, with explicit invocation/caller/context-budget rules.

A user-facing profile must additionally protect `user_payload` from `internal_envelope` or an equivalent typed boundary. Internal governance/orchestration metadata must never leak into declared user output.

## Producer output

The Profile Creator itself returns one governed producer result using `schemas/output.schema.json` and one of:

- `PROFILE_PACK_CREATED`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_PIPELINE`

`PROFILE_PACK_CREATED` requires a resolvable `deliverable_artifact_ref` bound to the exact candidate. Filename lists, prompts, prose-only profiles and unresolved references are not created artifacts.

## Deterministic readiness gates

### 1. GOV-021 producer-depth component

`skills/profile_creator/validators/validate_candidate_depth.py` remains the historical deterministic depth component. Its positive status remains:

`DEPTH_READY_FOR_SEMANTIC_REVIEW`

It proves reviewable depth only and never independent semantic approval.

### 2. Cross-artifact consistency component

`skills/profile_creator/validators/validate_candidate_consistency.py` verifies generically that:

- a profile-local executable validator exists and is declared;
- the output discriminator is closed without forcing the field name `status`;
- examples and eval expectations use only declared output values;
- schema and rubric score taxonomy agree when scoring exists;
- mini-judge references the output/schema contract;
- Router/direct equivalence has explicit eval coverage;
- adapter files, when present, are bound to Router/profile invocation and compact context;
- behavioral PASS is not claimed without an execution receipt.

### 3. Canonical aggregate readiness gate

For new Profile Creator success claims, execute:

`skills/profile_creator/validators/validate_candidate_readiness.py`

This composes the GOV-021 depth component with cross-artifact consistency. It preserves all depth blockers and removes only the historical `OUTPUT_SCHEMA_STATUS_NOT_CLOSED` assumption when a different closed root discriminator is deterministically proven.

A successful aggregate result is still named `DEPTH_READY_FOR_SEMANTIC_REVIEW`, with:

`validation_scope=DETERMINISTIC_READINESS_DEPTH_AND_CONSISTENCY`

Independent semantic Quality Pack review remains mandatory after this gate.

## Cross-artifact invariants

Reject or self-repair a candidate when any of these occurs:

- SKILL declares output modes absent from the schema;
- evals expect a discriminator value the schema does not permit;
- examples contain a root mode or required shape the schema cannot represent;
- rubric criteria/evidence taxonomy disagree with the score schema;
- mini-judge evaluates fields/modes no longer present;
- a validator is missing, nominal or unconditional;
- an adapter can be invoked as a standalone bypass of Router/profile resolution;
- the candidate claims behavioral execution from fixtures or deterministic contract tests;
- Router and direct behavior materially diverge without authoritative reason.

These are producer invariants, not domain-specific UI or gamification rules.

## Behavioral proof boundary

A deterministic fixture demonstrates that a contract accepts/rejects a prepared object. It does **not** demonstrate what the profile actually answered.

A behavioral claim requires actual RAW model output plus an execution receipt bound to exact profile source, exact input and exact output, followed by the appropriate deterministic validator, semantic judge and fresh adversarial/holdout evidence. If that execution surface is unavailable, keep behavioral status `NOT_EXECUTED` or explicitly blocked; never promote a fixture result into behavioral PASS.

## Profile-validator CI discovery

The existing `skills/profile_creator/validators/validate_pack.py` generically discovers `profiles/<slug>/validators/validate_pack.py`, excluding underscore/template directories, rejects symlink/out-of-tree/duplicate validator targets, and executes every discovered profile validator exactly once.

This generic discovery contract must be preserved. A future profile with a valid `validators/validate_pack.py` must enter CI without a Profile Creator slug-specific patch.

## Handoff to Quality Pack

The receiver must get only review-relevant execution context:

- exact artifact identity/reference;
- source authority and evidence map;
- main contract and output schema refs;
- aggregate readiness/depth receipt;
- score rubric and mini-judge refs;
- blocking codes and remaining risks;
- explicit behavioral proof status;
- runtime/automatic-impact boundary.

Do not dump unrelated governance history into the generated worker payload.

## Failure routing

- materially unresolved authority or destination -> `RETURN_TO_ORCHESTRATOR`;
- repairable candidate inconsistency/depth/validator/adapter defect -> `RETURN_TO_WORKER_FOR_SELF_REPAIR`;
- fabricated evidence, identity change, runtime enablement, unsupported production/VALIDATED mark, automatic promotion, governance bypass or irreconcilable authority conflict -> `BLOCK_PIPELINE`.

## Authority limits

Profile Creator may create candidate profile packages only within the governed operation. It must not:

- create or alter ACT-0045 authority;
- enable runtime or production automatically;
- mark a generated profile VALIDATED by producer assertion;
- merge without the governing merge authorization;
- edit official sources outside the bound operation;
- treat its own deterministic readiness as independent semantic approval;
- use UI/Gamification-specific domain mechanics as a universal template.

Runtime state and automatic impact remain exactly as governed upstream.
