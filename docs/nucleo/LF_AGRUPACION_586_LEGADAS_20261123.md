# LF — Agrupación auditable de 586 legadas

Corte read-only 23/11/2026 Lima. **586/586 etiquetadas**, 46 familias, 150 asignaciones familiares con validación pendiente. Semántica: MIGRAR = sin bloqueo explícito de decisión, familia ni binding; FALTA_MIGRAR = familia por validar; PAULO = pendiente literal menciona binding/runtime/Paulo; DECISION = pendiente_decision; CUBIERTA solo con relación de cobertura verificada (ninguna hoy). Etiquetas operativas, **no validación semántica individual**.

**Resultado:** CUBIERTA **0**, MIGRAR **354**, FALTA_MIGRAR **106**, PAULO **3**, DECISION **123**. **Cobertura certificada 0/586 = 0,00%**. Se detectaron **71 IDs** legados referenciados en `origen.ref` de reglas publicadas (73 enlaces), **12,12% de procedencia documentada, NO cobertura funcional certificada**. Las 57 publicadas existentes no se suman sin vínculo validado. Inventario fila por fila: `docs/nucleo/LF_INVENTARIO_586_LEGADAS_20261123.csv`.

## Familias

| Familia | Total | MIGRAR | FALTA | PAULO | DECISION |
|---|---:|---:|---:|---:|---:|
| SECURITY | 82 | 72 | 0 | 1 | 9 |
| PAYMENTS_CHECKOUT | 61 | 42 | 4 | 0 | 15 |
| TRANSITIONS | 55 | 32 | 1 | 0 | 22 |
| OFFERS_INSTALLMENTS | 53 | 14 | 27 | 0 | 12 |
| B2B_PORTFOLIO_LOADS | 27 | 3 | 12 | 0 | 12 |
| LEGAL_CONSENT | 26 | 15 | 0 | 0 | 11 |
| LOADING_EMPTY_ERROR_STATES | 21 | 16 | 5 | 0 | 0 |
| STATES | 20 | 9 | 9 | 1 | 1 |
| B2B_PARTNERS | 19 | 0 | 17 | 0 | 2 |
| GOVERNANCE_APPROVAL | 18 | 17 | 0 | 0 | 1 |
| UI_MESSAGES | 16 | 14 | 1 | 0 | 1 |
| ANALYTICS | 16 | 16 | 0 | 0 | 0 |
| FINANCIAL_INTEGRITY_RECONCILIATION | 16 | 0 | 6 | 0 | 10 |
| MFA_OTP_SSO | 15 | 3 | 7 | 0 | 5 |
| OBSERVABILITY | 15 | 15 | 0 | 0 | 0 |
| ACCESSIBILITY | 10 | 10 | 0 | 0 | 0 |
| RATE_LIMIT | 8 | 8 | 0 | 0 | 0 |
| NOTIFICATIONS_DELIVERY | 8 | 7 | 0 | 0 | 1 |
| DOMAIN_LIFECYCLE | 8 | 0 | 3 | 0 | 5 |
| ROUTING_NAVIGATION | 8 | 7 | 0 | 0 | 1 |
| SESSION | 7 | 7 | 0 | 0 | 0 |
| AUDIT | 7 | 7 | 0 | 0 | 0 |
| API_DATA_CONTRACT | 7 | 6 | 1 | 0 | 0 |
| VALIDATIONS | 5 | 4 | 0 | 0 | 1 |
| EXPERIMENTS_AB | 5 | 5 | 0 | 0 | 0 |
| FIELDS | 5 | 0 | 4 | 0 | 1 |
| DASHBOARD_REPORTING | 5 | 0 | 2 | 0 | 3 |
| COMMERCIAL_CAMPAIGNS | 5 | 0 | 2 | 0 | 3 |
| HEATMAP_SESSION_RECORDING | 4 | 4 | 0 | 0 | 0 |
| ERRORS | 4 | 4 | 0 | 0 | 0 |
| THEME_LIGHT_DARK_SYSTEM | 3 | 2 | 0 | 0 | 1 |
| RESPONSIVE | 3 | 3 | 0 | 0 | 0 |
| PERMISSIONS | 3 | 1 | 0 | 0 | 2 |
| DOCUMENTS_CERTIFICATES | 3 | 0 | 1 | 0 | 2 |
| FEATURE_FLAGS | 2 | 0 | 1 | 0 | 1 |
| INTEGRATIONS_WEBHOOKS | 2 | 0 | 2 | 0 | 0 |
| DESIGN_SYSTEM | 2 | 2 | 0 | 0 | 0 |
| TIMEOUT_RETRY | 2 | 2 | 0 | 0 | 0 |
| SCHEDULED_PROCESSES | 2 | 0 | 1 | 0 | 1 |
| RUNTIME_CONFIG | 2 | 2 | 0 | 0 | 0 |
| PRIVACY_PII | 1 | 1 | 0 | 0 | 0 |
| PERFORMANCE | 1 | 1 | 0 | 0 | 0 |
| ASSETS_ICONS | 1 | 1 | 0 | 0 | 0 |
| DATA_RETENTION | 1 | 1 | 0 | 0 | 0 |
| BROWSER_PLATFORM | 1 | 0 | 0 | 1 | 0 |
| TESTING_OBLIGATIONS | 1 | 1 | 0 | 0 | 0 |

