# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación.

## v2.1.0 — Router primero, Merge Train siempre

Toda escritura de base de datos de un agente empieza en el Router (ACT-0001) y termina en el LF Migration Merge Train. No existe ruta directa para agentes.

```
agente → lf_router_resolve_v1 (solo lectura) → operation_code
agente → select_route(target_type, migration_path, router_execution_id, router_operation)
   sin ejecución EXEC-… y sin router_operation=ACTUALIZACION_DB_LF → REDIRECT_TO_ROUTER
   con cualquiera de las dos → MIGRATION_VIA_MERGE_TRAIN (PR + ready-to-merge + Train)
```

v2.1.0 agrega a la respuesta:
- `steps`: checklist del Train (una migración por PR, PR fuera de borrador, checks en verde en el HEAD exacto, un Train a la vez, la versión la asigna o reasigna el Train).
- `on_denied`: un rechazo por solo lectura o permisos es intencional; no se busca otra ruta, se va al Train.
- `execution_request`: si no hay ejecución `ACTUALIZACION_DB_LF`, se indica el target exacto en el PR y se pide al dueño (hasta que el Train gestione ejecuciones).
- `prevention_rules`: códigos de `transversal.prevention_rules` que aplican (PRV-CI-009, PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001, PRV-SQL-001, PRV-SQL-007, PRV-SQL-012, PRV-RTE-006).

| target_type | ruta para agentes |
|---|---|
| `MIGRATION`, `DB`, `FUNCTION`, `TRIGGER`, `CAPABILITY` | `MIGRATION_VIA_MERGE_TRAIN` (con ejecución del Router) o `REDIRECT_TO_ROUTER` (sin ella) |

Prohibido para agentes: MCP `apply_migration`, MCP `execute_sql` con DDL o DML de migración, `supabase db push`, SQL Editor, `psql` directo, DML manual sobre `supabase_migrations.schema_migrations`, nombres de migración no clasificados (`POL-LF-MIGRATION-NAMING`).

CLI para agentes:

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py \
  --target-type MIGRATION \
  --migration-path supabase/migrations/<version>_<name>.sql \
  --router-operation ACTUALIZACION_DB_LF   # o --router-execution-id EXEC-…
```

`select_transport` (y `--train-internal`) es interno del Merge Train: lo usa `lf_migration_exact_apply.py` para elegir su ejecutor sobre una migración ya admitida. No es una ruta para agentes. Las escrituras directas `DB`/`FUNCTION`/`TRIGGER` por `SUPABASE_MCP` de v1.0.0 quedan retiradas.

## Soluciones encadenadas para MIGRATION

### 1. MIGRATION_WRITE_AHEAD_V1

Antes de cualquier apply, la fuente exacta debe quedar durable y releída desde Git mediante `lf_migration_git_persist.py`.

WRITE_AHEAD no ejecuta parity ni controles CI; su responsabilidad termina con source durable + readback exacto.

### 2. MIGRATION_ORCHESTRATED_SAGA_V1

Después del write-ahead, `lf_migration_orchestrated_saga.py` gobierna secuencialmente el mismo identity scope:

1. write-ahead durable;
2. ready-to-apply;
3. apply exacto por `ACTUALIZACION_DB_LF` / `DB_WRITE_TRANSPORT`;
4. ledger readback;
5. `MIGRATION_SOURCE_PARITY=PASS` respaldado por evidencia canónica `LF_GATE_ERROR_V1` del mismo exact-head;
6. `CONSISTENT`.

El state gate es determinista e idempotente: reintentar el mismo snapshot produce el mismo verdict. No ejecuta writes por sí mismo y no depende del workflow/carrier que transporte `MIGRATION_SOURCE_PARITY`.

`MIGRATION_SOURCE_PARITY` es una dependencia funcional de evidencia para el cierre de Saga; S30, E.16, `Validate LF Packs`, `LF DB Regression` y `lf-contract-check` son controles/carriers de pase y no forman parte de la Saga.

La reconciliación es una tercera capacidad separada y condicional ante findings reparables de parity.

## Ejecutor interno del Train

| target_type | ejecutor interno (solo Merge Train) |
|---|---|
| `MIGRATION` | `EXACT_VERSION_SOURCE_FIRST` |
| `DB`, `FUNCTION`, `TRIGGER`, `CAPABILITY` | retirado en v2.0.0: se expresan como migración |

Para `MIGRATION`, el filename `YYYYMMDDHHMMSS_name.sql` es la identidad canónica. La versión registrada en `supabase_migrations.schema_migrations.version` debe ser exactamente ese prefijo de 14 dígitos.

## Fronteras del pedido

El pedido superior resuelve Router, EKB y controles de pase. Las capacidades de Migration solo consumen las entradas/evidencias que les corresponden y no se convierten en dueñas de CI ni del lifecycle general.

## Relaciones canónicas

### MIGRATION_WRITE_AHEAD_V1
- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_SOURCE_PARITY`.

### MIGRATION_ORCHESTRATED_SAGA_V1
- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `GOBERNADO_POR -> ACT-0001`.

## Límites

`DB_WRITE_TRANSPORT`, WRITE_AHEAD y Saga no llaman S30/E.16 ni convierten workflows CI en dependencias funcionales. No autorizan producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que corresponda.
