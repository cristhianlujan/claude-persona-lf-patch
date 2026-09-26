# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación. Su única responsabilidad es elegir el transporte correcto según `target_type` y mantener fail-closed las migrations que requieren identidad exacta entre Git y `supabase_migrations.schema_migrations`.

## Soluciones encadenadas para MIGRATION

### 1. MIGRATION_WRITE_AHEAD_V1

Antes de cualquier apply, la fuente exacta debe quedar durable y releída desde Git mediante `lf_migration_git_persist.py`.

### 2. MIGRATION_ORCHESTRATED_SAGA_V1

Después del write-ahead, `lf_migration_orchestrated_saga.py` gobierna secuencialmente el mismo identity scope:

1. write-ahead durable;
2. ready-to-apply;
3. apply exacto por `ACTUALIZACION_DB_LF`;
4. ledger readback;
5. `MIGRATION_SOURCE_PARITY=PASS` respaldado por evidencia canónica `LF_GATE_ERROR_V1` del mismo exact-head;
6. `CONSISTENT`.

El state gate es determinista e idempotente: reintentar el mismo snapshot produce el mismo verdict. No ejecuta writes por sí mismo y no depende del workflow/carrier que transporte `MIGRATION_SOURCE_PARITY`.

La reconciliación/auto-repair es una tercera solución dependiente y separada.

## Regla de selección

| target_type | transporte |
|---|---|
| `MIGRATION` | `EXACT_VERSION_SOURCE_FIRST` |
| `DB` | `SUPABASE_MCP` |
| `FUNCTION` | `SUPABASE_MCP` |
| `TRIGGER` | `SUPABASE_MCP` |

Para `MIGRATION`, el filename `YYYYMMDDHHMMSS_name.sql` es la identidad canónica. La versión registrada en `supabase_migrations.schema_migrations.version` debe ser exactamente ese prefijo de 14 dígitos.

## Preflight obligatorio

Antes de cualquier write:

1. Resolver Router: `MIGRATION + UPDATE -> ACTUALIZACION_DB_LF`.
2. Leer EKB aplicable.
3. Fijar `target_path`, `version`, `name`, source revision y source SHA exactos.
4. Ejecutar migration source parity precheck.
5. Definir rollback o fail-forward plan.
6. Persistir/readback Git antes de apply.
7. Exigir `MIGRATION_ORCHESTRATED_SAGA_READY_TO_APPLY`.

## Cierre obligatorio

Después del apply:

- ledger exacto version/name;
- migration source parity PASS con evidencia canónica ligada al mismo exact-head;
- `MIGRATION_ORCHESTRATED_SAGA_CONSISTENT`;
- exact-head CI PASS como condición de pase del cambio, no como estado interno de Saga;
- EKB closeout cuando corresponda.

## Dependencias y activos relacionados

- Router: `ACT-0001`.
- Operación consumidora: `ACTUALIZACION_DB_LF`.
- Capacidad padre: `DB_WRITE_TRANSPORT`.
- Write-ahead: `MIGRATION_WRITE_AHEAD_V1`.
- Saga: `MIGRATION_ORCHESTRATED_SAGA_V1`.
- Gate de validación existente: `MIGRATION_SOURCE_PARITY`.
- Downstream: `MIGRATION_SOURCE_RECONCILIATION_V1`.

## Límites

`DB_WRITE_TRANSPORT` no autoriza producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que lo consume.
