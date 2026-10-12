# ANALYSIS PROCEDURE V1 — A1 a A9

**Estado del artefacto:** `PROCEDURE_SOURCE_COMPLETE / VALIDATION_DEFERRED`. **Alcance:** definición del proceso, exclusivamente. No se admite ningún caso, ni se invoca un agente sobre un objetivo real, ni se ejecuta una prueba o validación en vivo durante este lote. No hay habilitación de runtime, pase a Programación, implementación o despliegue.

**Contrato de ejecución canónico:** [analysis_procedure_v1.json](analysis_procedure_v1.json). Reutiliza, sin copiarlos ni modificarlos, los nueve contratos existentes del directorio. El plan fuente es `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Los estados `DONE` de unidades en el ledger no sustituyen la futura validación integral del procedimiento.

## Secuencia obligatoria

| Orden | Responsable lógico | Acción procedimental | Salida obligatoria | Continuación |
|---|---|---|---|---|
| A1 | Analysis | Normalizar solicitud y alcance, sin suponer solución | `REQUEST_CONTEXT_V1` | A2 o decisión esencial |
| A2 | Analysis | Clasificar trabajo, granularidad y profundidad L1/L2/L3 con señales gobernadas | `ANALYSIS_CHANGE_CLASSIFICATION_V1` | A3; incertidumbre material no baja a L1 |
| A3 | Analysis + autoridades canónicas | Leer EKB, resolver evidencias vigentes, target, `AUTHORITY_STATE` e `IMPLEMENTATION_STATE` por separado | `TARGETED_EVIDENCE_SET_V1` | A4 o evidencia faltante tipada |
| A4 | `SHARED_CHANGE_IMPACT_ANALYSIS` vía adapter Analysis | Derivar impacto directo, indirecto, consumidores y dependencias | `SHARED_CHANGE_IMPACT_ANALYSIS` | A5; sin motor paralelo |
| A5 | Analysis + dueño de decisión si aplica | Separar hechos de decisiones, consultar ADR vigente y formular decisión material abierta | `ANALYSIS_DECISION_CONTEXT_V1` | A6 o `REQUIRES_DECISION` |
| A6 | Analysis | Traducir intención a obligaciones tipadas, contratos, riesgos de efectos, condiciones y bindings canónicos | `IMPLEMENTABILITY_SCHEMA_V1` / `CANONICAL_IMPLEMENTATION_BINDINGS` | A7; nunca elegir HOW ni programar |
| A7 | Analysis | Inventariar sin pérdida cada frente material, su evidencia, alcance y resolución | `MATERIAL_FRONT_COVERAGE_V1` | A8; unknown explícito |
| A8 | Analysis | Decidir estabilidad de investigación y cobertura | `ANALYSIS_STOP_RULE_V1` | A9 si STOP; retorno dirigido si falta evidencia; bloqueo o decisión |
| A9 | Analysis assembler + juez semántico independiente gobernado | Ensamblar package y snapshot completo, matriz frente↔scope, estados por scope, referencias, huellas y contrato del handoff | `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` + `PROGRAMMING_CONTEXT_SNAPSHOT_V1` | Preparado para validación futura; NO ejecutar PG-01 ahora |

**Condición de flujo:** A1→A2→A3→A4→A5→A6→A7→A8→A9. Un retorno de A8 se limita a la fase cuyo vacío material está identificado; no reinicia el flujo ni habilita exploración libre.

## Reglas duras de operación

1. **Separación:** Análisis decide el QUÉ con evidencia; PG-03 decide el CÓMO; Testing diseña/ejecuta las pruebas solo después de este trabajo; el trabajo de implementación del producto no pertenece a este procedimiento.
2. **Fuente primero:** EKB y autoridades canónicas, no memoria del chat como evidencia. Preferir referencias exactas/resolved values y resolutores tipados. Respetar `CURRENTNESS_AUTHORITY` y no repetir consultas si sigue vigente el fingerprint.
3. **Estados independientes:** la existencia de una autoridad NO demuestra que exista implementación. Existente exige AS-IS + delta; nuevo exige ausencia acotada de implementación + revisión reutilizar/extender.
4. **Reutilización:** consultar capacidades `CURRENT RELEASED` y consumidores existentes; `CAPABILITY_SELECTOR` solo sugiere candidatos, nunca concede ejecución. No motor paralelo.
5. **Contratos tipados:** cada obligación material expone scope, estado, authority/evidence/currentness, inputs, outputs, errores, permisos, efectos, precondiciones, blockers y señales de aceptación. Falta material ≠ omisión tolerada.
6. **Frentes materiales:** `REQUIRED | REUSE_AS_IS | NOT_APPLICABLE`. Los no aplicables requieren razón y evidencia; los reutilizados requieren currentness; los desconocidos quedan visibles como bloqueados.
7. **STOP no es READY:** A8 puede detener búsqueda aunque existan decisiones o frentes bloqueados explícitamente. A9 no podrá calificarlos como READY. No fabricar una condición terminal.
8. **Calificación por scope:** `READY | NEED_MORE_EVIDENCE | REQUIRES_DECISION | BLOCKED | NOT_APPLICABLE`. El package solo es `PARTIAL_READY` si hay scope READY independiente, con dependencias cerradas y sin frente `BLOCKS`.
9. **Handoff sin pérdida:** A9 conserva íntegros requirements, `IMPLEMENTABILITY_SCHEMA_V1`, `MATERIAL_FRONT_COVERAGE_V1`, `ANALYSIS_STOP_RULE_V1`, `scope_front_matrix[]`, `scope_readiness[]`, decisiones, evidencia y digests. No reemplazar con un resumen.
10. **Identidad y persistencia:** `DECISION_CONTEXT_ASOF@CURRENT` es el único almacén previsto para el snapshot; append-only, ref y versión exactas. No nueva tabla, no mutación retroactiva. PG-01 debe verificar digest y currentness *cuando se autorice ejecutar el handoff*, no ahora.
11. **Trabajos pequeños:** el contexto entregado al siguiente paso es solo el subconjunto material pertinente; consulta repetida únicamente ante `MISSING | STALE | CONTRADICTION | SOURCE_DRIFT | MATERIAL_NEW_QUESTION`.
12. **Fail closed:** si falta autoridad, un riesgo material no está delimitado, existe un conflicto o se necesita decisión humana, registrar objeto `blocker` con código, scope, causa, evidencia, dueño y siguiente resolución. No inferir ni sortear el bloqueo.

## Responsabilidad y cierre

| Resultado del procedimiento | Qué significa | ¿Prueba que el agente funciona? |
|---|---|---|
| `PROCEDURE_SOURCE_COMPLETE` | Están definidos los nueve pasos, inputs/outputs, transiciones, owners y gates | **No** |
| `VALIDATION_DEFERRED` | No se ejecutaron pruebas ni casos por restricción expresa de este lote | **No** |
| `READY` para un scope real | Requiere evidencia real y validación independiente del modelo cuando llegue su fase | **No declararlo ahora** |
| `ANALYSIS_V1_FROZEN` | Exige gates empíricos/receipts válidos, no un archivo `SOURCE_ONLY` | **No declararlo ahora** |

**A10–A15:** permanecen definidos en su plan histórico pero quedan expresamente fuera de ejecución mientras se termina la fuente del procedimiento. No fabricar resultados, tocar holdouts, ejecutar benchmarks ni crear fixtures.

**No cambiar el estado de implementación de ningún producto. No ejecutar PG-01. No ejecutar el juez con un caso. No desplegar.** La validación integral vendrá únicamente cuando se abra expresamente esa fase, después del cierre de los procedimientos.

## Evidencia y trazabilidad

- Fuente de pasos: `analysis_request_context_v1.schema.json`, `analysis_change_classification_contract_v1.json`, `analysis_targeted_evidence_contract_v1.json`, `shared_change_impact_contract_v1.json`, `analysis_decision_context_adr_contract_v1.json`, `analysis_implementability_contract_v1.json`, `analysis_material_front_coverage_contract_v1.json`, `analysis_stop_rule_contract_v1.json`.
- Frontera final: `analysis_programming_handoff_parity_contract_v1.json` y `programming_entry_contract_v1.json`.
- Flujo machine-readable, dueños y transiciones: `analysis_procedure_v1.json`.
- Alcance de este commit: **solamente procedimiento/documentación nueva**; ningún cambio a los contratos originales, esquema SQL, producto, runtime ni catálogo de casos.
