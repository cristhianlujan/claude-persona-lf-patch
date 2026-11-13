# Enmienda candidata B09/G12 y G15-MOTOR — sin aplicar
Estado: ACEPTACION_DOCUMENTAL_EN_CONVERSACION; identity_verified=false; NO_GO vigente.
Decisor declarado: Cristhian Luján. Hora declarada: 13-nov-2026, 08:31 America/Lima (sin segundos autenticados).
Origen de esta aceptación: mandato del dueño en conversación; no constan JWT/MFA/firma criptográfica humana ni recibo oficial de autorización de ejecución.
Ámbito: Motor Input Governance en Supabase temporal. No autoriza producción, DML live ni alterar RUN históricos.

## 1. Fuentes / criterio literal (sin reinterpretar retrospectivamente)
- L28 doc12: `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md` en `lf/issue-3779-lote28-blocker-closure-plan-v1`.
- B09/G12 literalmente exige: "RUN **nuevo** de perfil por ruta EKB ACT-0001→Gate2→Perfil→RUN→IG/Curator/Validator→proveedor nativo genuino→Step70/juez independiente con recibo verificable→escritor oficial niño 7/7→promoción/corrección de regla→Step80 oficial→11/11 pasos `STEP_PASS_WITH_EVIDENCE`, RUN `COMPLETED`, terminal `READY` y VIGENTE/readback exactos."
- L21 `audits/rule-quality-lote21/04_go_no_go_firmable.md`: G15 exige literalmente: "Dossier y todos los recibos actuales; signoff NO delega ejecución; futuro cambio debe tener operación gobernada separada y rollback."
- SQL activo: `public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)` exige `CRYPTOGRAPHICALLY_VERIFIED`, `producer_independence_proven=true` y `PASS_INDEPENDENT_SEMANTIC` para el perfil con efectos. No lo modifica este PR.
- `public.lf_ig_g15_motor_temporary_v1(jsonb)` exige siete recibos del Motor y devuelve NO_GO si no están firmados auténticamente. No lo modifica este PR.

## 2. Decisión documental recibida del dueño
Aceptar, solo para la base temporal, un ejecutor de chat nuevo GPT_NATIVE dentro de ChatGPT, sin API keys, y un juez como componente versionado de instrucciones del mismo LLM, preferiblemente en un segundo chat separado. Reemplazar Ed25519/JWKS/attester externo por verificación SHA-256 sobre recibos encadenados, bajo autoridad del escritor oficial. Esta aceptación NO acredita firma humana autenticada, autenticidad técnica del proveedor, independencia de modelo ni disponibilidad de un writer vinculado.

## 3. Texto propuesto para modificación futura del criterio B09/G12
"Para el E2E temporal de Input Governance se admite ejecutar GPT nativo mediante conversación nueva, preservando el RAW íntegro de entrada y salida, referencias de chat, versión y SHA-256 exacto de ambos prompts, hash de candidato y alcance, nonce de un solo uso reservado por un escritor oficial y cadena SHA-256 de recibos. Se admite un juez del mismo LLM exclusivamente como COMPONENTE DE INSTRUCCIONES CON SEPARACIÓN LÓGICA en chat diferente del productor y con prompt SHA distinto; está prohibido declarar `model_independence_proven=true` o autenticidad criptográfica del proveedor. Cada vínculo requiere readback del escritor canónico con permisos deny-by-default, antirreplay y evidencia RAW; el SHA por sí solo no acredita autoría. Se mantienen 11/11 pasos limpios, Step70 y Step80 oficiales, 2 casos (nueva/corregida), cierre RUN COMPLETED, terminal READY, VIGENTE y readback exactos, sin bypass de Login/MFA. Si falta cualquier binding/autorización o recibo, resultado BLOCKED/NO-GO."

## 4. Texto propuesto para futura modificación G15-MOTOR
"El dueño acepta DOCUMENTALMENTE el riesgo residual de juez del mismo modelo y SHA-256 sin Ed25519/JWKS para el Motor de la base temporal; identidad humana verificada=false. No se reconoce firma de proveedor, independencia de modelo ni confianza por URL de chat. Antes de un eventual GO_MOTOR_LIMITADO deberán existir siete recibos verificados B02/B03/B06/B07/B08/B09/B12, autoridad del escritor único, pruebas positivas y negativas con invariantes, nonce/idempotencia, cadena SHA, rollback y evidencia del perfil ejecutado. G15 original sigue exigiendo autorización posterior gobernada separada; producción y base final siguen NO-GO."

## 5. Transición técnica gobernada pendiente (NO incluida en esta migración)
1. PR lector únicamente: tabla append-only de recibos y `lf_ig_verified_native_provider_receipt_v1(text)`, retornando `SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED`; no `CRYPTOGRAPHICALLY_VERIFIED`.
2. PR posterior distinto: conectar **registrador oficial existente** `lf_record_profile_execution_step_v1` o bridge gobernado que resulte del readback de autoridad, sin introducir escritor paralelo, registrar nonce autoritativo y acreditar su receipt mediante fuente independiente.
3. Otro cambio de contrato Step70: aceptar solo el nuevo estado explícito de riesgo y `PASS_SEMANTIC_COMPENSATED_SAME_MODEL`, con SHA + writer autenticado y pruebas negativas. **No permitir pasar `producer_independence_proven=true` falsamente**; no relajar ruta read-only ni B01.
4. Cambio separado y firmado de G15-MOTOR: evaluar 7 recibos de Motor, no convertir la sola aceptación del riesgo en GO.
5. Merge Train para cada SQL nuevo, con PASE/R17/clasificación PASS, preimagen, exact-head, apply, ledger readback y rollback. Nunca hacer merge directo ni dar `ready-to-merge` a un PR que todavía no puede desplegarse.

## 6. Fronteras, riesgo residual y estado
- **SHA-256:** demuestra correspondencia de bytes bajo un hash confiable; no identidad del emisor. Control compensatorio: GitHub/OIDC/ACL del registrador ya establecido, registro append-only, SHA de writer receipt, nonce único por RUN, idempotencia y readback.
- **Mismo modelo:** errores correlacionados y prompt injection. Controles: chat distinto, prompt distinto hashado, test adversarial, juez por ítem con evidencias y fallo ante RAW ausente.
- **Origen de chat:** referencia URL no acredita plataforma ni inmutabilidad. Mantener `vendor_model_provenance_verified=false` hasta evidencia independiente.
- **Riesgo de efectos:** no emitir autoridad de escritura desde verificador; el permiso procede exclusivamente del recorder oficial.
- **Estado de cierre:** B09 ABIERTO, G15-MOTOR NO_GO, producción NO_GO. Solo se registra aceptación documental del riesgo, no la firma autenticada exigida por el gate vigente.
