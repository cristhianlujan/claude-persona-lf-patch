# MIGRATION_PERSIST_VERIFY_V1

Procedimiento transversal consumido por `ACTUALIZACION_DB_LF` dentro de `DB_WRITE_TRANSPORT`; no crea una operación ni autoridad paralela.

## Objetivo

Impedir que una migración pueda considerarse aplicada/cerrada si su source exacto no quedó primero durable en Git y si después no existe readback consistente Git ↔ Supabase.

## Una ejecución, dos superficies

La identidad común es:

- `execution_id` gobernado;
- `effect_scope=MIGRATION:<version>`;
- `target_path=supabase/migrations/<version>_<name>.sql`;
- `migration_version` y `migration_name` derivados del filename;
- `source_sha256` del source exacto.

### Fase A — persistencia Git

Antes de cualquier apply DB se exige:

- source presente en Git;
- `head_sha` exacto;
- `blob_sha1` exacto;
- `source_sha256` exacto;
- readback Git positivo.

`lf_migration_git_persist.py` es el transporte transversal de esta fase. Solo puede escribir el path exacto `supabase/migrations/<version>_<name>.sql` en ramas `lf/migration-source-persist/*` o `lf/migration-source-repair/*`; no puede escribir `main`, fusionar PRs ni tocar Supabase. La autoridad de invocación sigue siendo `ACTUALIZACION_DB_LF`.

Solo después del readback remoto `lf_migration_persist_verify.py` puede emitir:

`GIT_SOURCE_DURABLE_READY_FOR_EXACT_APPLY`.

### Fase B — apply exacto

El write continúa siendo responsabilidad de `ACTUALIZACION_DB_LF`, usando la decisión `DB_WRITE_TRANSPORT`:

1. `SUPABASE_CLI_DB_PUSH_LINKED`, o
2. fallback gobernado `SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML`.

Sigue prohibido usar `apply_migration` cuando se exige exact-version.

### Fase C — doble readback

Después del apply se exige:

- `schema_migrations.version` = versión del filename;
- `schema_migrations.name` = nombre del filename;
- readback Supabase positivo;
- `MIGRATION_SOURCE_PARITY=PASS` para la misma versión/nombre/path.

Solo entonces el state gate emite:

`PASS_GIT_SUPABASE_DUAL_READBACK` / `CONSISTENT`.

## Reparación histórica

Si Supabase ya tiene la migración aplicada, la Fase B no se repite. Se localiza el source histórico mediante evidencia durable, se vuelven a comprobar sus bytes, se persiste mediante el mismo transporte Git y se reejecuta parity con `ddl_replayed=false`.

## Fail closed

Bloqueos mínimos:

- `BLOCK_GIT_SOURCE_NOT_DURABLE`;
- `BLOCK_SUPABASE_READBACK_MISSING`;
- `BLOCK_DUAL_SURFACE_PARITY_NOT_PASS`;
- mismatch de path/version/name/hash/head/blob = error determinístico.

No se permite:

- DB-first;
- timestamp remoto remintado;
- rename post-apply como flujo normal;
- bypass de parity;
- PASS con una sola superficie verificada;
- Git write directo a `main`.

## Uso

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py --request persist-request.json
python sandbox/lf_contract_gate_test/db_write_transport/lf_migration_persist_verify.py --file receipt.json
```

Los helpers son transporte/verificación; no conceden autoridad. La autoridad permanece en Router + `ACTUALIZACION_DB_LF` + contratos/policies vigentes.
