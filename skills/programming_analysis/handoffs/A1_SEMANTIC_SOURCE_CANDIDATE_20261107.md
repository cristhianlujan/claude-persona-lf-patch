# A1 — Normalización semántica y transporte local a A2

Estado: SOURCE_CANDIDATE / NOT_QUALIFIED / no merged. Alcance: desarrollo interno A1 y punto de entrega a A2. NO Router, RUN, SQL, políticas oficiales ni activación.

## Decisión técnica
- No usar parser léxico o booleanos diseñados para la frase «por primera vez».
- Distinguir operación IMPLEMENT de hipótesis CLAIMED_GREENFIELD y estado real PENDING_INVENTORY.
- Separar SCREEN, AUTH_FLOW, IDENTITY_AND_ACCESS y B2B (actor). Menciones originales son pistas, no nombres oficiales.
- Preguntas de investigación documental no equivalen a políticas inexistentes ni a ambigüedades materiales.
- Contrato canónico REQUEST_CONTEXT_V1 permanece intacto; INTENT_ANALYSIS_CANDIDATE_V1 es anexo de la envoltura interna.
- Política A2 de nueve señales L1/L2/L3 permanece intacta. A1 no puede fabricar señales de autoridad, currentness, reversibilidad o materialidad.

## Archivos fuente candidatos
1. steps/a1/semantic_intake_candidate_v1.py: recibe productor semántico y revisor SEPARADOS como callbacks; valida esquema, spans y veredicto, pero NO autentica identidad externa.
2. steps/a1/schemas/intent_analysis_candidate_v1.schema.json: anexo genérico, operación, arquetipo, capacidad, actor, evidencia, supuestos, dimensiones a investigar.
3. steps/a1/validators/run.py: acepta str/raw_prompt con negocio explícito y callbacks; conserva ruta histórica estructurada.
4. steps/a1/judges/semantic_guard.py y steps/a1/schemas/output.schema.json: consistencia del anexo y sha; no altera contrato canónico.
5. steps/a2/validators/run.py: verifica continuidad de operación y tipo de artefacto; no cambia señalización canónica.
6. adapters/a1_a2_candidate_bridge_v1.py:prepare_semantic_transport: transporte interno, sin RUN, requiere evidencia tipada para proyectar A2.
7. steps/a1/evals/test_a1_semantic_candidate_v1.py: 12 pruebas sintéticas definidas; NO ejecutadas todavía en Python, NO modelo real.

## Protocolo de productor y revisor
El productor semántico debe inferir por significado, considerando negación, intención, restricciones y contexto. No debe depender de la primera coincidencia de palabras. Debe entregar fragments exactos con offset y dimensiones de sustento, y no puede atribuir estado de repositorio ni crear IDs de pantalla.
El revisor separado debe comparar texto original contra interpretación, rechazar negación no reconocida, contradicciones, invención de decisiones y pérdida de restricciones. Verificar substring no es revisión semántica suficiente. Los callbacks no acreditan por sí mismos independencia, por tanto semantic_review_identity_verified=false.

## Ejemplo funcional
Entrada: Implementa por primera vez el login B2B o también llamado inicio de sesión.
Esperado (NO resultado de modelo real): IMPLEMENT + CLAIMED_GREENFIELD + SCREEN + AUTH_FLOW + IDENTITY_AND_ACCESS + B2B. Investigar mecanismos AUTH, sesión, rutas, recuperación y errores en políticas CURRENT; NO asumir código inexistente.
El A1 devuelve REQUEST_CONTEXT_V1 como payload y el anexo externo INTENT_ANALYSIS_CANDIDATE_V1. La transición A2 solo transporta la intención revisada; no inventa los nueve depth_signals.

## Estados de transporte
- Sin productor/revisor: BLOCKED, sin pase A2.
- Sin revisión semántica: REQUIRES_SEMANTIC_REVIEW, sin pase A2.
- Candidato revisado sin ambigüedades materiales: VALID_OUTPUT / SEMANTIC_REVIEWED_CANDIDATE / next_capability=A2. Sigue NO AUTENTICADO operacionalmente.
- Sin señales tipadas + evidencia externa: A1_READY_A2_EVIDENCE_REQUIRED, A2 sin ejecutar.
- Con nueve señales tipadas de fuente externa: A2 entrega clasificación candidata no atestada; ninguna admisión A3.

## Pendientes verificables
- Integrar productor semántico real y juez realmente independiente, con identidad/receipt verificable.
- Ejecutar tests Python y casos holdout exact-HEAD. Tests sintéticos no demuestran semántica real.
- Endurecer resistencia a productor/revisor falsificado, contradicciones de lenguaje y evidencia inventada.
- Mantener PR DRAFT sin merge ni declaración READY.
