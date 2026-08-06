# PR93 · Production readiness P0 · public read RPCs

## Objective

Remove unnecessary `SECURITY DEFINER` elevation from the two remaining public read-only RPCs while preserving their intended public behavior.

## Target functions

- `lf_buscar_activos(text,text,text,text,integer)`
- `lf_healthcheck()`

## Baseline

Both functions were:

- SQL-language wrappers;
- owned by `postgres`;
- `SECURITY DEFINER`;
- configured with `search_path=public`;
- executable by `anon`, `authenticated` and `service_role`.

Their underlying views already use `security_invoker=true` and are selectable by the same roles.

## Change

```sql
ALTER FUNCTION ... SECURITY INVOKER;
```

Function bodies, signatures, defaults, return types, grants and fixed `search_path` remain unchanged.

## Preflight evidence

The complete change was simulated in a transaction. Both functions were invoked successfully as:

- `anon`;
- `authenticated`;
- `service_role`.

The transaction was rolled back before this patch was authored.

## Expected post-state

- `security_definer=false` for both functions;
- existing EXECUTE grants remain true for all three intended roles;
- fixed function configuration remains present;
- public read behavior remains available without owner privilege elevation.

## Security effect

The functions can no longer bypass the caller's permissions or RLS through the `postgres` owner. Data visibility is determined by the caller and the underlying `security_invoker` views.

## Excluded

This lot does not:

- expose new data;
- add grants;
- change view definitions;
- mutate application data;
- authorize runtime, readiness, merge, deployment or production.
