# L29 — MATRIZ HUMANA COMPLETA | 49 reglas reales, 2 códigos ausentes

**Fuente real sólo lectura:** `lf_ops.reglas` snapshot G SHA-256 `4959cfd6d9319ea26b60f9a21a1751c674e06c4417fb4d589f3665424d539bd3`; cotejado con copia PG18 por SQL en CI [#43340333844](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43340333844), job `131606765364`, **SUCCESS**.

**Matriz de before/after literal completo:** `07_login_b2b_matriz_diffs_51.json` contiene `antes.descripcion`, `antes.valor_config`, `despues.descripcion`, `despues.valor_config` y cada `diff_literal`. **Vueltas por código:** `08_login_b2b_vueltas_curator_51.json`, reconstrucción del algoritmo SQL verificada contra totales de CI. Los 49 registros fuente permanecieron inmutables.

## Resultado de vueltas reales del mini-Curator determinista

| Medida | Resultado |
|---|---:|
| Códigos solicitados | 51 |
| Registros reales en fuente | 49 |
| Faltantes no creados (009/010) | 2 |
| Candidatos originales | 40 |
| Vigentes originales | 9 |
| Evaluaciones SQL reales (49 + 4 revisados) | **53** |
| Devoluciones de primera vuelta | **4** |
| Reglas con segunda vuelta | **4** |
| ACEPTAR_PRELIMINAR_SANDBOX sin cambios/humano adicional | **23** |
| ESCALAR_A_HUMANO final (dueño/dependencia) | **26** |
| Sin fuente | 2 |
| Aprobaciones, promociones y firmas | **0** |

**Lectura correcta:** 23 reglas pasaron la comprobación documental determinista sin corrección o intervención humana *adicional*, pero **ninguna está habilitada para promoción oficial** sin firma, tests externos e integración nativa. Las 4 reglas corregidas llegaron a segunda vuelta y se detuvieron por decisiones/dependencias. Las 26 escaladas no se repiten automáticamente: hacerlo sin resolver dependencias sería una vuelta inútil.

## Matriz regla por regla

| Código real / esperado | Estado | Hallazgo | Diff literal | Vueltas | DEVOLVER | Curator final | Motivo de bloqueo específico |
|---|---|---|---|---:|---:|---|---|
| `AUTH-001` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-002` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/multi_company_physical_model_status |
| `AUTH-003` | VIGENTE | DEPENDENCIA_POLITICA_CENTRAL | Sin cambio | 1 | 0 | ESCALAR | EXT:POLICY_3_VIGENTE_REQUIRES_CANDIDATE_UPDATE_B07_OWNER_APPROVAL |
| `AUTH-004` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-005` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-006` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-007` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-008` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-011` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-012` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-013` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision; EXT:BINDING_PENDIENTE_/valor_config/selected_server_adapter; EXT:BINDING_PENDIENTE_/valor_config/brevo_webhook_runtime_status; EXT:BINDING_PENDIENTE_/valor_config/admin_identity_provider_status; EXT:BINDING_PENDIENTE_/valor_config/selected_server_adapter_status |
| `AUTH-014` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-015` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision; EXT:BINDING_PENDIENTE_/valor_config/identity_contract_status |
| `AUTH-016` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_selected; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-017` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-018` | CANDIDATO | CONTRADICCION_MFA_SIEMPRE; DUPLICACION_PERFILES_EN_CONFIG | /descripcion, /valor_config/covered_profile_ids, /valor_config/mfa_profile_coverage, /valor_config/mfa_required_outcome | 2 | 1 | ESCALAR | DUEÑO:OTROS_DISPARADORES_MFA_PENDIENTE; EXT:ACTUALIZACION_GOBERNADA_POLITICA_3; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-019` | CANDIDATO | DEPENDENCIA_FACTORES_SAML_SMS | /descripcion, /valor_config/sms_contingency_channel, /valor_config/sms_provider_status | 2 | 1 | ESCALAR | DUEÑO:PROVEEDOR_SMS_SIN_CONFIRMAR; DUEÑO:APLICABILIDAD_SMS_A_ADMIN_SAML_SIN_DEFINIR; EXT:GOOGLE_WORKSPACE_SAML_TENANT_METADATA_PRUEBAS; EXT:BREVO_CREDENCIALES_Y_QA; EXT:BINDING_PENDIENTE_/valor_config/admin_provider_status; EXT:BINDING_PENDIENTE_/valor_config/non_admin_delivery_provider_status |
| `AUTH-020` | CANDIDATO | VACIO_RECUPERACION_Q11; DEPENDENCIA_IMPL_Q11 | /descripcion, /valor_config/account_recovery_hold_source, /valor_config/email_access_recovery_status, /valor_config/non_admin_recovery_mode, /valor_config/previous_contact_notice | 2 | 1 | ESCALAR | DUEÑO:ALCANCE_Q11_SOPORTE_VS_ADMINS_GOOGLE_NO_CONFIRMADO; EXT:SOPORTE_DOBLE_CONTROL_DOCUMENTO_ALERTA_QA; EXT:POLITICA_20_CAMBIO_GOBERNADO; EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision; EXT:BINDING_PENDIENTE_/valor_config/non_admin_recovery_mode; EXT:BINDING_PENDIENTE_/valor_config/email_access_recovery_status |
| `AUTH-021` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-022` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-023` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-024` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-025` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-026` | CANDIDATO | DEPENDENCIA_IDENTIDAD | Sin cambio | 1 | 0 | ESCALAR | EXT:ADR003_SPIKE_M1_OIDC_PROVIDER_REAL; EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision; EXT:BINDING_PENDIENTE_/valor_config/local_identity_provider; EXT:BINDING_PENDIENTE_/valor_config/preferred_adapter_status; EXT:BINDING_PENDIENTE_/valor_config/brevo_webhook_runtime_status; EXT:BINDING_PENDIENTE_/valor_config/implementation_validation_status |
| `AUTH-027` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-028` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-029` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-030` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-031` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-032` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-033` | CANDIDATO | CONTRADICCION_DISPOSITIVO_VS_MFA_CONDICIONAL | /descripcion, /valor_config/recognized_device_outcome, /valor_config/second_control_trigger, /valor_config/unrecognized_device_outcome | 2 | 1 | ESCALAR | DUEÑO:OTROS_CASOS_MFA_DISPOSITIVO_NO_RECONOCIDO_PENDIENTE; EXT:POLITICA_25_DEVICE_ONLY_PENDIENTE_RECONCILIAR; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-034` | CANDIDATO | DEPENDENCIA_ROUTING_MFA | Sin cambio | 1 | 0 | ESCALAR | EXT:AUTH033_Y_POLITICA3; EXT:BREVO_ENTREGA_QA; EXT:BINDING_PENDIENTE_/valor_config/delivery_provider_status |
| `AUTH-035` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/provider_binding; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-036` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-037` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/delivery_provider_status |
| `AUTH-038` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-039` | VIGENTE | CONTRADICCION_POTENCIAL_REVOCACION_VS_OTROS_DISPARADORES | Sin cambio | 1 | 0 | ESCALAR | DUEÑO:REVOCACION_DISPOSITIVO_COMO_DISPARADOR_MFA_NO_CONFIRMADO; EXT:POLITICA_25_Y_REGISTRO_DISPOSITIVOS_QA |
| `AUTH-040` | CANDIDATO | DEPENDENCIA_DEVICE_TRUST | Sin cambio | 1 | 0 | ESCALAR | EXT:POLITICA_25_AJUSTE_QA |
| `AUTH-041` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-042` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-043` | CANDIDATO | DEPENDENCIA_RATE_LIMIT_NUEVOS_MFA | Sin cambio | 1 | 0 | ESCALAR | DUEÑO:ALCANCE_NUEVOS_DISPARADORES_MFA_PENDIENTE; EXT:OPERACION_RATE_LIMIT_Y_PANTALLA_PARA_30D_3M_QA |
| `AUTH-044` | CANDIDATO | DEPENDENCIA_BREVO | Sin cambio | 1 | 0 | ESCALAR | EXT:BREVO_TRANSACTIONAL_EMAIL_REAL_Y_WEBHOOK_QA; EXT:BINDING_PENDIENTE_/valor_config/credential_status |
| `AUTH-045` | CANDIDATO | DEPENDENCIA_WEBHOOK_BREVO | Sin cambio | 1 | 0 | ESCALAR | EXT:BREVO_WEBHOOK_FIRMADO_CALLBACK_TEST_QA; EXT:BINDING_PENDIENTE_/valor_config/secret_rotation_status |
| `AUTH-046` | VIGENTE | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-047` | CANDIDATO | DECISION_PENDIENTE_EN_ORIGEN | Sin cambio | 1 | 0 | ESCALAR | DUEÑO:PENDIENTE_DECISION_AUTH047_CAPS_LOCK; DUEÑO:PENDIENTE_DECISION_ORIGEN_B2B-RULE-AUTH-047 |
| `AUTH-048` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ESCALAR | EXT:BINDING_PENDIENTE_/valor_config/submit_target; EXT:BINDING_PENDIENTE_/valor_config/local_identity_decision |
| `AUTH-STATE-001` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `NAV-LEGAL-001` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `SECURITY-BASELINE-001` | CANDIDATO | SIN_CONTRADICCION_ESPECIFICA_DETECTADA | Sin cambio | 1 | 0 | ACEPTAR preliminar | Sin bloqueo específico detectado; firma y QA oficiales pendientes |
| `AUTH-009` | NO_ENCONTRADA | VACIO_NO_EXISTE_REGISTRO | Sin cambio | 0 | 0 | SIN FUENTE | EXT:FUENTE_FALTANTE_VERIFICAR_INVENTARIO_NO_CREAR_AUTOMATICAMENTE |
| `AUTH-010` | NO_ENCONTRADA | VACIO_NO_EXISTE_REGISTRO | Sin cambio | 0 | 0 | SIN FUENTE | EXT:FUENTE_FALTANTE_VERIFICAR_INVENTARIO_NO_CREAR_AUTOMATICAMENTE |

## Diffs completos de las cuatro correcciones de reglas (NO aprobados)

Los textos siguientes son las preimágenes literales de los registros consultados y sus propuestas; no se insertan en `lf_ops.reglas` ni se corrige producción. Las nueve fuentes VIGENTE permanecen sin cambio.

### `B2B-RULE-AUTH-018` · CONTRADICCION_MFA_SIEMPRE / DUPLICACION_PERFILES_EN_CONFIG

**ANTES — descripción literal del origen:**
> Cuando las credenciales primarias son válidas y la política MFA aplica al profile_id del usuario, LF_AUTH_BOUNDARY debe responder MFA_REQUIRED y detener la autenticación antes de crear una sesión plenamente autenticada. La política central exige MFA a los seis perfiles humanos actuales del Backoffice. Hasta completar satisfactoriamente MFA no se conceden permisos funcionales, no se considera AUTHENTICATED y el cliente no puede promover por sí mismo el estado de autenticación.

**DESPUÉS — descripción propuesta:**
> Cuando las credenciales primarias son válidas, LF_AUTH_BOUNDARY consulta la política central MFA para determinar si corresponde un desafío en este acceso. Sólo si la política exige MFA responde MFA_REQUIRED y bloquea la sesión operativa hasta verificar el factor. La cobertura de perfiles no equivale a exigir MFA en todos los accesos. Los umbrales y disparadores se conservan exclusivamente en la política central; otros disparadores siguen pendientes del dueño. Nunca se conceden permisos ni AUTHENTICATED antes de completar un MFA exigido.

**Diff exacto de `valor_config`/texto:**
- `/descripcion` **ANTES:** `"Cuando las credenciales primarias son válidas y la política MFA aplica al profile_id del usuario, LF_AUTH_BOUNDARY debe responder MFA_REQUIRED y detener la autenticación antes de crear una sesión plenamente autenticada. La política central exige MFA a los seis perfiles humanos actuales del Backoffice. Hasta completar satisfactoriamente MFA no se conceden permisos funcionales, no se considera AUTHENTICATED y el cliente no puede promover por sí mismo el estado de autenticación."` **DESPUÉS:** `"Cuando las credenciales primarias son válidas, LF_AUTH_BOUNDARY consulta la política central MFA para determinar si corresponde un desafío en este acceso. Sólo si la política exige MFA responde MFA_REQUIRED y bloquea la sesión operativa hasta verificar el factor. La cobertura de perfiles no equivale a exigir MFA en todos los accesos. Los umbrales y disparadores se conservan exclusivamente en la política central; otros disparadores siguen pendientes del dueño. Nunca se conceden permisos ni AUTHENTICATED antes de completar un MFA exigido."`
- `/valor_config/covered_profile_ids` **ANTES:** `[1,2,3,4,5,6]` **DESPUÉS:** `null`
- `/valor_config/mfa_profile_coverage` **ANTES:** `"ALL_HUMAN_PROFILES"` **DESPUÉS:** `"ELIGIBILITY_FROM_CENTRAL_POLICY_NOT_ALWAYS"`
- `/valor_config/mfa_required_outcome` **ANTES:** `"MFA_REQUIRED"` **DESPUÉS:** `"MFA_REQUIRED_WHEN_CENTRAL_POLICY_APPLIES"`

**Curator:** 1ª vuelta `DEVOLVER_CON_MOTIVO`, 2ª vuelta `ESCALAR_A_HUMANO`; corrección aplicada sólo a copia PG18. **Dueño pendiente:** OTROS_DISPARADORES_MFA_PENDIENTE. **Dependencias:** ACTUALIZACION_GOBERNADA_POLITICA_3, BINDING_PENDIENTE_/valor_config/local_identity_decision.

### `B2B-RULE-AUTH-019` · DEPENDENCIA_FACTORES_SAML_SMS

**ANTES — descripción literal del origen:**
> El Login no selecciona dinámicamente un canal de segundo factor fuera de la política central. Para profile_id 1 y 2 se mantiene Google Workspace mediante SAML 2.0 con requisito resistente a phishing. Para profile_id 3, 4, 5 y 6, el control aprobado es OTP por correo gestionado por LF y entregado mediante Brevo. La pantalla no conoce credenciales del proveedor y no debe declarar este correo OTP como Supabase native AAL2.

**DESPUÉS — descripción propuesta:**
> El Login no selecciona el segundo control fuera de la política central. Para los perfiles 1 y 2 se conserva Google Workspace SAML 2.0 con factor resistente a phishing; para los perfiles 3 a 6 el segundo control principal, cuando MFA aplique, es OTP por correo gestionado por LF y entregado mediante Brevo. SMS se contempla únicamente como contingencia; su proveedor no está confirmado y no se habilita hasta reconciliar contrato, autorización y seguridad. No hay fallback a contraseña sola ni afirmación de Supabase native AAL2 para el OTP por correo.

**Diff exacto de `valor_config`/texto:**
- `/descripcion` **ANTES:** `"El Login no selecciona dinámicamente un canal de segundo factor fuera de la política central. Para profile_id 1 y 2 se mantiene Google Workspace mediante SAML 2.0 con requisito resistente a phishing. Para profile_id 3, 4, 5 y 6, el control aprobado es OTP por correo gestionado por LF y entregado mediante Brevo. La pantalla no conoce credenciales del proveedor y no debe declarar este correo OTP como Supabase native AAL2."` **DESPUÉS:** `"El Login no selecciona el segundo control fuera de la política central. Para los perfiles 1 y 2 se conserva Google Workspace SAML 2.0 con factor resistente a phishing; para los perfiles 3 a 6 el segundo control principal, cuando MFA aplique, es OTP por correo gestionado por LF y entregado mediante Brevo. SMS se contempla únicamente como contingencia; su proveedor no está confirmado y no se habilita hasta reconciliar contrato, autorización y seguridad. No hay fallback a contraseña sola ni afirmación de Supabase native AAL2 para el OTP por correo."`
- `/valor_config/sms_contingency_channel` **ANTES:** `null` **DESPUÉS:** `"SMS_ONLY_IF_GOVERNED_FALLBACK"`
- `/valor_config/sms_provider_status` **ANTES:** `null` **DESPUÉS:** `"NOT_CONFIRMED_NO_BINDING"`

**Curator:** 1ª vuelta `DEVOLVER_CON_MOTIVO`, 2ª vuelta `ESCALAR_A_HUMANO`; corrección aplicada sólo a copia PG18. **Dueño pendiente:** PROVEEDOR_SMS_SIN_CONFIRMAR, APLICABILIDAD_SMS_A_ADMIN_SAML_SIN_DEFINIR. **Dependencias:** GOOGLE_WORKSPACE_SAML_TENANT_METADATA_PRUEBAS, BREVO_CREDENCIALES_Y_QA, BINDING_PENDIENTE_/valor_config/admin_provider_status, BINDING_PENDIENTE_/valor_config/non_admin_delivery_provider_status.

### `B2B-RULE-AUTH-020` · VACIO_RECUPERACION_Q11 / DEPENDENCIA_IMPL_Q11

**ANTES — descripción literal del origen:**
> Si un usuario sujeto al segundo control por correo pierde acceso a su correo, el Login no puede degradar a contraseña sola ni habilitar un bypass. Para perfiles no administradores, la recuperación de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y debe resolverse en flujo separado con validación de identidad y auditoría antes de producción. Para administradores la recuperación continúa en Google Workspace. Si se perdio el control del correo o existe sospecha de compromiso, reenviar un OTP al mismo buzon no aporta verificacion independiente. Para los perfiles no administradores debe aplicarse un procedimiento de identidad separado, auditable y aun PENDING_FUNCTIONAL_DEFINITION, bajo la politica central de recuperacion ID 20, sin autorizar acceso operativo ni bypass.

**DESPUÉS — descripción propuesta:**
> Ante pérdida del segundo control por correo, la cuenta no puede recuperar acceso por contraseña sola ni por OTP al mismo buzón comprometido. La recuperación asistida decidida en conversación se inicia por soporte, exige documento de identidad, control de dos personas, espera establecida en la política central de recuperación y notificación al contacto anterior. Debe ser auditable, con verificación de identidad y autorización server-side antes de revocar o reemplazar el factor. No crea sesión operativa durante el trámite. La relación de esta recuperación con perfiles administradores gestionados por Google Workspace requiere reconciliación de alcance antes de producción.

**Diff exacto de `valor_config`/texto:**
- `/descripcion` **ANTES:** `"Si un usuario sujeto al segundo control por correo pierde acceso a su correo, el Login no puede degradar a contraseña sola ni habilitar un bypass. Para perfiles no administradores, la recuperación de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y debe resolverse en flujo separado con validación de identidad y auditoría antes de producción. Para administradores la recuperación continúa en Google Workspace. Si se perdio el control del correo o existe sospecha de compromiso, reenviar un OTP al mismo buzon no aporta verificacion independiente. Para los perfiles no administradores debe aplicarse un procedimiento de identidad separado, auditable y aun PENDING_FUNCTIONAL_DEFINITION, bajo la politica central de recuperacion ID 20, sin autorizar acceso operativo ni bypass."` **DESPUÉS:** `"Ante pérdida del segundo control por correo, la cuenta no puede recuperar acceso por contraseña sola ni por OTP al mismo buzón comprometido. La recuperación asistida decidida en conversación se inicia por soporte, exige documento de identidad, control de dos personas, espera establecida en la política central de recuperación y notificación al contacto anterior. Debe ser auditable, con verificación de identidad y autorización server-side antes de revocar o reemplazar el factor. No crea sesión operativa durante el trámite. La relación de esta recuperación con perfiles administradores gestionados por Google Workspace requiere reconciliación de alcance antes de producción."`
- `/valor_config/account_recovery_hold_source` **ANTES:** `null` **DESPUÉS:** `"CENTRAL_SECURITY_POLICY_ID_20"`
- `/valor_config/email_access_recovery_status` **ANTES:** `"PENDING_FUNCTIONAL_DEFINITION"` **DESPUÉS:** `"OWNER_CONVERSATION_DECIDED_FORMAL_SIGNATURE_AND_IMPLEMENTATION_PENDING"`
- `/valor_config/non_admin_recovery_mode` **ANTES:** `"PENDING_FUNCTIONAL_DEFINITION_EMAIL_ACCESS_RECOVERY"` **DESPUÉS:** `"ASSISTED_SUPPORT_IDENTITY_DOCUMENT_TWO_PERSON_POLICY_HOLD"`
- `/valor_config/previous_contact_notice` **ANTES:** `null` **DESPUÉS:** `"REQUIRED"`

**Curator:** 1ª vuelta `DEVOLVER_CON_MOTIVO`, 2ª vuelta `ESCALAR_A_HUMANO`; corrección aplicada sólo a copia PG18. **Dueño pendiente:** ALCANCE_Q11_SOPORTE_VS_ADMINS_GOOGLE_NO_CONFIRMADO. **Dependencias:** SOPORTE_DOBLE_CONTROL_DOCUMENTO_ALERTA_QA, POLITICA_20_CAMBIO_GOBERNADO, BINDING_PENDIENTE_/valor_config/provider_binding, BINDING_PENDIENTE_/valor_config/local_identity_decision, BINDING_PENDIENTE_/valor_config/non_admin_recovery_mode, BINDING_PENDIENTE_/valor_config/email_access_recovery_status.

### `B2B-RULE-AUTH-033` · CONTRADICCION_DISPOSITIVO_VS_MFA_CONDICIONAL

**ANTES — descripción literal del origen:**
> Después de validar el primer factor, LF_AUTH_BOUNDARY evalúa del lado servidor si el dispositivo está reconocido conforme a SEC-B2B-TRUSTED-DEVICE. Para perfiles no administradores, un dispositivo reconocido continúa sin desafío OTP; un dispositivo no reconocido dirige a B2B-AUTH-004 y genera el segundo control OTP por correo según OTP_POL_B2B_AUTH_EMAIL_BREVO. El cliente no decide el reconocimiento del dispositivo, el factor, el proveedor ni el resultado de autenticación. La ruta B2B-AUTH-004 no es pública: authentication_required=true se interpreta como exigencia de un contexto MFA transitorio válido administrado por servidor, no como una sesión operativa completa; la navegación directa sin desafío se deniega.

**DESPUÉS — descripción propuesta:**
> Después del primer factor, LF_AUTH_BOUNDARY consulta del lado servidor la aplicabilidad del MFA en la política central antes de usar cualquier señal de dispositivo confiable. El dispositivo reconocido no puede omitir un MFA que la política central exige. Cuando corresponde MFA para perfiles no administradores, el desafío se realiza mediante contexto transitorio y OTP por correo; no se concede sesión operativa antes de verificarlo. El dispositivo no reconocido y otros posibles disparadores adicionales permanecen pendientes de decisión del dueño; esta propuesta no autoriza suprimir controles vigentes ni habilitar bypass. Cliente, navegación y cookies no deciden el estado.

**Diff exacto de `valor_config`/texto:**
- `/descripcion` **ANTES:** `"Después de validar el primer factor, LF_AUTH_BOUNDARY evalúa del lado servidor si el dispositivo está reconocido conforme a SEC-B2B-TRUSTED-DEVICE. Para perfiles no administradores, un dispositivo reconocido continúa sin desafío OTP; un dispositivo no reconocido dirige a B2B-AUTH-004 y genera el segundo control OTP por correo según OTP_POL_B2B_AUTH_EMAIL_BREVO. El cliente no decide el reconocimiento del dispositivo, el factor, el proveedor ni el resultado de autenticación. La ruta B2B-AUTH-004 no es pública: authentication_required=true se interpreta como exigencia de un contexto MFA transitorio válido administrado por servidor, no como una sesión operativa completa; la navegación directa sin desafío se deniega."` **DESPUÉS:** `"Después del primer factor, LF_AUTH_BOUNDARY consulta del lado servidor la aplicabilidad del MFA en la política central antes de usar cualquier señal de dispositivo confiable. El dispositivo reconocido no puede omitir un MFA que la política central exige. Cuando corresponde MFA para perfiles no administradores, el desafío se realiza mediante contexto transitorio y OTP por correo; no se concede sesión operativa antes de verificarlo. El dispositivo no reconocido y otros posibles disparadores adicionales permanecen pendientes de decisión del dueño; esta propuesta no autoriza suprimir controles vigentes ni habilitar bypass. Cliente, navegación y cookies no deciden el estado."`
- `/valor_config/recognized_device_outcome` **ANTES:** `"AUTHENTICATED"` **DESPUÉS:** `"CENTRAL_MFA_POLICY_RECHECK_BEFORE_AUTHENTICATED"`
- `/valor_config/second_control_trigger` **ANTES:** `"UNRECOGNIZED_DEVICE_ONLY"` **DESPUÉS:** `"CENTRAL_POLICY_WITH_OTHER_TRIGGERS_PENDING_OWNER"`
- `/valor_config/unrecognized_device_outcome` **ANTES:** `"MFA_REQUIRED"` **DESPUÉS:** `"MFA_REQUIRED_UNTIL_OTHER_CASES_RECONCILED"`

**Curator:** 1ª vuelta `DEVOLVER_CON_MOTIVO`, 2ª vuelta `ESCALAR_A_HUMANO`; corrección aplicada sólo a copia PG18. **Dueño pendiente:** OTROS_CASOS_MFA_DISPOSITIVO_NO_RECONOCIDO_PENDIENTE. **Dependencias:** POLITICA_25_DEVICE_ONLY_PENDIENTE_RECONCILIAR, BINDING_PENDIENTE_/valor_config/local_identity_decision.

## Políticas centrales — propuestas separadas de las reglas de pantalla

La decisión de **30 días sin uso**, **3 meses sin cambio de clave** y el plazo de recuperación de **48 horas** se propone exclusivamente en configuración de políticas, no en descripciones ni `valor_config` de AUTH-003/018/019/020/033. No se inventa proveedor SMS. Estas son propuestas de cambio a políticas existentes, nunca un nuevo alta de políticas.

### Política 3 — `SEC-B2B-MFA` (`VIGENTE` en origen)

**ANTES — descripción literal:**
> Requerir MFA a todos los perfiles humanos del Backoffice B2B definidos por profile_id numérico. La política determina aplicabilidad; las reglas de pantalla no duplican listas de perfiles ni parámetros del factor.

**DESPUÉS — descripción propuesta:**
> La política central MFA determina condicionalmente la necesidad del segundo control para perfiles humanos. Se exige MFA tras 30 días sin uso o 3 meses calendario sin cambio de clave según parámetros centrales configurables. Otros disparadores adicionales quedan pendientes de definición del dueño. La cobertura de perfiles no obliga desafío en cada acceso; no se permite acceso operativo si un MFA aplicable está pendiente.

**Diff literal del JSON de política:**
- `/description`: **antes** `"Requerir MFA a todos los perfiles humanos del Backoffice B2B definidos por profile_id numérico. La política determina aplicabilidad; las reglas de pantalla no duplican listas de perfiles ni parámetros del factor."` → **después** `"La política central MFA determina condicionalmente la necesidad del segundo control para perfiles humanos. Se exige MFA tras 30 días sin uso o 3 meses calendario sin cambio de clave según parámetros centrales configurables. Otros disparadores adicionales quedan pendientes de definición del dueño. La cobertura de perfiles no obliga desafío en cada acceso; no se permite acceso operativo si un MFA aplicable está pendiente."`
- `/policy_config/current_required_profile_ids`: **antes** `[1,2,3,4,5,6]` → **después** `null`
- `/policy_config/eligible_profile_ids`: **antes** `null` → **después** `[1,2,3,4,5,6]`
- `/policy_config/mfa_applicability_mode`: **antes** `null` → **después** `"CONDITIONAL"`
- `/policy_config/mfa_inactivity_trigger_days`: **antes** `null` → **después** `30`
- `/policy_config/mfa_password_unchanged_months`: **antes** `null` → **después** `3`
- `/policy_config/other_triggers_decision`: **antes** `null` → **después** `"PENDING_OWNER"`

**Bloqueos:** dueño = OTROS_DISPARADORES_MFA_PENDIENTE; externos = POLITICA_3_VIGENTE_SE_REQUIERE_SUCESORA_Y_QA. **Estado:** CANDIDATO documental, no firma ni promoción.

### Política 19 — `SEC-B2B-MFA-FACTOR-ELIGIBILITY` (`CANDIDATO` en origen)

**ANTES — descripción literal:**
> La politica central de factores define metodos por perfil. Los administradores requieren SSO Google Workspace SAML con control resistente a phishing. Los demas perfiles usan un segundo control LF de OTP por correo entregado con Brevo; debe verificarse del lado servidor antes del acceso operativo. No puede atribuirse a este OTP la garantia de AAL2 nativo del proveedor sin evidencia. Los bindings del proveedor de identidad permanecen pendientes de M1/ADR-003.

**DESPUÉS — descripción propuesta:**
> La politica central de factores define metodos por perfil. Los administradores requieren SSO Google Workspace SAML con control resistente a phishing. Los demas perfiles usan un segundo control LF de OTP por correo entregado con Brevo; debe verificarse del lado servidor antes del acceso operativo. No puede atribuirse a este OTP la garantia de AAL2 nativo del proveedor sin evidencia. Los bindings del proveedor de identidad permanecen pendientes de M1/ADR-003. El correo OTP de LF/Brevo se mantiene como principal para perfiles no administradores cuando corresponda MFA; SMS es exclusivamente contingencia con proveedor no confirmado. La aplicación de contingencia SMS a administradores Google SAML requiere conciliación.

**Diff literal del JSON de política:**
- `/description`: **antes** `"La politica central de factores define metodos por perfil. Los administradores requieren SSO Google Workspace SAML con control resistente a phishing. Los demas perfiles usan un segundo control LF de OTP por correo entregado con Brevo; debe verificarse del lado servidor antes del acceso operativo. No puede atribuirse a este OTP la garantia de AAL2 nativo del proveedor sin evidencia. Los bindings del proveedor de identidad permanecen pendientes de M1/ADR-003."` → **después** `"La politica central de factores define metodos por perfil. Los administradores requieren SSO Google Workspace SAML con control resistente a phishing. Los demas perfiles usan un segundo control LF de OTP por correo entregado con Brevo; debe verificarse del lado servidor antes del acceso operativo. No puede atribuirse a este OTP la garantia de AAL2 nativo del proveedor sin evidencia. Los bindings del proveedor de identidad permanecen pendientes de M1/ADR-003. El correo OTP de LF/Brevo se mantiene como principal para perfiles no administradores cuando corresponda MFA; SMS es exclusivamente contingencia con proveedor no confirmado. La aplicación de contingencia SMS a administradores Google SAML requiere conciliación."`
- `/policy_config/sms_contingency_channel`: **antes** `null` → **después** `"SMS"`
- `/policy_config/sms_contingency_only`: **antes** `null` → **después** `true`
- `/policy_config/sms_provider_status`: **antes** `null` → **después** `"NOT_CONFIRMED"`

**Bloqueos:** dueño = PROVEEDOR_SMS_PENDIENTE, SMS_CONTINGENCIA_EN_SAML_ADMIN_PENDIENTE; externos = GOOGLE_SAML_Y_BREVO_QA. **Estado:** CANDIDATO documental, no firma ni promoción.

### Política 20 — `SEC-B2B-MFA-RECOVERY` (`CANDIDATO` en origen)

**ANTES — descripción literal:**
> La recuperación del segundo control no puede convertirse en bypass. Para perfiles no administradores que usan OTP por correo, la contingencia por pérdida de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y bloquea producción de esa rama hasta definir validación de identidad y recuperación segura. Para administradores, la recuperación continúa delegada a Google Workspace. Cuando el mismo buzon recibe codigos para recuperar la contrasena y para el segundo control, controlar ese buzon no demuestra una segunda verificacion independiente de identidad. Ante sospecha o reporte de compromiso del correo, ningun codigo enviado a ese mismo canal puede justificar por si solo la recuperacion del factor o una sesion operativa. El procedimiento independiente y auditable para los perfiles no administradores permanece PENDING_FUNCTIONAL_DEFINITION. No se permite bypass ni degradacion a contrasena sola.

**DESPUÉS — descripción propuesta:**
> La recuperación del segundo control no puede convertirse en bypass. Para perfiles no administradores que usan OTP por correo, la contingencia por pérdida de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y bloquea producción de esa rama hasta definir validación de identidad y recuperación segura. Para administradores, la recuperación continúa delegada a Google Workspace. Cuando el mismo buzon recibe codigos para recuperar la contrasena y para el segundo control, controlar ese buzon no demuestra una segunda verificacion independiente de identidad. Ante sospecha o reporte de compromiso del correo, ningun codigo enviado a ese mismo canal puede justificar por si solo la recuperacion del factor o una sesion operativa. El procedimiento independiente y auditable para los perfiles no administradores permanece PENDING_FUNCTIONAL_DEFINITION. No se permite bypass ni degradacion a contrasena sola. La recuperación asistida decidida en conversación requiere solicitud por soporte, documento, control de dos personas, espera según parámetro central y aviso al contacto anterior. No habilita bypass; alcance de perfiles administradores pendiente de reconciliar.

**Diff literal del JSON de política:**
- `/description`: **antes** `"La recuperación del segundo control no puede convertirse en bypass. Para perfiles no administradores que usan OTP por correo, la contingencia por pérdida de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y bloquea producción de esa rama hasta definir validación de identidad y recuperación segura. Para administradores, la recuperación continúa delegada a Google Workspace. Cuando el mismo buzon recibe codigos para recuperar la contrasena y para el segundo control, controlar ese buzon no demuestra una segunda verificacion independiente de identidad. Ante sospecha o reporte de compromiso del correo, ningun codigo enviado a ese mismo canal puede justificar por si solo la recuperacion del factor o una sesion operativa. El procedimiento independiente y auditable para los perfiles no administradores permanece PENDING_FUNCTIONAL_DEFINITION. No se permite bypass ni degradacion a contrasena sola."` → **después** `"La recuperación del segundo control no puede convertirse en bypass. Para perfiles no administradores que usan OTP por correo, la contingencia por pérdida de acceso al correo queda PENDING_FUNCTIONAL_DEFINITION y bloquea producción de esa rama hasta definir validación de identidad y recuperación segura. Para administradores, la recuperación continúa delegada a Google Workspace. Cuando el mismo buzon recibe codigos para recuperar la contrasena y para el segundo control, controlar ese buzon no demuestra una segunda verificacion independiente de identidad. Ante sospecha o reporte de compromiso del correo, ningun codigo enviado a ese mismo canal puede justificar por si solo la recuperacion del factor o una sesion operativa. El procedimiento independiente y auditable para los perfiles no administradores permanece PENDING_FUNCTIONAL_DEFINITION. No se permite bypass ni degradacion a contrasena sola. La recuperación asistida decidida en conversación requiere solicitud por soporte, documento, control de dos personas, espera según parámetro central y aviso al contacto anterior. No habilita bypass; alcance de perfiles administradores pendiente de reconciliar."`
- `/policy_config/assisted_recovery_support`: **antes** `null` → **después** `true`
- `/policy_config/assisted_recovery_wait_hours`: **antes** `null` → **después** `48`
- `/policy_config/identity_document_required`: **antes** `null` → **después** `true`
- `/policy_config/previous_contact_notification`: **antes** `null` → **después** `"REQUIRED"`
- `/policy_config/recovery_document_spec`: **antes** `null` → **después** `"PENDING_IMPLEMENTATION_SPEC"`
- `/policy_config/two_person_approval_required`: **antes** `null` → **después** `true`

**Bloqueos:** dueño = ALCANCE_SOPORTE_VS_GOOGLE_ADMIN_PENDIENTE; externos = SOPORTE_2_PERSONAS_DOCUMENTO_48_HORAS_QA. **Estado:** CANDIDATO documental, no firma ni promoción.

### Política 25 — `SEC-B2B-TRUSTED-DEVICE` (`CANDIDATO` en origen)

**ANTES — descripción literal:**
> Control de dispositivo confiable para Backoffice Empresa. El OTP por correo se solicita únicamente cuando el login proviene de un dispositivo no reconocido. La duración de confianza es configurable por empresa y no puede ser permanente.

**DESPUÉS — descripción propuesta:**
> Control de dispositivo confiable para Backoffice Empresa. El OTP por correo se solicita únicamente cuando el login proviene de un dispositivo no reconocido. La duración de confianza es configurable por empresa y no puede ser permanente. El reconocimiento de dispositivo no puede sustituir los disparadores MFA exigidos por la política central; otros casos ligados a dispositivo no reconocido se someten a decisión posterior del dueño.

**Diff literal del JSON de política:**
- `/description`: **antes** `"Control de dispositivo confiable para Backoffice Empresa. El OTP por correo se solicita únicamente cuando el login proviene de un dispositivo no reconocido. La duración de confianza es configurable por empresa y no puede ser permanente."` → **después** `"Control de dispositivo confiable para Backoffice Empresa. El OTP por correo se solicita únicamente cuando el login proviene de un dispositivo no reconocido. La duración de confianza es configurable por empresa y no puede ser permanente. El reconocimiento de dispositivo no puede sustituir los disparadores MFA exigidos por la política central; otros casos ligados a dispositivo no reconocido se someten a decisión posterior del dueño."`
- `/policy_config/second_control_trigger`: **antes** `"UNRECOGNIZED_DEVICE_ONLY"` → **después** `"CENTRAL_MFA_POLICY_REQUIRED__OTHER_DEVICE_TRIGGERS_PENDING_OWNER"`

**Bloqueos:** dueño = OTROS_CASOS_DEVICE_TRUST_MFA_PENDIENTE; externos = REENLACE_CONFIG_25_MFA_QA. **Estado:** CANDIDATO documental, no firma ni promoción.

## Contradicciones y precauciones no resueltas

- **AUTH-003** VIGENTE delega umbrales a política 3. No cambiar ni insertar 30/3 en la regla. La política 3 VIGENTE no contiene esos parámetros; su modificación requiere sucesora gobernada y firma formal.
- **AUTH-018** CANDIDATO obliga MFA a seis perfiles; el dueño decidió MFA condicional. Primera devolución corregida en copia.
- **AUTH-033** CANDIDATO y política 25 basan el desafío en dispositivo no reconocido; no pueden cancelar disparadores de 30d/3m. Si dispositivo no reconocido o revocado será otro disparador requiere decisión pendiente del dueño. **No retirar controles VIGENTE** para simular una corrección.
- **AUTH-019** conserva Google Workspace SAML para perfiles 1-2 y OTP correo Brevo para 3-6. SMS es sólo contingencia sin proveedor confirmado, y su uso en administradores SAML requiere revisión.
- **AUTH-020** distingue recuperación de factor con soporte/documento/dos personas/espera central/aviso anterior de reinicio de contraseña por correo (AUTH-028..031 y 037). No introducir bypass ni trasladar aceptación del dueño a una firma formal.
- **AUTH-039** VIGENTE exige OTP ante revocación. El efecto como disparador adicional no fue expresamente confirmado: sin alteración de fuente; bloqueo antes de una propuesta de sucesora.
- **AUTH-047** pendiente_decision=true en origen, permanece escalada.
- **AUTH-009/010** no tienen fila. No se inventan códigos, políticas ni reglas nuevas por ausencia en el rango.
- **Duplicidades exactas:** 0 pares en las 49 filas según igualdad de descripción normalizada + JSON de config. **No equivale a certificación semántica de no duplicidad.**

**Estado final de gobierno:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA para Q11 y MFA; 0 firmas, 0 aprobaciones, 0 promociones; 0/14 bloqueos cerrados. Curator SQL mismo modelo GPT-6 y JWT real no utilizado: **NO-GO / UNVERIFIED**.
