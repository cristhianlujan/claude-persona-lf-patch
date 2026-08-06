# PR93 · Production readiness P0 · privileged RPC grants

## Objective

Remove unauthenticated execution of privileged `SECURITY DEFINER` mutation RPCs while preserving the controlled `service_role` caller.

## Observed baseline

The eleven functions in this lot were verified on the active technical baseline as:

- owned by `postgres`;
- `SECURITY DEFINER`;
- executable by `anon`;
- executable by `authenticated`;
- executable by `service_role`;
- configured with an explicit `search_path`.

No rows for these functions were present in `pg_stat_user_functions` at the observation point. That absence is not treated as proof of historical non-use.

## Exact scope

Migration:

- `supabase/migrations/20260806033000_pr93_p0_revoke_public_definer_mutations.sql`

Post-migration read-only verification:

- `sandbox/lf_contract_gate_test/PR93_PRODUCTION_P0_RPC_GRANT_TESTS.sql`

The patch changes ACL only. It does not alter function bodies, tables, policies, data, Edge Functions, workflows, `main`, runtime state, or deployment state.

## Functions restricted

1. `lf_archivar_activo(text,text)`
2. `lf_archivar_activo_demo(text,text)`
3. `lf_cambiar_estado_activo(text,text,text,text)`
4. `lf_cambiar_estado_activo_demo(text,text,text,text)`
5. `lf_log_activar(text,boolean,text)`
6. `lf_log_registrar(text,text,text,text,text,text,text,jsonb,text,uuid)`
7. `lf_prod_enforcement_precheck_step_v01(text,integer,text,text,text,jsonb)`
8. `lf_prod_enforcement_record_observation_v01(text,text,text,text,text,text,text,text,jsonb)`
9. `lf_registrar_deuda(text,text,text,text,jsonb)`
10. `lf_registrar_evento(text,text,text,text,text,jsonb,uuid)`
11. `lf_registrar_evento_demo(text,text,text,text,jsonb)`

## Expected post-state

For all eleven signatures:

- `anon EXECUTE = false`;
- `authenticated EXECUTE = false`;
- `service_role EXECUTE = true`;
- `SECURITY DEFINER = true`;
- fixed function configuration remains present.

## Excluded from this lot

- read-only `lf_buscar_activos` and `lf_healthcheck`;
- view `security_invoker` remediation;
- RLS policy design;
- Edge Function authentication;
- rulesets and branch protection;
- runtime or production deployment.

Those items remain tracked in GitHub issue #96.

## Rollback rule

Do not restore execution to `PUBLIC`. A rollback requires an explicit caller decision and must grant only the minimum identified role. Any rollback must be followed by the same grant readback and a new security review.

## State limits

This patch does not grant or imply:

- `RUNTIME_PASS`;
- `PRODUCTION_READINESS_PASS`;
- merge authorization;
- deployment authorization;
- production authorization.
