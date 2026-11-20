# Auditoría Perfil → IG → Perfil — reporte V2

**FLUJO NO ACREDITADO.** Cobertura del lote conocido: **64.29 %**. Nueva ejecución E2E: **False**.

La tabla muestra observaciones precisas y sus límites. Un estado guardado como PASS no acredita por sí mismo el comportamiento completo.

## Lo que funcionó y lo que falta por paso

| Paso | Qué se comprobó | Estado reportado | Tipo de evidencia | Recibo / evidencia | Falta comprobar | Confianza |
|---|---|---|---|---|---|---|
| 0 | Existe el padre y un recibo de init_execution enlazado por execution_id. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-808379962BF5ACA150004167; E-STEP-0, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 10 | Existe referencia de autorización del Router y el paso está persistido como PASS. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | router-authorization://7ffc3d59d8ea67dec29a68a85e0aa89bee2d15ef543cec9fc527ae017c0e653d; E-STEP-10, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 20 | El paso identifica PERFIL-PRODUCT-DIRECTOR-LF y la fuente lf_activos. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_activos/PERFIL-PRODUCT-DIRECTOR-LF; E-STEP-20, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 30 | Se guardaron revisión bd599aff y digest de la fuente del perfil. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | github://cristhianlujan/claude-persona-lf-patch@bd599aff0a1353e5850fef1b9675c13b7344b317/profiles/product_director_lf/SKILL.md; E-STEP-30, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 40 | Se guardaron scope y finding de selección; receipts=[]: no prueba ejecución IG. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_profile_execution_input_validate_v1/EXEC-PROFILE-GATE2-808379962BF5ACA150004167; E-STEP-40, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría.; IG no fue invocado en esta corrida; selector opcional y ejecución son obligaciones distintas. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 45 | Se guardó context_receipt_ref y digest de contexto. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_eventos/21901#context_receipt; E-STEP-45, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 47 | La política guardada dice research_baseline NOT_REQUIRED / NOT_APPLICABLE. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-808379962BF5ACA150004167/research_baseline_freeze; E-STEP-47, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 50 | Se guardó artefacto del perfil con digest de candidato y digest del contexto 45. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | actions://cristhianlujan/claude-persona-lf-patch/runs/43783735524/artifact/profile-native-output-43783735524/profile-native-output.json; E-STEP-50, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 60 | Se guardó validación determinista PASS y el mismo digest externo de 50. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | actions://cristhianlujan/claude-persona-lf-patch/runs/43783735524/artifact/profile-native-output-43783735524/profile-native-validation.json; E-STEP-60, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría.; El raw hash interno de source_bound_validation difiere del digest externo; comprobar representación antes de diagnosticar drift. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 70 | Se guardó PASS_REVIEWED_CURRENT_CONTEXT con candidato/alcance enlazados; no prueba independencia. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | actions://cristhianlujan/claude-persona-lf-patch/runs/43783869639/artifact/profile-native-output-43783869639/profile-semantic-judge.json; E-STEP-70, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |
| 80 | Se guardó reporte con no_write_performed=true e ig_findings_reported=true; no es recibo IG. | STEP_PASS_WITH_EVIDENCE | MEASURED_THIS_AUDIT | supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-808379962BF5ACA150004167/report_output; E-STEP-80, E-BINDINGS | Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.; No es una ejecución nueva de esta auditoría. | HIGH: Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado. |

## SQL medido e inventario pendiente

ANALYZE ejecuta el SELECT. Los planes medidos se capturaron con BEGIN READ ONLY y ROLLBACK, timeout de 3 s. Las funciones escritoras no se invocaron.

| Consulta | Rol | Tablas / joins | Índices existentes | Ejecución ms | Buffers hit/read | Muestras | Frecuencia | Materialización |
|---|---|---|---|---|---|---|---|---|
| Q_STEPS | AUDIT_QUERY | lf_operation_execution_steps;  | lf_operation_execution_steps_pkey, uq_lf_operation_execution_steps_execution_step | 0.162 | 11/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_PARENT | AUDIT_QUERY | lf_operation_execution;  | lf_operation_execution_idempotency_uq, lf_operation_execution_pkey | 0.714 | 3/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_IG_INVOCATIONS | AUDIT_QUERY | lf_skill_invocation_v1;  | lf_skill_invocation_v1_new_parent_skill_input_uniq, lf_skill_invocation_v1_pkey | 0.211 | 3/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_RECENT_COHORT | AUDIT_QUERY | lf_operation_execution, lf_operation_execution_steps, lf_skill_invocation_v1; cohort LEFT JOIN steps por execution_id; cohort LEFT JOIN invocations por parent_execution_id | lf_operation_execution_idempotency_uq, lf_operation_execution_pkey, lf_operation_execution_steps_pkey, lf_skill_invocation_v1_new_parent_skill_input_uniq, lf_skill_invocation_v1_pkey, uq_lf_operation_execution_steps_execution_step | 219.673 | 1212/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_SKILL_REGISTRY | AUDIT_QUERY | lf_skill_selection_registry_v1;  | lf_skill_selection_registry_v1_pkey | 2.511 | 2/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_RUNTIME_PARENT | FLOW_QUERY | lf_operation_execution;  | lf_operation_execution_idempotency_uq, lf_operation_execution_pkey | 0.129 | 3/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_RUNTIME_SCOPE | FLOW_QUERY | lf_operation_execution_steps;  | lf_operation_execution_steps_pkey, uq_lf_operation_execution_steps_execution_step | 0.97 | 33/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| Q_RUNTIME_SELECTION | FLOW_QUERY | lf_skill_catalog_v1, lf_skill_selection_registry_v1, lf_skill_selector_policy_v1; policy LEFT JOIN skill_catalog por skill_code; LEFT JOIN selection_registry por skill_code; descriptor CURRENT y filtros de canal | lf_skill_catalog_v1_pkey, lf_skill_selection_registry_v1_pkey, lf_skill_selector_policy_v1_pkey | 4.927 | 10/0 | 1 | NO MEDIDA | NOT_EVALUATED |
| UNMEASURED-lf_profile_native_bridge_prepare_v1 | SOURCE_INVENTORY_ONLY | ;  | No resueltos | NO MEDIDO | None/None | 0 | NO MEDIDA | NOT_EVALUATED |
| UNMEASURED-lf_profile_native_bridge_record_semantic_v1 | SOURCE_INVENTORY_ONLY | ;  | No resueltos | NO MEDIDO | None/None | 0 | NO MEDIDA | NOT_EVALUATED |
| UNMEASURED-lf_profile_native_bridge_record_report_v1 | SOURCE_INVENTORY_ONLY | ;  | No resueltos | NO MEDIDO | None/None | 0 | NO MEDIDA | NOT_EVALUATED |

