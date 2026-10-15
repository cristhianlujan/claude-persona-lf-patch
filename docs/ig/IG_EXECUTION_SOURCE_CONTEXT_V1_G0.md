# IG_EXECUTION_SOURCE_CONTEXT_V1 — G0 (alcance y gobierno)
Estado: CANDIDATO, no activo. Origen: IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.7. Propietario: autoridad existente INPUT_GOVERNANCE (Supabase).
Aprobación de encaminar: autorización del usuario para Migration/Operation del 2026-10-15. No es autorización para saltar guards ni activar producción.

## Cambio independiente de CP3
Esta intervención es un cambioset transversal separable. No se altera el action_spec ni la evidencia del CP3 NO_FALSE_PASS, cuyo target declarado continúa siendo `sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py`.
Objeto nuevo autorizado **solo en forma candidata no ejecutable para clientes**: `programacion.fn_input_governance_run_context_packet_v1(bigint)`. Se propone mediante una migración SQL aislada y un PR propio a través de LF Migration Merge Train. No activar ni modificar las 21 guardas/transiciones de Validator.

## Contrato de datos
La identidad del paquete es (run_id, pantalla_id, version_id, contract_snapshot_sha256, source_manifest_identity_sha256, curator_identity, validator_identity). RUN_PINNED puede transportarse y releerse por run_id; no certifica autoridad actual por sí solo.
El proveedor admite solo run VALIDATING con snapshot/contrato materializados, identidad Validator independiente, familia completa y `fn_input_governance_continuation_currentness_v1` favorable.
El paquete contiene datos/ref únicas de familias y propuestas, jamás resultados PASS, evidencia de Validator ni una afirmación de autorización para producción.

## Seguridad de cambios concurrentes
Supabase usa READ COMMITTED y los resolvers son VOLATILE. Un SHA del contexto almacenado NO demuestra currentness. No compartir una GUC Curator entre transacciones ni usar caché mutable incondicional. Revalidar autoridad al consumir; si la instantánea, el alcance o el readback no concuerdan, FAIL_CLOSED y relectura de la fuente. Conservar evaluación semántica Validator independiente y triggers. Prohibida cache cross-run/cross-screen.

## Fases de admisión
G0: esta declaración de objeto, dueño, ámbito, veto y pruebas, ruta Router ACT-0001 -> ACTUALIZACION_DB_LF; no es una mutación de CP3.
G1: migration standalone (una por PR), función SECURITY DEFINER con search_path restringido y EXECUTE revocado a PUBLIC. Pruebas de ausente y terminal; sin permisos de runtime, sin usuarios, sin nuevos run.
G2: lectura material real con run VALIDATING y readback independiente; prueba de cambio de fuente entre llamadas y concurrencia con rollback, aserciones adulteradas, cross-run, contratos alterados; equiparidad JSON/SHA.
G3: conectar consumidores Curator/Validator/propuestas solo tras G2, y medir triggers y consultas; no descartar 246 reglas ni controles Q0–Q8.
G4: una pantalla compleja, tiempos y percentiles comparables; CP3 sigue PENDING hasta >=2 observaciones históricas as-of por pantalla/familia, 0 falsos PASS, 0 D4, 0 timeout >150 s, duración completa y ventana congelada.

## Rutas, rollback, EKB
Todas las escrituras DB solo por PR -> label ready-to-merge -> LF Migration Train REAL -> apply exact-version -> ledger -> Git/main/readback DB. Operación ACTUALIZACION_DB_LF la reserva Train; NO reservarla manualmente. Operation runtime posterior, no sustituto de DDL.
G1 es aditiva y sin GRANT público. Reversión controlada antes de consumo autorizado: DROP FUNCTION mediante una migración nueva (no borrar historial).
EKB: IG-SHADOW-V2-CONTEXT-REUSE-001, IG-M107-TRIGGER-ROLLBACK-PROFILE-008, IG-M107-ATOMIC-MANIFEST-REPEAT-005, ENGINEERING-CP-SECURITY-CONTEXT-NO-EXPLICITO-028.
Prueba local 12/12 del context_guard del paquete offline; NO es prueba PostgreSQL. Issue #2733: bloqueo de herramientas anterior; no declarar resuelto si reaparece.

## Criterio de cierre de G0
Documento incorporado a main por Train con hashes y readback. NO declara G1 aplicado, rendimiento mejorado, ni CP3 superado.
