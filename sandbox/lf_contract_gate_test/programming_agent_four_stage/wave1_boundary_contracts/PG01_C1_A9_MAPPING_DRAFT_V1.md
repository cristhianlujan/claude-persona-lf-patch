# PG01_C1_A9_MAPPING_DRAFT_V1

26-oct-2026. Borrador para reunión C1; PENDING_DECISION. No constituye acuerdo A9→PG-01 ni admisión. Sin implementación del envelope, cambios de contrato, D7 o runtime.

## Marco v3 y responsabilidad

A9 es el último paso de Análisis A1–A9 del propio agente de Programación, frente de Paulo. No es un productor externo ni depende de un responsable A9 ajeno. A9 ensambla fuera del modelo; lo independiente es el juez semántico gobernado, y una operación gobernada registra su resultado. Fuentes y recorrido: A9_ASSEMBLER_SOURCES_V1.md. D7-A: PG01_D7_OPTION_A_SPEC_V1.md. No se ejecuta el procedimiento ni se implementa el envelope.

## Fuentes exactas y límite de autoridad

Main leído: ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267.
Productor: profiles/programming_analysis_lf/schemas/runtime_output.schema.json, schema_version ANALYSIS_IMPLEMENTATION_PACKAGE_V1, candidate_only=true, additionalProperties=false. SHA256 del schema productor: b31076818c6b8b0700004dfd01aa1f021abe2a02e7a0f7d0fd0bd910d183ad80. Es salida de modelo no cualificada, no envelope de admisión ni paquete A9 ya admitido.
Consumidor: programming_entry_contract_v1.json, PROGRAMMING_ENTRY_CONTRACT_V1, SOURCE_ONLY_CANDIDATE, SHA256 d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8.
Snapshot: extensions.programming_context_snapshot, PROGRAMMING_CONTEXT_SNAPSHOT_V1.

Las unidades A5/A6/A7/A8/A9 tienen contratos fuente adicionales en esta carpeta, pero su presencia no significa que runtime_output los emita completos ni que exista una ejecución/admisión operativa. stage_trace con stage=A9 es texto del candidato, no identidad de ejecución ni recibo independiente.

La preparación A1–A9 pertenece a Paulo. La admisión semántica corresponde al juez gobernado independiente y a la operación que lo registra; su implementación/calificación y binding todavía se deben acordar. Las autoridades canónicas de Producto/evidencia siguen siendo fuente, no una autoaprobación del ensamblador. A9 no convierte READY_CANDIDATE en READY por renombrado.

## Tabla campo a campo del snapshot obligatorio

