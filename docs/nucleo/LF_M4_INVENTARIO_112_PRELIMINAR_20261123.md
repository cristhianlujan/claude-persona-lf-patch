# LF M4 — Inventario completo de 112 fuentes legadas (preparación sin migración)

Corte: lunes 23/11/2026, Lima. Fuente primaria: SELECT sobre `lf_ops.nucleo_regla_familia` unido por `regla_id=id` a `lf_ops.v_reglas_compat_v1`, instancia LF Supabase **solo lectura**. Son 112 asignaciones únicas: SECURITY=82, MFA_OTP_SSO=15, RATE_LIMIT=8, SESSION=7. Esta clasificación es **diagnóstico inicial**, no equivalencia aprobada ni autorización para retirar fuentes. `PALABRA_CLAVE` no demuestra pertenencia funcional.

## Estado de cobertura
Ninguna de las 112 fuentes se declara **CUBIERTA por regla núcleo VIGENTE** en alcance M4: el inventario de `lf_ops.nucleo_reglas` contiene 2 VIGENTE, ambas PAYMENTS_CHECKOUT (REG_CHK_002 y REG_TEC_007), y 25 CANDIDATA de M1–M3/previas. El estado `FALTA_MIGRAR` es una obligación pendiente que exige revisión semántica, no una orden de migración inmediata. `PAULO` identifica necesidad de integración, hecho runtime o fuente real. `DECISION` indica resolución funcional o autoridad pendiente; algunas legadas ya tienen propuesta CANDIDATO y NO se promueven por este documento.

## Inventario 1:1 (ID de fuente conservado)

### M4-OTP-PRIVACY — OTP, sesión y privacidad base (8)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 19 | `REG_SEG_001` | VIGENTE | PAULO | Bloqueo temporal tras agotar intentos de un OTP |
| 20 | `REG_SEG_002` | VIGENTE | PAULO | Bloqueo de sesión tras agotar tres reenvíos OTP |
| 21 | `REG_SEG_003` | VIGENTE | MIGRAR | DNI no se expone en logs ni analytics |
| 22 | `REG_SEG_004` | VIGENTE | MIGRAR | OTP no se almacena en texto plano en producción |
| 23 | `REG_SEG_005` | VIGENTE | MIGRAR | Cambio de número inline tiene límite antifraude |
| 24 | `REG_SEG_006` | VIGENTE | MIGRAR | Token de sesión no viaja en URL |
| 25 | `REG_SEG_007` | VIGENTE | MIGRAR | Validación de formato antes de consultar base de datos |
| 62 | `REG_SEG_008` | VIGENTE | MIGRAR | OTP no se expone en respuesta de API |

