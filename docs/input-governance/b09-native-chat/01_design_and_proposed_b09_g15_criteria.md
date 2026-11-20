# B09 / G15 — E2E ChatGPT nativo por SHA y escritor oficial (DISEÑO CANDIDATO)
**Estado:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA (dueño: Cristhian Luján), NO IMPLEMENTADA, NO-GO.
**Fecha del diseño:** 2026-11-13. **Ámbito:** Supabase temporal; NO producción ni modificación de RUN existentes.
**Rama de trabajo:** lf/issue-3779-b09-native-chat-sha-design-v1. Ningún SQL de este paquete va a supabase/migrations/.

## 0. Fuentes leídas (y distinciones)
- EKB "INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4": ACT-0001→Gate2→perfil→RUN→IG si aplica→validador→juez→registro→cierre; 11 pasos y recibo terminal READY. Prohíbe rutas IG paralelas, no permite cambiar fuentes oficiales sin autorización ni inferir PASS.
- L28 doc12 en rama `lf/issue-3779-lote28-blocker-closure-plan-v1`: `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md`. **B09 está etiquetado G12, no G15**.
- L21 criterio G15: `audits/rule-quality-lote21/04_go_no_go_firmable.md` en rama L28: "Dossier y todos los recibos actuales; signoff NO delega ejecución; futuro cambio debe tener operación gobernada separada y rollback".
- L28 G15-MOTOR temporal: `audits/rule-quality-lote28/09_spec_candidata_g15_motor.md`: B02, B03, B06, B07, B08, B09 y B12 (7/7).
- SQL desplegado `supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql`: `lf_ig_g15_motor_temporary_v1` devuelve NO_GO si faltan siete y también NO_GO con siete declarados no autenticados.
- SQL histórico #3807 en commit `97c963aeccb6aff03fef8bc15906d7ec1fce58a3`: Step70 `lf_profile_native_bridge_record_semantic_v1` deniega CURRENT_CONTEXT_REVIEW/HMAC_TEST/MOCK, exige `lf_ig_verified_native_provider_receipt_v1(text)` y status `CRYPTOGRAPHICALLY_VERIFIED`. El SQL aplicado fue consumido por Merge Train. **No se cambia aquí**.
- La descripción de #3807 detalla proveedor, attester Ed25519/JWKS, vinculación RUN/nonce, juez acreditado y verificador ausentes. Son **condiciones de la implementación propuesta de #3807**, no texto literal de B09 del doc12.

## 1. Decisión del dueño en conversación (NO firma autenticada)
- Proveedor/executor: conversación nueva GPT nativa. Sin API keys ni credenciales externas.
- Juez: mismo LLM con **componente de instrucciones versionado**, no modelo distinto.
- SHA-256 sobre recibos ya existe como mecanismo de integridad. Un digest NO equivale a firma electrónica ni autenticación.
- Riesgo de misma familia de modelo y autenticidad operacional limitada debe ser **aceptado explícitamente** por el dueño antes de cualquier cambio a Step70/G15.
- No hay autorización para promover reglas ni escribir datos Supabase en este lote. El cambio de requisitos sería otro PR gobernado.

