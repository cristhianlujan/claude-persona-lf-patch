# LF Step70 — lectura actual y contrato de independencia del owner (14-11-2026)

## Autoridad y fuente

EKB INPUT GOVERNANCE LF V1.4: un RUN único, pasos canónicos 0→80,
paso 70 con V3, evidencia/hash/identidad persistidos. Nunca atribuir
independencia a `CURRENT_CONTEXT_REVIEW`; no inventar recibos o llamadas.

## Qué se verificó con SELECT (sandbox `mhwmirqcgxxukpctffuv`)

- `pg_proc.prosrc` de `public.lf_profile_native_bridge_prepare_v1`:
  `position('SEMANTIC_SELECTION_REQUIRED' in prosrc)=0`.
- `pg_proc.prosrc` de `public.lf_profile_execution_input_validate_v1`:
  `position('SEMANTIC_SELECTION_REQUIRED' in prosrc)=0`.
- No es una compatibilidad vigente de esas funciones ni un olvido demostrable
  en su código desplegado. La referencia anterior no coincide con el SELECT
  actual. No modificar ambas funciones por una coincidencia inexistente.

## Dónde está el hallazgo

- Tabla: `public.lf_profile_semantic_independence_finding_v1`.
- Columnas: `execution_id`, `finding_code` =
  `JUDGE_INDEPENDENCE_NOT_PROVEN`, `independence_status` =
  `NOT_PROVEN`, `step70_sha256`, `step80_sha256`,
  `original_step70_ref`, `original_step80_ref`.
- Se insertaron 3 hallazgos por PR #3938, migración
  `20261114203100`, vinculados a los RUN 0248912F, 15B9 y C506.
- Los `evidence_payload` canónicos de pasos 70 y 80 anteriores siguen
  inmutables. **No** contienen `content_findings`, ni recibo
  independiente. Esto no se presenta como reejecución de pasos históricos.
- Vista nueva `public.v_lf_profile_step70_independence_readback_v1`:
  une los hashes de los pasos con el hallazgo append-only y expone
  `combined_findings`; `original_evidence_payload` sigue intacto.

## Contrato del dueño para futura independencia real

Se admitirá como independencia lógica una **segunda llamada real al mismo
LLM** con su propio `model_call_id`, prompt, schema_id
`LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1`, eval_id
`LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1`, contenido de decisión, recibo,
`model_call_count>0`, candidato y alcance idénticos, todos distintos
de los equivalentes del productor en 50. El schema/eval fueron implementados.

La prueba estructural NO acredita sola el modelo llamado. GitHub OIDC
acredita el transporte, **no** la invocación LLM. Si el host de ChatGPT
no proporciona una atestación verificable de esa nueva llamada,
el SQL responde `RECEIPT_FORMAT_VALID_MODEL_CALL_NOT_ATTESTED`;
el runner nunca construye `model_call_count=1` ni marca
`reviewer_is_producer=false` desde una afirmación del propio modelo.
Conservar `CURRENT_CONTEXT_REVIEW` y el hallazgo sin bloquear la
salida de contenido bajo autorización READ_ONLY.

## E2E sin Issue

Ruta ya desplegada en #3938: `workflow_dispatch` /
`begin-native-profile` → verificación de Gate2 exacto → GitHub OIDC →
Edge `profile_native_begin_from_context_v1` → RUN único.
La existencia del YAML y las pruebas de contrato no acreditan por sí
mismas una invocación `workflow_dispatch` real, ni un recibo terminal.
El readback debe asociar un GitHub run del evento `workflow_dispatch`
a un nuevo `execution_id` y a los pasos registrados por SELECT.