Hay consultas del flujo y consultas creadas para esta auditoría: sus costos no se atribuyen entre sí. Una muestra no acredita p95, cache fría ni concurrencia. El SQL interno dinámico no resuelto sigue fuera de cobertura. Un nodo Materialize no es una vista materializada.

## Transporte en cada salto

| Salto | Emisor → receptor | Campos enviados | Perdidos | RUN | Hash y significado | No verificado |
|---|---|---|---|---|---|---|
| H-0-10 | init_execution → Router | execution_id, profile_code | Sin pérdida demostrada | RECORDED_PARENT_MATCH | NOT_APPLICABLE: Candidato aún no existe; la autorización tiene referencia propia. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-10-20 | Router → profile_resolve | execution_id, profile_code, authorization_ref | Sin pérdida demostrada | RECORDED_PARENT_MATCH | NOT_VERIFIED: No se revalidó el digest de autorización; candidate_sha256 aún no aplica. | Se cotejan registros del mismo padre, no una traza nueva del transporte.; Resolver/recalcular el hash aplicable. |
| H-20-30 | profile_resolve → profile_source_read | profile_code, source_ref, source_revision | Sin pérdida demostrada | RECORDED_PARENT_MATCH | SOURCE_CHECK_OBSERVED: Fuente bd599aff y profile_source_digest guardados; no se rehashó aquí el perfil original. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-30-40 | profile_source_read → input_validate | execution_id, profile_source_ref, input_context, resolved_scope | Sin pérdida demostrada | RECORDED_PARENT_MATCH | NOT_VERIFIED: Hash de fuente y scope son identidades diferentes; falta traza del derivado. | Se cotejan registros del mismo padre, no una traza nueva del transporte.; Resolver/recalcular el hash aplicable. |
| H-40-45 | input_validate → context_admission | execution_id, scope_sha256, input_governance, skill_findings | Resolución de scope requerida antes de seleccionar IG no demostrada en el input del selector; evidencia anterior describe llegada tardía. | RECORDED_PARENT_MATCH | NOT_VERIFIED: scope→context_receipt es derivación, no comparación de hashes iguales. | Se cotejan registros del mismo padre, no una traza nueva del transporte.; Resolver/recalcular el hash aplicable. |
| H-45-47 | context_admission → research_baseline_freeze | execution_id, context_receipt_ref, context_receipt_digest | Sin pérdida demostrada | RECORDED_PARENT_MATCH | NOT_APPLICABLE: Baseline se declara NOT_REQUIRED; no se exige candidato antes de 50. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-47-50 | research_baseline_freeze → execute_profile | execution_id, research_baseline_binding, context_receipt_digest | Sin pérdida demostrada | RECORDED_PARENT_MATCH | RECORDED_MATCH: Digest de contexto 45=50; baseline NOT_APPLICABLE guardado, sin forzar hash inexistente. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-50-60 | execute_profile → output_validate | raw_output_sha256, candidate_digest, profile_output_ref | Sin pérdida demostrada | RECORDED_PARENT_MATCH | RECORDED_MATCH: Digest externo 50=60; el hash de RAW interno corresponde a otra representación pendiente de resolver. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-60-70 | output_validate → semantic_judge | candidate_digest, scope_sha256, deterministic_validation | Sin pérdida demostrada | RECORDED_PARENT_MATCH | RECORDED_MATCH: 848f908e… es el mismo candidato externo 50/60/70 tras quitar prefijo sha256:. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-70-80 | semantic_judge → report_output | candidate_sha256, scope_packet_sha256, verdict, evaluation_mode | Sin pérdida demostrada | RECORDED_PARENT_MATCH | RECORDED_MATCH: Candidato y scope guardados coinciden 70/80; no prueba autorización de efecto. | Se cotejan registros del mismo padre, no una traza nueva del transporte. |
| H-IG-REQUEST | input_validate → IG runtime |  | Sin pérdida demostrada | NOT_APPLICABLE | NOT_APPLICABLE: No hay invocación IG registrada; no se inventa request, respuesta ni hash. | Recorrido E2E que invoque y consuma IG. |
| H-IG-RETURN | IG runtime → execute_profile |  | Sin pérdida demostrada | NOT_APPLICABLE | NOT_APPLICABLE: No hay invocación IG registrada; no se inventa request, respuesta ni hash. | Recorrido E2E que invoque y consuma IG. |

## Muestra de corridas

N solicitado: 20; N observado: 20.

Estados observados: {'IN_PROGRESS': 2, 'COMPLETED': 11, 'ABANDONED': 7}.

