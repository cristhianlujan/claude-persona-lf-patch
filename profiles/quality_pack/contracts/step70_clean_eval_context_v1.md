# LF Step70 — separación lógica del mismo LLM (V1, sandbox)

## Autoridad y límite
La independencia del juez Step70 se define por **aislamiento comprobado de contexto y evaluación**, no por proveedor, modelo distinto, API externa ni atestación criptográfica del host. Se mantiene el RUN `EJECUCION_PERFIL_LF`, el escritor `lf_profile_native_bridge_record_semantic_v1`, Step80 y retorno ACT-0001. Esta modalidad no autoriza producción, promoción ni efectos nuevos.

## Única modalidad aditiva
`review_mode=INDEPENDENT_EVAL_CONTEXT` / `verdict=PASS_INDEPENDENT_SEMANTIC`.

Un PASS de esta modalidad requiere **todos**:
1. RAW de Step50 congelado (SHA256 exacto) + digest de alcance Step40 + Step60 determinístico PASS del **mismo execution_id**.
2. Tres registros **inmutables** de procedencia de contexto `REQUEST → EXECUTOR → JUDGE` en `public.lf_ig_native_chat_receipt_v1`, con cadena SHA256 completa, nonce y SHA de bundle constante; fuente registrada únicamente por escritor gobernado; no aceptar JSON autoafirmado como evidencia.
3. El evento EXECUTOR contiene `executor_context_ref`, `producer_schema_id`, `producer_eval_id` y atributos del productor; JUDGE contiene `reviewer_context_ref` **distinto**, esquema `LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1`, eval `LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1`, y atributos efectivos distintos. La entrada del juez se limita al bundle congelado, sin contexto ni veredicto previo del productor.
4. La evaluación debe tener su propio RAW JSON, ejecutar validador del juez y acreditar `decision_checks` V3 completos, referencias resueltas, contraejemplos y ausencia de bloqueos. La referencia al recibo de juicio debe resolver al evento inmutable JUDGE.
5. El bridge SQL verifica independientemente las fuentes de RUN, cadena y recibo antes de declarar `CLEAN_CONTEXT_EVAL_VERIFIED`. `model_call_count`/host provenance pueden ser nulos: **no se inventan**. `CURRENT_CONTEXT_REVIEW` no puede tener independencia ni cerrar ejecuciones con efectos.

## Fallo seguro
Sin una segunda evaluación real en contexto aislado y su cadena registrada: `LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED`; Step70 no se registra, Step80 no corre, Quality ni solicitudes de promoción se activan. La existencia de este contrato **no crea invocaciones LLM ni registros de juez**. Hashes y flags autodeclarados no acreditan independencia.

## Validación y no regresión
CAS por MD5 exacto del bridge preexistente, transacción, `*_DRIFT`, pruebas PG17/18 en `BEGIN/ROLLBACK`. No modificar Step50/60, perfil Product Director histórico, mecanismo B09 legacy ni reglas LF. El juez puede devolver RETURN/BLOCK y permanece en flujo gobernado.

## Excepción gobernada del owner — mismo contexto SRCR (2026-11-15, sandbox)

Para el Reparador que **solo entregó artefactos candidatos de sandbox** y no posee
autorización del paso 40 para mutar reglas/producto, se permite
`CURRENT_CONTEXT_REVIEW / PASS_REVIEWED_CURRENT_CONTEXT` **dentro de la misma
conversación y el mismo RUN**. No hay evento JUDGE independiente, segunda llamada,
tercer recibo ficticio ni cambio retroactivo del manifiesto histórico.

Aplicabilidad real la deriva SQL:
`lf_profile_srcr_same_context_candidate_scope_v1(execution_id)`. Requiere
manifest de no promoción/no impacto automático, Router sin efecto autorizado,
Step40 `mutation_authorized=false` y acciones de análisis, Step60 PASS,
y Step50 con cambios CREATE referidos exclusivamente a fuentes
`sandbox/lf_contract_gate_test/` del repositorio LF. Fuera de ese alcance,
la revisión de contexto propio sigue rechazada. Nunca se permite este modo
en Product Director, producción, promoción, Quality o aprobación de efectos.

