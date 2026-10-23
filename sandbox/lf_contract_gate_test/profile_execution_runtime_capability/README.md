# PROFILE_EXECUTION_RUNTIME

Identidad lógica de capability para exponer el runtime de perfiles existente a orquestadores gobernados.

No es un runtime nuevo. Su implementación sigue siendo:

```text
ACT-0001
  -> EJECUCION_PERFIL_LF
  -> lf_profile_execution_begin_v1
  -> private.lf_profile_runtime_queue_v1
  -> services/profile_runtime_api
```

La necesidad de la identity capability proviene del contrato transversal de dispatch: `fn_lf_orchestrator_dispatch_receipt_v1` emite receipts por `capability_code` y exige una capability activa con entry guard. El bridge de ejecución de perfiles no debe inventar una excepción a ese contrato.

## Frontera

Este lote solamente define y valida la identidad y sus invariantes. No registra la capability, no crea `lf_capability_current`, no modifica `EJECUCION_PERFIL_LF`, no encola trabajo y no habilita runtime o producción.

El registro/cutover debe ser posterior y atómico, después de resolver los blockers declarados en el contrato. No se permite una fase intermedia que habilite receipts contra una capability sin current/binding suficiente.

## Reutilización

- identidad de Profile: `public.lf_activos`;
- operación: `public.lf_operation_registry/EJECUCION_PERFIL_LF`;
- Router: `ACT-0001`;
- currentness: `CURRENTNESS_AUTHORITY`;
- dispatch/guard: infraestructura transversal existente;
- runtime: `services/profile_runtime_api`.

## Blockers antes de cutover

1. Resolver el source-root/package de los perfiles embebidos en Skills sin duplicarlos bajo `profiles/`.
2. Probar currentness y binding exacto de cada Profile objetivo.
3. Calificar el wiring orquestador -> child profile -> runtime con receipts fail-closed.