| Indicador | Numerador / denominador | Interpretación |
|---|---|---|
| PASS sin referencia | 0 / 175 (0.0 %) | Presencia de puntero; no calidad semántica |
| IG reportado sin invocación registrada | 9 / 9 (100.0 %) | Señal de nomenclatura/observabilidad; IG puede ser opcional |
| Tasa real de falsos PASS | NO MEDIDA | Requiere resolver contrato y ejecutar negativos por caso |

## Matriz de contratos

🟢 Aceptable · 🟡 contenido débil · 🔴 faltante/contradicción · ⚪ no evaluado · — no aplica. La nota no usa longitud ni cantidad de palabras.

| Contrato / tipo | Objetivo y alcance | Entrada | Tipos, nulos y defaults | Precondiciones | Reglas y ramas | Salida y significado | Errores y siguiente acción | Autoridad y efectos | Versión, hashes y compatibilidad | Positivos, negativos y readback | Consumidor y bindings | Ejemplos concretos | Frescura e invalidación | Nota |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C01 Entrada del auditor V1 / INPUT | — No aplica | 🟢 Aceptable | 🟡 Débil | 🟡 Débil | — No aplica | — No aplica | 🟢 Aceptable | — No aplica | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | 🟡 Débil | — No aplica | Bajo |
| C02 Reporte V1 / OUTPUT | — No aplica | — No aplica | 🟢 Aceptable | — No aplica | — No aplica | 🟡 Débil | ⚪ No evaluado | — No aplica | 🟢 Aceptable | 🟡 Débil | ⚪ No evaluado | ⚪ No evaluado | — No aplica | Bajo |
| C03 Salida de revisión Step70 / OUTPUT | — No aplica | — No aplica | 🟡 Débil | — No aplica | — No aplica | 🟢 Aceptable | ⚪ No evaluado | — No aplica | 🟢 Aceptable | 🟡 Débil | ⚪ No evaluado | ⚪ No evaluado | — No aplica | Bajo |
| C04 Normalización y transporte Step70 / TRANSPORT | — No aplica | 🔴 Faltante | ⚪ No evaluado | — No aplica | ⚪ No evaluado | 🔴 Contradictorio | 🟡 Débil | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | — No aplica | — No aplica | Bajo |
| C05 EVAL Step70 / EVAL | — No aplica | 🟢 Aceptable | 🔴 Contradictorio | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | — No aplica | — No aplica | Bajo |
| C06 Juez contextual del auditor / JUDGE | 🟢 Aceptable | ⚪ No evaluado | ⚪ No evaluado | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟡 Débil | 🟢 Aceptable | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | ⚪ No evaluado | — No aplica | No evaluado |
| C07 Selector de skills: contrato SQL / SQL | — No aplica | 🟢 Aceptable | ⚪ No evaluado | — No aplica | 🟢 Aceptable | ⚪ No evaluado | ⚪ No evaluado | 🟢 Aceptable | ⚪ No evaluado | 🟡 Débil | — No aplica | — No aplica | ⚪ No evaluado | Bajo |
| C08 Snapshot local de ejemplo / SNAPSHOT | — No aplica | 🟢 Aceptable | 🟢 Aceptable | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | 🟢 Aceptable | Aceptable |
| C09 Handoff candidato V1 / HANDOFF | ⚪ No evaluado | ⚪ No evaluado | — No aplica | — No aplica | — No aplica | 🟡 Débil | ⚪ No evaluado | 🟢 Aceptable | ⚪ No evaluado | ⚪ No evaluado | 🟢 Aceptable | ⚪ No evaluado | — No aplica | Bajo |
| C10 Contrato de reporte V2 / SPEC | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | Aceptable |
| C11 Entrada del auditor V2 / INPUT | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | — No aplica | 🟢 Aceptable | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | Aceptable |
| C12 Handoff candidato V2 / HANDOFF | 🟢 Aceptable | 🟢 Aceptable | — No aplica | — No aplica | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟡 Débil | 🟢 Aceptable | 🟡 Débil | — No aplica | Medio |
| C13 Juez contextual V2 / JUDGE | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | 🟢 Aceptable | — No aplica | Aceptable |

Cada celda del HTML incluye literal, fuente, motivo contextual y propuesta exacta. Nota contractual no equivale a aprobación del flujo. Revisión de contenido: CURRENT_CONTEXT_SPEC; no acredita independencia.

### C01 — Entrada del auditor V1

- Tipos, nulos y defaults: **Débil**. La lista de nombres no fija tipo, nulos, cardinalidad ni diferencia entre un ref declarado y uno resuelto. Un ejecutor debe inferirlos.
  Propuesta: Definir base_commit como SHA40 no nulo; read_scope/consumer_targets como arrays no vacíos de referencias resueltas; documentar validación y error por campo.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/main_contract_v1.txt
- Precondiciones: **Débil**. La intención es clara, pero no identifica cómo se demuestra currentness de cada fuente ni qué se hace si divergen las versiones.
  Propuesta: Si commit/ref no resuelve o el hash cambia, registrar el campo y bloquear solo la afirmación afectada; continuar lectura independiente con NOT_VERIFIED.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/main_contract_v1.txt
- Ejemplos concretos: **Débil**. Exige casos por capacidad, pero no describe ejemplos de intake que diferencien tipos inválidos de fuentes aún no resueltas.
  Propuesta: Añadir input válido completo; base_commit=null; consumer_targets=[]; write_scope fuera del mandato y salida esperada por cada caso.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/main_contract_v1.txt

### C02 — Reporte V1

- Salida y significado: **Débil**. Su forma no separa cobertura del lote, ledger de once pasos y acreditación del E2E; el lector debe reconstruir esa diferencia desde prosa.
  Propuesta: Usar audit_report_v2: completion.lot_coverage_percent y completion.flow_verdict independientes, más steps/hops/sql_queries/contracts/provenance.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/output_v1.schema.json
