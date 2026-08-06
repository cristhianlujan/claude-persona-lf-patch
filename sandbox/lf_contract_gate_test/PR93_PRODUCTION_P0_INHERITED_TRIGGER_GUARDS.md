# PR93 · Production readiness P0 · inherited trigger ACLs

## Objective

Remove direct EXECUTE from 11 trigger functions that already had fixed configuration before the mutable-search-path lot, while preserving their 16 canonical trigger bindings.

## Exact target set

Ten functions are in `private`; one production execution gate is in `public`.

The set includes:

- append-only and governance-history mutation blockers;
- validation-exemption consumption;
- contract, provenance, deployment and fingerprint guards;
- event-contract history recording;
- `public.lf_prod_enforcement_execution_gate_v01`.

## Change

- Revoke EXECUTE from `PUBLIC`, `anon`, `authenticated` and `service_role` on all 11 functions.
- Replace `public, pg_temp` with `pg_catalog, public` for `lf_prod_enforcement_execution_gate_v01`.
- Preserve all other existing fixed search paths.
- Do not recreate functions or triggers.

## Preflight evidence

The complete change was simulated inside a transaction and rolled back:

- functions: `11/11`;
- canonical bindings before temporary probes: `16/16`;
- direct EXECUTE after simulated change: `0/11` for anon, authenticated and service_role;
- binding identity and enablement unchanged.

Representative runtime cases after revocation:

1. `fn_block_lf_eventos_mutation` rejected an UPDATE with SQLSTATE `55000`;
2. `fn_consume_lf_event_validation_exemption_v3` passed through an INSERT without an exemption token;
3. `lf_prod_enforcement_execution_gate_v01` rejected an unknown operation with SQLSTATE `P0001`.

The three runtime probes use temporary triggers and are rolled back. Their bindings are excluded from the canonical count.

## Security effect

- The SECURITY DEFINER exemption-consumption trigger can no longer be invoked directly by exposed roles.
- Guard and ledger trigger functions cannot be called through ordinary function privileges.
- The production execution gate no longer resolves objects through an explicit `pg_temp` path.
- Existing trigger-driven behavior remains active.

## Excluded

This lot does not:

- change function bodies;
- change trigger enablement;
- change persistent data;
- add grants;
- authorize runtime, readiness, merge, deployment or production.