## Agrupación transversal por similitud de títulos (propuesta, revisar contenido antes de fusionar)

| Familia + grupo preliminar | Cantidad | Arreglo común sugerido |
|---|---:|---|
| OFFERS_INSTALLMENTS/OFERTAS_CUOTAS | 27 | Modalidad seleccionada, quote, intento real |
| SECURITY/OTP_MFA | 24 | Intento + violación; límites compartidos lf_global_config |
| TRANSITIONS/OTROS_LEER_DESCRIPCION | 23 | Lectura semántica obligatoria; no asumir cobertura |
| PAYMENTS_CHECKOUT/OTROS_LEER_DESCRIPCION | 22 | Lectura semántica obligatoria; no asumir cobertura |
| SECURITY/OTROS_LEER_DESCRIPCION | 20 | Lectura semántica obligatoria; no asumir cobertura |
| TRANSITIONS/OFERTAS_CUOTAS | 18 | Modalidad seleccionada, quote, intento real |
| LEGAL_CONSENT/OTROS_LEER_DESCRIPCION | 16 | Lectura semántica obligatoria; no asumir cobertura |
| SECURITY/PII_CREDENCIALES | 16 | No exponer PII/secretos, validar hecho y canal |
| PAYMENTS_CHECKOUT/PAGOS_PRECIO | 14 | Precios configurables, estado autoritativo e idempotencia |
| GOVERNANCE_APPROVAL/OTROS_LEER_DESCRIPCION | 13 | Lectura semántica obligatoria; no asumir cobertura |
| ANALYTICS/OTROS_LEER_DESCRIPCION | 11 | Lectura semántica obligatoria; no asumir cobertura |
| OFFERS_INSTALLMENTS/OTROS_LEER_DESCRIPCION | 11 | Lectura semántica obligatoria; no asumir cobertura |
| STATES/OTROS_LEER_DESCRIPCION | 10 | Lectura semántica obligatoria; no asumir cobertura |
| B2B_PORTFOLIO_LOADS/OTROS_LEER_DESCRIPCION | 10 | Lectura semántica obligatoria; no asumir cobertura |
| B2B_PARTNERS/OTROS_LEER_DESCRIPCION | 10 | Lectura semántica obligatoria; no asumir cobertura |
| PAYMENTS_CHECKOUT/OFERTAS_CUOTAS | 10 | Modalidad seleccionada, quote, intento real |
| OFFERS_INSTALLMENTS/PAGOS_PRECIO | 9 | Precios configurables, estado autoritativo e idempotencia |
| ACCESSIBILITY/OTROS_LEER_DESCRIPCION | 8 | Lectura semántica obligatoria; no asumir cobertura |
| B2B_PORTFOLIO_LOADS/OFERTAS_CUOTAS | 8 | Modalidad seleccionada, quote, intento real |
| LOADING_EMPTY_ERROR_STATES/UI_MENSAJES | 7 | Distinguir render, navegación y acción |
| STATES/ESTADOS_TRANSICIONES | 7 | Hecho de transición separado del intento |
| PAYMENTS_CHECKOUT/UI_MENSAJES | 7 | Distinguir render, navegación y acción |
| LEGAL_CONSENT/CONSENTIMIENTO | 6 | Evidencia de consentimiento con versión y fecha |
| OBSERVABILITY/OTROS_LEER_DESCRIPCION | 6 | Lectura semántica obligatoria; no asumir cobertura |
| UI_MESSAGES/OFERTAS_CUOTAS | 6 | Modalidad seleccionada, quote, intento real |
| SECURITY/AUTORIZACION | 6 | Validación server-side de permisos, recurso y empresa |
| DOMAIN_LIFECYCLE/ESTADOS_TRANSICIONES | 6 | Hecho de transición separado del intento |
| MFA_OTP_SSO/OTROS_LEER_DESCRIPCION | 5 | Lectura semántica obligatoria; no asumir cobertura |
| SESSION/PII_CREDENCIALES | 5 | No exponer PII/secretos, validar hecho y canal |
| FINANCIAL_INTEGRITY_RECONCILIATION/PAGOS_PRECIO | 5 | Precios configurables, estado autoritativo e idempotencia |
| FIELDS/OTROS_LEER_DESCRIPCION | 5 | Lectura semántica obligatoria; no asumir cobertura |
| DASHBOARD_REPORTING/OTROS_LEER_DESCRIPCION | 5 | Lectura semántica obligatoria; no asumir cobertura |
| MFA_OTP_SSO/PII_CREDENCIALES | 5 | No exponer PII/secretos, validar hecho y canal |
| B2B_PORTFOLIO_LOADS/CARGAS_ARCHIVOS | 5 | Tipo/MIME/plantilla/checksum y seguridad, límites parametrizados |
| UI_MESSAGES/OTROS_LEER_DESCRIPCION | 4 | Lectura semántica obligatoria; no asumir cobertura |
| SECURITY/PARAMETROS_LIMITES | 4 | Parámetros y ventanas en lf_global_config |
| RATE_LIMIT/OTP_MFA | 4 | Intento + violación; límites compartidos lf_global_config |
| TRANSITIONS/PII_CREDENCIALES | 4 | No exponer PII/secretos, validar hecho y canal |
| EXPERIMENTS_AB/OTROS_LEER_DESCRIPCION | 4 | Lectura semántica obligatoria; no asumir cobertura |
| SECURITY/NO_ENUMERAR | 4 | Respuestas indistinguibles ante existencia o estado de cuenta |
| B2B_PARTNERS/OFERTAS_CUOTAS | 4 | Modalidad seleccionada, quote, intento real |
| NOTIFICATIONS_DELIVERY/OTROS_LEER_DESCRIPCION | 4 | Lectura semántica obligatoria; no asumir cobertura |
| PAYMENTS_CHECKOUT/AUTORIZACION | 4 | Validación server-side de permisos, recurso y empresa |
| FINANCIAL_INTEGRITY_RECONCILIATION/OTROS_LEER_DESCRIPCION | 4 | Lectura semántica obligatoria; no asumir cobertura |
| TRANSITIONS/PAGOS_PRECIO | 4 | Precios configurables, estado autoritativo e idempotencia |
| ROUTING_NAVIGATION/OTROS_LEER_DESCRIPCION | 4 | Lectura semántica obligatoria; no asumir cobertura |
| AUDIT/TELEMETRIA | 3 | Excluir PII y secretos de logs |
| VALIDATIONS/PII_CREDENCIALES | 3 | No exponer PII/secretos, validar hecho y canal |
| ANALYTICS/UI_MENSAJES | 3 | Distinguir render, navegación y acción |
| LOADING_EMPTY_ERROR_STATES/OTROS_LEER_DESCRIPCION | 3 | Lectura semántica obligatoria; no asumir cobertura |
| LOADING_EMPTY_ERROR_STATES/PII_CREDENCIALES | 3 | No exponer PII/secretos, validar hecho y canal |
| LOADING_EMPTY_ERROR_STATES/OFERTAS_CUOTAS | 3 | Modalidad seleccionada, quote, intento real |
| API_DATA_CONTRACT/INTEGRACIONES | 3 | Validación de frontera y respuesta normalizada |
| THEME_LIGHT_DARK_SYSTEM/OTROS_LEER_DESCRIPCION | 3 | Lectura semántica obligatoria; no asumir cobertura |
| RESPONSIVE/OTROS_LEER_DESCRIPCION | 3 | Lectura semántica obligatoria; no asumir cobertura |
| PERMISSIONS/AUTORIZACION | 3 | Validación server-side de permisos, recurso y empresa |
| MFA_OTP_SSO/OTP_MFA | 3 | Intento + violación; límites compartidos lf_global_config |
| DOCUMENTS_CERTIFICATES/ESTADOS_TRANSICIONES | 3 | Hecho de transición separado del intento |
| UI_MESSAGES/OTP_MFA | 2 | Intento + violación; límites compartidos lf_global_config |
| RATE_LIMIT/PARAMETROS_LIMITES | 2 | Parámetros y ventanas en lf_global_config |
| TRANSITIONS/ESTADOS_TRANSICIONES | 2 | Hecho de transición separado del intento |
| TRANSITIONS/OTP_MFA | 2 | Intento + violación; límites compartidos lf_global_config |
| AUDIT/OTROS_LEER_DESCRIPCION | 2 | Lectura semántica obligatoria; no asumir cobertura |
| VALIDATIONS/OTROS_LEER_DESCRIPCION | 2 | Lectura semántica obligatoria; no asumir cobertura |
| OBSERVABILITY/UI_MENSAJES | 2 | Distinguir render, navegación y acción |
| OBSERVABILITY/OTP_MFA | 2 | Intento + violación; límites compartidos lf_global_config |
| HEATMAP_SESSION_RECORDING/OTROS_LEER_DESCRIPCION | 2 | Lectura semántica obligatoria; no asumir cobertura |
| OBSERVABILITY/INTEGRACIONES | 2 | Validación de frontera y respuesta normalizada |
| FINANCIAL_INTEGRITY_RECONCILIATION/OFERTAS_CUOTAS | 2 | Modalidad seleccionada, quote, intento real |
| STATES/OFERTAS_CUOTAS | 2 | Modalidad seleccionada, quote, intento real |
| PAYMENTS_CHECKOUT/ESTADOS_TRANSICIONES | 2 | Hecho de transición separado del intento |
| API_DATA_CONTRACT/OTROS_LEER_DESCRIPCION | 2 | Lectura semántica obligatoria; no asumir cobertura |
| B2B_PARTNERS/CONSENTIMIENTO | 2 | Evidencia de consentimiento con versión y fecha |
| UI_MESSAGES/PAGOS_PRECIO | 2 | Precios configurables, estado autoritativo e idempotencia |
| OFFERS_INSTALLMENTS/ESTADOS_TRANSICIONES | 2 | Hecho de transición separado del intento |
| FINANCIAL_INTEGRITY_RECONCILIATION/ESTADOS_TRANSICIONES | 2 | Hecho de transición separado del intento |
| LEGAL_CONSENT/CARGAS_ARCHIVOS | 2 | Tipo/MIME/plantilla/checksum y seguridad, límites parametrizados |
| ERRORS/UI_MENSAJES | 2 | Distinguir render, navegación y acción |
| ERRORS/TELEMETRIA | 2 | Excluir PII y secretos de logs |
| SECURITY/TELEMETRIA | 2 | Excluir PII y secretos de logs |
| GOVERNANCE_APPROVAL/AUTORIZACION | 2 | Validación server-side de permisos, recurso y empresa |
| COMMERCIAL_CAMPAIGNS/OTROS_LEER_DESCRIPCION | 2 | Lectura semántica obligatoria; no asumir cobertura |
| FINANCIAL_INTEGRITY_RECONCILIATION/AUTORIZACION | 2 | Validación server-side de permisos, recurso y empresa |
| ROUTING_NAVIGATION/AUTORIZACION | 2 | Validación server-side de permisos, recurso y empresa |
| B2B_PORTFOLIO_LOADS/CONSENTIMIENTO | 2 | Evidencia de consentimiento con versión y fecha |