- Positivos, negativos y readback: **Débil**. Completar seis fases no prueba once pasos ni un E2E nuevo. Faltaba negativo que impida deducirlo del porcentaje.
  Propuesta: Añadir regresión que rechace FLOW_ACCREDITED sin nueva corrida, recibos resueltos y enlaces de cada salto.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/output_v1.schema.json

### C03 — Salida de revisión Step70

- Tipos, nulos y defaults: **Débil**. La cota de doce propiedades no enumera nombres ni forma de cada check. Otro productor puede enviar doce claves arbitrarias y pasar la forma.
  Propuesta: Definir decision_checks.required con los 12 IDs; additionalProperties=false y schema por check con result/razón/refs/contexto aplicable.
  Fuente: profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json
- Positivos, negativos y readback: **Débil**. El contrato exige mínimo 4 para referencias; EVAL acepta ['x'] en la reproducción actual. La prueba de paridad no estaba cubriendo ambas capas.
  Propuesta: Ejecutar paridad schema/EVAL con refs [], [''], ['x'] y referencia válida; conservar diagnóstico exacto de ambas capas.
  Fuente: profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json

### C04 — Normalización y transporte Step70

- Entrada: **Faltante**. No recibe el execution_id esperado del padre, aunque assess_separate_call_receipt sí permite compararlo.
  Propuesta: normalize_when_unverified(review, *, execution_id); pasar el parámetro desde complete_native_profile_semantic_and_report hasta assess_separate_call_receipt.
  Fuente: scripts/lf_step70_separate_call_receipt_v1.py
- Salida y significado: **Contradictorio**. La ruta material EVAL_FAILURE puede terminar en PASS contextual, borrando el recibo que contradice el dictamen externo.
  Propuesta: Separar errores de evidencia/procedencia y errores materiales; conservar el fallo y retornar REVIEW_INVALID sin persistir PASS.
  Fuente: scripts/lf_step70_separate_call_receipt_v1.py
- Errores y siguiente acción: **Débil**. El catch agrupa errores de contrato, RUN, hashes y EVAL bajo el mismo diagnóstico de independencia.
  Propuesta: Propagar STEP70_RUN_ID_DRIFT y STEP70_SEPARATE_EVALUATOR_NOT_PASS; permitir fallback solo para procedencia no acreditada con revisión material válida.
  Fuente: scripts/lf_step70_separate_call_receipt_v1.py

### C05 — EVAL Step70

- Tipos, nulos y defaults: **Contradictorio**. Exige string no vacío, pero la SPEC exige longitud mínima 4; se reprodujo EVAL PASS y schema FAIL para el mismo RAW.
  Propuesta: Validar source_refs con el schema congelado o len(ref)>=4; añadir regresión de equivalencia.
  Fuente: scripts/lf_step70_same_llm_eval_v1.py; profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json

### C06 — Juez contextual del auditor

- Errores y siguiente acción: **Débil**. Distingue la causa, pero no define un payload de error propio del juez ni el código y receptor de devolución.
  Propuesta: Definir judge_result {evaluation_valid,independence_status,promotion_authorized,blocking_codes,missing_evidence,next_action,source_refs} y ejemplos de retorno.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/context_spec_judge_v1.txt

### C07 — Selector de skills: contrato SQL

- Positivos, negativos y readback: **Débil**. La fuente describe el modo, pero no agota negativos de todas las emisiones y ramas con esta auditoría.
  Propuesta: Añadir negativos por rama y resolver hashes/recibos antes de acreditar un E2E; mantener separados selector y ejecución.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql

### C08 — Snapshot local de ejemplo


### C09 — Handoff candidato V1

- Salida y significado: **Débil**. Lista nombres de elementos, pero no tipa su contenido ni enlaza un schema concreto para construir un paquete ejecutable.
  Propuesta: Enlazar payload_schema=audit_report_v2.schema.json; exigir evidencia, pendientes tipados y next_action sin convertir el descriptor en despacho automático.
  Fuente: skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/contract_sources/to_quality_pack_v1.json

### C10 — Contrato de reporte V2


### C11 — Entrada del auditor V2


### C12 — Handoff candidato V2

- Positivos, negativos y readback: **Débil**. El contrato exige binding de bytes/CI, pero esta actualización no ejecuta el consumidor Quality con un handoff real.
  Propuesta: En una prueba gobernada futura, rechazar report_sha256 incorrecto y CI de otro HEAD; verificar recepción exacta por Quality sin aplicar efectos.
  Fuente: skills/auditoria-profunda-implementacion-lf/contracts/main_contract.md
- Ejemplos concretos: **Débil**. Hay schema y descriptor, pero no un payload real ejecutado por Quality en este lote.
  Propuesta: Guardar el payload con HEAD/CI finales, resultado de validación y recibo del consumidor al ejecutar la operación autorizada.
  Fuente: skills/auditoria-profunda-implementacion-lf/handoffs/to_quality_pack.handoff.json

### C13 — Juez contextual V2


## Barrido de PASS

Sitios inventariados: 45; emisores confirmados por lectura contextual: 11; negativos que rechazaron la entrada rota: 1.

Los negativos que ACEPTAN entrada rota se muestran como defecto, nunca como verificación verde. Los sitios no ejecutados conservan pendiente su negativo. Emisiones dinámicas no agotadas: la cobertura no es exhaustiva.

