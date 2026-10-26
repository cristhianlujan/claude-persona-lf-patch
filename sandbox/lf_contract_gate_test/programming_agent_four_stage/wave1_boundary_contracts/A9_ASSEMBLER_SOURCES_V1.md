# A9_ASSEMBLER_SOURCES_V1

26-oct-2026 · Diseño v3, no ejecución. Base main ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267 y #3135 1bb2ca277a333d3b80a72ac533e4e9bac88c2919.

## A9 pertenece al agente de Programación

A1–A9 son la etapa de Análisis del propio agente, frente de Paulo. A9 es su ensamblador final, no un productor organizativo externo. La frontera A9→PG-01 es interna al agente. El juez semántico gobernado es independiente del productor y la operación que registra su resultado acredita la decisión; no se delega la construcción de A9 a Cristhian.

Fuentes de este marco: ANALYSIS_PROCEDURE_V1.md y analysis_procedure_v1.json en esta carpeta; profiles/programming_analysis_lf/SKILL.md, contracts/analysis_source_binding.json y contracts/runtime_binding.json. El nombre humano ANALYSIS_PROCEDURE_V1 corresponde al flujo machine-readable PROGRAMMING_AGENT_ANALYSIS_PROCEDURE_V1. El binding del perfil sigue CANDIDATE_NOT_RELEASED, current_release_verified=false y pre_inference_gate=NOT_WIRED_FAIL_CLOSED. Eso es estado de la fuente, no calificación del servicio vivo.

runtime_output.schema.json solo contiene el candidato del modelo. No se le piden hashes, autoridad o currentness inventados. Los contratos completos de las fases y los lectores autorizados alimentan al ensamblador fuera del modelo. Existencia de contrato/función no demuestra que el adapter A9 esté conectado o cualificado.

Convenciones: B = sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/; M = sandbox/lf_contract_gate_test/material_currentness/. Los paths relativos de contratos en las tablas se resuelven contra B.

## Los 12 campos faltantes o parciales

