# PG01_C1_A9_MAPPING_DRAFT_V1

26-oct-2026. Borrador para reunión C1; PENDING_DECISION. No constituye acuerdo A9→PG-01 ni admisión. Sin implementación del envelope, cambios de contrato, D7 o runtime.

## Fuentes exactas y límite de autoridad

Main leído: ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267.
Productor: profiles/programming_analysis_lf/schemas/runtime_output.schema.json, schema_version ANALYSIS_IMPLEMENTATION_PACKAGE_V1, candidate_only=true, additionalProperties=false. SHA256 del schema productor: b31076818c6b8b0700004dfd01aa1f021abe2a02e7a0f7d0fd0bd910d183ad80. Es salida de modelo no cualificada, no envelope de admisión ni paquete A9 ya admitido.
Consumidor: programming_entry_contract_v1.json, PROGRAMMING_ENTRY_CONTRACT_V1, SOURCE_ONLY_CANDIDATE, SHA256 d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8.
Snapshot: extensions.programming_context_snapshot, PROGRAMMING_CONTEXT_SNAPSHOT_V1.

Las unidades A5/A6/A7/A8/A9 tienen contratos fuente adicionales en esta carpeta, pero su presencia no significa que runtime_output los emita completos ni que exista una ejecución/admisión operativa. stage_trace con stage=A9 es texto del candidato, no identidad de ejecución ni recibo independiente.

La columna «quién lo admite» describe el rol que debe acordarse en C1, salvo que se indique el validador estructural actual. No se afirma que ese actor/proveedor esté implementado o autorizado. A9 ensambla; no se autoacredita la autoridad ni se convierte READY_CANDIDATE en READY por renombrado.

## Tabla campo a campo del snapshot obligatorio

