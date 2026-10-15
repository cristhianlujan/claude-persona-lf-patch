# IG M10.7 A5 — optimización acotada del manifiesto de origen

**Objetivo:** reducir recálculo evitable de las siete fuentes distintas usadas en cada reconstrucción del manifiesto, sin compartir contextos entre llamadas ni alterar los 21 triggers.

**EKB preflight:** `IG-M107-ATOMIC-MANIFEST-REPEAT-005`, `IG-M107-TRIGGER-ROLLBACK-PROFILE-008`, `IG-M107-CONTEXT-G2A-REPLAY-READBACK-011`.

**Función autorizada:** `programacion.fn_input_build_source_manifest_safe_v1(bigint)`. Único reemplazo si pasa la prueba de rendimiento; ningún cambio a `fn_input_run_source_currentness_v1`, `fn_input_build_source_manifest`, los triggers, el catálogo de reglas ni la independencia Validator.

**Gate y rollback:** Train crea un candidato temporal sin permisos públicos; exige definiciones fuente exactas MD5, igualdad JSONB y SHA en run 931 y 933, negativo de run inexistente, comparaciones cronometradas alternadas AB/BA y al menos 3/4 ensayos estrictamente más rápidos; revalida igualdad después de la promoción, propietario/ACL y 21 triggers. Elimina el candidato. Todo sucede en un único DO: cualquier fallo aborta y revierte todos los cambios, sin registrar EKB como PASS.

**Limitaciones:** no prueba tiempo total del Validator ni p90; no activa el proveedor G1, G2B ni G3. El checkpoint CP3 requiere prueba separada. No multiplicar ahorros de microbenchmark por 47 familias.

**Ruta:** Router ACT-0001 → ACTUALIZACION_DB_LF → Migration Train → ledger → GitHub main → readback independiente.
