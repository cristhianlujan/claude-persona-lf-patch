# PR93 · Production readiness P0 · trigger-function hardening

## Objective

Fix mutable `search_path` and remove unnecessary direct EXECUTE grants from the exact current trigger-function set without recreating functions, changing trigger definitions or disabling bindings.

## Exact inventory

- triggger functions: `59`;
- non-internal trigger bindings: `82`;
- schemas: `public`, `private`, `overall_design`;
- one unbound legacy function: `public.fn_update_lf_eventos_timestamp`.

The migration contains an explicit allowlist with the expected binding count for every function. It fails closed if:

- a target is missing;
- an additional mutable trigger function appears in the governed schemas;
- any function has an unexpected binding count;
- total bindings differ from 82.

## Change

Search paths:

- `public`: `pg_catalog, public`;
- `private`: `pg_catalog, private, public`;
- `overall_design`: `pg_catalog, overall_design`.

Direct execution is revoked from:

- `PUBLIC`;
- `anon`;
- `authenticated`;
- `service_role`.

Trigger firing is not removed. The migration uses `ALTER FUNCTION`, preserving each function OID and every trigger binding.

## Preflight evidence

The complete migration was executed in a transaction and rolled back:

- functions observed: `59/59`;
- search paths fixed: `59/59`;
- direct EXECUTE after simulated change: `0/59` for anon, authenticated and service_role;
- canonical binding identity unchanged: `82/82`;
- representative trigger firing after EXECUTE revocation:
  - `overall_design`: PASS;
  - `private`: PASS;
  - `public`: PASS.

The first simulation failed only because its comparison accidentally included unrelated triggers. It rolled back completely. The corrected comparison was restricted to the target set and passed.

## Verification

The post-migration test:

- rechecks the exact 59-function allowlist;
- requires all fixed configurations and zero direct public execution;
- requires 82 canonical bindings with the expected per-function cardinality;
- attaches three target functions to temporary tables;
- executes updates as `service_role`;
- requires all three trigger functions to fire successfully;
- rolls back all temporary test activity.

## Security effect

Clients can no longer invoke trigger functions directly through function privileges, and unqualified object resolution is no longer controlled by a caller-modifiable search path. Existing database triggers continue to execute.

## Excluded

This lot does not:

- recreate or alter function bodies;
- change trigger enablement;
- change tables or persistent data;
- add schema or table grants;
- define RLS policies;
- authorize runtime, readiness, merge, deployment or production.
