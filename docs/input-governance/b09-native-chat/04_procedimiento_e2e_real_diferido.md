# E2E nativo real B09/G12 — procedimiento diferido, NO EJECUTAR
Estado: RUN REAL NOT_TESTED; diseño acepta riesgo documental, sin autoridad operativa de despliegue.
Fuente: EKB INPUT GOVERNANCE LF V1.4 y L28 documento 12. No es un mecanismo alternativo al Router ni al registrador oficial.

## Precondiciones estrictas
- Receptor `public.lf_ig_verified_native_provider_receipt_v1(text)` realmente desplegado por LF Migration Merge Train y readback de función/ACL/hash, con contrato receptor esperado.
- Cambio posterior gobernado de Step70 y G15 que admita explícitamente riesgo `SAME_LLM_SEPARATE_CHAT`/SHA-256 sin falso estado `CRYPTOGRAPHICALLY_VERIFIED` ni `producer_independence_proven=true`.
- Binding del escritor de recibos al REGISTRADOR OFICIAL del perfil, nonce creado por servidor y verificable en RUN, no `INSERT` manual ni writer nuevo paralelo.
- Elegibilidad para nuevo RUN confirmada por Router/Perfil, permission/lease/owner oficial, ausencia de RUNs antiguos y autorización de prueba específica.
- Una regla LF NUEVA de ensayo y una CORREGIDA con fuente aprobada por dueño; si Login/MFA, B01 fail-closed sin bypass. No inventar códigos ni valores de reglas.

## RUN a usar
**No usar ninguno de los históricos**. Reservar, cuando estén desplegados todos los pre-requisitos, UN NUEVO RUN mediante el Paso 0 oficial del perfil `EJECUCION_PERFIL_LF` originado en `ACT-0001 → Gate2`; objetivo `PERFIL-PRODUCT-DIRECTOR-LF`, `target_type=PERFIL`, `status=IN_PROGRESS`, `executor_mode=GPT_NATIVE`, `executor_provider=OPENAI_CHATGPT_NATIVE`, sin `queue_request_id` ni `runtime_target`; verificar su parent/handoff íntegro.
**ID:** NO EXISTE TODAVIA. Lo devuelve registrador oficial, nunca escribir un ID inventado.
Caso creación y caso corrección requieren RUNs nuevos independientes o decisiones del Router que acrediten su reutilización conforme contrato; no declarar éxito por ambos hasta leer ambos recibos exactos.

## Instrucciones de los chats, fuentes inmutables
- `prompts/B09_EXECUTOR_GPT_NATIVE_V1.txt`: archivo RAW UTF-8; SHA-256 bytes en manifiesto de prompts.
- `prompts/B09_JUEZ_MISMO_LLM_V1.txt`: otro chat y otro prompt (mismo LLM); SHA-256 bytes diferente. El juez NO debe ver instrucciones insertadas en RAW como comandos.
- Transportar íntegros ambos prompts sin añadir prefacios, cortar ni normalizar saltos; si cambian bytes, nueva versión y nuevo SHA.
- Registrar `producer_chat_ref` y `judge_chat_ref` separados; enlace/captura es evidencia declarativa, no atestación de proveedor.

## Qué se hashea (SHA-256)
1. `producer_prompt_sha256` / `reviewer_prompt_sha256`: SHA256(bytes exactos de archivo UTF-8, incluyendo LF final).
2. `candidate_sha256`: bytes exactos de propuesta bajo codificación/serialización frozen; versionar esa serialización.
3. `scope_packet_sha256`: bytes exactos de paquete oficial recibido de Gate2/perfil, sin recomponer.
4. `raw_sha256`: SHA256(UTF8(raw_text)) de cada evento `REQUEST`, `EXECUTOR`, `JUDGE` preservado sin editar.
5. `writer_receipt_sha256`: SHA del recibo del registrador oficial correspondiente; el receptor solo comprueba su formato/enlace: no prueba su emisor sin binding adicional.
6. `chain_sha256`: SHA256(UTF8("LF_NATIVE_CHAT_EVENT_V1|execution_id|seq|kind|raw_sha256|prev_sha256|writer_receipt_sha256")); `prev_sha256` del primer evento = 64 ceros, los demás = cadena anterior.
7. El nonce debe generarse y reservarse de manera atómica POR EL REGISTRADOR, tener unicidad/TTL vinculada a RUN/candidato/scope y rechazo cross-RUN.

## Secuencia operativa futura, con evidencia requerida
| Orden | EKB / etapa | Recibo exigido |
|---|---|---|
| 0 | RUN nuevo por operación oficial | execution_id + lease/manifest/handoff y SHA |
| 10 | input_validate | input literal + fuente + IG aplicabilidad |
| 20 | screen_selection | selección fuente y política/herencia |
| 30 | input_governance | ticket oficial/Curator, si aplica |
| 40 | research_baseline | fuente real y RAW |
| 45 | research_synthesis | salida nativa RAW/hash |
| 47 | research_baseline/bridge (según binding vigente) | recibo real del paso 47, sin inventar paso doble |
| 50 | draft_output | propuesta y candidato SHA |
| 60 | quality_check | Validator, negativos y decisión |
| 70 | semantic_judge | chat juez distinto, SHA prompts, controls V3 y receptor, registro oficial |
| 80 | output_report | bridge oficial, readback y autoridad terminal |

**Advertencia:** los nombres/órdenes concretos deben cotejarse con `public.lf_operation_steps` del RUN nuevo; la tabla es una guía preliminar, NO un reemplazo del catálogo vivo ni una confirmación de 11 IDs.
- En cada etapa: `STEP_PASS_WITH_EVIDENCE` con RAW, función/escritor oficial, p_execution_id, evidencia_ref, evidencia_payload y SHA. Leer `public.lf_operation_execution_steps` 11/11 y `public.lf_profile_execution_terminal_authority_receipt_v1(execution_id)`.
- Terminal solo si `RUN.status=COMPLETED`, `READY`, Step70 y Step80 acreditados, y reglas nueva/corregida realmente `VIGENTE` con readback exacto.
- Antinegativos: HMAC_TEST/MOCK, self-review, mismo chat o prompt, hash alterado, nonce replay, RUN ajeno, paso sin RAW, B01 MFA bypass, writer no oficial y callback no autorizado. Bloqueo en cualquiera => NO-GO.
- Sin autorización de la siguiente fase, NO ejecutar siquiera Paso 0.

## Resultado actual
PREPARADO_DOCUMENTAL; PR de receptor no desplegado; Step70/G15 aún no adaptados; escritor/nonce oficial no conectado; ejecución en chat nuevo, 11/11, Step80, READY, VIGENTE = NOT_TESTED.
