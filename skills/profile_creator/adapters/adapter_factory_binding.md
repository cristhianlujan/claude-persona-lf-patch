# Adapter Factory Binding — ACT-0045 → CREACION_ADAPTER_LF

Status: CANDIDATO / READ_ONLY / NO_RUNTIME / NO_AUTOMATIC_IMPACT

## Purpose

Reuse the existing ACT-0040/ACT-0045 factory rather than maintaining a parallel Adapter factory. ACT-0045 supplies common creation concerns; `CREACION_ADAPTER_LF` owns Adapter-specific validation.

## Composition

`Router → ACT-0040 reusable-capability authority → ACT-0045 factory core → CREACION_ADAPTER_LF specialization → Adapter candidate → independent validation/readback`

This is one governed creation flow. It is not a second worker, a second factory runtime or a second Adapter-specific model call.

## Common factory responsibilities reused from ACT-0045

- source/context authority resolution;
- existing-asset and duplicate check;
- research/baseline when applicable;
- generic vs specific classification;
- candidate design and evidence packaging;
- sandbox/reviewability;
- governed write/readback/handoff/closure concerns.

These common responsibilities must not be copied into another Adapter-only lifecycle.

## Adapter-specific responsibilities

The specialization must own only what differs for Adapter:

- exact Router binding authority;
- explicit consumer/profile/skill target mapping;
- context-contamination boundary;
- invocation contract;
- bounded runtime capsule when runtime use is applicable;
- context/token budget;
- `NO_SECOND_LLM_CALL`;
- Adapter-specific schema, examples, evals and judge;
- positive, negative and bypass canaries;
- Input Governance mediation when functional input governance applies.

## Hard rules

- Adapter is a binding/context boundary, not an alternate worker.
- Adapter does not select workers independently of Router.
- Adapter does not acquire Profile/Skill semantic authority.
- ACT-0045 is factory core, not resulting Adapter parent/owner authority.
- Direct loose Adapter invocation is forbidden.
- Direct Profile → `INPUT_GOVERNANCE_AGENT` invocation is forbidden.
- Profile declares governance need; Adapter determines applicability, selects minimum governance sections, builds bounded input and returns typed governance receipt.
- Runtime or production enablement is outside this factory binding and remains blocked unless separately authorized.

## Required factory receipt

- `parent_authority_code=ACT-0040`
- `factory_core_code=ACT-0045`
- `factory_sources_consumed`
- `candidate_type=ADAPTER`
- `candidate_needed=true`
- `no_parallel_factory=true`
- `router_binding_authority_checked=true`
- `consumer_mapping_checked=true`
- `runtime_change=false`
- `production_change=false`

## Fail closed

Block with a governed reason on:

- `PARALLEL_FACTORY_DUPLICATION`
- `ACT0040_ACT0045_FACTORY_BYPASS`
- `ADAPTER_WITHOUT_EXPLICIT_CONSUMER_MAPPING`
- `ADAPTER_AS_ALTERNATE_WORKER`
- `ADAPTER_SELECTS_WORKERS`
- `SECOND_LLM_CALL_REQUIRED_BY_ADAPTER`
- `DIRECT_PROFILE_INPUT_GOVERNANCE_INVOCATION`
- `DIRECT_OR_UNBOUND_ADAPTER_INVOCATION`