### M4-ABUSE — Abuso, antiautomatización, webhooks y perímetro (20)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 121 | `REG_ATQ_001` | VIGENTE | FALTA_MIGRAR | CAPTCHA invisible como primera línea |
| 122 | `REG_ATQ_002` | VIGENTE | FALTA_MIGRAR | CAPTCHA visible solo como escalada |
| 123 | `REG_ATQ_003` | VIGENTE | MIGRAR | CAPTCHA no aplica al campo OTP |
| 124 | `REG_ATQ_004` | VIGENTE | PAULO | Autenticación del webhook OTP en n8n |
| 125 | `REG_ATQ_005` | VIGENTE | PAULO | Firma HMAC en peticiones al endpoint OTP |
| 126 | `REG_ATQ_006` | VIGENTE | PAULO | Validación de estado antes de despachar OTP |
| 127 | `REG_ATQ_007` | VIGENTE | PAULO | Rate limiting en el endpoint OTP independiente del frontend |
| 128 | `REG_ATQ_008` | VIGENTE | MIGRAR | Respuesta genérica ante DNI duplicado o bloqueado |
| 129 | `REG_ATQ_009` | VIGENTE | MIGRAR | Respuesta genérica ante celular duplicado o bloqueado |
| 130 | `REG_ATQ_010` | VIGENTE | PAULO | Tiempo de respuesta constante ante errores de validación |
| 131 | `REG_ATQ_011` | VIGENTE | PAULO | Backoff progresivo en intentos OTP fallidos |
| 132 | `REG_ATQ_012` | VIGENTE | PAULO | Protección del session_id al agotar ciclos OTP |
| 133 | `REG_ATQ_013` | CANDIDATO | DECISION | Cloudflare como proxy obligatorio en producción |
| 134 | `REG_ATQ_014` | VIGENTE | PAULO | WAF rules mínimas para el onboarding |
| 135 | `REG_ATQ_015` | VIGENTE | PAULO | Supabase no expuesto directamente a internet público |
| 136 | `REG_ATQ_016` | VIGENTE | PAULO | Detección de patrones de credential stuffing |
| 137 | `REG_ATQ_017` | VIGENTE | PAULO | Validación de consistencia DNI + celular |
| 138 | `REG_ATQ_018` | VIGENTE | PAULO | Expiración de JWT post-onboarding |
| 139 | `REG_ATQ_019` | VIGENTE | PAULO | JWT almacenado en httpOnly cookie, no en localStorage |
| 140 | `REG_ATQ_020` | VIGENTE | PAULO | Revocación de JWT al detectar actividad sospechosa |