## Estructura de cobertura — propuesta, NO creada

`nucleo_reglas.regla_legacy_id` soporta un único enlace y está NULL en las 58 reglas. Propongo tabla puente `lf_ops.nucleo_cobertura_legada`: `legacy_id` FK, `nucleo_codigo` FK, `nucleo_version`, `tipo` TOTAL/PARCIAL/COMPARTIDA, `estado` PROPUESTA/VERIFICADA/RECHAZADA, `evidencia_ref`, `hash_paquete`, `criterio`, `revisado_por`, `revisado_en`, PK (legacy_id,nucleo_codigo,nucleo_version). Ningún origen textual crea cobertura VERIFICADA automáticamente.

## Prioridad, por MIGRAR real

1. SECURITY: **73 MIGRAR / 82** legadas; prioridad por OTP, PII, seguridad transversal.
2. PAYMENTS_CHECKOUT: **42 / 61**, riesgo de pagos e idempotencia.
3. TRANSITIONS: **32 / 55**, estados y transiciones.
4. GOVERNANCE_APPROVAL: **17 / 18**, autorización.
5. LOADING_EMPTY_ERROR_STATES: **16 / 21** y ANALYTICS **16 / 16**.

Primer piloto: SECURITY `S1-C01`, legada `REG_SEG_004` id 22; excluye IDs 21/24/62 ya citados como origen del núcleo, pendientes de validación formal. Solo candidata, sin promoción.
