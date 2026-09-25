# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación. Su única responsabilidad es elegir el transporte correcto según `target_type` y mantener fail-closed las migrations que requieren identidad exacta entre Git y `supabase_migrations.schema_migrations`.

## Regla transversal MIGRATION

Toda migración nueva o reparación source-only debe cerrar mediante `MIGRATION_PERSIST_VERIFY_V1`:

1. Git source exacto persistido y readback.
2. Apply exacto a Supabase, o readback de `applied=true` para reparación histórica sin DDL replay.
3. Ledger exacto version/name.
4. `MIGRATION_SOURCE_PARITY` reejecutado.
5. Cierre únicamente con estado `CONSISTENT`.

No se permite declarar éxito con solo una superficie consistente.

## Regla de selección

| target_type | transporte |
|---|---|
| `MIGRATION` | `EXACT_VERSION_SOURCE_FIRST` |
| `DB` | `SUPABASE_MCP` |
| `FUNCTION` | `SUPABASE_MCP` |
| `TRIGGER` | `SUPABASE_MCP` |

Para `MIGRATION`, el filename `YYYYMMDDHHMMSS_name.sql` es la identidad canónica. La versión registrada en `supabase_migrations.schema_migrations.version` debe ser exactamente ese prefijo de 14 dígitos.

## Transporte de migrations

Orden preferido:

1. `SUPABASE_CLI_DB_PUSH_LINKED`: aplicar el archivo ya versionado desde `supabase/migrations` mediante la CLI enlazada al proyecto. La CLI compara las migrations locales con `supabase_migrations.schema_migrations` y aplica las pendientes conservando la identidad del archivo.
2. `SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML`: fallback gobernado cuando el entorno no dispone del canal CLI. El SQL fuente y el registro de `version/name/statements/idempotency` deben formar una sola transacción con prestate/drift guards.

No usar `apply_migration`/Management API cuando el gate exige exact-version: ese canal puede acuñar un timestamp remoto distinto del filename y producir `RECONCILE_REQUIRED`.

## Preflight obligatorio

Antes de cualquier write:

1. Resolver Router: `MIGRATION + UPDATE -> ACTUALIZACION_DB_LF`.
2. Leer EKB aplicable.
3. Fijar `target_path`, `version`, `name`, source revision y source SHA exactos.
4. Ejecutar migration source parity precheck.
5. Definir rollback o fail-forward plan.
6. Persistir/readback Git antes de apply.
7. No continuar si existe remote-only drift no clasificado, source ambiguity, checksum mismatch o identidad no resuelta.

## Readback obligatorio

Después del write, `ACTUALIZACION_DB_LF` debe verificar:

- Git `target_path` exacto, head SHA, blob SHA y source SHA256;
- `schema_migrations.version` = timestamp del filename;
- `schema_migrations.name` = nombre del filename sin timestamp ni `.sql`;
- representación de statements compatible con el comparador de transport de LF;
- migration source parity PASS;
- CI exact-head PASS;
- target readback sin cambios fuera de alcance;
- EKB closeout cuando corresponde.

El helper `lf_migration_persist_verify.py` no escribe: evalúa el estado dual y solo emite `READY_TO_APPLY` después del readback Git y `CONSISTENT` después del readback Supabase + parity PASS.

## Reconciliaciones históricas

Una migration ya aplicada no se reaplica. La reparación entra con Supabase ya aplicado/readback y `ddl_replayed=false`; se persiste el source histórico exacto en Git y se reejecuta parity. El cierre requiere `CONSISTENT`.

## Dependencias y activos relacionados

- Router: `ACT-0001`.
- Operación consumidora: `ACTUALIZACION_DB_LF`.
- Gate de validación: `MIGRATION_SOURCE_PARITY`.
- Selector: `sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py`.
- Dual-surface gate: `sandbox/lf_contract_gate_test/db_write_transport/lf_migration_persist_verify.py`.
- EKB principal: `CI-MIGRATION-SOURCE-PARITY-001`.

## Límites

`DB_WRITE_TRANSPORT` no autoriza producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que lo consume.
