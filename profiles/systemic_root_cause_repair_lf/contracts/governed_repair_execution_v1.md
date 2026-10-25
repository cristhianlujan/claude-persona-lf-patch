# Governed Repair Execution V1

## Purpose

Allow `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF` to implement a minimum sufficient structural repair only when the execution is explicitly authorized by the Router and remains inside the exact governed scope.

## Default

The profile is read-only by default. A repair specification or diagnosis never grants write authority by itself.

## Required execution authority

A write-capable execution MUST carry a `repair_execution_authority` object bound to the Router-authorized profile handoff with:

- `schema_version = LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1`
- `mode = GOVERNED_REPAIR_WRITE`
- `profile_code = PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF`
- an explicitly allowed `profile_task_intent`
- `operation_code = EJECUCION_PERFIL_LF`
- exact Router request/binding identity
- exact scope supplied by the Router
- `readback_required = true`
- `rollback_required = true`
- `promotion_allowed = false`
- `automatic_impact = false`

Initial allowed intent:

- `REPAIR_MISSING_PRODUCT_STRUCTURE`

No other intent inherits write capability.

## Write boundary

The profile may only mutate the minimum canonical structure required to close the established failure class. It may create, bind, modify, unbind or remove an in-scope governed structure only when the repair specification and current evidence establish that action.

It MUST NOT:

- widen the target or business scope;
- modify unrelated screens, rules, permissions, transitions, data meanings or runtime behavior;
- reinterpret product intent;
- promote a candidate to VIGENTE/production;
- activate runtime;
- invoke another profile directly;
- treat a suggested `target_profile` or `profiles_to_activate` as authority;
- claim success without post-write canonical readback.

## Required execution sequence

1. Validate `repair_execution_authority`.
2. Read and bind the exact current canonical target.
3. Capture a before-state digest/readback.
4. Reconfirm the established repair specification and preserved constraints.
5. Apply the minimum sufficient mutation.
6. Read the exact target again.
7. Verify:
   - defect closed;
   - expected binding/structure exists;
   - preserved constraints remain unchanged;
   - no out-of-scope mutation is observed.
8. Record rollback/reversible-baseline evidence.
9. Emit `repair_execution.mode = EXECUTED_WITH_READBACK`.
10. Return to Router/Orchestrator.

## Output projection

When no write authority exists:

- `repair_execution` may be absent or `null`.

When authority exists but no write occurs:

- `repair_execution.mode = AUTHORIZED_NOT_EXECUTED` or `BLOCKED`.

When a repair is implemented:

- `repair_execution.mode = EXECUTED_WITH_READBACK`;
- `authority_ref` must identify the carried authority;
- `changes` must identify every mutation;
- `preserved_constraints` must be explicit;
- `readback_refs` must contain post-write evidence;
- `rollback_ref` must be present;
- `returned_to_router = true`;
- `promotion_performed = false`.

## Terminal rule

A successful write does not make the profile the next Router. The only valid continuation is return to the Router with the verified repair result so the original request can be re-evaluated.