| Campo consumidor | Campo productor existente | Transformación propuesta | Quién prepara / quién admite | Brecha actual |
|---|---|---|---|---|
| objective | request_context.intent | Conservar intención literal y vínculo a pedido; no ampliar alcance | A1/A9 (Paulo); juez gobernado + operación que lo registra | Candidato no autentica pedido ni alcance autorizado |
| target | request_context.target_ref | Resolver referencia canónica exacta a repo/base/fuente; no inferirlos del texto | A3/A9 (Paulo); juez gobernado + operación que lo registra | target_ref es string; faltan repo_full_name, base_head_sha, source_snapshot_sha256 y prueba de identidad exacta |
| target_granularity | classification.target_granularity | Normalización explícita y versionada de vocabulario, conservar original | A2/A9 (Paulo); juez gobernado + operación que lo registra | String libre; no prueba de granularidad canónica ni correspondencia acordada |
| authority_state | classification.authority_state | Preservar EXISTING/NEW/UNKNOWN; UNKNOWN no se transforma en certeza | A3/A9 (Paulo); juez gobernado + operación que lo registra | Declaración candidata sin evidencia de autoridad |
| implementation_state | classification.implementation_state | Preservar dimensión independiente de authority_state | A3/A9 (Paulo); juez gobernado + operación que lo registra | Falta revisión exacta/delta si EXISTING y evidencia negativa/reuso si NEW |
| requirements[] | requirements[] | Conservar requirement_id, scope_id, outcome, acceptance_signal, evidence_refs; resolver referencias sin reducir a IDs | A6/A9 (Paulo); juez gobernado + operación que lo registra | Los cinco campos candidatos no completan IMPLEMENTABILITY_SCHEMA_V1 ni autoridad/currentness/permisos |
| authority_bindings[] | No existe campo equivalente | Resolver bindings canónicos con valor vigente y resolver tipado | A3/A6/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; evidence_refs y stage_trace.source_refs no acreditan bindings |
| applicable_rules[] | No existe | Obtener reglas aplicables desde fuente autorizada | A3/A6/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; no derivar reglas del nombre del dominio ni inventar [] |
| applicable_invariants[] | No existe | Obtener invariantes aplicables con evidencia | A3/A4/A6/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; ausencia no demuestra no aplicabilidad |
| preserve[] | material_fronts[].obligation_mode=REUSE_AS_IS, parcialmente | Identificar material a preservar y sus bindings; no convertir automáticamente frente en objeto preservado | A3/A4/A6/A7/A9 (Paulo); juez gobernado + operación que lo registra | Faltan identidad material, autoridad y currentness; REUSE_AS_IS no basta |
| material_front_coverage | material_fronts[]; research_stop.all_material_fronts_accounted | Integrar artefacto A7 completo, preservar frentes/evidencia y trazabilidad | A7/A9 (Paulo); juez gobernado + operación que lo registra | Faltan front_kind, source_signal_refs, authority_refs, currentness_refs, front_candidate_refs, unmapped_material_signals, fingerprint y refs globales; booleano candidato no acredita cobertura |
| implementability_schema | requirements[] y material_fronts[], parcialmente | Ensamblar artefacto A6 completo sin elegir estrategia PG-03 | A6/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA de contrato: no canonical_implementation_bindings, fingerprints, obligaciones, permisos, efectos, precondiciones y contratos completos |
| decision_context | decisions_pending[]; material_unknowns[], parcialmente | Conservar pendientes como pendientes; obtener artefacto A5 y resolución/ADR independiente | A5/A9 (Paulo); juez gobernado + operación que lo registra | Lista de preguntas no es ANALYSIS_DECISION_CONTEXT_V1 estable ni recibo de resolución; no inventar STABLE |
| analysis_stop_rule | research_stop | Preservar decision, decision_stable, all_material_fronts_accounted, unresolved_decision_changing_questions; completar artefacto A8 | A8/A9 (Paulo); juez gobernado + operación que lo registra | Faltan material_front_coverage_ref, additional_available_evidence_capable_of_changing_material_decision, evidence_refs y reason; STOP candidato no es admisión |
| scope_front_matrix[] | material_fronts[].scope_ids y scope_proposals[].material_front_refs | Join bidireccional por IDs; obligation_mode→front_status, closure→front_closure; preservar evidence_refs/reason | A7/A9 (Paulo); juez gobernado + operación que lo registra | effect_on_scope no se emite: no inferir PRESERVE para REQUIRED/BLOCKED ni silenciar blockers; falta regla acordada |
| scope_readiness[] | scope_proposals[] | Preservar IDs/frentes/blockers; readiness_candidate queda candidato hasta admisión explícita | A9 (Paulo); juez gobernado + operación que lo registra | BRECHA de procedencia READY; faltan scope_kind, depends_on_scope_ids, authority_refs, reason y recibo de admisión |
| package_readiness | package_readiness_candidate | READY_CANDIDATE/PARTIAL_READY_CANDIDATE requieren juicio y scopes admitidos antes de READY/PARTIAL_READY | A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; no renombrado automático ni promoción por schema válido |
| unresolved_material_items[] | material_unknowns[] + decisions_pending[] + blockers de frentes/scopes + research_stop.unresolved_decision_changing_questions | Unión trazable con tipo e identidad original; no descartar preguntas ni inventar equivalencias | A3–A8/A9 (Paulo); juez gobernado + operación que lo registra | No existe esquema consolidado ni política de identidad/dedupe/severidad y propagación acordada |
| source_refs[] | stage_trace[].source_refs; requirements[].evidence_refs; material_fronts[].evidence_refs | Inventariar referencias completas conservando procedencia; resolver por tipo | A3–A8/A9 (Paulo); juez gobernado + operación que lo registra | Strings sin readback exacto/digest ni identidad/versionado admitidos |
| currentness_refs[] | No existe | Consumir decisiones y referencias de CURRENTNESS_AUTHORITY para material afectado | A3–A8/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; source_refs no sustituyen currentness admitida |
| snapshot_schema_digest_sha256 | No existe | Calcular SHA256 de bytes exactos del contrato consumidor admitido, fuera del modelo | A3/A9 (Paulo); juez gobernado + operación que lo registra | El digest local existe; productor no lo emite y falta binding de admisión a versión exacta |
| authority_fingerprint_sha256 | No existe | Calcular con artefactos/bindings de autoridad completos según contrato acordado | A3/A6/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; no usar hash del texto candidato como autoridad |
| source_snapshot_sha256 | No existe | Binding al snapshot fuente exacto, con algoritmo/canonicalización acordados | A3/A9 (Paulo); juez gobernado + operación que lo registra | BRECHA; ni request_context ni refs sueltos prueban snapshot fuente |

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
| status | scope_proposals[].readiness_candidate | Juez gobernado evalúa; operación registra decisión tras evidencia y cierre | READY admitido no existe en salida |
| depends_on_scope_ids[] | Ninguna | Cierre explícito de dependencias por scope | [] no está justificado por ausencia |
| material_front_refs[] | scope_proposals[].material_front_refs | Preservar y cotejar unión bidireccional con material_fronts[].scope_ids | Identidad interna no acredita cobertura admitida |
| authority_refs[] | Ninguna | Resolver autoridad canónica por scope | evidence_refs no son autoridad |
| blockers[] | scope_proposals[].blockers | Preservar y propagar otros pendientes materiales | Falta política de cierre/propagación admitida |
| reason | material_fronts[].reason solo de frente | Justificación específica del scope por juez gobernado y operación registradora | No se emite razón de scope |

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
| Identidad | schema_version, stage_trace A1–A9, ExpectedHandoff local | Identidad real de ejecución/productor, juez gobernado y operación registradora autorizados y prevención de replay; stage=A9 no es prueba |
| Destino | target_ref candidato; contrato target_binding; lector exacto PG-01 | Resolución canónica repo/base/target/snapshot y juez gobernado y operación que registran su admisión |
| Entrada | PROGRAMMING_ENTRY_CONTRACT_V1; snapshot/as-of/ExpectedHandoff | Envelope admitido y transformación campo a campo sin pérdida; los candidatos no satisfacen solos la entrada |
| Salida | Recibo PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 de siete campos + schema_version; permisos false | Vinculación verificable recibo↔paquete/admisión/scope. D7 persistencia se decide en reunión, no aquí |
| Evaluación | JSON schemas y validadores Python/SQL, currentness local, reglas de scope/front | Juez gobernado + operación que lo registra, criterios de evaluación semántica/material y autoridad/currentness operativos; distinguir schema válido de admisión |
| Retornos | decision_policy Router y códigos PG-01; tabla PG01_ROUTER_COMPATIBILITY_V1.md | Binding de causas a RETURN_TO_ANALYSIS_NO_CODE/BLOCK_NO_CODE, responsable de corrección, reintento y nueva versión; no dispatch hoy |
| Versiones | Paquete V1, snapshot V1, entrada V1/digest, recibo V1; pins Git | Algoritmo de digest del paquete/envelope, compatibilidad, corte V2 y coexistencia sin bypass; no confundir nombres con bytes iguales |

