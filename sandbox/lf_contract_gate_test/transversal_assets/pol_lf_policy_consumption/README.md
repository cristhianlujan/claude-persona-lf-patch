# POL-LF-POLICY-CONSUMPTION

Inventory status: `ACTIVE_TRANSVERSAL_POLICY`.

## Propósito

Gobierna cómo una operación LF resuelve policies transversales y específicas una sola vez, las congela por version + SHA y compila el contexto mínimo que se entrega al modelo. En `v1.2-context-admission` también declara `TRANSVERSAL_BASE_SET_V1`, los sets condicionales, JIT y el presupuesto de contexto.

## Cuándo consumirlo

Siempre que una operación gobernada pase por Router/context admission. No se carga el payload completo al modelo si el snapshot compacto es suficiente.

## Cómo consumirlo

1. Resolver `POL-LF-POLICY-CONSUMPTION` desde `public.v_lf_operation_policy_snapshot`.
2. Verificar `policy_version` y `policy_sha`.
3. Usar `context_compilation.base_set` y `conditional_sets` para applicability determinístico.
4. Entregar al modelo sólo referencias compactas; policies completas, EKB completos y README completos permanecen fuera del prompt.
5. Rehidratar detalle únicamente por JIT cuando una decisión concreta lo requiera.
6. Cerrar contra el mismo snapshot congelado y el readback de budget/enforcement.

## Superficies canónicas

- Policy versions: `public.lf_policy_versions`
- Policy snapshot: `public.v_lf_operation_policy_snapshot`
- Asset inventory: `public.lf_activos.codigo_activo=POL-LF-POLICY-CONSUMPTION`
- Context compiler: `public.fn_lf_router_preflight_v1(text)`
- Budget ledger: `private.lf_context_budget_events_v2`
- Budget readback: `public.v_lf_context_budget_latest_v2`
- Source: `supabase/migrations/20260918054000_lf_s30_operation_policy_context_admission_v1.sql`

## Fail-closed / límites

Bloquear si la policy requerida no resuelve SHA, si el Router no está vigente, si una capability requerida por el set aplicable no está activa, o si el receipt supera el hard context budget. No convertir cada set en un activo independiente: los sets son configuración declarativa de esta policy.

## Validación y readback

Readback mínimo: policy ACTIVE + version/SHA exactos, context receipt `READY`, sets aplicables correctos, `CONTEXT_BUDGET_GOVERNANCE` vigente, y ausencia de payloads/README/EKB completos en la entrega al modelo. El hard limit actual es 3.000 tokens estimados y el soft limit 1.500.

## No duplicación

No crear otro policy resolver, context compiler, context-budget ledger ni enums paralelos para los sets. Extender esta policy y las capabilities existentes.

## Currentness

Antes de consumir, releer `public.lf_policy_versions`, `public.v_lf_operation_policy_snapshot`, `public.lf_activos` y este README desde el mismo main/execution snapshot.
