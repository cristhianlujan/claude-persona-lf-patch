# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación. Su única responsabilidad es elegir el transporte correcto según `target_type` y mantener fail-closed las migrations que requieren identidad exacta entre Git y `supabase_migrations.schema_migrations`.

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

## Regla de selección

| target_type | transporte |
|---|---|
| `MIGRATION` | `EXACT_VERSION_SOURCE_FIRST` |
| `DB` | `SUPABASE_MCP` |
| `FUNCTION` | `SUPABASE_MCP` |
| `TRIGGER` | `SUPABASE_MCP` |

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