## Ocho preguntas cerradas para Cristhian, corregidas v3

1. **Producto / definición:** dado que B2B_AUTH001_SUBMIT ya figura como «Acceder» en el catálogo candidato, ¿para este caso se elige **A)** confirmar pedido satisfecho/no-op o **B)** entregar una definición canónica de delta con referencia y versión antes de continuar?
2. **Producto / alcance:** ¿se confirma que la definición de ese caso preserva autenticación, validaciones y el resto de la pantalla, y delimita únicamente el cambio explícito que Producto admita (**sí/no**)?
3. **Juez compartido:** ¿se autoriza reutilizar el patrón de readback/recomputación/registro de tu juez de lecturas como base de un juez A9 específico, manteniendo intacto el juez de lecturas y sin tratarlo como suficiente para A9 (**sí/no**)?
4. **Liberación del perfil:** ¿se mantiene PERFIL-PROGRAMMING-ANALYSIS-LF sin liberar hasta contar con ensamblador, adapter de autoridad/currentness y juez gobernado calificados sobre el contrato acordado (**sí/no**)?
5. **D7:** ¿se confirma la opción **A**, ledger append-only de recibos/envelopes ligado al snapshot único existente, como posición de diseño que pasa a revisión (**sí/no**)?
6. **D7 / writer:** para su futura operación, ¿se elige **A)** escrituras solo vía Train o **B)** diseñar por separado una operación runtime gobernada antes de habilitar escrituras frecuentes? La opción B no autoriza ningún write ahora.
7. **D8:** ¿se ratifica el vocabulario candidato REPOSITORY_ARTIFACT/CODE_DEVELOPMENT de #3167, manteniendo el PR draft, write_allowed=false y sin activación hasta revisar el contrato completo de la operación (**sí/no**)?
8. **Contrato V2:** ¿se aprueba diseñar PROGRAMMING_ENTRY_CONTRACT_V2 para exigir el resultado del juez gobernado registrado por operación y su envelope, preservando V1 y su digest d2e347ef… (**sí/no**)?

Documento complementario: PG01_A9_ADMISSION_ENVELOPE_DESIGN_V1.md. Este borrador no cierra C1, C6, P1 ni I0.
