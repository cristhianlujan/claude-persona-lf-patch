# MIGRATION_WRITE_AHEAD_V1

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
MIGRATION_WRITE_AHEAD_V1
```

El guard es compartido; no se reimplementa dentro del writer. Registrar esta capability no autoriza una escritura Git.

## Objetivo

Garantizar que la intención de una migration y sus bytes exactos queden durables en Git antes de cualquier apply en Supabase.

## Alcance

Esta solución cubre únicamente persistencia previa. No orquesta el apply ni el cierre dual-surface y no ejecuta reconciliación automática.

## Identidad gobernada

Cada persistencia queda ligada a:

- `execution_id` gobernado;
- `effect_scope=MIGRATION:<version>`;
- `target_path=supabase/migrations/<version>_<name>.sql`;
- `source_sha` exacto;
- `source_blob` exacto;
- `source_sha256` exacto;
- rama gobernada `lf/migration-source-persist/*` o `lf/migration-source-repair/*`.

## Invariantes

1. Git durable antes de DB apply.
2. Readback remoto obligatorio del head persistido.
3. Path exacto version/name.
4. No escribir `main`.
5. No merge.
6. No tocar Supabase desde este transporte.
7. Mismatch SHA/blob/path = bloqueo.
8. Sin current pointer, una entrada guardada termina `BLOCK_NO_CURRENT_CAPABILITY`.

## Implementación

- Transporte: `lf_migration_git_persist.py`.
- Tests: `test_lf_migration_git_persist_contract.py`.
- Consumidor material histórico: `ACTUALIZACION_DB_LF` vía `DB_WRITE_TRANSPORT`.
- Registry projection: `MIGRATION_WRITE_AHEAD_V1_registry_projection.sql`.

## Relaciones canónicas

- `OWNER -> SUPER_ADMIN`.
- `ENTRY_GUARD -> ORCHESTRATOR_EXECUTION_GUARD_V1`.
- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_SOURCE_PARITY`.
- `MIGRATION_SOURCE_RECONCILIATION_V1` puede delegar la persistencia aquí; no obtiene por ello autoridad de activación.

## Evidencia de salida

Receipt `lf-migration-git-persist/v1` con:

- `persisted_head_sha`;
- source SHA/blob/hash;
- branch/path exactos;
- `readback=true`.

## Límites

No autoriza apply, producción, merge, runtime ni promoción. Su única salida material, cuando esté activada de forma gobernada, es una fuente Git durable y verificable.

## Activación

Este cutover solo registra ownership/version/entry guard. No crea `lf_capability_current`. La activación requiere un paso separado con evidencia y autorización específica.
