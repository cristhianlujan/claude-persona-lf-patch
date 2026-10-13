# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación.

## v2.2.0 — Router primero, Merge Train como única ruta

Toda escritura de base de datos empieza en el Router (ACT-0001) y se entrega al LF Migration Merge Train. El Train reserva, registra y cierra la ejecución actual `ACTUALIZACION_DB_LF` (`EXEC-DB-TRAIN-PR<n>-<version>-R<run>`); el agente no reserva ni solicita una ejecución al dueño.

```
agente → lf_router_resolve_v1 (solo lectura) → operation_code
agente → select_route(target_type, migration_path, router_operation)
   sin ruta del Router → REDIRECT_TO_ROUTER
   con ruta del Router → MIGRATION_VIA_MERGE_TRAIN
```

La respuesta usa `execution_request=NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION`. El único flujo de escritura es PR + checks + `ready-to-merge` + Merge Train. El Train asigna o reasigna la versión.

Para objetivos de migración, pase también el estado del cambio y las evidencias de presencia en `main` y en el ledger. Si el target está en cualquiera de ellos, una edición, renombre o borrado produce `BLOCK_APPLIED_MIGRATION_IMMUTABLE`; el arreglo debe ser una migración nueva fail-forward por el Train. Un archivo realmente nuevo (`added`, ausente de `main` y del ledger) sigue por `MIGRATION_VIA_MERGE_TRAIN`.

`select_transport` es interno del Train y no habilita una ruta directa. No hay fallback de DML manual del ledger. MCP `apply_migration`, MCP `execute_sql` para DDL o DML de migración, `supabase db push` por un agente, SQL Editor, `psql` directo y DML manual sobre `supabase_migrations.schema_migrations` están prohibidos.

CLI para agentes:

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py \
  --target-type MIGRATION \
  --migration-path supabase/migrations/<version>_<name>.sql \
  --router-operation ACTUALIZACION_DB_LF
```

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
