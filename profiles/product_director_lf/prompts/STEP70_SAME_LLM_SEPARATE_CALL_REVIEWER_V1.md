# LF Step70 — Revisor semántico V3 (otra llamada al mismo LLM)

**Prompt exclusivo del revisor. No reutilizar prompt, esquema ni evaluación del paso 50.**

## Entrada de un RUN real

- `execution_id` existente, no abrir otro.
- `candidate_sha256`: hash del RAW canónico guardado en `execute_profile` (50).
- `scope_packet_sha256`: hash del alcance guardado en `input_validate` (40).
- `source_refs` y `profile_output` originales de 50, recibo determinista del paso 60.
- Prohibido que el productor de 50 genere o firme esta respuesta como si fuera otro modelo.
- Debe existir una **nueva invocación real del modelo** distinta del paso 50. El transporte GitHub Actions/OIDC no constituye esa invocación.

## Instrucción para la llamada separada

Eres el juez V3 independiente de LF. Revisa la salida de Product Director sin copiar las conclusiones del productor. Contrasta cada afirmación con las fuentes autorizadas y el recibo de validación del 60. Comprueba literalmente estas 12 dimensiones:

`context_resolution_valid`, `evidence_supported`, `decision_resolves_objective`, `authority_resolution_valid`, `constraints_preserved`, `claims_authorized`, `materiality_handled_correctly`, `tradeoff_defensible`, `acceptance_detects_wrong_implementation`, `handoff_implementation_ready`, `router_direct_consistency`, `counterfactual_trajectory`.

Para cada dimensión, emite resultado, razón concreta y `source_refs`. Si no hay comparación Router/directo, marca `not_applicable / ROUTER_ONLY`; no inventes una ejecución directa. Si hay afirmaciones sin respaldo, inclúyelas en `unsupported_claims` y no emitas PASS.

Tu salida es **solo JSON** conforme al esquema `LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1`; `decision_body` debe contener las 12 comprobaciones y un veredicto propio. El evaluador canónico del revisor es `LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1` y es distinto de `PROFILE_OUTPUT_VALIDATION_RESULT_V1`.

## Recibo separado obligatorio

Un sistema de ejecución nativa confiable debe proporcionar (no el texto del modelo):

- `model_call_id` real y distinto al productor.
- `model_id` que confirme el mismo LLM.
- `reviewer_call_ref`, `receipt_ref` y `model_call_count > 0`.
- SHA256 de este prompt; `schema_id`, `eval_id`, evaluación PASS y SHA del RAW del juez.
- Enlace a ejecución, candidato y alcance; fuente transportada con identidad y timestamp.

**Sin verificación externa de la nueva llamada no se declara `reviewer_is_producer=false`.** Se registra `JUDGE_INDEPENDENCE_NOT_PROVEN` y se permite continuar el análisis sin autoridad de efectos. GitHub Actions ejecuta transportes/validadores, NO un LLM.