| Campo | Fuente existente exacta y nivel | Se prepara en | Entrega a A9 y límite actual |
|---|---|---|---|
| authority_bindings | analysis_targeted_evidence_contract_v1.json: authority_binding_refs y target_resolution; analysis_implementability_contract_v1.json: canonical_implementation_bindings y binding_contract. Para Producto: public.lf_router_product_context_v1(text,jsonb) → lf_ops.fn_screen_contract_v1(text,text,text), lf_ops.pantalla_elementos y lf_design.component_tokens | A3 resuelve autoridades/valores; A6 tipa bindings y obligaciones | Artefactos A3/A6 íntegros, refs exactas, valores resueltos y currentness. BRECHA: adapter que materializa esos bindings en authority_bindings del snapshot; no inferirlos de evidence_refs |
| applicable_rules | lf_ops.reglas_pantallas + lf_ops.reglas; lf_ops.fn_screen_contract_v1(text,text,text) incluye rules y políticas; public.lf_router_product_context_v1(text,jsonb) da contexto canónico. Políticas de operación: public.v_lf_operation_policy_snapshot | A3 obtiene la autoridad; A6 determina aplicabilidad al scope | Conservar código/estado/config/ref y decisión de aplicabilidad. BRECHA: selección admitida y adapter; ni 71 reglas directas ni 283 efectivas significan automáticamente 283 reglas vigentes aplicables. CANDIDATO no se promueve a VIGENTE |
| applicable_invariants | Reglas y políticas canónicas anteriores + obligaciones explícitas de analysis_implementability_contract_v1.json; análisis A4/A6 y preserve. EKB: programacion.fn_engineering_ekb_lookup_v1(text,text[],integer), autoridad public.lf_error_knowledge, solo precedentes/preventivos | A3 consulta; A4 identifica impacto; A6 deriva invariantes con autoridad | Cada invariante debe referir una obligación canónica y scope. BRECHA: no se identificó en esta inspección un emisor/registro que entregue directamente applicable_invariants admitidos. EKB no autoriza por sí mismo una decisión de Producto; no fabricar [] ni una tabla universal de invariantes |
| currentness_refs | M/CURRENTNESS_AUTHORITY_v1.manifest.json, M/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json; M/lf_currentness_authority_v1.py:evaluate_authority(binding,repo); M/lf_source_attestation_v1.py:create_attestation / verify_attestation. Referencias vigentes de capacidades en public.lf_capability_current/version_registry | A3 obtiene evidencia y currentness; A5–A8 preservan refs de sus artefactos | Recibos/materiales/closure y proveedor gobernado deben llegar como entradas independientes del modelo. BRECHA: adapter/proveedor admitido para este handoff. programacion.fn_engineering_source_pack_currentness_from_context_v1(jsonb,text) detecta ciertos conflictos de source_pack; no sustituye el cierre material completo de CURRENTNESS_AUTHORITY |
| snapshot_schema_digest_sha256 | B/programming_entry_contract_v1.json, SHA256 de bytes exactos d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8; B/programming_pg01_exact_artifact_reader_v1.py:ExactArtifactReader y LocalGitBackend/ConnectedReadbackBackend | A3 obtiene pin admitido; A9 calcula y coteja fuera del modelo | V1 no cambia. BRECHA para futuro V2: contrato, pin/digest y cutover acordados; no heredar d2e347ef… a bytes V2 distintos |
| authority_fingerprint_sha256 | Materiales/bindings exactos de A3/A6; modelo material y huellas en M/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json; attestation de M/lf_source_attestation_v1.py | A3 reúne materiales; A6 fija bindings; A9 compone huella | BRECHA: la selección/canonicalización final de la huella específica PG-01 no queda implementada por tener un motor de currentness. No equiparar automáticamente hash del paquete/modelo o huella Git a este campo |
| source_snapshot_sha256 | Target/fuente exactos de A3, refs/materiales de A5–A8 y ExactArtifactReader de B/programming_pg01_exact_artifact_reader_v1.py | A3 fija baseline; A9 congela la representación fuente acordada | BRECHA: regla de composición/normalización y proveedor de fuente admitido. No confundir con context_sha256, digest de contrato ni package digest. fn_screen_contract_v1 incorpora metadata.generated_at=now(); hay que acordar congelación/proyección material antes de hashear, no quitar timestamps silenciosamente |
| preserve | A3 AS-IS/delta; A4 shared_change_impact_contract_v1.json, inventory.fn_impact_analysis_v1(text,integer,numeric), inventory.fn_dependencies_v1(text,text,integer); A6 obligaciones MUST_PRESERVE_EXACT/SEMANTICS y A7 REUSE_AS_IS | A3/A4 identifican consumidores; A6 formula obligación; A7 verifica frente | Entregar objeto/ref/semántica/razón/alcance/currentness completos. BRECHA: adapter de preserve y evidencia del caso; REUSE_AS_IS por sí solo no construye preserve |
| implementability_schema | B/analysis_implementability_contract_v1.json, IMPLEMENTABILITY_SCHEMA_V1 completo: requirements, canonical_implementation_bindings, permisos/efectos/errores/estados, refs y fingerprint | A6, tomando A3–A5 | A9 conserva el artefacto completo, no una reconstrucción desde las cinco propiedades de requirements del modelo. BRECHA: producción tipada/admitida y transporte del artefacto fuera del modelo |
| decision_context | B/analysis_decision_context_adr_contract_v1.json; transversal.decision_log; programacion.fn_engineering_current_adr_assert_v1(text); DECISION_CONTEXT_ASOF record/resolve existentes | A5, consumido por A6–A8 | Entregar decisión, opciones/razón, autoridad, resolución/ADR, refs y persistencia. BRECHA: decisión específica del cambio si falta, y adapter de resolución admitida. Lista decisions_pending no se convierte en STABLE |
| unresolved_material_items | A3 unresolved_material_gaps; A4 unresolved_material_impacts; A5 decisiones/preguntas abiertas; A6 unresolved_material_items; A7 frentes bloqueados/señales no mapeadas; A8 preguntas que cambian decisión. Contracts A3–A8 en B | A3–A8, consolidado A9 | Unión trazable por identidad y scope, conservar severidad/causa/autoridad y retorno dirigido. BRECHA: reglas de identidad/dedupe/propagación y transporte íntegro, no borrar material al resumir |
| target | analysis_request_context_v1.schema.json: target_hints; analysis_targeted_evidence_contract_v1.json: target_resolution y evidencia de implementación; public.lf_router_product_context_v1(text,jsonb) para identidad Producto; B/programming_pg01_exact_artifact_reader_v1.py:Identity/ExactArtifactReader para fuente Git exacta | A1 identifica; A3 resuelve y fija baseline; A9 conserva | Producto aporta sujeto/versión/elemento, no repo_full_name/base_head_sha automáticamente. BRECHA: binding admitido desde ese sujeto a repo/revisión/fuente de código; no inferirlo de B2B-AUTH-001 ni del nombre del perfil |

