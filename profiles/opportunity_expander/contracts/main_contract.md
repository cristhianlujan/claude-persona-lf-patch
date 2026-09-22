# Opportunity Expander LF — Main Contract

## Input contract

Inputs must include:
- `authorized_scope`;
- `current_baseline`;
- `problem_statement`;
- `evidence_refs`;
- `constraints`;
- `forbidden_impacts`.

Optional input:
- governed materialized capability context supplied by Router/Orchestrator.

The profile must block rather than infer missing authority.

## Decision scope

The profile may:
- generate and rank exploration opportunities;
- classify opportunity lane;
- identify required capability context;
- recommend bounded experiments.

The profile may not:
- approve implementation;
- change pricing or business rules;
- mutate runtime or production state;
- write canonical knowledge;
- own external domain Cards;
- perform free-search Card discovery.

## Evidence contract

Every surviving opportunity must include `evidence_refs[]` with at least one non-empty source reference.

Evidence must support the stated mechanism, constraint, baseline or experiment assumption. Model intuition alone is not sufficient when a governed source is required.

## Capability context contract

When governed external context is necessary but absent:
- `status = NEEDS_CAPABILITY_CONTEXT`;
- `reason_code = CAPABILITY_CONTEXT_REQUIRED`;
- `capability_requests[]` must identify `owner_domain`, `intent` and `reason`;
- the profile must not invent the missing knowledge;
- Router/Orchestrator owns resolution/materialization;
- a second pass may occur only after context is materialized.

## Output contract

Strict object:
- `status`;
- `reason_code`;
- `user_payload`;
- `internal_envelope`;
- `evidence_map`;
- `capability_requests`.

Allowed statuses:
- `READY_FOR_REVIEW`;
- `NEEDS_CAPABILITY_CONTEXT`;
- `RETURN_TO_WORKER_FOR_DIVERGENCE`;
- `BLOCKED`.

Allowed reason codes:
- `READY`;
- `CAPABILITY_CONTEXT_REQUIRED`;
- `REDUNDANT_SET`;
- `INCOMPLETE_OPPORTUNITY`;
- `SCOPE_MUTATION`;
- `OUTPUT_CONTRACT`;
- `AUTHORITY_OVERREACH`.

## Scope firewall

`requires_scope_change=true` is advisory only. It never changes the current WP or implementation scope automatically.

## Authority limits

No runtime, production, scheduler, promotion, Golden, canonical business-rule mutation, direct business write or automatic scope expansion is authorized.
