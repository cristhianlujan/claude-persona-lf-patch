# Conexión A9 → INDEPENDENT_ASSURANCE@2.0.1 · V1

## Estado y fronteras

**Propuesta de código y contrato sin efectos.** El juez es `INDEPENDENT_ASSURANCE@2.0.1`; el sujeto es `PROGRAMMING_ANALYSIS_PACKAGE`; la operación gobernada existente es `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`. No se agregan operaciones, engines, tablas ni registros. La ejecución real debe pasar por el Router y el runtime autorizado bajo `service_role` (con permisos confirmados). **PG-01 nunca invoca begin_v3 ni anchor_v1.** El nivel GPT Native en chat es `OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT`, siempre `provider_attested=false`.

## Secuencia propuesta y seis pasos

1. **Congelar A9 y recuperar snapshot as-of (previo a `route_bind`).** El productor A9 produce el snapshot real; el orquestador autorizado obtiene `context_id`, `context_payload`, `context_sha256` y la referencia exacta al HEAD. Verificar en PostgreSQL que `context_sha256` proviene de `SHA256(UTF8(context_payload::text))`; no recalcularlo con `json.dumps` (representación de JSONB distinta). Comprobar los 23 campos presentes. `build_subject_anchor_params` prepara un *borrador* de los 17 argumentos de `fn_lf_evidence_ledger_anchor_v1`, sin ejecutar la función. Los campos de verificación del ledger (`authority_ref`, `resolver_id`, `provider`, `provider_ref`, `verification_method`, `verification_state`) permanecen sin determinar: **no ejecutar el anclaje con nulos sin antes completar y validar el contrato real**. `VERIFIED` solo lo determina la operación gobernada; no se puede deducir de una transcripción de chat.
2. **`route_bind` (operación gobernada).** El orquestador autorizado prepara la ruta y las identidades de productor, revisor y actor. Obtiene los recibos originales verificables. El código puro no despacha ni cambia estados.
3. **`target_currentness` (operación gobernada).** Verificar `INDEPENDENT_ASSURANCE@2.0.1`, digest del manifiesto vigente y disponibilidad del sujeto anclado en `private.lf_evidence_ledger_v1` con `verification_state='VERIFIED'`, identidad/hash/HEAD exactos. `build_begin_params` valida localmente manifest, independencia, identidades y hash y genera kwargs de `public.lf_independent_review_begin_v3`. La operación, no este adaptador, ejecutará begin_v3 tras verificar receipts y autoridad. El runtime de begin_v3 ejecuta también sus comprobaciones definitivas.
4. **`semantic_review`.** `build_blind_review_packet` quita trazas/identificadores directos del productor, conserva el snapshot semántico y declara las siete dimensiones. En una conversación de GPT Native **independiente**, un humano entrega este paquete y `packet_sha256` con la plantilla `A9_INDEPENDENT_REVIEWER_PROMPT_V1.md`. La respuesta RAW es material de chat, **no prueba de transporte**. `parse_review_verdict` valida estructura, identidad del paquete y evidencias, y deriva PASS/RETURN_TO_WORKER/BLOCKED. Nunca invoca modelo.
5. **`judge_record`.** `build_a9q_c3_evidence` prepara los campos de aceptación alcanzables: `frozen_subject_sha256`, identidades propuestas, referencia a resultado, `exact_stage_assertion_results`, `no_critical_regressions`. En nivel chat deja en `null` todo campo que solo emite el runtime (`evidence_ledger_verified_ref`, `governed_execution_id`, `router_dispatch_receipt_id`, `provider_response_id_attested_by_transport`). La operación, usando pruebas proveedor-bound reales, debe registrar el resultado y decidir su aceptación definitiva. No está implementado en este PR.
6. **`reviewer_readback` y `report_output`.** El runtime gobernado recupera el veredicto y verifica consistencia con el sujeto congelado, recibos y dimensiones. `build_v2_envelope_review_fragment` deja un fragmento **provisional y no admisible**, para contrato V2 aún inexistente. La salida gobernada y el informe final se harán después, no aquí.

## Registro de los pasos (verificado RO por Claude, 26-oct)

Después de `begin_v3`, cada paso se registra con `public.lf_record_independent_review_step_v3(p_execution_id, p_step_id, p_evidence_ref, p_evidence_payload, p_actor_execution_id, p_evidence_ledger_execution_id)`, que solo ejecutan `postgres` y `service_role`. Para `semantic_review` exige:

- `verdict` igual a `PASS` o `FAIL` (no hay tercer estado);
- `review_type` en `INDEPENDENT_REVIEW` / `INDEPENDENT_HOLDOUT`;
- `review_context = INDEPENDENT_OPERATION_CONTEXT`;
- `rationale_summary` no vacío y `evidence_refs` como array no vacío;
- para sujetos que no son `STRATEGY`, `utility_dimensions_checked` exactamente igual a `required_dimensions` del manifiesto (si no, `UTILITY_DIMENSIONS_INCOMPLETE`).

