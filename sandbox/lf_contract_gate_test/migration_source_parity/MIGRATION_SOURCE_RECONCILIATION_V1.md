# MIGRATION_SOURCE_RECONCILIATION_V1

## Objetivo

Detectar divergencias conocidas Git ↔ Supabase y reparar únicamente la fuente exacta faltante, sin reejecutar DDL ni mutar el migration ledger.

## Dependencias obligatorias

1. `MIGRATION_WRITE_AHEAD_V1` para persistir el source recuperado.
2. `MIGRATION_ORCHESTRATED_SAGA_V1` para verificar cierre dual-surface.
3. `MIGRATION_SOURCE_PARITY` como detector/verificador canónico existente.

## Flujo

1. `lf-contract-check` falla por un código de parity reparable.
2. El reconciliador extrae la versión exacta.
3. Usa receipts históricos solo como locators, nunca como autoridad vigente.
4. Relee `source_sha + source_blob + path` exactos desde Git.
5. Revalida los bytes contra el ledger vivo con el comparador transport-aware existente.
6. Persiste el source mediante `MIGRATION_WRITE_AHEAD_V1` en `lf/migration-source-repair/*`.
7. Abre un PR draft de reparación source-only.
8. `lf-contract-check` vuelve a ejecutar `MIGRATION_SOURCE_PARITY`.
9. `MIGRATION_ORCHESTRATED_SAGA_V1` exige estado `CONSISTENT`.
10. Si el PR reparado sigue rojo, no hay segundo write automático; escala por PRE_EKB.

## Invariantes

- secuencial: una identidad/version por reparación;
- `ddl_replayed=false`;
- `ledger_mutated=false`;
- no merge automático;
- no direct-main write;
- locator ambiguo o source mismatch = bloqueo;
- ningún segundo motor de parity ni writer paralelo.

## Implementación

- Workflow: `.github/workflows/lf-migration-source-parity-repair.yml`.
- Coordinator: `lf_migration_source_parity_repair.py`.
- Tests: `test_lf_migration_source_parity_repair.py` + integración histórica.

## Relación arquitectónica

`DB_WRITE_TRANSPORT -> MIGRATION_WRITE_AHEAD_V1 -> MIGRATION_ORCHESTRATED_SAGA_V1 -> MIGRATION_SOURCE_RECONCILIATION_V1`.

`MIGRATION_SOURCE_RECONCILIATION_V1` consume `MIGRATION_SOURCE_PARITY`; no lo reemplaza.

## Activación

Candidato únicamente. El workflow no debe considerarse activo hasta que la cadena upstream exista en `main` y exista promoción explícita. Este PR no autoriza merge, producción ni runtime.
