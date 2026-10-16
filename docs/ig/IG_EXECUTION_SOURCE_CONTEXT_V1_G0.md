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

## M10.7 — Método contractual vigente de snapshot en memoria (V2)

Esta revisión **sustituye el método anterior basado en bloquear tablas, crear épocas por fuente y verificar todos los escritores**. La prueba G2B de dos sesiones queda como antecedente del fixture, no como requisito para la optimización. No se modifica runtime, CP3 ni controles existentes.

### Implementación obligatoria
1. Leer **una sola vez por ejecución** las reglas aplicables, contratos, vínculos, políticas, dependencias y demás datos necesarios, con identidad de `run_id`, pantalla y versión.
2. Guardar los datos en un **snapshot íntegro e inmutable en memoria**, con hash canónico, identidad y cálculos deterministas reutilizables.
3. Curator, Validator, familias, propuestas y validaciones consumen los **mismos datos congelados**; si se separan por procesos, se transmite el mismo contenido íntegro. Sin consultas ni reconstrucciones redundantes.
4. Compartir **entradas, no decisiones**. Las validaciones independientes y Q0–Q8 siguen vigentes.
5. Rechazar snapshot alterado, incompleto o usado con otra identidad. No compartir paquetes entre ejecuciones. Los cambios posteriores en Supabase no cambian retroactivamente la evaluación; los actos que requieran vigencia actual conservan un guard independiente, sin reconstruir las entradas de cada fase.

### Método obligatorio de validación
1. **Equivalencia:** mismo caso y entradas; comparar flujo actual vs snapshot (reglas, vínculos, hallazgos, decisiones independientes y estados). Cero falsos PASS.
2. **Reutilización:** contar consultas, compilaciones, reconstrucciones y cálculos; demostrar una extracción lógica por conjunto y reutilización desde memoria en todo el flujo.
3. **Negativos:** tamper de datos/hash e identidad cruzada se rechazan; un cambio posterior de fuente no mezcla versiones, y el guard de vigencia vigente sigue aplicando cuando corresponda.
4. **Rendimiento:** comparar tiempos y consultas antes/después en muestra representativa; medir por fase y total, repetir y calcular p50/p90 si procede. Evidenciar ahorro real sin inventar porcentajes ni ampliar 150 segundos.
5. **Regresión:** preservar triggers existentes, reglas aplicables y Q0–Q8; no cerrar CP3 ni activar G3 sin esas evidencias.

**Criterio de aceptación:** equivalencia exacta, aislamiento e integridad, cero falsos PASS, reducción medida de trabajo repetido y preservación de controles vigentes. No exigir nuevas pruebas de bloqueo/versión por tabla para esta optimización.

## Rutas, rollback, EKB
Todas las escrituras DB solo por PR -> label ready-to-merge -> LF Migration Train REAL -> apply exact-version -> ledger -> Git/main/readback DB. Operación ACTUALIZACION_DB_LF la reserva Train; NO reservarla manualmente. Operation runtime posterior, no sustituto de DDL.
G1 es aditiva y sin GRANT público. Reversión controlada antes de consumo autorizado: DROP FUNCTION mediante una migración nueva (no borrar historial).
EKB: IG-SHADOW-V2-CONTEXT-REUSE-001, IG-M107-TRIGGER-ROLLBACK-PROFILE-008, IG-M107-ATOMIC-MANIFEST-REPEAT-005, ENGINEERING-CP-SECURITY-CONTEXT-NO-EXPLICITO-028.
Prueba local 12/12 del context_guard del paquete offline; NO es prueba PostgreSQL. Issue #2733: bloqueo de herramientas anterior; no declarar resuelto si reaparece.

## Cierre contractual V2
La revisión fija método y validación. Solo queda aplicada tras PR → LF Merge Train → readback; no activa runtime, no acredita mejoras ni cierra CP3.
