# B09/G12–G15: Step70 y G15 admiten vía documental SHA condicionada — fase 1

Estado: **CANDIDATO**, NO GO, fuente: EKB V1.4, enmienda documental B09/G12–G15 de 2026-11-13, criterio de dueño mismo LLM + SHA sin Ed25519. Identidad humana verificada=false. No equivale a firma de proveedor, independencia del modelo ni autorización de efectos.

## Decisión técnica

- No se cambia el camino original `PASS_INDEPENDENT_SEMANTIC` para otras rutas ni la revisión `CURRENT_CONTEXT_REVIEW` estrictamente solo-lectura.
- Exclusivamente `EJECUCION_PERFIL_LF` + `PERFIL-PRODUCT-DIRECTOR-LF` + GPT_NATIVE/OPENAI_CHATGPT_NATIVE permite **candidato** `PASS_SEMANTIC_COMPENSATED_SAME_MODEL` con `review_mode=SAME_LLM_SEPARATE_CHAT`, juez de chat y prompt diferentes, `producer_independence_proven=false`, `reviewer_model_independence_proven=false`, `vendor_model_provenance_verified=false`, `effect_authority=false`. `model_call_count=1` es declaración de la ruta, **no atestación**.
- El Step70 consulta `lf_ig_verified_native_provider_receipt_v1` y exige un recibo separado `lf_ig_native_chat_official_writer_binding_receipt_v1(text)` con cadena SHA y nonce **anclados al escritor canónico / OIDC**. Ese binding no lo instala esta fase; sin él retorna `LF_STEP70_SHA_OFFICIAL_WRITER_BINDING_MISSING`, sin mutar pasos.
- Se preservan los 11 pasos y el registrador `lf_record_profile_execution_step_v1`. La etapa Step70 no declara que el juez sea independiente, ni emite `CRYPTOGRAPHICALLY_VERIFIED`.
- G15 sigue **`NO_GO_MOTOR` en todos los casos**. Solo si 7 recibos con forma declarada y B09 realmente vinculado por OIDC/nonce podrá informar `b09_documental_accepted=true`, sin firmar los otros seis bloqueos ni autorizar producción.
- Rollback manual restaura fuentes exactas Step70 MD5 `78cb1b8fab6975f4539a79baa2ab11fd`, G15 MD5 `eb1779e3d958d26d56a20f22ed717235`. Bloquea inversa si existe un recibo semántico compensado durable.
- Nunca escribir en Supabase fuera del Merge Train y nunca usar RUN histórico para probar el B09 real.

## Dependencias antes de permitir un Step70 real

1. PR gobernado diferente para registrar nonce servidor y cadena con recibo validado por `lf-profiles-governance-caller-v1` en OIDC. El oficial `lf_record_profile_execution_step_v1` conserva exclusividad de los pasos. No usar `INSERT` directo para evidencias.
2. `lf_profile_execution_trust_validation_v2` y `lf_profile_execution_terminal_authority_receipt_v1` aún reconocen solo `PASS_INDEPENDENT_SEMANTIC` y `PASS_REVIEWED_CURRENT_CONTEXT`: requieren enmienda gobernada separada con negativos, sin falsear independencia.
3. `supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts` exige `read_only/no_write/no_promotion=true` y acepta solo el veredicto independiente o current context. Se requiere actualización de la ruta OIDC del runtime del perfil, sin abrir una ruta paralela ni eliminar `repair_execution_authority`.
4. B02/B03/B06/B07/B08/B12 y G15 continúan NO-GO. La aceptación documental B09 no los desbloquea.

## Evidencia exigida

PG17.6 y PG18.7 con matriz: preflight MD5, ACL negativa, B09 sin writer bloqueado, falsedad de independencia bloqueada, HMAC/self-review bloqueados, G15 sin 7/7 NO-GO, G15 7/7 declarados sin firma NO-GO, rollback exacto; 0 cambio de RUN histórico. `PASS` únicamente para pruebas ejecutadas. No se ha iniciado el E2E.
