# MIGRATION_ORCHESTRATED_SAGA_V1

## Objetivo

Gobernar secuencialmente la transición de una migration ya persistida en Git hacia apply exacto en Supabase y cierre verificado, sin crear un segundo writer ni otra autoridad.

## Dependencias obligatorias

1. `MIGRATION_WRITE_AHEAD_V1` debe haber producido source durable + readback exacto.
2. `DB_WRITE_TRANSPORT` conserva la autoridad de transporte material del apply.
3. `MIGRATION_SOURCE_PARITY` debe producir evidencia canónica PASS antes de que la Saga pueda cerrar `CONSISTENT`.

La dependencia de `MIGRATION_SOURCE_PARITY` es de evidencia funcional; Saga no invoca ni depende de `lf-contract-check`, S30, E.16 ni de ningún carrier CI.

## Secuencia

1. `WRITE_AHEAD_DURABLE`
2. `READY_TO_APPLY`
3. `SUPABASE_APPLIED`
4. `SUPABASE_LEDGER_READBACK`
5. `MIGRATION_SOURCE_PARITY_PASS` con evidencia canónica ligada al mismo Git head
6. `CONSISTENT`

Cada transición conserva la misma identidad:

- `execution_id`;
- `effect_scope=MIGRATION:<version>`;
- target path;
- version/name;
- source SHA256.

## Evidencia de parity

La saga no acepta un booleano/autodeclaración `status=PASS` como prueba suficiente. Para cerrar `CONSISTENT` consume la evidencia transversal existente `LF_GATE_ERROR_V1` producida por `LF_GATE_CHECK_OBSERVABILITY_V1` para el check canónico `MIGRATION_SOURCE_PARITY`.

La evidencia debe:

- corresponder al source path canónico `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`;
- tener exactamente un check ejecutado y PASS;
- declarar `MIGRATION_SOURCE_PARITY` en su impacto;
- tener `source_commit` y `tested_commit` iguales al `git.head_sha` de la migration persistida;
- conservar un `manifest_sha256` válido sobre su contenido.

La saga consume la evidencia del control, no depende del workflow/carrier que lo transportó.

## Idempotencia / retry

El state gate es puro y determinista: revaluar el mismo snapshot produce el mismo verdict. Las acciones materiales continúan en las autoridades existentes (`ACTUALIZACION_DB_LF` y `DB_WRITE_TRANSPORT`) y deben ser reintentables contra la misma identidad; la saga no acuña otra versión ni otro path.

## Fail closed

- DB-first sin write-ahead durable → `BLOCK_WRITE_AHEAD_NOT_DURABLE`.
- apply sin readback ledger → `BLOCK_SUPABASE_READBACK_MISSING`.
- parity distinto de PASS → `BLOCK_DUAL_SURFACE_PARITY_NOT_PASS`.
- PASS sin evidencia canónica → error determinístico.
- evidencia parity con digest/head/source inválido → error determinístico.
- mismatch de execution/path/version/name/hash → error determinístico.

## Implementación

- State gate: `lf_migration_orchestrated_saga.py`.
- Tests: `test_lf_migration_orchestrated_saga.py`.
- Autoridad material: Router `ACT-0001` + `ACTUALIZACION_DB_LF` + `DB_WRITE_TRANSPORT`.
- Dependencia de validación: `MIGRATION_SOURCE_PARITY`.
- Contrato de evidencia reutilizado: `LF_GATE_ERROR_V1` / `LF_GATE_CHECK_OBSERVABILITY_V1`.

## Relaciones canónicas

- `DEPENDE_DE -> DB_WRITE_TRANSPORT`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `GOBERNADO_POR -> ACT-0001`.
- `MIGRATION_SOURCE_RECONCILIATION_V1` es una capacidad posterior y condicional ante un finding reparable; Saga no la invoca.

## Límites

No crea operación, tabla, writer, router, juez ni receipt engine paralelos. No llama S30, E.16 ni carriers CI como parte de su funcionamiento. No hace merge, no activa producción/runtime y no autoriza reconciliación automática; esa función pertenece a la tercera solución.