| Archivo:línea | Marcador | Clasificación | Evidencia exigida por contrato | Negativo | Dictamen contextual |
|---|---|---|---|---|---|
| scripts/lf_profile_native_resume.py:818 | PASS_REVIEWED_CURRENT_CONTEXT | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| scripts/lf_profile_native_resume.py:819 | PASS_INDEPENDENT_SEMANTIC | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| scripts/lf_profile_native_resume.py:913 | PASS_REVIEWED_CURRENT_CONTEXT | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:914 | PASS_INDEPENDENT_SEMANTIC | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | NOT_EXECUTED: INDEPENDENT_EVAL_CONTEXT sin aislamiento acreditado no debe emitir independencia; negativo no ejecutado aquí. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:919 | PASS | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:920 | DYNAMIC:verdict | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:921 | PASS | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:929 | DYNAMIC:verdict | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material. |
| scripts/lf_profile_native_resume.py:1009 | DYNAMIC:status | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian. |
| scripts/lf_profile_native_resume.py:1178 | DYNAMIC:outcome | EMITTER_CANDIDATE | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | NOT_EXECUTED: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | Outcome propagado desde consumidor: resolver valores y ramas; no se acredita revisión exhaustiva de emisiones dinámicas. |
| scripts/lf_profile_native_resume.py:1209 | DYNAMIC:outcome | EMITTER_CANDIDATE | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | NOT_EXECUTED: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | Outcome propagado desde consumidor: resolver valores y ramas; no se acredita revisión exhaustiva de emisiones dinámicas. |
| scripts/lf_profile_native_resume.py:1240 | DYNAMIC:status | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian. |
| scripts/lf_profile_native_resume.py:1302 | DYNAMIC:status | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian. |
| scripts/lf_profile_native_resume.py:1401 | DYNAMIC:outcome | EMITTER_CANDIDATE | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | NOT_EXECUTED: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | Outcome propagado desde consumidor: resolver valores y ramas; no se acredita revisión exhaustiva de emisiones dinámicas. |
| scripts/lf_profile_native_resume.py:1472 | DYNAMIC:status | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian. |
| scripts/lf_profile_native_resume.py:1511 | DYNAMIC:status | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian. |
| scripts/lf_step70_separate_call_receipt_v1.py:14 | PASS_INDEPENDENT_SEMANTIC | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| scripts/lf_step70_separate_call_receipt_v1.py:88 | DYNAMIC:verdict | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| scripts/lf_step70_separate_call_receipt_v1.py:127 | PASS_REVIEWED_CURRENT_CONTEXT | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_ACCEPTED_BROKEN_INPUT: Romper el campo aplicable debe producir código causal y ningún PASS del consumidor. | Reproducción actual: EVAL material inválido termina en PASS contextual. Falta de independencia por sí sola sí puede permitir pase contextual. |
| scripts/lf_step70_same_llm_eval_v1.py:56 | PASS | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente | EXECUTED_REJECTED_BROKEN_INPUT: Hash candidato incorrecto debe devolver EVAL FAIL; ejecutado. source_refs=['x'] aún acepta entrada rota, LF-DA-003. | PASS derivado de errors=[]; negativo de hash rechaza, pero hay obligación SPEC omitida en referencias. Un negativo no prueba todas las ramas. |
| supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts:631 | STEP_PASS_WITH_EVIDENCE | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente; RPC STEP_RECORDED y STEP_PASS_WITH_EVIDENCE; Un único paso PASS en getLedger; GitHub HEAD/sha y autoridad del hijo validados | NOT_EXECUTED: RPC rechazado, ledger vacío/duplicado o HEAD inválido debe bloquear sin añadir receipt PASS. | Emisión del hijo ACTUALIZACION_SKILL_LF, no ejecución IG; guardas leídas, negativo no ejecutado. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:21 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:22 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:23 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:24 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:43 | DEFAULT_TRUE | RISK_PATTERN_ONLY |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | COALESCE(...,true) actúa como guard fail-closed en este contexto; no marcar defecto sin seguir la negación y su consumidor. |
| supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql:69 | APPLIED | EMITTER | Contexto válido según SPEC/EVAL; RUN y hashes aplicables enlazados; No conceder efecto sin política vigente; request con status APPLIED; Readback regla VIGENTE y target enlazado; Política y score actuales | NOT_EXECUTED: Sin autoridad, score o readback VIGENTE, no devolver APPLIED; requiere sandbox aislado de escritura, no ejecutado. | APPLIED tiene comprobación del request y regla vigente. No ejecutar writer para probar el auditor. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:21 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:208 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:412 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:456 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:473 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:486 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:492 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:761 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:771 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:795 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:858 | ig_findings_reported=true | EMITTER | Reporte ligado al RUN y candidato; Finding/resultado IG identificado por tipo; No confundir reporte de selección con invocación IG | NOT_EXECUTED: Con finding de selección y sin invocación no afirmar IG ejecutado; negativo del writer no ejecutado. | Asignación ig_findings_reported=true; SELECT confirma 9/9 reportados sin invocación. Semántica de nombre ambigua; no prueba 9 falsos PASS. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:879 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1039 | PASS_INDEPENDENT_SEMANTIC | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1066 | PASS_INDEPENDENT_SEMANTIC | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1070 | PASS_INDEPENDENT_SEMANTIC | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1077 | PASS_REVIEWED_CURRENT_CONTEXT | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1080 | DEFAULT_TRUE | RISK_PATTERN_ONLY |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | COALESCE(...,true) actúa como guard fail-closed en este contexto; no marcar defecto sin seguir la negación y su consumidor. |
| skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql:1170 | STEP_PASS_WITH_EVIDENCE | NOT_EMITTER |  | NOT_EXECUTED: Resolve the applicable input/contract before testing | Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra. |

## Hallazgos y procedencia

