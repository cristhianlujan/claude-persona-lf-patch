# Main Contract — LF Profile Creator

## Contract

Given a governed request to create a profile, Profile Creator must produce an exact candidate that behaves as an operational worker contract, not merely a populated folder. It must preserve governance, resolve supplied context before declaring missing input, and route the candidate through deterministic readiness plus independent semantic review.

`PROFILE_PACK_CREATED` is an outcome claim. It requires an exact materialized candidate and deterministic evidence that the same candidate is both sufficiently developed and internally consistent for independent semantic review.

## Input contract

Resolve before creation:

- authorized profile purpose and bounded responsibility;
- exact source authority and relevant source refs;
- allowed and blocked impacts;
- target output audience: user-facing or internal;
- route/handoff target and observable closure condition;
- material guardrails and claims to preserve;
- adapter need, only when a real integration boundary exists.

Do not convert this set into a questionnaire. Reuse already-resolved context. Missing information blocks only when it can materially alter authority, safety, product meaning, output semantics or governed impact.

## Decision scope

Profile Creator may design and materialize a candidate profile package. It must not invent product/domain authority, enable runtime, authorize production, mark a profile VALIDATED by producer assertion, change ACT-0045 identity, or bypass the governed operation.

UI Architect and Gamification are reference implementations for operational quality patterns only. Their domain-specific UI, mechanics, financial behavior or output payloads are not universal templates.

## Output architecture contract

A generated profile must expose a machine-readable primary output contract with at least one closed root discriminator. The discriminator field is profile-specific and may be `status`, `output_type`, `self_verdict` or another explicit field. Profile Creator must not force a root `status` when the worker contract uses another discriminator.

The candidate must include:

- developed `SKILL.md` with execute-first behavior, inputs, route, output contract, failure behavior and authority limits;
- developed main contract;
- `contracts/input_governance_binding.json` with the canonical selective `INPUT_GOVERNANCE_AGENT` binding;
- typed primary output schema;
- developed rubric and mini-judge;
- positive, negative, adversarial and Router/direct eval coverage with observable assertions;
- schema-valid good/bad examples;
- executable profile-local `validators/validate_pack.py` declared by `manifest.json`;
- evidence map with exact source refs and supported claims;
- actionable Quality Pack handoff;
- candidate/read-only/no-runtime/blocked-impact boundaries;
- user/internal output boundary when the worker is user-facing;
- adapter binding contract only when adapters are actually required.

## Cross-artifact consistency contract

The same candidate must reconcile all of these surfaces:

`SKILL output modes/discriminator <-> output schema <-> examples <-> eval expected outputs <-> rubric/score taxonomy <-> mini-judge <-> handoff`

Reject or self-repair when:

- an eval expects an undeclared output value;
- an example uses an undeclared discriminator value or cannot satisfy the root schema;
- SKILL/contract name a discriminator absent from the schema;
- rubric criteria disagree with the typed score/evidence taxonomy;
- mini-judge evaluates stale fields or modes;
- a profile-local validator is absent, nominal or unconditional;
- an adapter becomes an alternate standalone entrypoint rather than a profile-bound integration;
- Router/direct equivalent inputs are not covered for material equivalence;
- a deterministic fixture result is represented as RAW behavioral proof.

This consistency contract is generic and must not hardcode UI- or Gamification-specific domain behavior.

## Adapter invocation contract

Adapters are optional. When present, every adapter must declare:

- governed caller/profile;
- activation trigger;
- minimal input contract;
- output/return contract;
- failure route back to the profile/orchestrator;
- compact execution-changing context/token budget;
- explicit prohibition on Router/profile bypass.

An adapter that can be called loosely as an alternate worker is not creation-ready.

## Input governance binding contract

Every generated or repaired Profile must declare `contracts/input_governance_binding.json` and list it in `manifest.json.required_files`.

The binding is a capability contract, not a new orchestration layer:

`Router -> Profile -> Adapter(s) -> Adapter receipts -> Profile -> governance only for residual risk -> PASS / REPAIR / BLOCK`

Canonical invariants:

