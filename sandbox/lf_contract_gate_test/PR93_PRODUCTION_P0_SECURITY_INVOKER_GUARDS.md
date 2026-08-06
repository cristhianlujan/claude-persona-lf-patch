# PR93 · Production readiness P0 · security-invoker views

## Objective

Remove owner-privilege execution from 21 public views identified by the Supabase Security Advisor.

## Change

Each target view receives:

```sql
ALTER VIEW ... SET (security_invoker=true);
```

The migration does not replace view definitions and does not change existing grants.

## Preflight evidence

Before authoring the migration:

- all 21 views were `security_invoker=false`;
- all were selectable by `service_role`;
- `service_role` had SELECT on every direct dependency of every view;
- a transaction applied all 21 options, changed to `service_role`, selected from every view and rolled back without error.

## Security effect

After the change, permissions and RLS are evaluated as the querying role instead of `postgres`, the view owner.

Consequences are intentional:

- `service_role` retains access;
- callers already authorized on all base relations retain access;
- callers that only obtained access through owner privilege elevation lose that access;
- no new grants or RLS bypasses are introduced.

## Target set

1. `v_lf_artifact_destination_registry`
2. `v_lf_artifact_pack_template_registry`
3. `v_lf_fuente_operativa_busqueda`
4. `v_lf_operation_contract`
5. `v_lf_operation_execution_checklist`
6. `v_lf_operation_execution_judge`
7. `v_lf_operation_judge_definition`
8. `v_lf_operation_step_contract_judge_coverage`
9. `v_lf_operation_step_contracts`
10. `v_lf_operation_steps`
11. `v_lf_operation_steps_with_contracts`
12. `v_lf_product_rules_current`
13. `v_lf_profile_runtime_protocol`
14. `v_lf_reporte_salida`
15. `v_lf_strategy_events`
16. `v_lf_strategy_latest`
17. `v_lf_test_run_observability`
18. `v_lf_test_suite_observability`
19. `v_sbx_competitive_observation_summary`
20. `v_sbx_mod_8_13_1_dashboard`
21. `v_sbx_mod_8_13_1_matriz`

## Verification

The post-migration test requires:

- exact target cardinality `21/21`;
- `security_invoker=true` on every target;
- a real `SELECT ... LIMIT 1` from every target while the transaction role is `service_role`.

## Rollback

A rollback may restore `security_invoker=false` only with an explicit security exception that documents why owner privilege elevation is required. Restoring the previous option without such an exception is prohibited.

## Excluded

This lot does not:

- grant access to any role;
- define RLS policies;
- alter tables or data;
- change Edge Functions;
- authorize runtime, readiness, merge or production.