| ID | Estado | Tipo de evidencia | Confianza y motivo | Defecto |
|---|---|---|---|---|
| LF-DA-001 | CONFIRMED | MEASURED_THIS_AUDIT | HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción. | La llamada omite el execution_id esperado; un recibo sintético de otro RUN pasa el EVAL local si sus hashes coinciden. |
| LF-DA-002 | CONFIRMED | MEASURED_THIS_AUDIT | HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción. | Un receipt cuyo decision_body tiene unsupported_claims falla EVAL; el normalizador borra el receipt y genera PASS contextual que acepta el validador local con checks externos favorables. |
| LF-DA-003 | CONFIRMED | MEASURED_THIS_AUDIT | HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción. | source_refs=['x'] incumple la SPEC pero el mismo RAW obtiene eval_status=PASS. |

### LF-DA-001

Ubicación: scripts/lf_step70_separate_call_receipt_v1.py:118 · normalize_when_unverified · commit bd599aff0a1353e5850fef1b9675c13b7344b317

Código encontrado:

```
        r=assess_separate_call_receipt(review)
```

Esperado: El RUN del caller debe llegar al validador del recibo y compararse con su execution_id.
Contrato: profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json; profiles/quality_pack/contracts/step70_clean_eval_context_v1.md; scripts/lf_step70_separate_call_receipt_v1.py

Defecto: La llamada omite el execution_id esperado; un recibo sintético de otro RUN pasa el EVAL local si sus hashes coinciden.

Causa raíz: El padre conoce execution_id pero normalize_when_unverified no lo recibe. assess tiene guard opcional; evaluate recibe el mismo r.execution_id como dato y esperado.

Impacto: Binding de procedencia local; Diagnóstico del Step70 antes de SQL; No demuestra que SQL acepte promoción cruzada

Corrección propuesta (sin aplicar):

```
# Propuesta coordinada, no aplicada
# lf_profile_native_resume.py, complete_native_profile_semantic_and_report:
semantic_review, assessment = normalize_when_unverified(semantic_review, execution_id=execution_id)
# lf_step70_separate_call_receipt_v1.py:
def normalize_when_unverified(review, *, execution_id):
    r = assess_separate_call_receipt(review, execution_id=execution_id)
# Propagar el mismo argumento a validate_independent_semantic_review y sus callers;
# rechazar STEP70_RUN_ID_DRIFT antes de cualquier degradación de procedencia.
```

Prueba positiva: Recibo fixture válido del RUN esperado devuelve evaluator_status=PASS, con independencia no acreditada. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/run_binding

Prueba negativa: Recibo fixture de otro RUN: llamada sin binding acepta EVAL; con execution_id explícito rechaza STEP70_RUN_ID_DRIFT. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/run_binding

Resultado observado: wrong_run_evaluator_status=PASS; explicit_binding_rejects=STEP70_RUN_ID_DRIFT
Comando: `python skills/auditoria-profunda-implementacion-lf/scripts/v2_negative_probes.py --output skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json`

Readback: assess_separate_call_receipt → evaluate → wrong_run_evaluator_status=PASS; explicit_binding_rejects=STEP70_RUN_ID_DRIFT; no DB/Edge promotion invoked

Estado: CONFIRMED · MEASURED_THIS_AUDIT · HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción.

### LF-DA-002

Ubicación: scripts/lf_step70_separate_call_receipt_v1.py:119 · normalize_when_unverified · commit bd599aff0a1353e5850fef1b9675c13b7344b317

Código encontrado:

```
    except ValueError as exc:
        r={"status":"JUDGE_INDEPENDENCE_NOT_PROVEN",
           "producer_independence_proven":False,
           "receipt_contract_error":str(exc),
           "content_continuation_allowed":True}
    if r["status"]=="JUDGE_INDEPENDENCE_NOT_PROVEN" or not r["producer_independence_proven"]:
        safe=dict(review)
```

Esperado: Separar procedencia no acreditada de EVAL material fallido; conservar contradicciones de dictamen y no emitir PASS por fallback.
Contrato: profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json; profiles/quality_pack/contracts/step70_clean_eval_context_v1.md; scripts/lf_step70_separate_call_receipt_v1.py

Defecto: Un receipt cuyo decision_body tiene unsupported_claims falla EVAL; el normalizador borra el receipt y genera PASS contextual que acepta el validador local con checks externos favorables.

Causa raíz: El catch de todo ValueError convierte errores materiales en JUDGE_INDEPENDENCE_NOT_PROVEN; luego sobrescribe verdict y elimina la evidencia discordante.

Impacto: Consistencia de dictamen anidado/externo; Validación local permite continuar tras material FAIL; Aceptación final por SQL/Edge no probada

Corrección propuesta (sin aplicar):

```
# Propuesta, no aplicada
except ValueError as exc:
    return review, {"status": "REVIEW_INVALID",
        "receipt_contract_error": str(exc),
        "producer_independence_proven": False,
        "content_continuation_allowed": False}
# En complete_native_profile_semantic_and_report, antes de persistir/normalizar:
if assessment.get("content_continuation_allowed") is not True:
    print(json.dumps({"phase": "SEMANTIC_REVIEW",
        "code": assessment.get("receipt_contract_error")}))
    return 1
# Mantener el caso de receipt ausente como procedencia no probada;
# para revaluar contenido producir evaluación explícita, sin borrar contradicción.
```

Prueba positiva: Receipt materialmente válido mantiene baseline RECEIPT_FORMAT_VALID_PROVENANCE_UNATTESTED, sin afirmar independencia. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/eval_masking

Prueba negativa: unsupported_claims no vacío provoca STEP70_SEPARATE_EVALUATOR_NOT_PASS; comprobar si el fallback conserva el rechazo. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/eval_masking

Resultado observado: STEP70_SEPARATE_EVALUATOR_NOT_PASS → PASS_REVIEWED_CURRENT_CONTEXT; receipt_retained=false; downstream.accepted=true
Comando: `python skills/auditoria-profunda-implementacion-lf/scripts/v2_negative_probes.py --output skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json`