| Campo consumidor | Campo productor existente | Transformación propuesta | Quién lo admite | Brecha actual |
|---|---|---|---|---|
| objective | request_context.intent | Conservar intención literal y vínculo a pedido; no ampliar alcance | Dueño del pedido + A9, por acordar; receptor valida estructura | Candidato no autentica pedido ni alcance autorizado |
| target | request_context.target_ref | Resolver referencia canónica exacta a repo/base/fuente; no inferirlos del texto | Autoridad del destino/lector exacto + A9, por acordar | target_ref es string; faltan repo_full_name, base_head_sha, source_snapshot_sha256 y prueba de identidad exacta |
| target_granularity | classification.target_granularity | Normalización explícita y versionada de vocabulario, conservar original | A9 y consumidor acuerdan catálogo | String libre; no prueba de granularidad canónica ni correspondencia acordada |
| authority_state | classification.authority_state | Preservar EXISTING/NEW/UNKNOWN; UNKNOWN no se transforma en certeza | Autoridad de fuente + A9, por acordar | Declaración candidata sin evidencia de autoridad |
| implementation_state | classification.implementation_state | Preservar dimensión independiente de authority_state | Autoridad de implementación + A9, por acordar | Falta revisión exacta/delta si EXISTING y evidencia negativa/reuso si NEW |
| requirements[] | requirements[] | Conservar requirement_id, scope_id, outcome, acceptance_signal, evidence_refs; resolver referencias sin reducir a IDs | A6/A9 y evaluador de suficiencia, por acordar | Los cinco campos candidatos no completan IMPLEMENTABILITY_SCHEMA_V1 ni autoridad/currentness/permisos |
| authority_bindings[] | No existe campo equivalente | Resolver bindings canónicos con valor vigente y resolver tipado | Autoridad canónica + A6/A9, por acordar | BRECHA; evidence_refs y stage_trace.source_refs no acreditan bindings |
| applicable_rules[] | No existe | Obtener reglas aplicables desde fuente autorizada | Autoridad de reglas + A9, por acordar | BRECHA; no derivar reglas del nombre del dominio ni inventar [] |
| applicable_invariants[] | No existe | Obtener invariantes aplicables con evidencia | Autoridad de invariantes + A9, por acordar | BRECHA; ausencia no demuestra no aplicabilidad |
| preserve[] | material_fronts[].obligation_mode=REUSE_AS_IS, parcialmente | Identificar material a preservar y sus bindings; no convertir automáticamente frente en objeto preservado | A6/A7/A9, por acordar | Faltan identidad material, autoridad y currentness; REUSE_AS_IS no basta |
| material_front_coverage | material_fronts[]; research_stop.all_material_fronts_accounted | Integrar artefacto A7 completo, preservar frentes/evidencia y trazabilidad | A7/A9 + evaluación independiente, por acordar | Faltan front_kind, source_signal_refs, authority_refs, currentness_refs, front_candidate_refs, unmapped_material_signals, fingerprint y refs globales; booleano candidato no acredita cobertura |
| implementability_schema | requirements[] y material_fronts[], parcialmente | Ensamblar artefacto A6 completo sin elegir estrategia PG-03 | A6/A9 + consumidor, por acordar | BRECHA de contrato: no canonical_implementation_bindings, fingerprints, obligaciones, permisos, efectos, precondiciones y contratos completos |
| decision_context | decisions_pending[]; material_unknowns[], parcialmente | Conservar pendientes como pendientes; obtener artefacto A5 y resolución/ADR independiente | Autoridad decisora/ADR + A5/A9, por acordar | Lista de preguntas no es ANALYSIS_DECISION_CONTEXT_V1 estable ni recibo de resolución; no inventar STABLE |
| analysis_stop_rule | research_stop | Preservar decision, decision_stable, all_material_fronts_accounted, unresolved_decision_changing_questions; completar artefacto A8 | A8/A9 + evaluación, por acordar | Faltan material_front_coverage_ref, additional_available_evidence_capable_of_changing_material_decision, evidence_refs y reason; STOP candidato no es admisión |
| scope_front_matrix[] | material_fronts[].scope_ids y scope_proposals[].material_front_refs | Join bidireccional por IDs; obligation_mode→front_status, closure→front_closure; preservar evidence_refs/reason | A7/A9 + PG-01 valida consistencia | effect_on_scope no se emite: no inferir PRESERVE para REQUIRED/BLOCKED ni silenciar blockers; falta regla acordada |
| scope_readiness[] | scope_proposals[] | Preservar IDs/frentes/blockers; readiness_candidate queda candidato hasta admisión explícita | Admisor A9 independiente del modelo, identidad por acordar; PG-01 consume | BRECHA de procedencia READY; faltan scope_kind, depends_on_scope_ids, authority_refs, reason y recibo de admisión |
| package_readiness | package_readiness_candidate | READY_CANDIDATE/PARTIAL_READY_CANDIDATE requieren juicio y scopes admitidos antes de READY/PARTIAL_READY | Admisor A9, por acordar | BRECHA; no renombrado automático ni promoción por schema válido |
| unresolved_material_items[] | material_unknowns[] + decisions_pending[] + blockers de frentes/scopes + research_stop.unresolved_decision_changing_questions | Unión trazable con tipo e identidad original; no descartar preguntas ni inventar equivalencias | A5/A6/A7/A8/A9 + evaluación, por acordar | No existe esquema consolidado ni política de identidad/dedupe/severidad y propagación acordada |
| source_refs[] | stage_trace[].source_refs; requirements[].evidence_refs; material_fronts[].evidence_refs | Inventariar referencias completas conservando procedencia; resolver por tipo | Lector exacto/autoridad de evidencia + A9, por acordar | Strings sin readback exacto/digest ni identidad/versionado admitidos |
| currentness_refs[] | No existe | Consumir decisiones y referencias de CURRENTNESS_AUTHORITY para material afectado | Proveedor de currentness admitido, por acordar | BRECHA; source_refs no sustituyen currentness admitida |
| snapshot_schema_digest_sha256 | No existe | Calcular SHA256 de bytes exactos del contrato consumidor admitido, fuera del modelo | A9 y PG-01 cotejan contra pin independiente | El digest local existe; productor no lo emite y falta binding de admisión a versión exacta |
| authority_fingerprint_sha256 | No existe | Calcular con artefactos/bindings de autoridad completos según contrato acordado | Autoridad/assembler A9 y lector independiente, por acordar | BRECHA; no usar hash del texto candidato como autoridad |
| source_snapshot_sha256 | No existe | Binding al snapshot fuente exacto, con algoritmo/canonicalización acordados | Autoridad de fuente + lector exacto/A9, por acordar | BRECHA; ni request_context ni refs sueltos prueban snapshot fuente |

schema_version del snapshot no se copia del schema_version del paquete: son discriminadores distintos. A9 lo debe ensamblar conforme al contrato acordado. No es un campo nuevo del productor.

### Detalle obligatorio del target

| Campo consumidor target | Fuente productor | Transformación/admisión pendiente | Brecha |
|---|---|---|---|
| repo_full_name | Solo request_context.target_ref | Resolver referencia exacta por autoridad del destino | No se emite; no inferir repo |
| base_head_sha | Ninguna | Pin de revisión exacta obtenido por lector admitido | No se emite; no usar main mutable |
| source_snapshot_sha256 | Ninguna | Vincular snapshot fuente exacto | No se emite; no confundir con digest de contrato/paquete |

### Detalle obligatorio de scope_readiness

| Campo consumidor | Fuente productor | Transformación/admisión pendiente | Brecha |
|---|---|---|---|
| scope_id | scope_proposals[].scope_id | Igualdad exacta de ID, sin sustitución | Falta vínculo a paquete/ejecución admitidos |
| scope_kind | Ninguna | Clasificación explícita por scope | No inferir de granularidad global |
| status | scope_proposals[].readiness_candidate | Admisor transforma candidato tras evidencia y cierre | READY admitido no existe en salida |
| depends_on_scope_ids[] | Ninguna | Cierre explícito de dependencias por scope | [] no está justificado por ausencia |
| material_front_refs[] | scope_proposals[].material_front_refs | Preservar y cotejar unión bidireccional con material_fronts[].scope_ids | Identidad interna no acredita cobertura admitida |
| authority_refs[] | Ninguna | Resolver autoridad canónica por scope | evidence_refs no son autoridad |
| blockers[] | scope_proposals[].blockers | Preservar y propagar otros pendientes materiales | Falta política de cierre/propagación admitida |
| reason | material_fronts[].reason solo de frente | Justificación específica del scope por admisor | No se emite razón de scope |