## 2. Comparación exigencia → alternativa mínima (NO sustituye contrato vigente)
| Exigencia actual | Resultado con decisión nativa sola | Alternativa mínima propuesta sin credenciales externas | Evidencia necesaria |
|---|---|---|---|
| Modelo/proveedor GPT_NATIVE/CLAUDE_NATIVE genuino | Propuesto; sesión real no ejecutada aquí | Chat nuevo desde ChatGPT nativo; usuario facilita enlace y export RAW íntegro, sin declarar procedencia criptográficamente atestada | chat_ref, transcript SHA256, versión del prompt, input/output literal y prueba de origen disponible |
| Juez distinto del productor | NO cumple independencia de modelo | Separación de contexto/rol (segundo chat GPT para juez, mismo LLM) e instrucciones inmutables con SHA; autoevaluación mismo chat falla | juez_prompt_sha256, juez_chat_ref distinto, revisión de evidencia original, matriz 12 controles, fallo ante evidencia ausente |
| Ed25519/JWKS/issuer/aud | NO cumple | SHA-256 por evento y cadena vinculada al RUN + sello del **escritor oficial existente** y registro append-only protegido por ACL/GitHub OIDC/branch protection cuando esté acreditado | hash pre/post, writer receipt oficial, actor técnico acreditado por ruta, repositorio/commit verificado; no decir "firma Ed25519" |
| Antirreplay de firmante | NO cumple con SHA | nonce aleatorio emitido y reservado **por el servidor/escritor oficial** + unique(RUN,evento), unique(nonce REQUEST), idempotency key, TTL/estado y bloqueo de reuso | prueba de doble envío, cross-RUN, nonce repetido y stale hash; la restricción en PG aislado NO demuestra emisor seguro |
| RPC `lf_ig_verified_native_provider_receipt_v1(text)` | NO instalado | Función lectora candidata, invocable solo por service_role y sin privilegio DML; **estado SHA_CHAIN_INTACT_NATIVE_PROVENANCE_UNATTESTED**, sin conceder efecto | DDL y test Docker PG17.6/PG18.7; migración oficial separada si se acepta el riesgo |
| 11/11 + Step80 + terminal READY, VIGENTE | NO probado | Mantener perfil, escritores canónicos, rollback, verificación por paso y readback nativo; no escribir antes de autorización | execution_id nuevo, 11 step receipts, Step70, Step80, terminal authority receipt y reglas nueva/corregida |
| G15 7/7 autenticado | NO cumplido | Riesgo residual explícito, recibos de los siete bloqueos, dueño con conformidad atribuida documentalmente y futuro mecanismo autenticado; no simular autenticación humana | B02/B03/B06/B07/B08/B09/B12 con pruebas, hashes y recepción; aprobación separada |

## 3. Riesgos y mitigaciones que sí son evaluables
1. **Autenticidad**: un atacante con control de escritura puede sustituir datos y todos los SHA a la vez. Mitigar con único escritor oficial, ACL deny by default, idempotencia, recibo técnico firmado por infraestructura ya existente (si existe) y anclaje de hash en commit GitHub protegido. No asumir que GitHub SHA o campo actor textual autentican a la persona.
2. **Juez mismo LLM**: errores correlacionados, sesgo hacia su respuesta, omisiones compartidas y prompt injection. Mitigar con componente/versión SHAs, contexto separado, pruebas adversariales con control negativo, no exponer dictamen productor como verdad, criterios deterministas por campo y evidencia RAW. Declarar `SAME_MODEL_LOGICAL_SEPARATION`, nunca `MODEL_INDEPENDENCE_PROVEN`.
3. **Replay**: un digest válido puede copiarse; mitigación parcial con nonce único, vinculación execution_id+scope_sha+candidate_sha+prompt_sha+stage, unicidad transaccional y caducidad. El fixture testea unicidad, **no** emisión genuina.
4. **Proveniencia de chat**: enlace de chat o captura es una declaración, no un recibo del proveedor. Mitigar con export RAW y SHA anclado, custodia, referencia, fecha verificable y control externo de procedencia si se dispone; en ausencia, `vendor_model_provenance_verified=false`.
5. **Rollback/retención**: no borrar recibos reales. El inverso candidato bloquea si hay filas. Test elimina únicamente fixtures en Docker desechable para verificar inverso.
6. **Confusión de seguridad**: aunque SHA válido, no emitir `CRYPTOGRAPHICALLY_VERIFIED`; Step70 desplegado bloqueará. Una adaptación normativa y técnica gobernada separada sería indispensable para reconocer una aceptación de riesgo distinta.

