# MIGRATION_WRITE_AHEAD_V1

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
3. El path debe coincidir exactamente con la identidad version/name.
4. No se escribe `main`.
5. No se hace merge.
6. No se toca Supabase desde este transporte.
7. Mismatch de SHA/blob/path bloquea.

## Implementación

- Transporte: `lf_migration_git_persist.py`.
- Consumidor: `ACTUALIZACION_DB_LF` a través de `DB_WRITE_TRANSPORT`.
- Gate previo existente: `MIGRATION_SOURCE_PARITY`.

## Dependencias

- Padre: `DB_WRITE_TRANSPORT`.
- Autoridad: Router `ACT-0001` + `ACTUALIZACION_DB_LF`.
- Downstream: `MIGRATION_ORCHESTRATED_SAGA_V1`.

## Evidencia de salida

Receipt `lf-migration-git-persist/v1` con:

- `persisted_head_sha`;
- source SHA/blob/hash;
- branch/path exactos;
- `readback=true`.

## Límites

Esta capacidad no autoriza apply, producción, merge, runtime ni promoción. Su única salida material es una fuente Git durable y verificable.
