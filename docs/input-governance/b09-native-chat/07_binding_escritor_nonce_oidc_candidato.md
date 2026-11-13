# B09 — DRAFT binding oficial OIDC/nonce sin escritor paralelo

Estado: CANDIDATO NO DESPLEGADO / NO_GO. Dependencia #3829 (Step70/G15 DRAFT). No se autoriza promoción, producción, RUN histórico ni E2E real. Este PR no certifica PG dual.

## Ruta canónica verificada
EKB V1.4: ACT-0001 → Gate2 → PERFIL-PRODUCT-DIRECTOR-LF → EJECUCION_PERFIL_LF → pasos oficiales. La única ruta de transporte sigue siendo GitHub Issue etiquetada 'lf-profile-resume-governed' → Actions OIDC → 'lf-profiles-governance-caller-v1' → 'profile_continuation.ts' → **registrador canónico existente** 'public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'. No se crea Edge Function, cola ni RPC de escritura en paralelo. El nuevo branch dentro del recorder emite nonce y registra eventos; las operaciones de los 11 pasos preservan llamada existente a trust-validation y operation-step-core.

## Contrato candidato
1. Solicitud 'LF_PROFILE_NATIVE_B09_WRITER_REQUEST_V1' modo 'ISSUE_NONCE', RUN nuevo real y SHA-256 de candidato, scope y prompt productor. El usuario NO envía ni inventa nonce.
2. GitHub OIDC verifica issuer/audience/repo/ref/workflow/run_id antes de pasar al actor; Edge NO acepta '_verified_oidc' del body y exige RUN 'IN_PROGRESS', perfil/provider GPT_NATIVE exactos, read_only/no_write/no_promotion.
3. El registrador canónico valida actor y elegibilidad, reserva nonce aleatorio inmutable y único por RUN y liga 3 SHA + workflow OIDC; TTL 24 horas.
4. Modo 'APPEND_EVENT': RAW exacto REQUEST(1), EXECUTOR(2), JUDGE(3) con nonce/candidato/scope/prompt SHA y referencias declaradas de chat. Únicamente el registrador canónico puede INSERTAR en tabla append-only del receptor. Secuencia, hash y recibo de escritor se calculan en servidor; replay y cross-RUN bloquean.
5. El lector 'lf_ig_native_chat_official_writer_binding_receipt_v1(text)' verifica 3/3, nonce, TTL, hashes del escritor y cadena SHA y responde 'OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND'; el receptor original conserva 'SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED'.
6. No se declara 'CRYPTOGRAPHICALLY_VERIFIED', 'PASS_INDEPENDENT_SEMANTIC', independencia de modelo, firma humana ni autoridad de efectos. G15 sigue 'NO_GO_MOTOR'.
7. **Cambio sensible:** la función canónica pasa de SECURITY INVOKER a SECURITY DEFINER para INSERT controlado en tablas con DML revocado. Requiere revisión de seguridad/regresiones de todos los pasos antes de aprobación. Rollback bloquea si existen recibos durables; sin borrado automático.
8. **Datos:** una GitHub Issue pública no es un canal seguro para PII, secretos ni RAW de usuarios reales. Primer ensayo exclusivamente sintético y sin PII. No introducir canal alternativo para sortearlo.

## Dependencias no cerradas
- #3829 tiene 4/4 CI PASS sobre HEAD exacto pero DRAFT/sin Train. Migración B09-binding tiene preflight fail-closed hasta Step70/G15 desplegados; escritor canónico MD5 vivo congelado en 7cf717887006e278356a716f3fd80182.
- Trust validator 'lf_profile_execution_trust_validation_v2', terminal Step80 y Edge consumidor de semantic_judge_review siguen exigiendo cambios gobernados para admitir 'PASS_SEMANTIC_COMPENSATED_SAME_MODEL'. Binding por sí solo NO habilita 11/11 ni VIGENTE.
- PG dual y E2E del segundo PR = NOT_TESTED, hasta prueba real; los tests estáticos no constituyen readback SQL.

## Caso corto primer RUN real (DIFERIDO)
1. Releer catálogo, contratos y autorización, confirmar #3829/binding y consumidores trust/terminal desplegados por Train, elegir regla sintética no MFA en sandbox.
2. Chat GPT productor nuevo: bytes exactos de 'prompts/B09_EXECUTOR_GPT_NATIVE_V1.txt', SHA-256 47ec11c44e859a0da5e93a5541c7a0959a0526efd9fcabfce24a66936a8dc66f.
3. ACT-0001 → Gate2 válido → PERFIL-PRODUCT-DIRECTOR-LF → Issue 'LF_PROFILE_NATIVE_BEGIN_REQUEST_V1' con etiqueta 'lf-profile-resume-governed'; leer execution_id NUEVO.
4. Emitir nonce por 'LF_PROFILE_NATIVE_B09_WRITER_REQUEST_V1/ISSUE_NONCE' en ruta OIDC; registrar REQUEST(1) con SHA exactos del candidato y scope.
5. Ejecutar GPT_NATIVE, conservar RAW íntegro y registrar EXECUTOR(2), chat_ref y SHA original del prompt, sin pretender atestación del proveedor.
6. Chat juez diferente: bytes exactos de 'prompts/B09_JUEZ_MISMO_LLM_V1.txt', SHA-256 c895c6f5bc36074545d9c9094651e7099e6a23d3a399b37a32d0c029baee065f; registrar JUDGE(3) con chat_ref diferente.
7. Leer SHA receipt+nonce binding, exigir evidencia documental con falsos explícitos para independencia/firmas; Step70 y Step80 solo si gate de confianza y autoridad está aprobado.
8. Verificar 11/11, RUN COMPLETED, terminal READY; cambio/VIGENTE de regla es operación aparte. Ante bloqueo: NO_GO y readback exacto; NO ejecutar E2E en este lote.