## 4. Especificación de prueba del candidato (NO receptor oficial)
- Fuentes: `sandbox/lf_contract_gate_test/input_governance_lifecycle/b09_native_chat_sha_receiver_candidate_v1.sql` y `rollback_b09_native_chat_sha_receiver_candidate_v1.sql`.
- **Aislamiento**: CREATE TABLE y FUNCTION sólo en contenedores Docker PG17.6/PG18.7 desechables. Inserts directos del fixture **no prueban el escritor oficial**, ni Supabase/ChatGPT reales.
- Cada evento contiene `execution_id,seq,kind,raw_text,raw_sha256,prev_sha256,chain_sha256,writer_receipt_ref,writer_receipt_sha256`.
- `raw_sha256=SHA256(UTF8(raw_text))`; `chain_sha256=SHA256(UTF8("LF_NATIVE_CHAT_EVENT_V1|execution_id|seq|kind|raw_sha256|prev_sha256|writer_receipt_sha256"))`. Primer prev=64 ceros. RAW en JSON con bytes preservados, entrada/candidato/scope/nonce en las tres etapas.
- Secuencia exacta REQUEST→EXECUTOR→JUDGE; hash vinculado al RUN; referencias de chats diferentes, prompt juez SHA. No permite inferir autenticidad de URLs ni independencia de modelo.
- ACL de lectura función solo `service_role`; tabla sin DML a `service_role`, `anon` o `authenticated`. La futura integración debe usar **el registrador oficial**, nunca un writer agregado por esta prueba.
- Veredicto positivo **integridad únicamente**: `SHA_CHAIN_INTACT_NATIVE_PROVENANCE_UNATTESTED`. Campos `writer_identity_verified=false`, `vendor_model_provenance_verified=false`, `reviewer_independence_proven=false`, `effect_authority=false`.
- Negativos previstos: RAW alterado, hash de enlace alterado, etapa faltante, mismo chat como juez, nonce duplicado cross-RUN, rol sin permisos, inserción no autorizada, rollback con datos, segundo rollback, RUN inexistente.

## 5. TEXTO DE AJUSTE PARA FIRMA DEL DUEÑO — PROPUESTA, NO APLICAR
> **B09_E2E / G12 — Sustitución limitada a Motor LF en base temporal.** Se permite acreditar ejecución de proveedor nativo mediante conversación nueva en ChatGPT, con prompt versionado, entrada y salida RAW preservadas, referencia de sesión y digest SHA-256 vinculados a un RUN nuevo y alcance exacto. El juez podrá usar el mismo modelo como componente de instrucciones con contexto separado, prompt versionado y comprobación de criterios/evidencias, reconociendo expresamente que no hay independencia de modelo ni firma de procedencia del proveedor. La integridad se verificará mediante cadena SHA-256, nonce servidor único, idempotencia, escritor canónico y readback independiente del productor. La autenticidad operacional solo podrá afirmarse hasta el nivel efectivamente acreditado por ACL, autoridad del escritor y anclaje de recibos. Se conserva ACT-0001→Gate2→Perfil→RUN→IG→Curator/Validator→Step70→Step80→11/11→COMPLETED→READY y pruebas positivas/negativas de regla nueva y corregida, con B01 Login fail-closed. Sin evidencia de cualquiera de esos hitos, B09 seguirá ABIERTO.

> **G15-MOTOR (7/7) — Aceptación de riesgo limitada.** El dueño podrá aceptar específicamente, para la base temporal, el riesgo residual de no usar Ed25519/JWKS/proveedor API y de juez del mismo LLM, siempre que consten controles compensatorios verificables, siete recibos válidos del Motor, evidencia RAW, hashes, control de acceso, pruebas antirreplay, idempotencia, rollback y readback. La decisión se registrará como `RISK_ACCEPTED_DOCUMENTAL_PENDING_AUTHENTICATED_SIGNATURE` hasta la firma formal. No se convierte un SHA en firma, no se declara independencia criptográfica ni se autoriza producción, pagos, MFA, reglas de contenido o despliegue final. **El contrato de Step70 y G15 vigente continúa fail-closed hasta otro cambio oficialmente gobernado, revisado, aprobado y desplegado.** Una aceptación documental no libera ejecutores.

## 6. Plantilla de decisión del dueño (VACÍA, no rellenar)
- Veredicto: [ACEPTA_RIESGO / AJUSTAR / RECHAZAR] — **pendiente**
- Frase literal del dueño: [pendiente]
- Fecha/hora y referencia de conversación: [pendiente]
- Paquete SHA256 y HEAD: [pendiente]
- Identidad humana autenticada: **NO ACREDITADA** (B08 temporal documental)
- Firma/recibo de autoridad: **PENDIENTE**
- Scope: sólo Motor IG temporal. Motor 0/7 y producción NO-GO.
- Si acepta, siguiente operación: **nuevo PR separado** de contratos, Step70 y registrador oficial; no se presume autorizado ahora.

## 7. Evidencia y cierre
- PASS únicamente de logs ejecutados por CI sobre el HEAD exacto.
- SQL aislado PG no significa E2E ChatGPT, proveedor genuino, receptor oficial desplegado o GO.
- RUN E2E real con chat nuevo: **NOT_TESTED**, hasta ejecutar instrucción exacta y readbacks.
- Supabase: **0 DML / DDL en este lote**; historial intacto; producción NO-GO.