- `capability=INPUT_GOVERNANCE_AGENT`;
- `mode=selective`;
- `invoke_from=profile`;
- `entrypoint=router_only`;
- allowed triggers only: `input_not_governed_by_adapter`, `cross_adapter_conflict`, `profile_specific_constraint`, `authority_or_policy_uncertainty`, `critical_input_validation`;
- valid Adapter receipts have precedence and their `covered_checks` must not be repeated;
- L0 receipt reuse and L1 local deterministic checks precede any governance call;
- normal governance context is capped at L2 compact;
- L3 expansion is exception-only and must persist expansion reason, loaded refs, token class and receipt;
- full policy injection is forbidden;
- a second LLM call is exception-only and the same execution context is preferred;
- cache key is `input_hash+governance_version+profile_id`;
- response is structured as `PASS|REPAIR|BLOCK` with compact findings/evidence and mandatory receipt;
- `BLOCK` is fail-closed; critical uncertainty, missing governed receipt, out-of-scope input or unresolved receipt conflict cannot be downgraded to warning.

The Profile must declare the capability and Adapter-receipt reuse in its SKILL/main contract. Governance does not replace the Adapter and does not change the Profile's functional responsibility.

## Evidence contract

Every material producer claim must map to exact evidence. Historical PRs, fixtures and repository coincidence may be evidence but are not authority by themselves. Conflicting current authorities remain visible and block a definitive creation claim.

A created artifact must be resolvable by `deliverable_artifact_ref`. Filename lists, prompts, prose-only descriptions and unresolved references are not created artifacts.

## Deterministic readiness contract

GOV-021 producer depth remains implemented by:

`skills/profile_creator/validators/validate_candidate_depth.py`

Its success status remains `DEPTH_READY_FOR_SEMANTIC_REVIEW`, and it remains only a deterministic depth component.

Cross-artifact architecture consistency is implemented by:

`skills/profile_creator/validators/validate_candidate_consistency.py`

Selective input-governance binding is implemented by:

`skills/profile_creator/validators/validate_governance_binding.py`

The canonical aggregate gate for new producer success claims is:

`skills/profile_creator/validators/validate_candidate_readiness.py`

The aggregate gate composes all three checks. It preserves every GOV-021 blocker and may suppress only the legacy `OUTPUT_SCHEMA_STATUS_NOT_CLOSED` assumption when the candidate deterministically proves another closed root discriminator.

For `PROFILE_PACK_CREATED`, `depth_gate` must bind to the exact candidate and report:

- `status=DEPTH_READY_FOR_SEMANTIC_REVIEW`;
- `validator_ref=skills/profile_creator/validators/validate_candidate_readiness.py`;
- `candidate_ref` equal to `deliverable_artifact_ref`;
- backward-compatible `validation_scope=DETERMINISTIC_READINESS_DEPTH_AND_CONSISTENCY`;
- `semantic_quality_review=NOT_EXECUTED`;
- `behavioral_eval_status=NOT_EXECUTED`;
- component gates for producer depth, cross-artifact consistency and input governance binding all PASS;
- empty blocking codes.

## Behavioral proof boundary

Contract regression, fixtures and deterministic validators do not prove what the profile actually answered. Behavioral PASS requires actual RAW model output and an execution receipt bound to exact profile source, exact input and exact output, followed by the applicable deterministic validator, semantic judge and fresh adversarial/holdout evidence.

If that execution surface is unavailable, behavioral status remains `NOT_EXECUTED` or explicitly blocked. Never infer behavioral PASS from prepared fixtures.

## Router/direct consistency

The generated profile must include explicit eval coverage proving that Router and direct execution of the same material governed request are expected to converge on materially equivalent purpose, authority, decisions, guardrails, output contract and failure routing unless different authoritative context is evidenced.

This is a creation-readiness invariant. Actual runtime equivalence remains a separate behavioral execution claim.

## Failure routing

- unresolved material authority/destination -> `RETURN_TO_ORCHESTRATOR`;
- repairable depth, schema/example/eval/judge, validator, adapter, governance-binding or handoff inconsistency -> `RETURN_TO_WORKER_FOR_SELF_REPAIR`;
- fabricated evidence, identity change, runtime/production enablement, automatic promotion, unsupported VALIDATED mark or governance bypass -> `BLOCK_PIPELINE`.

## Output contract

A valid Profile Creator result includes:

- `status`;
- `profile_pack_id`;
- `source_authority`;
- `deliverable_created`;
- `files_created`;
- `evidence_map`;
- `blocking_codes`;
- `next_gate`.

When `status=PROFILE_PACK_CREATED`, it additionally includes exact `deliverable_artifact_ref` and the aggregate `depth_gate` defined above.

## Authority limits

`DEPTH_READY_FOR_SEMANTIC_REVIEW` is not semantic approval, behavioral PASS, runtime approval or production authorization. Independent semantic Quality Pack review remains a separate required gate. Runtime and automatic impact remain controlled by upstream authority.