### M4-B2B-AUTH — Autenticación, recuperación y segundo control B2B (38)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 396 | `B2B-RULE-AUTH-001` | VIGENTE | MIGRAR | Denegar por defecto |
| 397 | `B2B-RULE-AUTH-002` | VIGENTE | MIGRAR | Aislamiento por empresa |
| 398 | `B2B-RULE-AUTH-003` | VIGENTE | FALTA_MIGRAR | MFA según políticas centrales de perfil y acción |
| 401 | `B2B-RULE-STORAGE-001` | CANDIDATO | PAULO | Storage privado |
| 402 | `B2B-RULE-STORAGE-002` | VIGENTE | MIGRAR | Carga endurecida |
| 418 | `B2B-RULE-RATE-001` | VIGENTE | PAULO | Límites por recurso |
| 425 | `B2B-RULE-AUTH-004` | VIGENTE | MIGRAR | Mensaje genérico ante credenciales inválidas |
| 426 | `B2B-RULE-AUTH-005` | VIGENTE | MIGRAR | Contraseña solo en runtime |
| 429 | `B2B-RULE-AUTH-008` | VIGENTE | FALTA_MIGRAR | Protección anti-bot invisible en Login |
| 432 | `B2B-RULE-AUTH-013` | VIGENTE | PAULO | Autenticación desacoplada y fail-closed |
| 433 | `B2B-RULE-AUTH-014` | VIGENTE | PAULO | Resultados normalizados del servicio de autenticación |
| 434 | `B2B-RULE-AUTH-015` | VIGENTE | PAULO | Contrato de solicitud hacia la capa de autenticación LF |
| 436 | `B2B-RULE-AUTH-017` | VIGENTE | PAULO | Sobre de respuesta seguro de autenticación |
| 437 | `B2B-RULE-AUTH-018` | VIGENTE | PAULO | MFA obligatorio antes de sesión autenticada |
| 438 | `B2B-RULE-AUTH-019` | VIGENTE | PAULO | Factor de segundo control gobernado por política central |
| 439 | `B2B-RULE-AUTH-020` | VIGENTE | PAULO | Recuperación del segundo control sin bypass |
| 440 | `B2B-RULE-AUTH-021` | VIGENTE | PAULO | Protección adaptativa contra abuso de autenticación |
| 441 | `B2B-RULE-AUTH-022` | VIGENTE | PAULO | Creación de sesión únicamente tras autenticación completa |
| 445 | `B2B-RULE-AUTH-026` | VIGENTE | PAULO | Proveedor OIDC desacoplado; binding pendiente del spike M1 |
| 446 | `B2B-RULE-AUTH-027` | CANDIDATO | PAULO | Recuperación sin enumeración de cuentas |
| 447 | `B2B-RULE-AUTH-028` | CANDIDATO | PAULO | Solicitud de recuperación mediante la frontera LF |
| 448 | `B2B-RULE-AUTH-029` | CANDIDATO | PAULO | OTP de recuperación verificado y contexto restringido |
| 449 | `B2B-RULE-AUTH-030` | CANDIDATO | PAULO | Cambio de contraseña gobernado por política central |
| 450 | `B2B-RULE-AUTH-031` | CANDIDATO | PAULO | Recuperación finaliza con nueva autenticación completa |
| 452 | `B2B-RULE-AUTH-033` | CANDIDATO | PAULO | Enrutamiento del segundo control gobernado por política |
| 453 | `B2B-RULE-AUTH-034` | CANDIDATO | PAULO | Desafío OTP por correo verificado por LF |
| 454 | `B2B-RULE-AUTH-035` | CANDIDATO | PAULO | Contrato legado de enrolamiento TOTP fuera del flujo normal |
| 493 | `B2B-RULE-AUTH-037` | CANDIDATO | PAULO | Desafío OTP de recuperación por correo |
| 496 | `B2B-RULE-AUTH-039` | VIGENTE | PAULO | Ciclo de vida del dispositivo confiable |
| 497 | `B2B-RULE-AUTH-040` | VIGENTE | PAULO | Token opaco de dispositivo confiable protegido por servidor |
| 498 | `B2B-RULE-AUTH-041` | CANDIDATO | PAULO | Uso único, reenvío estable y renovación controlada del OTP por correo |
| 501 | `B2B-RULE-AUTH-042` | CANDIDATO | PAULO | Rate limit de recuperación aislado por operación funcional |
| 503 | `B2B-RULE-AUTH-043` | CANDIDATO | PAULO | Rate limit de segundo control aislado por operación funcional |
| 505 | `B2B-RULE-AUTH-044` | CANDIDATO | PAULO | Entrega OTP mediante Brevo Transactional Email API |
| 506 | `B2B-RULE-AUTH-045` | CANDIDATO | PAULO | Autenticación del webhook de entrega Brevo |
| 576 | `B2B-RULE-AUTH-046` | VIGENTE | FALTA_MIGRAR | Precedencia de seguridad sobre divulgación visual antes de sesión operativa |
| 657 | `B2B-RULE-SECURITY-BASELINE-001` | VIGENTE | FALTA_MIGRAR | Baseline técnico de seguridad del Login B2B |
| 13114 | `B2B-RULE-AUTH-049` | CANDIDATO | DECISION | Contabilización de fallos de contraseña sin umbral asumido |

### M4-TENANT — Separación de empresas, tenant y permisos (3)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 586 | `B2B-RULE-SCOPE-001` | CANDIDATO | DECISION | Grupo corporativo con múltiples empresas y RUC |
| 587 | `B2B-RULE-SCOPE-002` | CANDIDATO | DECISION | Permiso efectivo limitado al conjunto de empresas autorizadas |
| 590 | `B2B-RULE-SCOPE-003` | CANDIDATO | DECISION | Scope corporativo no autoritativo desde URL o cliente |

