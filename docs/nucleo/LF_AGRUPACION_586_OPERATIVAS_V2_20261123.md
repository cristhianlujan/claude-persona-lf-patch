# LF — 586 legadas: clasificación V2 de definiciones operativas y decisiones de negocio

**Corte:** 23/11/2026 Lima; **586/586** identificadas, 46 familias. Se preservan las fuentes legadas. Se reinterpretan conservadoramente 123 indicadores históricos `pendiente_decision`: 34 requieren evaluación de elección de negocio y 89 se encaminan como dependencia/definición técnica, operativa, legal, visual o de fuente, sin convertirlas en nueva decisión de Cristhian.

## Totales mutuamente excluyentes

| Categoría | Legadas |
|---|---:|
| CUBIERTA formalmente verificada | **0** |
| MIGRAR (clasificable para trabajo) | **402** |
| FALTA_MIGRAR (familia aún por validar) | **134** |
| PAULO (binding/runtime textual) | **16** |
| DECISION (elección de negocio pendiente) | **34** |
| **Total** | **586** |

**Cobertura formal real: 0 / 586 = 0,00%.** Hay 71 legadas citadas como procedencia por 57 reglas PUBLICADAS, pero ninguna relación N:M certificada; procedencia no equivale a cobertura funcional. La columna `nucleo_reglas.regla_legacy_id` está NULL en las 58 reglas núcleo del corte inicial y no permite múltiples legadas por regla. Se propone, sin crearla, `lf_ops.nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,tipo_cobertura,estado,evidencia_ref,hash_paquete,revisado_por,revisado_en)`, FK bidireccionales y clave (legacy_id,nucleo_codigo,version_nucleo), estado VERIFICADA solo tras cotejo funcional.

### Criterio de decisión

La etiqueta original `pendiente_decision=true` **no es necesariamente una decisión de producto**. V2 conserva DECISION solo para un conjunto revisable de elecciones comerciales, financieras, alcance de productos, políticas de acceso y umbrales de riesgo que pueden modificar comportamiento. La clasificación es triage y requiere revisión semántica de los casos antes de darlos por resueltos. Los antiguos pendientes operativos se reubican según disponibilidad de familia y evidencia de dependencia. Fuente exacta de cada asignación: `lf_ops.reglas/{id}` descripción y pendiente_detalle, junto con `lf_ops.nucleo_regla_familia`. Incluye subtipo en el CSV.

**Definiciones operativas comunes con fuente:** pago PENDIENTE no autoriza modificar ofertas después de envío (Cristhian, instrucción 23/11/2026 18:00, regla REG_CHK_007 v3); el cambio antes de pagar exige retroceder a selección (Cristhian, instrucción 17:47, REG_CHK_007); MFA/OTP exige hechos de intento y violación y umbrales solo desde `public.lf_global_config` (familia SECURITY, legadas REG_SEG y REG_ATQ); no enumerar existencia de cuentas por respuestas (REG_ATQ_008/009 y B2B-RULE-AUTH-027); cuotas y pagos no equiparan estados ambiguos con un pago fallido (REG_CLIENT_CHECKOUT_PAYMENT_OUTCOME_NORMALIZATION_001); OTP de producción no se persiste en claro (REG_SEG_004). Para el resto, la agrupación es propuesta y no atribuye a Cristhian aprobación de detalle no probado.

## Familias y categorías

