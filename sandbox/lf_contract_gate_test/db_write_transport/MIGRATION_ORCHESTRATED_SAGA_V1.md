# MIGRATION_ORCHESTRATED_SAGA_V1

## Identidad y estado

- Tipo: `CAPABILITY` transversal.
- Owner canónico: `SUPER_ADMIN`.
- Owner legacy previo: `LF_GOVERNANCE_S30_DB`.
- Versión funcional: `1.0.0`.
- Estado funcional actual: `READ_ONLY` / runtime no activado.
- Registry state: `REGISTERED_GUARDED_NOT_CURRENT`.
- Current pointer: **no debe existir** hasta una activación separada y explícita.

## Punto de entrada obligatorio

```text
CALLER
  |
  v
ORCHESTRATOR DISPATCH
  |
  v
ORCHESTRATOR_EXECUTION_GUARD_V1
  |
  +-- receipt ausente/inválido -> BLOCK
  +-- orchestrator no operacional -> BLOCK
  +-- capability/consumer/plan_digest mismatch -> BLOCK
  |
  v
public.fn_lf_capability_bind_from_orchestrator_v1
  |
  +-- capability sin current pointer -> BLOCK_NO_CURRENT_CAPABILITY
  |
  v
MIGRATION_ORCHESTRATED_SAGA_V1
```

El guard es compartido. La capability no auto-admite callers ni decide su propia aplicabilidad. Registrar la capability no activa runtime, apply ni producción.

## Objetivo

Gobernar secuencialmente la transición de una migration ya persistida en Git hacia apply exacto en Supabase y cierre verificado, sin crear un segundo writer ni otra autoridad.

## Dependencias obligatorias

1. `MIGRATION_WRITE_AHEAD_V1` — source durable + readback exacto.
2. `DB_WRITE_TRANSPORT` — autoridad material del apply.
3. `MIGRATION_SOURCE_PARITY` — evidencia canónica PASS antes de `CONSISTENT`.
4. `CURRENTNESS_AUTHORITY` — currentness.
5. `ORCHESTRATOR_EXECUTION_GUARD_V1` — admisión transversal.

La capability consume evidencia/estado; no depende funcionalmente de `lf-contract-check`, S30, E.16 ni carriers CI.

## Secuencia

1. `WRITE_AHEAD_DURABLE`
2. `READY_TO_APPLY`
3. `SUPABASE_APPLIED`
4. `SUPABASE_LEDGER_READBACK`
5. `MIGRATION_SOURCE_PARITY_PASS`
6. `CONSISTENT`

Cada transición conserva `execution_id`, `effect_scope`, target path, version/name y source SHA256.

## Evidencia de parity

Para `CONSISTENT`, consume evidencia `LF_GATE_ERROR_V1` / `LF_GATE_CHECK_OBSERVABILITY_V1` del control `MIGRATION_SOURCE_PARITY`, ligada al mismo Git head. Un booleano autodeclarado no basta.

## Idempotencia / retry

El state gate es puro y determinista. Las acciones materiales permanecen en `ACTUALIZACION_DB_LF` y `DB_WRITE_TRANSPORT`; Saga no acuña otro writer, path ni apply engine.

## Fail closed

- DB-first sin write-ahead durable → `BLOCK_WRITE_AHEAD_NOT_DURABLE`.
- apply sin ledger readback → `BLOCK_SUPABASE_READBACK_MISSING`.
- parity distinto de PASS → `BLOCK_DUAL_SURFACE_PARITY_NOT_PASS`.
- evidencia parity inválida → error determinístico.
- identidad divergente → error determinístico.
- sin current pointer → `BLOCK_NO_CURRENT_CAPABILITY` antes de ejecutar Saga.

## Implementación

- State gate: `lf_migration_orchestrated_saga.py`.
- Tests: `test_lf_migration_orchestrated_saga.py`.
- Registry projection: `MIGRATION_ORCHESTRATED_SAGA_V1_registry_projection.sql`.
- Autoridad material: Router `ACT-0001` + `ACTUALIZACION_DB_LF` + `DB_WRITE_TRANSPORT`.

## Relaciones canónicas

- `OWNER -> SUPER_ADMIN`.
- `ENTRY_GUARD -> ORCHESTRATOR_EXECUTION_GUARD_V1`.
- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `GOBERNADO_POR -> ACT-0001`.
- `MIGRATION_SOURCE_RECONCILIATION_V1` es posterior/condicional; Saga no la invoca.

## Límites

No crea operación, tabla, writer, router, juez ni receipt engine paralelos. No hace merge, no activa producción/runtime y no autoriza reconciliación automática.

## Activación

Este cutover solo registra ownership/version/entry guard. No crea `lf_capability_current`. Activación requiere evidencia y autorización específica separada.
