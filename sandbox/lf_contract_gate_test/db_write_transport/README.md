# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación. Su única responsabilidad es elegir el transporte correcto según `target_type` y mantener fail-closed las migrations que requieren identidad exacta entre Git y `supabase_migrations.schema_migrations`.

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
2. `SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML`: fallback gobernado cuando el entorno no dispone del canal CLI. El SQL fuente y el registro de `version/name/statements/idempotency` deben formar una sola transacción con prestate/drift guards. Este patrón ya tiene precedente probado en LF.

No usar `apply_migration`/Management API cuando el gate exige exact-version: ese canal puede acuñar un timestamp remoto distinto del filename y producir `RECONCILE_REQUIRED`.

## Preflight obligatorio

Antes de cualquier write:

1. Resolver Router: `MIGRATION + UPDATE -> ACTUALIZACION_DB_LF`.
2. Leer EKB aplicable, como mínimo `CI-MIGRATION-SOURCE-PARITY-001`, `PROGRAMMING-E2E-MIGRATION-PARITY-001`, `CI-MIG-001` y `GOV-010` cuando correspondan.
3. Fijar `target_path`, `version`, `name` y source revision exactos.
4. Ejecutar migration source parity precheck.
5. Definir rollback o fail-forward plan.
6. No continuar si existe remote-only drift, source ambiguity, checksum mismatch o identidad no resuelta.

## Uso obligatorio del selector

Antes de invocar cualquier transporte de escritura, el ejecutor debe declarar también el transporte que pretende usar. El selector valida que coincida con la decisión canónica; un mismatch bloquea antes del write.

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py \
  --target-type MIGRATION \
  --migration-path supabase/migrations/20260917191749_lf_example_v1.sql \
  --requested-executor SUPABASE_CLI_DB_PUSH_LINKED
```

Para targets directos:

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py \
  --target-type FUNCTION \
  --requested-executor SUPABASE_MCP
```

Para una `MIGRATION`, `SUPABASE_MCP`, `APPLY_MIGRATION` y cualquier executor no seleccionado deben terminar en `BLOCK_DB_WRITE_TRANSPORT_EXECUTOR_NOT_ALLOWED`. No se permite llamar al transporte primero y validar después.

Salida relevante:

```text
capability_code=DB_WRITE_TRANSPORT
mode=EXACT_VERSION_SOURCE_FIRST
executor=SUPABASE_CLI_DB_PUSH_LINKED
fallback_executor=SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML
migration_version=20260917191749
migration_name=lf_example_v1
```

Para verificar la lógica local del selector:

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py --self-test
```

## Flujo con Supabase CLI

Con el proyecto ya enlazado y después de los gates source-first:

```bash
supabase migration list --linked
supabase db push --dry-run --linked
supabase db push --linked
```

El `--dry-run` no sustituye migration parity ni el readback LF. No usar `db reset --linked` para este flujo.

## Readback obligatorio

Después del write, `ACTUALIZACION_DB_LF` debe verificar:

- `schema_migrations.version` = timestamp del filename;
- `schema_migrations.name` = nombre del filename sin timestamp ni `.sql`;
- representación de statements compatible con el comparador de transport de LF;
- migration source parity PASS;
- CI exact-head PASS;
- target readback sin cambios fuera de alcance;
- EKB closeout.

Un resultado funcional correcto con version/name distintos sigue siendo `RECONCILE_REQUIRED`, nunca `PASS_CLOSED`.

## Reconciliación genérica de provenance

La capacidad distingue estados de una migration ya seleccionada sin conocer ninguna identidad concreta:

- `UNAPPLIED`: no existe en ledger.
- `APPLIED_EXACT`: existe y tiene provenance gobernada exacta del write original.
- `APPLIED_RECONCILED`: existe, no se reclama un receipt histórico, y existe una reconciliación gobernada separada.
- `APPLIED_UNVERIFIED`: existe pero no tiene ninguna de las dos pruebas anteriores; debe bloquear.

La reconciliación usa un scope dinámico `SUPABASE_MIGRATION_RECONCILIATION:<version>` y schema `lf-db-applied-source-reconciliation/v1`. Debe probar version, name y Git blob exactos, `write_readback=PASS`, `ddl_replayed=false`, `migration_source_parity=PASS` y que no se está reclamando el receipt del write original.

Nunca se hardcodean PR, migration version, filename, SHA u owner dentro del mecanismo. Esos valores vienen del candidato exact-head y del readback vivo.

Una migration ya aplicada bajo otra versión no se reaplica y no se corrige manipulando hashes. Se trata como reconciliación source-only del owner correspondiente, preservando el DDL ya ejecutado.

## Dependencias y activos relacionados

- Router: `ACT-0001`.
- Operación consumidora: `ACTUALIZACION_DB_LF`.
- Gate de validación: `MIGRATION_SOURCE_PARITY`.
- Selector ejecutable: `sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py`.
- EKB principal: `CI-MIGRATION-SOURCE-PARITY-001`.

## Límites

`DB_WRITE_TRANSPORT` no autoriza producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que lo consume.

El selector es un pre-write guard obligatorio: si no fue invocado con el executor seleccionado, el write no debe comenzar. La reconciliación tampoco convierte un write histórico no gobernado en un write original gobernado; conserva explícitamente esa diferencia.
