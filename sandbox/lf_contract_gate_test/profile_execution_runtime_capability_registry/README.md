# PROFILE_EXECUTION_RUNTIME — registry projection

Source-first migration que materializa únicamente la identidad transversal `PROFILE_EXECUTION_RUNTIME` sobre la lane existente `EJECUCION_PERFIL_LF`.

## Qué registra

- `lf_capability_registry`;
- versión `1.0.0` + manifest;
- current pointer mediante `fn_lf_capability_promote_v1`;
- activo técnico `PROFILE_EXECUTION_RUNTIME`;
- dependencia a `CURRENTNESS_AUTHORITY`.

## Qué reutiliza

```text
PROFILE_EXECUTION_RUNTIME
  -> EJECUCION_PERFIL_LF
  -> lf_profile_execution_begin_v1
  -> private.lf_profile_runtime_queue_v1
  -> services/profile_runtime_api
```

No existe un segundo runtime.

## Guard obligatorio

La capability se registra con:

```text
entry_guard_required = true
entry_guard_code = ORCHESTRATOR_EXECUTION_GUARD_V1
```

para que el dispatch transversal pueda emitir receipts reales sin crear una excepción específica del Story Creator.

## No es cutover de Story Creator

El manifest y el activo conservan explícitamente:

- `runtime_activation_authorized=false`;
- `production_authorized=false`;
- `automatic_impact_authorized=false`;
- `story_task_bound_cutover_authorized=false`;
- `runtime_enabled=false`;
- `runtime_estado=NO_HABILITADO`.

El runtime de Profiles ya existe; esta proyección sólo le da identidad capability-scoped para el contrato de orquestación.

## Apply

La migración requiere una ejecución `ACTUALIZACION_DB_LF` exacta y `CURRENTNESS_AUTHORITY` current. Este PR no aplica la migración. El apply queda para el pase transversal autorizado y sólo después de reconciliar la dependencia source del contrato.
