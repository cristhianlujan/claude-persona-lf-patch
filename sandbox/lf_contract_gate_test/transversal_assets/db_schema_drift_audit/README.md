# DB_SCHEMA_DRIFT_AUDIT

Capability transversal LF candidata: `DB_SCHEMA_DRIFT_AUDIT`.

## Estado

- Lifecycle de esta revisión: `CANDIDATO` / `READ_ONLY`.
- No está activada ni promovida por este PR.
- No reemplaza `MIGRATION_SOURCE_PARITY` / `MIGRATION_CONTROL`.
- No modifica `CREACION_PERFIL_LF`, runtime ni estado productivo.

## Propósito

Detectar drift de esquema fuera del camino crítico de un PR comparando dos huellas construidas con la misma consulta canónica:

1. esquema reconstruido desde Git en una base Supabase local desechable;
2. esquema vivo consultado en transacción `READ ONLY`.

El resultado es `MATCH` o `DRIFT_DETECTED` con identidades exactas faltantes, extra o modificadas y hashes de definición.

## Cómo funciona

```text
Git exact-head
   -> Supabase local desechable
   -> db reset / replay de migrations
   -> fingerprint SQL
                              \
                               -> compare -> MATCH | exact diff
                              /
Supabase sandbox vivo
   -> conexión postgres existente de CI
   -> BEGIN READ ONLY
   -> mismo fingerprint SQL
```

Superficies de esta revisión:

- `.github/workflows/lf-db-schema-drift-audit.yml`
- `sandbox/lf_contract_gate_test/db_schema_drift_audit/db_schema_fingerprint_v1.sql`
- `sandbox/lf_contract_gate_test/db_schema_drift_audit/db_schema_drift_audit_v1.py`

Reutiliza el patrón operativo ya usado por `LF Bootstrap Reproducibility Probe`: PostgreSQL 17.6, Supabase CLI fijado, credenciales cifradas existentes y reconstrucción local desechable.

## Seguridad y límites

- El acceso al sandbox vivo se fuerza con `default_transaction_read_only=on` y `BEGIN READ ONLY`.
- Está prohibido `db push`, DDL vivo, reparación automática y sincronización desde live hacia Git.
- Un trigger interno puede frenar errores honestos, pero **no es la frontera de seguridad**.
- La frontera para un cambio de DB sigue siendo la ejecución gobernada autorizada de DB (`ACTUALIZACION_DB_LF` / contrato vigente) con provenance y readback.
- Un drift detectado genera evidencia; no autoriza reparación.
- Si el replay Git falla, el audit falla por no poder demostrar la huella Git; no usa el esquema vivo como sustituto.

## Validación

- Self-test determinista: 5 casos (`MATCH`, missing, extra, column changed, function changed).
- Medición real: replay exact-head de Git + huella real del sandbox vivo.
- El workflow persiste únicamente el reporte de comparación, no el dump/JSONL crudo del vivo.

## Lifecycle

Esta revisión es candidata. La existencia del README/PR no cambia el estado de `public.lf_activos`. Registro, revisión, promoción o activación del activo requieren el flujo gobernado y autorización correspondientes. Los activos existentes no se degradan para introducir esta revisión.