Las fuentes canónicas y sus lectores existen o están definidas en fuente como se indica; el ensamblador que las consume todavía no está implementado en esta tarea. Las otras 11 entradas obligatorias del snapshot tampoco quedan automáticamente completas: objetivo/identidad, matriz bidireccional, procedencia READY, cobertura A7 y STOP A8 necesitan validar el contrato entero, no solo estos 12 campos.

### Entrega entre pasos, fuera del modelo

A3 produce un paquete de evidencia con refs exactas y readback, A4 añade impacto/consumidores, A5 decisiones, A6 obligaciones/bindings, A7 cobertura y A8 decisión STOP/retornos. A9 recibe esas salidas completas, sus versiones/digests y el candidato del modelo como una entrada más. Debe bloquear si falta un artefacto material o no puede demostrar su identidad. No se crea otro runtime, motor de impacto/currentness o almacén de snapshots.

## Caso Login B2B «Acceder»: recorrido de diseño

No se ejecutaron A1–A9, perfiles ni modelos con este caso. Las filas siguientes indican resultados que deberían producir, no artefactos ya generados.

Partida RO comprobada: EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282 está COMPLETED, 11/11 pasos con estado de evidencia satisfactorio registrado, task_intent=READ_PRODUCT_DEFINITION. Su decisión B2B-AUTH-001-CANONICAL-RULE-READ-001 describe extraer reglas: 71 directas y 283 efectivas, preservando estados. Esos números pertenecen a la cápsula histórica de esa ejecución. No es una definición de modificación, una corrida A1–A9 ni un recibo de admisión PG-01.

Lectura actual adicional: lf_ops.pantallas y lf_ops.pantalla_elementos contienen B2B-AUTH-001 v0.5, pantalla CANDIDATO, B2B_AUTH001_SUBMIT con label_visible=Acceder y status=CANDIDATO. Esto prueba AS-IS del catálogo, no que exista una definición de delta admitida, release o implementación runtime equivalente. No concluir «falta toda definición» ni «hay que cambiar código» solo por el ticket.