`build_semantic_review_step_payload` arma ese payload. `RETURN_TO_WORKER` y `BLOCKED` se registran ambos como `FAIL`; el veredicto original viaja en `a9_global_verdict` para no perder la distinción. Además, `begin_v3` y el CHECK del ledger exigen que `source_head_sha` sea un SHA de Git de 40 hex; el adaptador lo valida.

## Pregunta abierta: ¿el nivel chat cierra A9Q_C3?

`docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md` (13-oct) dice que el equivalente GPT Native en chat **no satisface** `INDEPENDENT_ASSURANCE@2.0.1` ni `begin_v3` (`independent_assurance_admitted=false`) para los checkpoints C2/C3 de la calificación del Análisis. En cambio, `EXEC-PE10C5-INDEP-d288c5ee8b3335e4` (21-oct) completó los 6 pasos de `INDEPENDENT_ASSURANCE` registrando la revisión de un material de chat por la operación gobernada. Antes de usar este adaptador para cerrar A9Q_C3, Cristhian debe decidir si una revisión GPT Native en chat, registrada por la operación gobernada como en PE10_C5, cuenta para A9Q_C3, o si A9Q_C3 exige el nivel `GOVERNED_RUNTIME`.

## Criterio de veredicto

- **PASS**: todas las dimensiones PASS, cada una con evidencia concreta.
- **RETURN_TO_WORKER**: hay al menos un FAIL probado y ningún UNKNOWN; devolver al productor por causa dirigida.
- **BLOCKED**: hay uno o más UNKNOWN (aunque existan FAIL); no se puede asegurar suficiencia semántica.

No se infiere que PASS estructural equivalga a PASS semántico. El runtime aún debe probar ausencia de regresiones críticas y el readback real de PG-01 (`context_id/hash/schema`, rechazo de missing/stale).

## Relación D7 / PG-01

D7 opción A ya prevé `private.lf_programming_context_handoff_receipts_v1` con lookup exacto; su lector permanece **siempre** `admissible=false` con `PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED`. Un A9 PASS no abre esa compuerta. `build_v2_envelope_review_fragment` NO es el envelope V2: el contrato V2 y las políticas sobre juez, scopes, vigencia y revocación requieren aprobación específica posterior.

## Requisitos antes de activar

- Snapshot A9 real y readback hashificado por PostgreSQL, con los 23 campos.
- Identidad, HEAD, ejecución productora y revisión independiente reales.
- Definición verificable de todos los parámetros de anchor_v1, incluyendo códigos y valores autorizados del ledger, más el anclaje `VERIFIED` provider-bound y su `receipt_id`.
- `plan_digest`, `request_sha256`, `idempotency_key`, despacho y manifests vigentes, enlazados al Router por el runtime.
- Aprobación expresa de Cristhian; revisión independiente y PR draft antes del Train.

## Limitaciones/decisiones pendientes

1. **No equivalencia de hash Python/PostgreSQL:** el adaptador exige el `context_sha256` provisto por el readback as-of, pero no puede demostrar por sí solo la fórmula `jsonb::text`; esa verificación es responsabilidad de la operación gobernada. Inventar una digestión Python sería inseguro.
2. **Anchor metadata (corregido por Claude, 26-oct):** el sujeto se ancla como `EVIDENCE_LEDGER` / `SOURCE_SNAPSHOT`, igual que el sujeto real del 21-oct (`731e93ae…`), no como recibo de revisión. Resolver, proveedor y método usan los valores ya existentes en el ledger para lecturas de Supabase: `LF_SUPABASE_READBACK_V1`, `SUPABASE`, `SUPABASE_SQL_READBACK_PLUS_DB_DIGEST`. `gate_code=A9_PROGRAMMING_ANALYSIS_SOURCE` es una propuesta a confirmar. `verification_state` queda `null`: solo la operación gobernada puede marcar `VERIFIED` tras su propio readback. El payload referencia la fila as-of y no copia `context_payload`.
3. **`review_scope`:** requerido como dato del plan, sin imponer un valor que aún no se autorizó para A9.
4. **Gobernanza de `provider_attested`:** el nivel `GOVERNED_RUNTIME` está descrito pero no se permite crearlo desde los builders de evidencias chat; necesita comprobación de receipts transport-bound y despliegue posterior.
5. **Blindaje:** se eliminan trazas y metadatos del productor por claves estructurales. Un texto arbitrario del snapshot que revele al productor requerirá anonimización/redacción gobernada adicional antes de enviarse al chat.
