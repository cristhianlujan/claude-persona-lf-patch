# B07 PADRE/HIJA — evidencia REAL de pruebas + límites

**Resultado:** candidate PG17.6/PG18.7 **PASS ejecutado**; B07 **ABIERTO/NO-GO**, decisión del dueño **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**. No se ha escrito en Supabase ni modificado RUN alguno.

## Fuente viva (únicamente SELECT, 2026-11-13T11:24:10.886 UTC)
- `lf_ops.reglas`: 578 filas (412 VIGENTE + 166 CANDIDATO); SHA256 de filas `15caa058184e52db3572bd0884810d0b731703d72e989c9e33dccc59ce983d8f`.
- `saly.reglas`: 14 filas VALIDADO; SHA256 `588bf6b8368eb48ff93ae3edaebf1e80018364c3078a409aeb153836d55256c7`.
- Tablas HIJA de B07: no existen en Supabase. LF V2 instalado se limita a actualizar padre y guardar recibos de hash; no conserva por sí mismo todas las versiones.

## Prueba nueva y logs (CI realmente ejecutado)
- [PR #3818 DRAFT](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3818), HEAD CI **`c47d27bfe6df0ac2b8435e130749b5cb74b5bfb3`**.
- [R17 run 43419563841](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43419563841), job `131865852947`: **SUCCESS**, `Ran 237 tests`, `OK (skipped=1)` (236 PASS + 1 omitida, incluye 2 B07).
- [PASE run 43419563938](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43419563938): **SUCCESS**.
- Test B07 `sandbox/lf_contract_gate_test/edge_function_operation/test_b07_parent_child_pg17_pg18.py` blob `625e4c259c15a58635524344772c9fbd7551b9a8`.
- UP SQL blob `35876bb3911b968b0bf17bb8ba528ce65dd0167e`; DOWN SQL blob `4b368eadff15dd772cbd899dc7ba87f81f1f5014`.

| Prueba/caso | PG17.6 | PG18.7 |
|---|---|---|
| Motor exacto | 170006 | 180007 |
| PRE-COMMIT UP → ROLLBACK, SHA igual, sin tablas hija remanentes | PASS | PASS |
| Backfill (578 LF incl. 166 CANDIDATO, 14 SALY VALIDADO; 1 versión base sin atribuir autor) | PASS | PASS |
| Hash hijo calculado, padre ↔ última hija para TODAS las filas | PASS | PASS |
| UPDATE aislado padre sin hija bloqueado al COMMIT | PASS | PASS |
| UPDATE padre + append hija en misma TX autorizado solo a service_role de CI | PASS | PASS |
| Negativos: hash viejo, evidencia incompleta, decision_ref LF sin recibo | PASS | PASS |
| Negativos: anon no invoca, historia UPDATE/DELETE/TRUNCATE prohibidos | PASS | PASS |
| DOWN con historia → rechazo sin borrar | PASS | PASS |

**Log PG17.6:** `PASS_B07_PRECOMMIT_ROLLBACK_postgres_17.6 SHA=deac8b6b6939b918d063688cdc9fa21c0d00dced5907e361053f5ffc9f1ede5f`; `PASS_B07_BASELINE_BACKFILL_578_LF_14_SALY_postgres_17.6`; `PASS_B07_ATOMIC_PARENT_CHILD_AND_NEGATIVE_GATES_postgres_17.6`; `PASS_B07_DOWN_FAIL_CLOSED_WITH_HISTORY_postgres_17.6`.

**Log PG18.7:** `PASS_B07_PRECOMMIT_ROLLBACK_postgres_18.7 SHA=083f206bf25b988c09d7e2c6b1eeb015769ea7f863462986ccae994de48826b5`; `PASS_B07_BASELINE_BACKFILL_578_LF_14_SALY_postgres_18.7`; `PASS_B07_ATOMIC_PARENT_CHILD_AND_NEGATIVE_GATES_postgres_18.7`; `PASS_B07_DOWN_FAIL_CLOSED_WITH_HISTORY_postgres_18.7`.

## Lo que NO es PASS
- **No restauración completa con datos de versiones:** DOWN fue probado solo en modo **fail-closed** cuando hay historia; se probó ROLLBACK transaccional pre-COMMIT de UP. No se eliminó historia para simular un DOWN engañoso.
- **No copia completa real:** la base LF del fixture es un slice de objetos e incluye 2 muestras sintéticas; se completa a 578 con filas sintéticas. SALY aporta 14 códigos/estados/decision IDs observados, pero el texto de reglas es sintético. Estos SHA CI **NO** son los hashes Supabase.
- **No escritor V2 integrado:** la función nueva es `*_candidate_v1`, con role `service_role` de CI y decisiones sintéticas en DB desechable; no se ejecutó ni acreditó una llamada nativa V2 del carril real, OIDC, decisión humana firmada ni promoción.
- **No modificación de criterio 12:** la exigencia literal 4/5 columnas permanece y debe enmendarse mediante acto firmado del dueño. La contradicción está documentada en `03_criterio_literal_b07_cobertura.md`.
- **No validación live después de migración:** deliberadamente no se desplegó ni escribió en Supabase; B07 queda ABIERTO.

## Incidencias CI históricas durante el lote (no atribuir PASS)
- Primer run R17: fixture SALY faltante. Segundo: 2 LF extra en fixture. Tercero: reorden de carga LF. Se corrigieron solo pruebas/manifest en la rama candidata; **únicamente el run final de arriba acredita PASS**.
- PASE inicial con fixture nuevo y sin manifest: FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED; corregido en manifest, PASE final SUCCESS.

**Decisión pendiente:** dueño ratifica tarjeta `02_tarjeta_decision_padre_hija_1_pagina.md` y enmienda del criterio. Después ingeniería integra finalizador oficial LF y escritura SALY, RLS/consumidores, restauración y readback Train. No cerrar G11.

**NOTA:** Este readback documental es posterior al commit CI `c47d...`. No modifica UP/DOWN ni tests validados; la evidencia de PG corresponde exactamente al HEAD citado, no atribuirla a otro HEAD sin comparar blobs.

## Evidencia adicional de integracion (head anterior, verificable)

- Commit previo `6ffa3453b93bf4ef431dcd0da40f5441c3ca0eea`: [R17 #43438754581](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43438754581) SUCCESS, 239 tests, 1 skip. [PASE #43438754755](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43438754755) SUCCESS y [clasificación #43438754552](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43438754552) SUCCESS. Incluye PG17.6/18.7 CREATE→v1, CANDIDATO nuevo→VIGENTE con v2, CORRECT_VIGENTE→append, writer oficial V2, permisos, backup/restore con datos confirmados.
- No atribuir estos PASS al HEAD posterior sin nueva corrida. Tras merge con `main f15ae1ff` se requiere 3 CI de nuevo por cambio de base y test reforzado. RLS/funciones solo en contenedor; Supabase vivo no modificado.
- El SIGUIENTE BLOQUEO DE FONDO sigue siendo escritor SALY oficial ausente y enmienda al documento 12 oficial sin aplicar; por eso NO habilitar ready-to-merge de una migración operativa ni Train.


## Lote nuevo — escritor SALY candidato y PR documental #3824

- PR #3824 DRAFT apunta a la rama L28 que contiene el documento 12 (ausente en main). Reemplaza exclusivamente párrafos Exacta/Falta de B07. SHA256 fuente `7a2ef3f621462dd9f79df9d6c36d2ae913b7661f2bae518230c39228dd3cdb40`; destino `84e56f4127c1be3f06bf45a5c733befef7e956a969e4c2577cfe1d6246889a7a`. Recibo PR #3821: `DEC-B07-PADRE-HIJA-001`, `identity_verified=false`. No merge de documentos.
- SQL nuevo `b07_saly_official_writer_candidate_v1.sql`, blob Git `ff6d47c70f42f5fb2ad6f8b132caf278ec16c79d`. Exige operación y owner SALY gobernados; no los crea en vivo. Historial hijo y recibo se generan en la misma transacción con el PADRE.
- PG17.6 y PG18.7 en GitHub Actions R17 run 43448460784, HEAD `2e938daef7fd6a9f7f6462a59f42c898379f7c3f`: ambos tests B07 `ok`; `PASS_B07_SALY_WRITER_GOVERNED_ATOMIC_ROLLBACK_HASH_EVIDENCE_REPLAY`, `PASS_B07_PG_DUMP_RESTORE_POST_COMMITTED_HISTORY`; fallos de hash viejo/evidencia incompleta/escritura directa, rollback previo y replay verificados; `VALIDADO` 14/14 preservado. El actor SALY y las decisiones en estos tests son sintéticos, no firmados.
- **R17 SUITE GLOBAL FAIL** en 43448460784 por B09 ajeno: prueba `test_b09_native_sha_receiver_governed_pg176_pg187.py` espera `20261113150000_lf_ig_native_chat_sha_receiver_v1.sql` no presente en main (`20261113143831...` es el archivo que existe). Además un test estático B09 falla durante import. No declarar 3/3 PASS, no corregir B09 desde PR B07.
- PASE run 43448460917 SUCCESS y clasificación 43448460575 SUCCESS; la integración B07 queda **candidato probado, no certificado para ready-to-merge/Train** hasta las tres CI PASS del mismo HEAD y dependencias operativas.