| Paso | Qué produce para el caso | Fuentes que lee | Qué falta / condición de salida |
|---|---|---|---|
| A1 | REQUEST_CONTEXT_V1 con intención literal, target B2B-AUTH-001/submit y exclusiones de autenticación/validaciones/otras partes si están en el pedido autorizado | analysis_request_context_v1.schema.json; pedido y definición canónica de Producto por referencia exacta | Necesita definición del cambio desde la entrada para diferenciar delta de AS-IS/no-op. La lectura de reglas no la sustituye |
| A2 | ANALYSIS_CHANGE_CLASSIFICATION_V1: granularidad del elemento y profundidad derivada de señales materiales | analysis_change_classification_contract_v1.json; A1 y riesgos del contrato | No fijar L1 por ser texto ni confundir estado documental con implementación; requiere delta/alcance claros |
| A3 | TARGETED_EVIDENCE_SET_V1: label AS-IS, reglas/estados, target/revisión y evidencia de implementación separada | public.lf_router_product_context_v1(text,jsonb), lf_ops.fn_screen_contract_v1(B2B_APP_SHELL,B2B_AUTENTICACION,B2B-AUTH-001), lf_ops.pantalla_elementos; EKB lookup; ExactArtifactReader para código si hay pin | Aquí se verifica materialmente la definición/versionado y su currentness. Falta en la evidencia de esta tarea una definición de delta admitida y pin del código runtime; no inferir implementación EXISTING solo por pantalla existente |
| A4 | SHARED_CHANGE_IMPACT_ANALYSIS: consumidores del label, traducciones/contratos/estados accesibles afectados o brechas explícitas | shared_change_impact_contract_v1.json; inventory.fn_impact_analysis_v1 / fn_dependencies_v1 y A3 | Scope de impacto real pendiente de delta y referencias; no crear obligaciones de otros scopes por nombre del dominio |
| A5 | ANALYSIS_DECISION_CONTEXT_V1: decidir con autoridad si hay delta real o pedido ya satisfecho; preservar decisiones/ADR cuando apliquen | analysis_decision_context_adr_contract_v1.json; definición de Producto, transversal.decision_log y fn_engineering_current_adr_assert_v1 | No convertir «Acceder ya figura» en decisión de negocio autoaprobada; falta confirmación de definición/alcance si hay contradicción |
| A6 | IMPLEMENTABILITY_SCHEMA_V1 del QUÉ admitido y bindings: label exacto, preservación de autenticación/validaciones y consumidores dentro del scope | analysis_implementability_contract_v1.json, A3–A5, reglas canónicas/valores vigentes | Falta assembler/adapter A6 completo y permiso de fuente/alcance; no endpoints, framework ni algoritmo PG-03 |
| A7 | MATERIAL_FRONT_COVERAGE_V1 y relaciones completas con scopes | analysis_material_front_coverage_contract_v1.json; impacto, obligaciones, decisiones y evidencia del caso | Frentes aplicables se derivan con evidencia; desconocidos quedan bloqueados. No declarar todos cerrados por los 11 pasos de Product Director |
| A8 | ANALYSIS_STOP_RULE_V1: STOP o retorno dirigido a fuente material pendiente | analysis_stop_rule_contract_v1.json; A3, A5, A7 | STOP no equivale a READY. No repetir búsquedas para resolver una definición que corresponde a Producto |
| A9 | Package y snapshot completos, matriz/scope/readiness propuestos, refs/huellas; decisión del juez gobernado registrada por operación | Todos los contratos A1–A8, programming_entry_contract_v1.json y analysis_programming_handoff_parity_contract_v1.json; fuentes de la tabla anterior | Faltan ensamblador y juez A9 calificados, perfil liberado, envelope V2 acordado y escritura/readback autorizados. No declarar ACCEPT operativo ni ejecutar código |

### Si no existe definición del cambio admitida

El precheck de Producto y A1 deben exigirla como entrada; A3 verifica su identidad y currentness. Ausencia/contradicción material devuelve RETURN_TO_PRODUCTO_NO_CODE con target, referencia faltante y causa, sin derivar tareas de programación ni fabricar READY. La SQL actual lf_router_route_v1 declara PROGRAMACION_PRECHECK_DEFINICION y continuación condicional; este retorno es comportamiento requerido del diseño, no un nuevo dispatch implementado aquí.

Si Producto confirma que el pedido ya está satisfecho en su autoridad, documentar la resolución/no-op por la vía gobernada correspondiente; no forzar una implementación. La lectura canónica de reglas y el valor Acceder sirven de evidencia AS-IS, no de sustituto de la definición acordada.

## Juez independiente gobernado de A9

A9 ensambla; el juez evalúa por separado las obligaciones semánticas y materiales, y una operación gobernada registra su resultado. La independencia exige fuente/identidad del evaluador, scope y expectativas independientes, sin confiar en self_verdict o booleanos del ensamblador.

Debe evaluar:
- Correspondencia pedido/definición/target/revisión y autoridad del QUÉ.
- Preservación completa A3–A8, requirements, decisiones y bindings; paridad y proyección sin pérdida.
- Frentes materiales completos, matriz bidireccional, evidencia y razones de REQUIRED/REUSE_AS_IS/NOT_APPLICABLE.
- READY por scope: dependencias cerradas, ningún frente BLOCKS ni decisión material abierta; PARTIAL_READY únicamente para scopes independientes.
- Currentness material/huellas/versiones y autenticidad de refs; STOP no implica READY.
- Ausencia de estrategia técnica atribuida a Análisis, ejecución o promoción implícita.
- Retornos dirigidos, blockers y trazabilidad de la decisión hasta la entrada exacta.