| Familia | Total | MIGRAR | FALTA | PAULO | DECISIÓN |
|---|---:|---:|---:|---:|---:|
| SECURITY | 82 | 73 | 0 | 2 | 7 |
| PAYMENTS_CHECKOUT | 61 | 54 | 4 | 2 | 1 |
| TRANSITIONS | 55 | 46 | 1 | 6 | 2 |
| OFFERS_INSTALLMENTS | 53 | 17 | 31 | 1 | 4 |
| B2B_PORTFOLIO_LOADS | 27 | 5 | 15 | 0 | 7 |
| LEGAL_CONSENT | 26 | 25 | 0 | 1 | 0 |
| LOADING_EMPTY_ERROR_STATES | 21 | 16 | 5 | 0 | 0 |
| STATES | 20 | 9 | 10 | 1 | 0 |
| B2B_PARTNERS | 19 | 0 | 19 | 0 | 0 |
| GOVERNANCE_APPROVAL | 18 | 17 | 1 | 0 | 0 |
| UI_MESSAGES | 16 | 15 | 1 | 0 | 0 |
| ANALYTICS | 16 | 16 | 0 | 0 | 0 |
| FINANCIAL_INTEGRITY_RECONCILIATION | 16 | 0 | 13 | 0 | 3 |
| MFA_OTP_SSO | 15 | 3 | 8 | 0 | 4 |
| OBSERVABILITY | 15 | 15 | 0 | 0 | 0 |
| ACCESSIBILITY | 10 | 10 | 0 | 0 | 0 |
| RATE_LIMIT | 8 | 8 | 0 | 0 | 0 |
| NOTIFICATIONS_DELIVERY | 8 | 8 | 0 | 0 | 0 |
| DOMAIN_LIFECYCLE | 8 | 0 | 5 | 0 | 3 |
| ROUTING_NAVIGATION | 8 | 8 | 0 | 0 | 0 |
| SESSION | 7 | 7 | 0 | 0 | 0 |
| AUDIT | 7 | 7 | 0 | 0 | 0 |
| API_DATA_CONTRACT | 7 | 6 | 1 | 0 | 0 |
| VALIDATIONS | 5 | 5 | 0 | 0 | 0 |
| EXPERIMENTS_AB | 5 | 5 | 0 | 0 | 0 |
| FIELDS | 5 | 0 | 5 | 0 | 0 |
| DASHBOARD_REPORTING | 5 | 0 | 4 | 0 | 1 |
| COMMERCIAL_CAMPAIGNS | 5 | 0 | 3 | 1 | 1 |
| HEATMAP_SESSION_RECORDING | 4 | 4 | 0 | 0 | 0 |
| ERRORS | 4 | 4 | 0 | 0 | 0 |
| THEME_LIGHT_DARK_SYSTEM | 3 | 2 | 0 | 0 | 1 |
| RESPONSIVE | 3 | 3 | 0 | 0 | 0 |
| PERMISSIONS | 3 | 3 | 0 | 0 | 0 |
| DOCUMENTS_CERTIFICATES | 3 | 0 | 2 | 1 | 0 |
| FEATURE_FLAGS | 2 | 0 | 2 | 0 | 0 |
| INTEGRATIONS_WEBHOOKS | 2 | 0 | 2 | 0 | 0 |
| DESIGN_SYSTEM | 2 | 2 | 0 | 0 | 0 |
| TIMEOUT_RETRY | 2 | 2 | 0 | 0 | 0 |
| SCHEDULED_PROCESSES | 2 | 0 | 2 | 0 | 0 |
| RUNTIME_CONFIG | 2 | 2 | 0 | 0 | 0 |
| PRIVACY_PII | 1 | 1 | 0 | 0 | 0 |
| PERFORMANCE | 1 | 1 | 0 | 0 | 0 |
| ASSETS_ICONS | 1 | 1 | 0 | 0 | 0 |
| DATA_RETENTION | 1 | 1 | 0 | 0 | 0 |
| BROWSER_PLATFORM | 1 | 0 | 0 | 1 | 0 |
| TESTING_OBLIGATIONS | 1 | 1 | 0 | 0 | 0 |

## Casos similares y arreglos comunes (agrupación preliminar por título)

