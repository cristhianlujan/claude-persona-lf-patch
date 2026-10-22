# IG M10.13 — Solicitud oficial de paridad integral

Programa: `IG_CURATOR_VALIDATOR_REFACTOR_V2`.
Unidad: `M10.13`.
Checkpoint: `GIT_RUNTIME_PARITY`.

Solicitar al Merge Train existente la prueba de solo lectura `FULL_CURRENT_STATE` sobre el `main` vigente y el ledger actual de Supabase. No aplicar migraciones, no modificar Supabase y no alterar las validaciones ordinarias de PR. El resultado deberá conservar SHA de `main`, inventario completo, atestaciones, prueba de las 15 excepciones registradas y evidencia material en artifact del Train. CP2 seguirá `PENDING` si la prueba falla o no queda evidencia verificable.
