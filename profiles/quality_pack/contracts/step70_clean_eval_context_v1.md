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