Readback: normalize_when_unverified → validate_independent_semantic_review → STEP70_SEPARATE_EVALUATOR_NOT_PASS → PASS_REVIEWED_CURRENT_CONTEXT; receipt_retained=false; downstream.accepted=true; no DB/Edge promotion invoked

Estado: CONFIRMED · MEASURED_THIS_AUDIT · HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción.

### LF-DA-003

Ubicación: scripts/lf_step70_same_llm_eval_v1.py:52 · evaluate · commit bd599aff0a1353e5850fef1b9675c13b7344b317

Código encontrado:

```
    chk(isinstance(refs,list) and len(refs)>0 and all(isinstance(r,str) and r for r in refs),
        "REVIEW_SOURCE_REFS_MISSING")
```

Esperado: EVAL debe respetar source_refs.items.minLength=4 del schema LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1.
Contrato: profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json; profiles/quality_pack/contracts/step70_clean_eval_context_v1.md; scripts/lf_step70_separate_call_receipt_v1.py

Defecto: source_refs=['x'] incumple la SPEC pero el mismo RAW obtiene eval_status=PASS.

Causa raíz: EVAL comprueba string no vacío y omite el mínimo del schema; no ejecuta ese schema completo.

Impacto: Paridad SPEC/EVAL de referencias; Calidad del recibo evaluado; No acredita resolución real de refs ni autorización

Corrección propuesta (sin aplicar):

```
chk(isinstance(refs, list) and len(refs) > 0
    and all(isinstance(ref, str) and len(ref) >= 4 for ref in refs),
    "REVIEW_SOURCE_REFS_SCHEMA_INVALID")
# Añadir regresión de paridad con el schema congelado;
# validar referencias materialmente en la capa contextual, no solo por longitud.
```

Prueba positiva: RAW con source_refs fixture válidos: schema sin errores y EVAL PASS. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/schema_eval

Prueba negativa: Mismo RAW con ['x']: schema rechaza 'x is too short'; EVAL actual devuelve PASS. · skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json#/step70/schema_eval

Resultado observado: evaluator_status=PASS y schema_errors=['x is too short']; baseline válida pasa ambos
Comando: `python skills/auditoria-profunda-implementacion-lf/scripts/v2_negative_probes.py --output skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json`

Readback: evaluate → assess_separate_call_receipt (no schema enforcement) → evaluator_status=PASS y schema_errors=['x is too short']; baseline válida pasa ambos; no DB/Edge promotion invoked

Estado: CONFIRMED · MEASURED_THIS_AUDIT · HIGH: Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción.

## Catálogo de evidencia

| ID | Tipo / origen | Captura / afirmación |
|---|---|---|
| E-SOURCE | CODE_READ_ONLY / SOURCE_FILE | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/live_functions.sql; Definiciones SQL leídas, incluidas escritoras NO invocadas; no es una migración. |
| E-PRIOR | MEASURED_PREVIOUSLY / PRIOR_REPORT | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/previous_report.json#/text; Informe anterior preservado; sus pruebas no se convierten en mediciones actuales. |
| E-PARENT | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/parent_rows; SELECT de padre existente COMPLETED; esta auditoría no lo ejecutó. |
| E-BINDINGS | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/bindings_readback.json#/rows; Proyección actual de enlaces guardados; no rehash de los artefactos originales. |
| E-PROBES | MEASURED_THIS_AUDIT / LOCAL_HELPER | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/negative_probes.json; Reproductores actuales sobre helpers LF con entradas sintéticas y red prohibida; no E2E. |
| E-COHORT | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/cohort; Últimas 20 corridas de cuatro perfiles: presencia de referencias y señal IG, no tasa semántica de falsos PASS. |
| E-SCAN | CODE_READ_ONLY / SOURCE_FILE | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/pass_scan.json; Barrido estático acotado a seis archivos; la clasificación contextual se revisó nativamente. |
| E-CONTRACTS | CODE_READ_ONLY / SOURCE_FILE | skills/auditoria-profunda-implementacion-lf/scripts/contract_reviews_v2.py; Revisión nativa por tipo, literal y consumidor; misma autoría/contexto, sin autoridad de efectos. |
| E-EKB | CODE_READ_ONLY / SOURCE_FILE | skills/auditoria-profunda-implementacion-lf/references/ekb_current_snapshot.json; Snapshot EKB histórico de V1 leído; V2 no vuelve a certificar vigencia por SQL. |
| E-METADATA | MEASURED_THIS_AUDIT / LIVE_METADATA | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/runtime_metadata.json#/rows/0; Cierre: PG17.6, supabase_read_only_user. Cambiaron hashes de bridge_prepare y record_report desde la captura inicial; no se reauditaron esas nuevas definiciones. |
| E-CURRENTNESS | CODE_READ_ONLY / SOURCE_FILE | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/base_currentness.json; Comparación Git: los tres helpers Step70 no cambiaron entre fuente auditada y base de entrega; SQL dinámico nuevo sin reauditar. |
| E-STEP-0 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/0; SELECT actual: Existe el padre y un recibo de init_execution enlazado por execution_id. Puntero guardado: supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-808379962BF5ACA150004167 |
| E-STEP-10 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/1; SELECT actual: Existe referencia de autorización del Router y el paso está persistido como PASS. Puntero guardado: router-authorization://7ffc3d59d8ea67dec29a68a85e0aa89bee2d15ef543cec9fc527ae017c0e653d |
| E-STEP-20 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/2; SELECT actual: El paso identifica PERFIL-PRODUCT-DIRECTOR-LF y la fuente lf_activos. Puntero guardado: supabase://public.lf_activos/PERFIL-PRODUCT-DIRECTOR-LF |
| E-STEP-30 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/3; SELECT actual: Se guardaron revisión bd599aff y digest de la fuente del perfil. Puntero guardado: github://cristhianlujan/claude-persona-lf-patch@bd599aff0a1353e5850fef1b9675c13b7344b317/profiles/product_director_lf/SKILL.md |
| E-STEP-40 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/4; SELECT actual: Se guardaron scope y finding de selección; receipts=[]: no prueba ejecución IG. Puntero guardado: supabase://public.lf_profile_execution_input_validate_v1/EXEC-PROFILE-GATE2-808379962BF5ACA150004167 |
| E-STEP-45 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/5; SELECT actual: Se guardó context_receipt_ref y digest de contexto. Puntero guardado: supabase://public.lf_eventos/21901#context_receipt |
| E-STEP-47 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/6; SELECT actual: La política guardada dice research_baseline NOT_REQUIRED / NOT_APPLICABLE. Puntero guardado: supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-808379962BF5ACA150004167/research_baseline_freeze |
| E-STEP-50 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/7; SELECT actual: Se guardó artefacto del perfil con digest de candidato y digest del contexto 45. Puntero guardado: actions://cristhianlujan/claude-persona-lf-patch/runs/43783735524/artifact/profile-native-output-43783735524/profile-native-output.json |
| E-STEP-60 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/8; SELECT actual: Se guardó validación determinista PASS y el mismo digest externo de 50. Puntero guardado: actions://cristhianlujan/claude-persona-lf-patch/runs/43783735524/artifact/profile-native-output-43783735524/profile-native-validation.json |
| E-STEP-70 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/9; SELECT actual: Se guardó PASS_REVIEWED_CURRENT_CONTEXT con candidato/alcance enlazados; no prueba independencia. Puntero guardado: actions://cristhianlujan/claude-persona-lf-patch/runs/43783869639/artifact/profile-native-output-43783869639/profile-semantic-judge.json |
| E-STEP-80 | MEASURED_THIS_AUDIT / LIVE_EXISTING_RUN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/step_rows/10; SELECT actual: Se guardó reporte con no_write_performed=true e ig_findings_reported=true; no es recibo IG. Puntero guardado: supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-808379962BF5ACA150004167/report_output |
| E-Q_STEPS | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/query_measurements/0; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_PARENT | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/query_measurements/1; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_IG_INVOCATIONS | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/query_measurements/2; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_RECENT_COHORT | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/query_measurements/3; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_SKILL_REGISTRY | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/source_capture.json#/query_measurements/4; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_RUNTIME_PARENT | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/runtime_query_plans.json#/queries/0; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_RUNTIME_SCOPE | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/runtime_query_plans.json#/queries/1; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |
| E-Q_RUNTIME_SELECTION | MEASURED_THIS_AUDIT / LIVE_QUERY_PLAN | skills/auditoria-profunda-implementacion-lf/reports/v2_inputs/runtime_query_plans.json#/queries/2; EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única. |

