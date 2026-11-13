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

## Secuencia operativa futura: 11/11 pasos, catálogo vivo `public.lf_operation_steps`

Fuente de nombres, orden y requisitos: **SELECT de solo lectura en Supabase**, `operation_code='EJECUCION_PERFIL_LF'`, 11 registros `required=true,active=true`, readback posterior al Train #3827 del 2026-11-13. Este mapeo es referencia documental; antes de un RUN real volver a leer `lf_operation_steps`, `lf_operation_step_contracts`, `lf_operation_step_judge_bindings` y `lf_operation_contracts`. No cambiar contratos ni dar PASS basándose en esta tabla.

| Orden | step_id **exacto** | Evidencia requerida por el catálogo vivo | Ejecución/autoridad |
|---|---|---|---|
| 0 | `init_execution` | `execution_id_created` | Solo RUN **nuevo** creado por mecanismo oficial de Paso 0; no inventar ni reutilizar |
| 10 | `router` | `router_read; action=PROFILE_EXECUTION` | ACT-0001 + Gate2 y recibo Router autorizado |
| 20 | `profile_resolve` | `exact_profile_resolved; codigo_activo; profile_slug` | Resolver perfil `PERFIL-PRODUCT-DIRECTOR-LF` |
| 30 | `profile_source_read` | `profile_source_ref; source_revision` | Fuente canónica y revisión exacta |
| 40 | `input_validate` | `input_scope; activation_trigger_match` | Verificar alcance, políticas/herencia e IG aplicable; EKB exige además comprobación de `scope_authority_packet` y SHA cuando corresponda |
| 45 | `context_admission` | `context_receipt_ref; context_receipt_digest; context_budget_status; context_event_id; context_budget_event_id; delivery; lazy_refs; profile_source_mode; jit_resolver_ref; server_validated` | Evidencia admitida y transporte del contexto, no reconstruir paquete Gate2 |
| 47 | `research_baseline_freeze` | `research_baseline_binding; baseline_receipt_ref; server_validated` | Función de baseline oficial y congelamiento del recibo |
| 50 | `execute_profile` | `profile_output; source_refs; context_receipt_ref; context_receipt_digest; context_transport; research_baseline_ref; research_baseline_digest` | Chat GPT productor genuino, salida RAW y hashes, ejecución del perfil por ruta oficial |
| 60 | `output_validate` | `output_contract_result; deterministic_validation` | Validator y controles deterministas; IG/Curator como dependencias si el contrato las solicita |
| 70 | `semantic_judge` | `semantic_judge_result; unsupported_claims` | Chat juez separado, prompt distinto, SHA nativo documental y bridge oficial `lf_profile_native_bridge_record_semantic_v1`; **BLOQUEA** hasta enmienda gobernada Step70/G15, escritor y nonce oficiales |
| 80 | `report_output` | `result; profile_code; execution_id; no_write_performed` | Bridge oficial `lf_profile_native_bridge_record_report_v1`, readback y recibo de terminal; no confundir reporte con modificación de reglas |

**No existen en este catálogo** los supuestos pasos `screen_selection`, `input_governance`, `research_synthesis`, `draft_output`, `quality_check` ni `output_report`: eran etiquetas preliminares, **no IDs ejecutables**. Las actividades de políticas/IG, investigación, propuesta y validación se resuelven dentro de los pasos oficiales mediante el binding del perfil, no por rutas paralelas. El ID exacto y sus `input_required`, `resolver_ref`, condiciones y claves deben releerse antes de ejecutar cada paso.

- En cada etapa: `STEP_PASS_WITH_EVIDENCE` con RAW, función/escritor oficial, p_execution_id, evidencia_ref, evidencia_payload y SHA. Leer `public.lf_operation_execution_steps` 11/11 y `public.lf_profile_execution_terminal_authority_receipt_v1(execution_id)`.
- Terminal solo si `RUN.status=COMPLETED`, `READY`, Step70 y Step80 acreditados, y reglas nueva/corregida realmente `VIGENTE` con readback exacto.
- Antinegativos: HMAC_TEST/MOCK, self-review, mismo chat o prompt, hash alterado, nonce replay, RUN ajeno, paso sin RAW, B01 MFA bypass, writer no oficial y callback no autorizado. Bloqueo en cualquiera => NO-GO.
- Sin autorización de la siguiente fase, NO ejecutar siquiera Paso 0.

## Resultado actual
PREPARADO_DOCUMENTAL_CON_CATALOGO_11_11; receptor desplegado y leído en ledger `20261113143831` (PR #3823, Train #43444580985), ruta R17 corregida en main por PR #3827 (Train #43457359558). Step70/G15 aún no adaptados; escritor/nonce oficial no conectado; chat GPT nuevo, 11/11, Step80, READY, VIGENTE = NOT_TESTED. No existe RUN elegible nuevo; nunca usar el RUN del Train como RUN de perfil.