| Familia / grupo por título | Reglas | Definición operativa/arreglo común |
|---|---:|---|
| SECURITY / AUTENTICACION_OTP | 29 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| OFFERS_INSTALLMENTS / OFERTAS_CUOTAS | 27 | Distinguir intención, oferta, modalidad, cuota y quote |
| TRANSITIONS / OTROS_REQUIERE_LECTURA | 23 | La similitud por título no acredita equivalencia; leer condición y efecto |
| PAYMENTS_CHECKOUT / OTROS_REQUIERE_LECTURA | 22 | La similitud por título no acredita equivalencia; leer condición y efecto |
| SECURITY / OTROS_REQUIERE_LECTURA | 21 | La similitud por título no acredita equivalencia; leer condición y efecto |
| TRANSITIONS / OFERTAS_CUOTAS | 18 | Distinguir intención, oferta, modalidad, cuota y quote |
| LEGAL_CONSENT / OTROS_REQUIERE_LECTURA | 15 | La similitud por título no acredita equivalencia; leer condición y efecto |
| PAYMENTS_CHECKOUT / PAGOS_PRECIOS | 14 | Estado del proveedor verificado, idempotencia y fuente de precios configurada |
| GOVERNANCE_APPROVAL / OTROS_REQUIERE_LECTURA | 13 | La similitud por título no acredita equivalencia; leer condición y efecto |
| ANALYTICS / OTROS_REQUIERE_LECTURA | 11 | La similitud por título no acredita equivalencia; leer condición y efecto |
| B2B_PARTNERS / OTROS_REQUIERE_LECTURA | 11 | La similitud por título no acredita equivalencia; leer condición y efecto |
| STATES / OTROS_REQUIERE_LECTURA | 10 | La similitud por título no acredita equivalencia; leer condición y efecto |
| B2B_PORTFOLIO_LOADS / OTROS_REQUIERE_LECTURA | 10 | La similitud por título no acredita equivalencia; leer condición y efecto |
| PAYMENTS_CHECKOUT / OFERTAS_CUOTAS | 10 | Distinguir intención, oferta, modalidad, cuota y quote |
| SECURITY / PII_IDENTIDAD | 9 | Respuestas sin PII ni secretos; valor agregado de exposición indebida |
| OFFERS_INSTALLMENTS / OTROS_REQUIERE_LECTURA | 9 | La similitud por título no acredita equivalencia; leer condición y efecto |
| OFFERS_INSTALLMENTS / PAGOS_PRECIOS | 9 | Estado del proveedor verificado, idempotencia y fuente de precios configurada |
| ACCESSIBILITY / OTROS_REQUIERE_LECTURA | 8 | La similitud por título no acredita equivalencia; leer condición y efecto |
| B2B_PORTFOLIO_LOADS / OFERTAS_CUOTAS | 8 | Distinguir intención, oferta, modalidad, cuota y quote |
| LOADING_EMPTY_ERROR_STATES / UI_CONTENIDO | 8 | Separar presentación, navegación y efecto funcional |
| STATES / ESTADOS_TRANSICIONES | 7 | Separar evento/intento del estado; proteger pagos pendientes |
| PAYMENTS_CHECKOUT / UI_CONTENIDO | 7 | Separar presentación, navegación y efecto funcional |
| DOMAIN_LIFECYCLE / ESTADOS_TRANSICIONES | 7 | Separar evento/intento del estado; proteger pagos pendientes |
| MFA_OTP_SSO / AUTENTICACION_OTP | 7 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| LEGAL_CONSENT / CONSENTIMIENTO_LEGAL | 6 | Vincular consentimiento a contexto y versión; validación legal antes de publicar |
| OBSERVABILITY / OTROS_REQUIERE_LECTURA | 6 | La similitud por título no acredita equivalencia; leer condición y efecto |
| UI_MESSAGES / OFERTAS_CUOTAS | 6 | Distinguir intención, oferta, modalidad, cuota y quote |
| SECURITY / CONTROL_ACCESO | 6 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| MFA_OTP_SSO / OTROS_REQUIERE_LECTURA | 5 | La similitud por título no acredita equivalencia; leer condición y efecto |
| UI_MESSAGES / OTROS_REQUIERE_LECTURA | 5 | La similitud por título no acredita equivalencia; leer condición y efecto |
| SESSION / OTROS_REQUIERE_LECTURA | 5 | La similitud por título no acredita equivalencia; leer condición y efecto |
| FINANCIAL_INTEGRITY_RECONCILIATION / PAGOS_PRECIOS | 5 | Estado del proveedor verificado, idempotencia y fuente de precios configurada |
| FIELDS / OTROS_REQUIERE_LECTURA | 5 | La similitud por título no acredita equivalencia; leer condición y efecto |
| B2B_PORTFOLIO_LOADS / CARGAS_ARCHIVOS | 5 | Verificación antes de cargar, plantillas y controles MIME/antimalware |
| SECURITY / LIMITES_PARAMETRIZADOS | 4 | Umbral y ventana desde lf_global_config, sin constante en regla |
| RATE_LIMIT / AUTENTICACION_OTP | 4 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| TRANSITIONS / ESTADOS_TRANSICIONES | 4 | Separar evento/intento del estado; proteger pagos pendientes |
| EXPERIMENTS_AB / OTROS_REQUIERE_LECTURA | 4 | La similitud por título no acredita equivalencia; leer condición y efecto |
| SECURITY / ANTI_ENUMERACION | 4 | Respuesta homogénea sin revelar existencia/estado de la cuenta |
| B2B_PARTNERS / OFERTAS_CUOTAS | 4 | Distinguir intención, oferta, modalidad, cuota y quote |
| NOTIFICATIONS_DELIVERY / OTROS_REQUIERE_LECTURA | 4 | La similitud por título no acredita equivalencia; leer condición y efecto |
| PAYMENTS_CHECKOUT / CONTROL_ACCESO | 4 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| FINANCIAL_INTEGRITY_RECONCILIATION / OTROS_REQUIERE_LECTURA | 4 | La similitud por título no acredita equivalencia; leer condición y efecto |
| TRANSITIONS / PAGOS_PRECIOS | 4 | Estado del proveedor verificado, idempotencia y fuente de precios configurada |
| ROUTING_NAVIGATION / OTROS_REQUIERE_LECTURA | 4 | La similitud por título no acredita equivalencia; leer condición y efecto |
| AUDIT / OBSERVABILIDAD | 3 | Omitir PII/OTP en logs, trazas y telemetría |
| VALIDATIONS / PII_IDENTIDAD | 3 | Respuestas sin PII ni secretos; valor agregado de exposición indebida |
| ANALYTICS / UI_CONTENIDO | 3 | Separar presentación, navegación y efecto funcional |
| LOADING_EMPTY_ERROR_STATES / OTROS_REQUIERE_LECTURA | 3 | La similitud por título no acredita equivalencia; leer condición y efecto |
| LOADING_EMPTY_ERROR_STATES / OFERTAS_CUOTAS | 3 | Distinguir intención, oferta, modalidad, cuota y quote |
| API_DATA_CONTRACT / FRONTERAS_API | 3 | Autenticación de frontera y resultados normalizados |
| DASHBOARD_REPORTING / UI_CONTENIDO | 3 | Separar presentación, navegación y efecto funcional |
| THEME_LIGHT_DARK_SYSTEM / OTROS_REQUIERE_LECTURA | 3 | La similitud por título no acredita equivalencia; leer condición y efecto |
| RESPONSIVE / OTROS_REQUIERE_LECTURA | 3 | La similitud por título no acredita equivalencia; leer condición y efecto |
| PERMISSIONS / CONTROL_ACCESO | 3 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| TRANSITIONS / PII_IDENTIDAD | 3 | Respuestas sin PII ni secretos; valor agregado de exposición indebida |
| DOCUMENTS_CERTIFICATES / ESTADOS_TRANSICIONES | 3 | Separar evento/intento del estado; proteger pagos pendientes |
| UI_MESSAGES / AUTENTICACION_OTP | 2 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| RATE_LIMIT / LIMITES_PARAMETRIZADOS | 2 | Umbral y ventana desde lf_global_config, sin constante en regla |
| TRANSITIONS / AUTENTICACION_OTP | 2 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| AUDIT / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| VALIDATIONS / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| OBSERVABILITY / UI_CONTENIDO | 2 | Separar presentación, navegación y efecto funcional |
| OBSERVABILITY / AUTENTICACION_OTP | 2 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| HEATMAP_SESSION_RECORDING / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| OBSERVABILITY / FRONTERAS_API | 2 | Autenticación de frontera y resultados normalizados |
| FINANCIAL_INTEGRITY_RECONCILIATION / OFERTAS_CUOTAS | 2 | Distinguir intención, oferta, modalidad, cuota y quote |
| LOADING_EMPTY_ERROR_STATES / AUTENTICACION_OTP | 2 | Hechos de intento y violación; parámetro AUTH desde lf_global_config; secreto no se registra |
| STATES / OFERTAS_CUOTAS | 2 | Distinguir intención, oferta, modalidad, cuota y quote |
| PAYMENTS_CHECKOUT / ESTADOS_TRANSICIONES | 2 | Separar evento/intento del estado; proteger pagos pendientes |
| API_DATA_CONTRACT / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| B2B_PARTNERS / CONSENTIMIENTO_LEGAL | 2 | Vincular consentimiento a contexto y versión; validación legal antes de publicar |
| OFFERS_INSTALLMENTS / ESTADOS_TRANSICIONES | 2 | Separar evento/intento del estado; proteger pagos pendientes |
| FINANCIAL_INTEGRITY_RECONCILIATION / ESTADOS_TRANSICIONES | 2 | Separar evento/intento del estado; proteger pagos pendientes |
| OFFERS_INSTALLMENTS / UI_CONTENIDO | 2 | Separar presentación, navegación y efecto funcional |
| LEGAL_CONSENT / CARGAS_ARCHIVOS | 2 | Verificación antes de cargar, plantillas y controles MIME/antimalware |
| ERRORS / UI_CONTENIDO | 2 | Separar presentación, navegación y efecto funcional |
| ERRORS / OBSERVABILIDAD | 2 | Omitir PII/OTP en logs, trazas y telemetría |
| SECURITY / OBSERVABILIDAD | 2 | Omitir PII/OTP en logs, trazas y telemetría |
| SECURITY / ESTADOS_TRANSICIONES | 2 | Separar evento/intento del estado; proteger pagos pendientes |
| DASHBOARD_REPORTING / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| GOVERNANCE_APPROVAL / CONTROL_ACCESO | 2 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| COMMERCIAL_CAMPAIGNS / OTROS_REQUIERE_LECTURA | 2 | La similitud por título no acredita equivalencia; leer condición y efecto |
| FINANCIAL_INTEGRITY_RECONCILIATION / CONTROL_ACCESO | 2 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| ROUTING_NAVIGATION / CONTROL_ACCESO | 2 | Permiso server-side, sujeto, empresa y recurso; no confiar en UI |
| B2B_PORTFOLIO_LOADS / CONSENTIMIENTO_LEGAL | 2 | Vincular consentimiento a contexto y versión; validación legal antes de publicar |

## Orden de lotes siguientes

SECURITY primero por 73 MIGRAR de 82; después PAYMENTS_CHECKOUT (54), TRANSITIONS (46) y siguientes según volumen MIGRAR y riesgo. Piloto SECURITY S1-C01 quedó candidata, sin juicio. Cada lote exige identificar cobertura existente, crear casos completos de intento/violación, PG17, cero promoción hasta juicio independiente. **No se abre otra familia ni se aprueba tabla puente en este trabajo.**