## Checklist EKB

Snapshot V1 preservado; estado actual EKB no reconsultado. No sustituye política vigente.

| Código | Resultado de esta auditoría | Procedencia | Evidencia |
|---|---|---|---|
| IG-M1013-REPOSITORY-REPAIR-POLICY-054 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| IG-M107-G-CURATOR-SQL-FASTPATH-041 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-IG-SCOPE-HASH-MISMATCH-20261114-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-OWNER-SCORE-CURRENT-CONTEXT-PROMOTION-20261115-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PE-STEP70-CHAT-VERDICT-NOT-PERSISTED-20261031-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PE-STEP70-MODEL-RECEIPT-NOT-ATTESTED-20261031-002 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PE-STEP70-RUN-CLOSED-EKB-ENFORCEMENT-OPEN-20261031-005 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PE-STEP70-WRITER-DIAGNOSIS-BEFORE-INSERT-20261031-003 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PE10A-ASSERTION-CONTRACT-PASSWHEN-NULL-READY-20261027-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-PROMO-INDEPENDENT-JUDGE-OWNER-20261114-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| LF-QUALITY-CURRENT-CONTEXT-TECHNICAL-PASS-NOT-APPROVAL-20261115-001 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| PE10_C6_DECLARED_PLANNER_TEST_COUNT_DRIFT_V1 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |
| PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1 | NOT_VERIFIED | CODE_READ_ONLY | E-EKB |

## Límites y cierre

- Revisiones C01/C02/C06/C09 describen snapshots V1 preservados; no se presentan como defecto pendiente ya reparado en V2.
- Formatos por tipo y análisis semántico nativo; el script valida consistencia y no decide calidad por palabras.
- Nota de contrato aceptable solo acredita el cometido revisado; no independencia ni permiso de promoción.
- EKB de V1 se conserva histórico; este lote no vuelve a certificar su vigencia completa.
- Fuente auditada 274b3c5; base de entrega a9b1248. Helpers Step70 sin cambios. SELECT final detectó cambios en bridge_prepare/record_report: nuevas definiciones NO REAUDITADAS, ver base_currentness/runtime_metadata.
- HTML: estructura/colores/escape verificados estáticamente. Chromium bloqueó socket(); visualización y filtro en navegador NOT_VERIFIED, ver html_readback_v2.json.
- Sin producción, migraciones, promoción ni reparaciones funcionales LF. Reporte nuevo no habilita runtime.
- La cobertura usa obligaciones conocidas del lote (9/14); no porcentaje de todo el repositorio.
- Cobertura pendiente de consumidores/SQL dinámicos aún no inventariados.

**FLUJO NO ACREDITADO.** Cobertura del lote: 64.29 %. No se transforma un lote terminado en aprobación E2E.
