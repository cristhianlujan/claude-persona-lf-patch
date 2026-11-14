# Step 50 autónomo — candidato DRAFT (NO desplegado)
## Diagnóstico (8 líneas)
1. Paso 10 Router selecciona perfil y transporta Gate2; no debe resolver IG.
2. Paso 40 `input_validate` gobierna IG como dependencia/skill del perfil.
3. Paso 45 `context_admission` debe registrar recibo verificado.
4. Paso 47 `research_baseline_freeze` debe registrar su baseline.
5. `lf_profile_native_bridge_prepare_v1` exige 7/7 y entrega `NATIVE_MODEL_INPUT_READY`.
6. Antes: Edge devuelve handoff al chat/Issue; no invoca un modelo.
7. Enganche: en `profile_native_continue_v1` tras el READY y antes del branch de `profile_output` manual.
8. Paso 50 se registra exclusivamente por `lf_profile_native_bridge_record_output_v1` → `lf_record_profile_execution_step_v1`; paso 60 queda en el bridge existente.

## Diseño ejecutable propuesto (sin pasos/gates nuevos)
- Fuente: Edge existente `lf-profiles-governance-caller-v1/profile_continuation.ts`, bajo OIDC ya autorizado.
- Disparo: `NATIVE_MODEL_INPUT_READY` exacto; nunca ante 45/47 incompletos; llama `executeStep50Automatically` automáticamente si `LF_PROFILE_STEP50_AUTO=true`.
- Modelo/producer real: OpenAI Responses API (model ID de secreto `LF_PROFILE_STEP50_OPENAI_MODEL`); **no confundir API con firma de ChatGPT nativo**. No simular `native_model_call_receipt`.
- Entrada: SKILL.md desde GitHub `source_revision` SHA40 y SHA256 verificado + solicitud + recibos IG/contexto/baseline.
- Validación: se exige servicio de validador canónico fuente-bound con `PROFILE_OUTPUT_VALIDATION_RESULT_V1`, errores vacíos y SHA-256 literal; sin servicio el flujo BLOQUEA, no emite PASS.
- Registro: la Edge llama al bridge existente `lf_profile_native_bridge_record_output_v1` con resultado real y `evidence_ref` de API/validador; **no escribe directamente en tablas ni crea otro registrador**.
- Trazabilidad futura: descarta `step50_status` y `governed_step50_executed` autorreferenciales; añade producer `OPENAI_RESPONSES_API` y model_response_id reales. El estado verdadero sale de `lf_operation_execution_steps`; RUN histórico 40471... intacto.
- Router: migración candidata con guards md5 elimina `profile_task_intent`/`input_governance_requirement` del binding; `lf_profile_input_governance_requirement_v1` consulta vínculo de skill del PERFIL en paso 40. Default seguro para perfil con vínculo: IG REQUIRED.
- Los flujos especiales de lectura `READ_PRODUCT_DEFINITION` deben revalidarse contra esta política antes de cualquier integración: no declarar equivalencia de skip IG sin evidencia.

## Prueba y límite
- El test anexado al runner existente inicia Docker PostgreSQL 17.6 y 18.7, inserta **RUN simulado 0/10/20/30/40/45/47/50/60/70/80**, obtiene `step_order|step_id|STEP_PASS_WITH_EVIDENCE` y hace `ROLLBACK`; **no ejecuta el writer canónico ni llama modelo**.
- La prueba de PG en CI y la revisión de respuesta de modelo son independientes: un PASS del fixture no demuestra perfil automático completo.
- No se desplegó Edge; no se hizo SQL vivo; no se modificó ni cerró RUN existente; no se autoriza merge/Train sin revisar regresiones del Router y configurar productor/validador.