### M4-CLIENT-SEC — Recuperación, DNI y superficies Cliente (13)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 456 | `REG_AUTH_PHONE_OWNERSHIP_001` | VIGENTE | MIGRAR | OTP verifica control del celular, no identidad de la persona |
| 458 | `REG_IDV_PROGRESSIVE_001` | CANDIDATO | DECISION | Validación de identidad progresiva activable por riesgo |
| 491 | `REG_ONB003_SESSION_BINDING_001` | VIGENTE | FALTA_MIGRAR | DNI ligado a la misma sesión OTP verificada |
| 492 | `REG_ONB003_DNI_CLIENT_STORAGE_001` | VIGENTE | MIGRAR | DNI no persiste en almacenamiento del navegador |
| 495 | `REG_ONB003_DNI_RESOLUTION_ATOMIC_001` | VIGENTE | DECISION | Resolución DNI atómica e idempotente por sesión OTP |
| 499 | `REG_ONB003_ANTI_ENUM_EXPLICIT_001` | VIGENTE | MIGRAR | No revelar explícitamente existencia de cuenta desde ONB_003 |
| 508 | `REG_CLIENT_RECOVERY_REBIND_ATOMIC_001` | VIGENTE | PAULO | Reasignación de celular de cuenta Cliente atómica e idempotente |
| 509 | `REG_RISK_PHONE_MULTI_DNI_001` | VIGENTE | DECISION | Múltiples DNI o cuentas exploradas desde un mismo celular verificado |
| 510 | `REG_CLIENT_RECOVERY_IDV_STEPUP_001` | VIGENTE | DECISION | Step-up de identidad para recuperación Cliente sin factor anterior |
| 538 | `REG_CLIENT_CHECKOUT_CARD_DATA_BOUNDARY_001` | VIGENTE | DECISION | Datos sensibles de tarjeta permanecen en la frontera segura del proveedor de pago |
| 547 | `REG_CLIENT_HOME_PUBLIC_PREAUTH_BOUNDARY_001` | VIGENTE | MIGRAR | HOME_001 es superficie pública genérica sin PII ni resolución de cuenta/oferta |
| 549 | `REG_CLIENT_HOME_CLARITY_PUBLIC_BOUNDARY_001` | VIGENTE | MIGRAR | Ruta de Claridad pública no consulta PII, cuenta, deuda ni oferta |
| 553 | `REG_CLIENT_HOME_LEARN_PUBLIC_BOUNDARY_001` | VIGENTE | MIGRAR | Aprenda antes de decidir es contenido público genérico sin consulta financiera |

### M4-MFA — OTP/MFA/SSO y UX de acceso (15)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 7 | `REG_ONB_002` | VIGENTE | MIGRAR | Datos del Paso 1 no se borran al cambiar número — **asociación léxica por validar** |
| 427 | `B2B-RULE-AUTH-006` | VIGENTE | FALTA_MIGRAR | Recuperación de contraseña visible y separada — **asociación léxica por validar** |
| 428 | `B2B-RULE-AUTH-007` | VIGENTE | MIGRAR | Mostrar u ocultar contraseña sin alterar el valor — **asociación léxica por validar** |
| 430 | `B2B-RULE-AUTH-011` | VIGENTE | MIGRAR | Entrada compatible con gestores de credenciales — **asociación léxica por validar** |
| 469 | `B2B-RULE-AUTH-036` | VIGENTE | MIGRAR | Contrato de acciones del Login — **asociación léxica por validar** |
| 494 | `B2B-RULE-AUTH-038` | CANDIDATO | PAULO | Expiración y reenvío OTP gobernados por política — **asociación léxica por validar** |
| 512 | `REG_CLIENT_PHONE_PASSWORDLESS_ACCESS_001` | VIGENTE | PAULO | Acceso passwordless Cliente por celular previamente asociado y OTP válido |
| 513 | `REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001` | VIGENTE | PAULO | Acceso Cliente después de recuperación y reasignación exitosa |
| 515 | `REG_CLIENT_NEW_ACCOUNT_ACCESS_AFTER_CREATION_001` | VIGENTE | PAULO | Acceso Cliente después de alta nueva completada |
| 577 | `B2B-RULE-AUTH-047` | CANDIDATO | DECISION | Aviso de Bloq Mayús ligado a política de intentos de contraseña — **asociación léxica por validar** |
| 580 | `B2B-RULE-AUTH-048` | VIGENTE | MIGRAR | Divulgación progresiva local sin duplicar lógica de autenticación por viewport — **asociación léxica por validar** |
| 13116 | `PROP-B2B-AUTH-MFA-CONDITIONAL-001` | CANDIDATO | DECISION | MFA condicional por actividad del dispositivo y antigüedad de contraseña |
| 13118 | `PROP-B2B-AUTH-TRUSTED-DEVICE-C-001` | CANDIDATO | DECISION | Dispositivo confiable opción C con inactividad parametrizada |
| 13120 | `PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001` | CANDIDATO | DECISION | SMS Intico solo por contingencia autorizada de soporte |
| 13122 | `PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001` | CANDIDATO | DECISION | Bloqueo escalonado parametrizado por fallos de contraseña |