El dictamen tiene procedencia explícita:
`reviewer_is_producer=true`, `producer_independence_proven=false`,
`model_call_count=0`, `independent_semantic_receipt_ref=null` y
`judge_independence_status=NOT_PROVEN`. Debe pasar los doce controles V3
y la verificación material de evidencias; un hallazgo de contradicción
puede devolver FAIL/RETURN y no se blanquea.

Solo después de integración por Migration Merge Train, despliegue Edge y
SELECT del RUN original se puede acreditar paso 70 y paso 80. No se modifica
el writer ni la cadena histórica REQUEST/EXECUTOR de B09.


## Ruta genérica CURRENT_CONTEXT

**Cierre técnico, no aprobación de Quality.** Para un RUN gobernado cuyo manifiesto
autoriza exclusivamente `read_only=true`, `no_write=true` y
`no_promotion=true`, la ruta genérica existente de
`CURRENT_CONTEXT_REVIEW` puede registrar Step70 con
`PASS_REVIEWED_CURRENT_CONTEXT` y resultado técnico
`STEP_PASS_WITH_EVIDENCE` (`EXECUTION_PASS`), continuar Step80 y cerrar
`COMPLETED` con recibo `READY`. Esto acredita solo la **ejecución del flujo**:
nunca significa `QUALITY_APPROVED`, `PASS_INDEPENDENT_SEMANTIC` ni
habilitación de producto, efectos o promoción. No se convierte un hallazgo de
contenido en un fallo de transporte. Fuente del cierre genérico:
[`20261101050034_lf_profile_current_context_semantic_review_v1.sql`](../../../supabase/migrations/20261101050034_lf_profile_current_context_semantic_review_v1.sql).

**Evidencia del caso Quality (SELECT, sandbox).** El RUN
`EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C` alcanzó 11/11 y
`COMPLETED`; Step70 quedó con `review_mode=CURRENT_CONTEXT_REVIEW`,
`verdict=PASS_REVIEWED_CURRENT_CONTEXT`, `reviewer_is_producer=true`,
`producer_independence_proven=false`, `model_call_count=0` e
`independence=NOT_PROVEN`. Se conserva intacto el dictamen de Step50:
`RETURN_TO_ORCHESTRATOR`, 19/25,
`QUALITY_SEMANTIC_INDEPENDENCE_NOT_PROVEN` y
`QUALITY_GOV037_FULL_RESOLVER_GATE_NOT_EXECUTED`. El retorno a ACT-0001
no autoriza modificaciones, solicitud de promoción ni un Quality PASS.
Esta ruta genérica no altera ni amplía la excepción SRCR anterior.

**Gate de promoción separado, existente y fail-closed.** La solicitud
`public.lf_rule_promotion_request_v1(text,text,text)` exige el Step70
`PASS_INDEPENDENT_SEMANTIC`, `producer_independence_proven=true`,
`judge_invocation_kind=NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE`, la
procedencia/hashes exactos de Step40/50/60/70 y autoridad del perfil.
Con el dictamen `CURRENT_CONTEXT_REVIEW`, devuelve
`PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED`, **sin crear solicitud**.
Fuente: [`20261114163200_lf_rule_promotion_independent_step70_existing_route_v1.sql`](../../../supabase/migrations/20261114163200_lf_rule_promotion_independent_step70_existing_route_v1.sql).
La aprobación humana es posterior y separada: jamás automática.

**Diferimiento explícito de Quality PASS pleno.** El artefacto de
`B2B-CARGA-002` devuelve `eligible_candidates=[]`: hoy no hay candidato
elegible que justifique un juicio limpio de aprobación. Solo cuando exista
**al menos una regla candidata elegible con evidencia suficiente**, se
solicitará al dueño ejecutar un **chat limpio distinto** para el juez,
con las **cinco compuertas GOV-037** verificadas por resolver y procedencia
exacta. Únicamente ese juicio independiente y la decisión humana posterior
pueden sustentar aprobación/promoción. No se modifica
`lf_profile_native_bridge_record_semantic_v1`, no se crea otro campo ni se
reescribe el RUN histórico.