Evidencia propuesta: identidad y versión del juez/política, operación/ejecución, package digest, context_id/context_sha256, target/contrato/digests, scopes evaluados y admitidos/rechazados, findings/códigos y refs de cobertura/decisiones/currentness. Son requisitos del resultado futuro, no campos ya emitidos por runtime_output.

### Evaluación del juez de Cristhian, commit 2ccfe57

Se leyó el código en main: supabase/migrations/20261024210331_lf_profile_canonical_read_semantic_close_v1.sql, public.lf_profile_execution_canonical_read_judge_v1(text). El commit 2ccfe57fcd7bb90a7836105e2cd6037caddf30d8 lo introdujo con versión de archivo 20261024220000; main tiene dos correcciones posteriores: admite ejecución IN_PROGRESS/COMPLETED y usa tuplas direct_rules de tres strings en vez de objetos. La evaluación se basa en main, no se extrapola el commit original sin esos cambios.

| Aspecto | Lo que hace en main | Reutilización para A9 |
|---|---|---|
| Ámbito | EJECUCION_PERFIL_LF, PERFIL-PRODUCT-DIRECTOR-LF, canal PRODUCTO/LF, READ_PRODUCT_DEFINITION y NOT_REQUIRED_CANONICAL_READ; GPT_NATIVE/OPENAI_CHATGPT_NATIVE, no_write/no_promotion | No aplica sin cambios a programming_analysis_lf o a definición/modificación |
| Evidencia | Relee input_validate, context_admission, execute_profile y output_validate; recalcula digest del output y comprueba formato del digest de scope, refs y conteos de reglas, afirmaciones derivadas, ausencia de blockers/assumptions | Reutilizable el patrón de readback y binding; A9 necesita artefactos A5–A8, scopes, dependencias, currentness y paridad que este juez no evalúa |
| Independencia | Determinista, model_call_count=0; el servidor recomputa el resultado y lf_profile_execution_trust_validation_v2 exige igualdad exacta del JSON en ese modo | No basta copiar producer_independence_proven=true, que el propio resultado emite; independencia de A9 requiere contrato y ruta de confianza propios |
| Registro | El script canario registra semantic_judge/report_output con public.lf_record_profile_execution_step_v1 y adjunta recibo terminal | Patrón aprovechable; adaptar la operación existente para A9 requiere decisión/contrato y calificación, no llamar ahora al registrador |
| Límite | Consulta canónica de reglas, validaciones de formato/refs/conteos y texto de claims; no juez general de suficiencia de análisis | No cerrar A9 reutilizándolo tal cual. Un juez A9 específico debe cubrir semántica del cambio, omisiones, decisiones y READY por scope |

No se ejecutó el juez ni los registradores; su ACL en fuente no concede EXECUTE a supabase_read_only_user. Para trabajo no reducible a comprobaciones deterministas, el diseño requiere evaluación semántica gobernada adicional y su evidencia; no se rebaja esa exigencia a conteos o a un modelo autoevaluado.

### Cómo alimenta el envelope

Secuencia propuesta, sin ejecución:
1. A9 ensambla y congela el payload completo fuera del modelo; validación estructural previa.
2. Operación escritora autorizada registra el snapshot en DECISION_CONTEXT_ASOF y hace readback exacto.
3. Juez gobernado evalúa ese snapshot exacto y el paquete/definición; la operación que registra su resultado lo vincula a context_id/hash y scopes.
4. El envelope referencia el recibo as-of, el resultado registrado del juez y sus bindings de versión/currentness; no muta el snapshot histórico para añadir retrospectivamente el juicio.
5. PG-01 exige esa evidencia independiente antes de la futura admisión V2. Su recibo de siete campos se persiste por el escritor D7-A, no por el receptor; después la compuerta operacional puede verificar PERSISTED_PROGRAMMING_CONTEXT_RECEIPT antes de código.