### Detalle obligatorio de scope_front_matrix

| Campo consumidor | Fuente productor | Transformación/admisión pendiente | Brecha |
|---|---|---|---|
| scope_id | material_fronts[].scope_ids y scope_proposals[].scope_id | Join exacto y bidireccional | Acordar manejo de huérfanos/duplicados |
| front_id | material_fronts[].front_id | Conservar ID y cotejar refs del scope | Falta admisión de identidad |
| front_status | material_fronts[].obligation_mode | Correspondencia nominal REQUIRED/REUSE_AS_IS/NOT_APPLICABLE | Candidato no prueba no aplicabilidad/reuso |
| front_closure | material_fronts[].closure | Preservar CLOSED/BLOCKED | CLOSED candidato no es cierre autorizado |
| effect_on_scope | Ninguna | Regla explícita con BLOCKS/PRESERVE/NOT_APPLICABLE | BRECHA; no inventar efecto |
| evidence_refs[] | material_fronts[].evidence_refs | Preservar y resolver evidencia exacta | Falta readback/currentness admitidos |
| reason | material_fronts[].reason | Conservar razón, completar relación scope/frente | Falta razón específica del vínculo si global no alcanza |

## Ocho temas del acuerdo C1

| Tema | Pieza existente | Falta acordar |
|---|---|---|
| Pedido | request_context.intent/target_ref; texto literal del Router | Identidad/hash y alcance autorizado del pedido; cómo se liga al paquete, target y ejecución sin caller boolean |
| Identidad | schema_version, stage_trace A1–A9, ExpectedHandoff local | Identidad real de ejecución/productor, admisor, operación autorizada y prevención de replay; stage=A9 no es prueba |
| Destino | target_ref candidato; contrato target_binding; lector exacto PG-01 | Resolución canónica repo/base/target/snapshot y responsable que la admite |
| Entrada | PROGRAMMING_ENTRY_CONTRACT_V1; snapshot/as-of/ExpectedHandoff | Envelope admitido y transformación campo a campo sin pérdida; los candidatos no satisfacen solos la entrada |
| Salida | Recibo PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 de siete campos + schema_version; permisos false | Vinculación verificable recibo↔paquete/admisión/scope. D7 persistencia se decide en reunión, no aquí |
| Evaluación | JSON schemas y validadores Python/SQL, currentness local, reglas de scope/front | Admisor independiente, criterios de evaluación semántica/material, autoridad/currentness operativos; distinguir schema válido de admisión |
| Retornos | decision_policy Router y códigos PG-01; tabla PG01_ROUTER_COMPATIBILITY_V1.md | Binding de causas a RETURN_TO_ANALYSIS_NO_CODE/BLOCK_NO_CODE, responsable de corrección, reintento y nueva versión; no dispatch hoy |
| Versiones | Paquete V1, snapshot V1, entrada V1/digest, recibo V1; pins Git | Algoritmo de digest del paquete/envelope, compatibilidad, corte V2 y coexistencia sin bypass; no confundir nombres con bytes iguales |

## Preguntas para Cristhian y responsable de A9

1. ¿Qué componente y operación admiten el candidato A9, con qué identidad verificable y evidencia independiente del modelo?
2. ¿Cuál es la referencia exacta del paquete y su ejecución/pedido/target, y qué lector entrega la expectativa independiente a PG-01?
3. ¿Quién certifica READY/PARTIAL_READY y el cierre de dependencias/frentes por scope? ¿Cómo queda trazable la transformación desde READY_CANDIDATE?
4. ¿Dónde están y cómo llegan completos los artefactos A5/A6/A7/A8 y los bindings/reglas/invariantes que runtime_output no emite?
5. ¿Qué proveedor admitido da currentness material y qué invalida la admisión por deriva, cambio de autoridad o target?
6. ¿Se aprueba PROGRAMMING_ENTRY_CONTRACT_V2 para exigir envelope, cuál es el corte y cómo se evita una ruta V1 menos estricta?
7. ¿Qué positivo real exacto de C1/PR2 se acuerda, qué negativos de replay/admisión se exigen y quién hace readback independiente?
8. Para D8/2F.P: ¿se ratifican REPOSITORY_ARTIFACT + CODE_DEVELOPMENT como vocabulario candidato y cuál será el contrato completo antes de activarlo? D7 se decide por separado en reunión.

Documento complementario: PG01_A9_ADMISSION_ENVELOPE_DESIGN_V1.md. Este borrador no cierra C1, C6, P1 ni I0.
