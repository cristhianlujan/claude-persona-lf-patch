# IG M10.7 — A3: promoción canónica, lote acotado

## Autoridad y problema
Usuario autorizó continuar optimizaciones transversales de Input Governance. EKB: `IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015`, `IG-M107-ALL-STAGES-QUERY-INVENTORY-007` y `IG-M96-MIGRATION-VERSION-COLLISION-001`. La función candidata fue instalada y probada en PR #2755; 10/10 pares JSONB/SHA SECURITY exactos y 2 controles DESIGN_SYSTEM. Sin EXECUTE público.

## Alcance exacto
Un archivo de migración con un único DO atómico. Se reemplaza solamente el cuerpo de `programacion.fn_input_subject_depth_expected_v510(integer,text)` por el cuerpo de la candidata `fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text)`; se mantiene firma, propietario, búsqueda, SECURITY DEFINER y privilegios. Las 17 referencias efectivas de SECURITY se comparten una sola vez por sentencia, sin cache entre llamadas ni alterar el resolvedor, reglas, selectores, jueces, triggers, Q0–Q8 o contexto entre sesiones. La función candidata no se retira.

## Pruebas y fail-closed en Train
1. Comprobar MD5 exactos: canónica `83c6b61cd23cc0c57abbd8ee4831f8b5` y candidata `70abaee8cb0426fc02b1e1d1c2cf088d`; EKB candidata activa y paridad 10/10; código de promoción ausente.
2. Antes del cambio: JSONB exacto y `fn_v09_sha256_jsonb` para pantallas 1,43,53,55,58 en SECURITY y DESIGN_SYSTEM; negativo pantalla inexistente.
3. Usar `pg_get_functiondef` de candidata y sustituir únicamente su nombre calificado; verificar igualdad del texto reconstruido, ACL sin cambio y prohibición de EXECUTE para anon/authenticated/service_role.
4. Repetir las 10 paridades luego del cambio, registrar `IG-M107-A3-INCALL-CANONICAL-PROMOTION-016`. Toda la secuencia dentro de un solo DO: ante error, rollback de cambio canónico y EKB sin residuo.

## Límites y readback
La ejecución del mismo SQL requiere Router ACT-0001 → ACTUALIZACION_DB_LF → PR/Train → ledger → main → readback. No equivale a aprobar G2B, no demuestra reducción total del Validator, no cierra CP3, no cambia presupuestos ni amplia pantallas. Si la promoción pasa, siguen pendientes G2B/G3 y optimización del manifiesto/triggers. Posteriormente comparar corrida focal con presupuesto 150000 ms, semántica exacta y negativos.