### M4-SESSION — Ciclo de vida de sesiones (7)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 14 | `REG_SES_001` | VIGENTE | MIGRAR | Expiración de sesión de onboarding incompleta |
| 15 | `REG_SES_002` | VIGENTE | MIGRAR | Sesión no se retoma después de expirar |
| 16 | `REG_SES_003` | VIGENTE | PAULO | Una sesión activa por dispositivo/IP en onboarding |
| 17 | `REG_SES_004` | VIGENTE | PAULO | Estado de sesión visible para el usuario |
| 18 | `REG_SES_005` | VIGENTE | MIGRAR | Sesión completada es inmutable |
| 399 | `B2B-RULE-SESSION-001` | VIGENTE | PAULO | Inactividad controlada |
| 400 | `B2B-RULE-SESSION-002` | VIGENTE | PAULO | Rotación y concurrencia gobernadas por políticas centrales |

### M4-RATE — Cuotas, reenvíos y rate limiting (8)

| ID | Fuente legada | Estado legada | Clasificación M4 | Nota |
|---:|---|---|---|---|
| 26 | `REG_RATE_001` | VIGENTE | PAULO | Límite de envíos del formulario Paso 1 por IP |
| 27 | `REG_RATE_002` | VIGENTE | PAULO | Límite de intentos de validación OTP por IP |
| 28 | `REG_RATE_003` | VIGENTE | PAULO | Límite de solicitudes de nuevo código OTP por número |
| 29 | `REG_RATE_004` | VIGENTE | PAULO | Límite de registros por DNI en 24 horas |
| 30 | `REG_RATE_005` | VIGENTE | MIGRAR | Cooldown entre reenvíos OTP |
| 63 | `REG_RL_001` | VIGENTE | MIGRAR | Cooldown entre reenvíos OTP |
| 64 | `REG_RL_002` | VIGENTE | MIGRAR | Bloqueo temporal al agotar reenvíos |
| 65 | `REG_RL_003` | VIGENTE | MIGRAR | Rate limiting en cambio de número inline |

## Balance

| Categoría | Fuentes |
|---|---:|
| MIGRAR | 32 |
| FALTA_MIGRAR | 8 |
| PAULO | 57 |
| DECISION | 15 |
| **TOTAL** | **112** |

## Primer sublote sugerido (máximo 8, NO implementado)

1. `REG_SEG_003` (21) PII DNI fuera de logs y analytics: guard solo ante **intento real de registrar/exponer DNI**.
2. `REG_SEG_006` (24) session_id fuera de URL: guard solo ante **intento de transporte de session_id por URL**.
3. `REG_SEG_008` (62) OTP fuera de respuesta API: guard solo ante **intento de construir respuesta API con otp_code**.
4. `REG_ATQ_008` (128) respuesta uniforme DNI: guard solo ante **intento de responder a verificación de DNI protegida**.
5. `REG_ATQ_009` (129) respuesta uniforme celular: guard solo ante **intento de responder a verificación de teléfono protegida**.
6. `REG_AUTH_PHONE_OWNERSHIP_001` (456) OTP no equivale a identidad civil: guard solo ante **intento de otorgar identidad o reasignación basándose únicamente en OTP**.
7. `REG_ONB003_DNI_CLIENT_STORAGE_001` (492) DNI no persiste en navegador: guard solo ante **intento de persistir DNI en el cliente**.
8. `REG_ONB003_ANTI_ENUM_EXPLICIT_001` (499) anti-enumeración ONB_003: guard solo ante **intento de emitir una respuesta explicita con existencia de cuenta**.

