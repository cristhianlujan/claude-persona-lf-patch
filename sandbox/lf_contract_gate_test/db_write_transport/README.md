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

La orquestación Git → Supabase → verificación y la reconciliación son soluciones dependientes separadas y no forman parte de WRITE_AHEAD.

## Regla de selección

| target_type | transporte |
|---|---|
| `MIGRATION` | `EXACT_VERSION_SOURCE_FIRST` |
| `DB` | `SUPABASE_MCP` |
| `FUNCTION` | `SUPABASE_MCP` |
| `TRIGGER` | `SUPABASE_MCP` |

Para `MIGRATION`, el filename `YYYYMMDDHHMMSS_name.sql` es la identidad canónica. La versión registrada en `supabase_migrations.schema_migrations.version` debe ser exactamente ese prefijo de 14 dígitos.

## Preflight del pedido de migration

El pedido superior puede exigir Router, EKB, identidad exacta, parity, rollback/fail-forward y otros controles. Esas capacidades no se convierten por ello en llamadas internas de WRITE_AHEAD.

La responsabilidad propia de WRITE_AHEAD empieza al recibir una identidad gobernada y termina cuando la fuente exacta queda persistida y releída desde Git.

## Dependencias y activos relacionados

- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_SOURCE_PARITY` como control del pedido, no como llamada interna.
- Persistencia write-ahead: `sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py`.
- EKB principal: `CI-MIGRATION-SOURCE-PARITY-001`.

## Límites

WRITE_AHEAD no llama S30, E.16, workflows CI ni `MIGRATION_SOURCE_PARITY`. `DB_WRITE_TRANSPORT` no autoriza producción, merge, runtime activation ni bypass de parity. Toda autoridad permanece en Router, contratos/policies activos y la operación gobernada que lo consume.
