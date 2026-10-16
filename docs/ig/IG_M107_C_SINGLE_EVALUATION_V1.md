# IG M10.7 — Lote C / una evaluación por fila de familia

**Alcance:** exclusivamente optimización C de cálculos/aserciones. La actualización conserva el conjunto de triggers y no usa caché entre triggers, familias, sentencias o sesiones.

## Causa y medición

EKB 007/012/033 y readback de la ejecución histórica 933: 47 aserciones, 19 aserciones exactas distintas, 34 familias con `ARRAY_LENGTH_EQ` sobre `SCREEN_CANONICAL_GRAPH`, una aserción por familia. El mismo `fn_input_evaluate_assertion` es invocado en el trigger `trg_input_family_assessment_00_execution_update` y de nuevo en `trg_input_family_assessment_update` para validar la misma aserción. El guard semántico de M4.6 continúa íntegro y puede reevaluar `CONTAINS` cuando la regla lo requiere; ese control no se elimina.

## Integración

- El **guard de ejecución** preserva: independencia de ejecución, identidad Validator/Curator, componente, binding a la ejecución del Curator, presencia de `assertions`, y obligatoriedad de los campos `result` y `source_observed_sha256` en cada aserción.
- El **guard final obligatorio** conserva `fn_input_evaluate_assertion` una sola vez por aserción y mantiene o incorpora exactamente los rechazos `ASSERTION_STORED_RESULT_MISMATCH`, `ASSERTION_STORED_SOURCE_SHA_MISMATCH`, `VALIDATOR_PASS_CONTAINS_FAILED_ASSERTION`. También conserva el cotejo de source/contract, relevancia independiente, currentness onepass, identidad, SHA del recibo, mutabilidad y otros controles previos.
- Los triggers no se eliminan, renombran ni deshabilitan. Preflight exige SHA exacto de ambas funciones actuales y los dos bindings antes de sustituir cuerpos. Postflight exige seis triggers UPDATE habilitados y la presencia de los tres rechazos en la función final.

## Aceptación por Migration Train

Prueba reversible de una pantalla (43), una familia `SCREEN_IDENTITY`, una propuesta:
1. Run Curator temporal → `VALIDATING`; validar fuente vigente.
2. Tres rechazos: SHA de snapshot falso; `result=FAIL` con afirmación realmente positiva y digest del assertion set correcto; `source_observed_sha256` falso con digest correcto.
3. Un UPDATE de familia positivo con seis triggers y uno de propuesta positivo con dos triggers.
4. Revertir por subtransacción el run y todos los cambios de tests. Persistir solo EKB `IG-M107-C-ONE-EVALUATION-034`.

**Condiciones:** si falla cualquier prueba, Train no aplica ni fusiona. El tiempo medido corresponde a esta única muestra, no representa CP3/p90 ni cierre total de C. El benchmark integral, consumers G y Router permanecen fuera de alcance.
