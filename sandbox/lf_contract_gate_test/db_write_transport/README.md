# DB_WRITE_TRANSPORT

Capacidad transversal LF para seleccionar el canal de escritura de base de datos sin convertir cada estrategia o proceso en dueño de su propio mecanismo de transporte.

## Propósito

`DB_WRITE_TRANSPORT` es un selector determinista consumido por `ACTUALIZACION_DB_LF`.

No concede permisos, no sustituye al Router y no crea una nueva operación. Su única responsabilidad es elegir el transporte correcto según `target_type` y mantener fail-closed las migrations que requieren identidad exacta entre Git y `supabase_migrations.schema_migrations`.

## Regla WRITE-AHEAD para MIGRATION

Antes de cualquier apply de una migration, la fuente exacta debe quedar durable y releída desde Git.

Identidad mínima obligatoria:

- `execution_id` gobernado;
- `effect_scope=MIGRATION:<version>`;
- `target_path=supabase/migrations/<version>_<name>.sql`;
- `source_sha`, `blob_sha1` y `source_sha256` exactos;
- rama gobernada distinta de `main`;
- readback remoto positivo.

El transporte de persistencia es `lf_migration_git_persist.py`. No toca Supabase, no hace merge y no concede autoridad.

La orquestación Git → Supabase → verificación y la reconciliación automática son soluciones dependientes separadas y no forman parte de este PR.

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
7. No continuar si existe remote-only drift no clasificado, source ambiguity, checksum mismatch o identidad no resuelta.

## Dependencias y activos relacionados

- Router: `ACT-0001`.
- Operación consumidora: `ACTUALIZACION_DB_LF`.
- Capacidad padre: `DB_WRITE_TRANSPORT`.
- Gate de validación existente: `MIGRATION_SOURCE_PARITY`.
- Persistencia write-ahead: `sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py`.
- EKB principal: `CI-MIGRATION-SOURCE-PARITY-001`.

## Límites

`DB_WRITE_TRANSPORT` no autoriza producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que lo consume.