No crear ninguna CANDIDATA hasta confirmar hechos ya tipados, operación/nodo/autoridad existentes, fuente y alcance de las 8. Diseñar pruebas positivo, negativo, límite y mutación por guard; PG17 aislado con BEGIN/ROLLBACK, snapshot exacto, CI, PR+Merge Train serial y readback. Los guards anteriores son **criterios de diseño**, no contratos aprobados ni implementación certificada. No afirmar binding o funcionamiento runtime.

## Decisiones consolidadas (máximo 5)
1. **Q12 contraseña / riesgo:** aclarar contador por cuenta/IP/dispositivo, ventana, reinicio y escalada. **Recomendación:** mantener bloqueos escalonados CANDIDATO hasta política aprobada; nunca transferir cifras de RATE-B2B-LOGIN.
2. **Q01 MFA:** OTP correo/Brevo principal y SMS contingencia ya referenciados en decisión histórica. **Recomendación:** no reabrir política; exigir evidencia real de identidad/QA de segundo factor y de soporte antes de publicar.
3. **Q11 recuperación:** recuperación asistida/doble control ya referida. **Recomendación:** preservar prohibición de bypass y exigir autorizaciones operativas reales; no declarar acceso solo por OTP del celular nuevo.
4. **Riesgo Cliente:** umbrales multi-DNI y step-up no se deben inventar. **Recomendación:** aprobar la tabla de señales/umbrales y el vínculo exacto a `public.lf_global_config` antes de activar bloqueo.
5. **Retención/seguridad de datos:** aclarar vigencia y eliminación de PII/OTP/tokens según política aplicable. **Recomendación:** no transformar una obligación de privacidad en retención fija sin fuente técnica/legal vigente.

## Sub-lotes siguientes, dependencias y límites
- **M4-B:** OTP/RATE: REG_SEG_001/002, REG_RATE_001..005, REG_RL_001..003, REG_SES_001..005; parametrización sin números duros; reconciliar duplicados semánticos.
- **M4-C:** B2B login y MFA: AUTH-001.. y propuestas 13116..13122, revisión de Q01/Q12; integraciones Brevo, OIDC y políticas de sesión Paulo.
- **M4-D:** seguridad perimetral / n8n / webhook: ATQ-001..020; clasificar asociaciones por PALABRA_CLAVE, contratos HTTP, WAF, HMAC y límites configurados.
- **M4-E:** recuperación, identidad y fronteras Cliente: fuentes 456, 458, 491, 492, 495, 499, 508..510, y superficies públicas; Q11/riesgo/retención.
- **M4-F:** tenant, storage, revisión residual y auditoría de equivalencia; no mover clasificación legada sin aprobación.

## Resguardos / evidencia
- Se leyó `LF_resguardos_construccion.md` B1/B2/B13/B21/B25/B30 y `INPUT GOVERNANCE LF V1.4`; además docs M1/M2/M3 y decisión histórica Q01/Q11/Q12.
- EKB focal inspeccionada por SELECT: `LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001`, `LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001`, `LF-NUCLEO-M3-FINANCIAL-FAMILY-KEYWORD-BLEED-20261123-001` activos. Ningún registro EKB nuevo se ha escrito en la base RO por este inventario documental.
- DEC-NR-001..004: el registro acumulativo no pudo localizarse por búsqueda de contenido GitHub; **pendiente lectura/verificación antes de migración**. No se le atribuyen decisiones ni se cambia su alcance.
- Cero escrituras a Supabase, cero nuevas reglas, cero publicaciones, cero deprecaciones. Este inventario no acredita PG17, PR de migración, CI, Train ni runtime.