La operación de registro para A9 no está calificada en este diseño. Se propone estudiar reutilizar EJECUCION_PERFIL_LF/semantic_judge/report_output; no se presume que sus contratos actuales ya admitan el nuevo flujo. Los writes se quedan en Router→operación gobernada→Train según autorización, no en llamadas directas del receptor.

## Funciones as-of vivas: cobertura real y límites

Se inspeccionaron por SELECT pg_get_functiondef; no se llamó a record_v1.

| Pieza viva | Qué cubre | Qué no cubre |
|---|---|---|
| public.fn_lf_decision_context_asof_record_v1(jsonb,text) | Capacidad DECISION_CONTEXT_ASOF vigente; payload base; referencias/versiones/hashes de CURRENTNESS_AUTHORITY, CAPABILITY_VERSION_COMPATIBILITY y TYPED_EVIDENCE_REGISTRY contra dependencias/current; SHA256 de UTF-8 p_context::text; insert en private.lf_decision_context_asof_v1; recibo LF_DECISION_CONTEXT_ASOF_RECEIPT_V1; replay mismo decision_ref/hash y conflicto DECISION_REF_REPLAY_CONFLICT | No ensambla los 23 campos; no juzga A9/READY ni verifica definición Producto. Actor no vacío es lo que comprueba en el cuerpo: no autentica por sí mismo la ejecución/permiso del escritor. Igualdad de versiones de capacidades no equivale a currentness material de todo el snapshot |
| private.fn_lf_decision_context_asof_payload_valid_v1(jsonb) | Discriminador LF_DECISION_CONTEXT_ASOF_INPUT_V1; decisión/consumer/subject/times; refs/digests de actor, policy y terms sin copias de autoridad; tres authority_refs obligatorias; typed_evidence, si se aporta, usa private.fn_lf_typed_evidence_payload_valid_v3 | No compara actor/política con su autoridad real ni verifica la semántica completa del arbitrary extensions.programming_context_snapshot. Validez formal no es admisión |
| public.fn_lf_decision_context_asof_resolve_v1(text,text,timestamptz) | Resuelve consumer/subject y contexto más reciente con decided_at≤as_of; devuelve payload, id/hash/ref/version/fechas y latest_reinterpreted=false | No recibe context_id/hash esperado ni es un lookup por clave exacta. Hay que cotejar contra el recibo independiente; no recalcula allí el digest ni revalida currentness/admisión actual |
| Tabla private.lf_decision_context_asof_v1 | UNIQUE decision_ref, UNIQUE context_sha256, PK context_id; trigger private.fn_lf_decision_context_asof_immutable_v1 bloquea UPDATE/DELETE | No contiene por sí sola el recibo PG-01 ni prueba de juez A9. El trigger deja pasar INSERT; la política del escritor no se deduce de append-only |

El ACL observado de record/resolve contiene EXECUTE para PUBLIC/anon/authenticated/service_role; el validador privado tiene ACL nulo (default). No se interpreta esa accesibilidad como autorización. El diseño de escritor/ACL debe impedir que un actor inventado o un caller HTTP se autoadmita; no se cambia ningún grant aquí.

Reutilizar la tabla as-of para el snapshot, los resolvers existentes y sus guardias exactas (incluida la corrección candidata de #3135). Las funciones programacion.fn_programming_context_snapshot_validate_v1/record_v1/resolve_v1 de la migración base de #3135 siguen siendo código candidato, no se declaran vivas por esta lectura.

El contrato genérico as-of ya ofrece persistencia/identidad/readback histórico; no sustituye el envelope de admisión A9, la validación específica del snapshot ni D7 para el recibo PG-01. Véase PG01_D7_OPTION_A_SPEC_V1.md. No se diseña otro almacén de snapshots.

Readback adicional de capacidades: CURRENTNESS_AUTHORITY 1.0.0, DECISION_CONTEXT_ASOF 1.0.0, CAPABILITY_VERSION_COMPATIBILITY 1.0.0 y TYPED_EVIDENCE_REGISTRY 3.0.0 tienen filas CURRENT/RELEASED. Esa existencia no califica el adapter A9 ni sustituye sus bindings. El catálogo no devuelve las tres funciones programacion.fn_programming_context_* candidatas citadas arriba.
