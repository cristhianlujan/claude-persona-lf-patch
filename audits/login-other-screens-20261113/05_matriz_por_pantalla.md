# Matriz LF #3847 — alcance autenticación B2B y Cliente (DRAFT)
**Fuente**: SELECT lf_ops.pantallas / reglas_pantallas / reglas. Inventario 344 vínculos originales; EKB LF V1.4. **Autoridad vigente para Cliente REC_001**: decisión documental 23:38 Lima, identity_verified=false (09_owner_documentary_decision_2338.json), reemplaza solo la espera para entrar propuesta en 22:03 (06 histórico). **No confundir propuesta con estado VIGENTE vivo.**

| Pantalla | Regla/propuesta | Diagnóstico y texto candidato |
|---|---|---|
| B2B-AUTH-002 | AUTH-028/042 + RECOVERY-ALTERNATE-CONTACT | Recuperación B2B por soporte/clave temporal; gates de aprobación/aviso, tiempo B2B del contrato anterior. No modificar políticas B2B protegidas. |
| B2B-AUTH-003 | AUTH-029 + RECOVERY-SUPPORT | Contraseña después de expediente B2B y clave temporal. Sin sesión operativa automática. |
| B2B-AUTH-004 | nuevo RECOVERY-MFA-SEPARATION | MFA OTP correo Brevo si corresponde; recuperación no acredita MFA. |
| B2B-AUTH-005 | ninguno | REEMPLAZADO/inactiva. Mantiene vínculos históricos a reglas VIGENTE sin autorización de ejecución. |
| B2B-AUTH-006 | AUTH-029/037/038 | Recuperación B2B asistida por soporte, sin OTP automático de recuperación. |
| ONB_001 | ninguno | Continúa ingreso celular; contacto secundario opcional no bloquea onboarding. |
| ONB_002 | UI_STATES + SMS_SUPPORT_GATE | OTP acredita control del celular, no identidad; contingencia SMS Intico solo por soporte. |
| ONB_004 | NO MODIFICADA | Alta Cliente exige email primario; no es formulario de cambio de correo ni exige contacto secundario para recuperación. |
| REC_001 | ACCESS_AFTER_REBIND, IDV_STEPUP, IDV_OUTCOME, PHONE_CONTROL, REBIND_ATOMIC (5 VIGENTE fuente → 5 CANDIDATO propuestos) | Tras aprobaciones según policy_config y aviso DELIVERED al OTRO canal histórico verificado, concede LIMITED_ACTIVE **inmediato**; duración de ventana y acciones bloqueadas leídas exclusivamente de política central Cliente; rebote impide sesión, objeción verificada la revoca. |

**Cambios de este PR (23:38):** 11 UPDATE de reglas con fuente SHA256; 9 reglas INSERT CANDIDATO / 12 vínculos; una política seguridad Cliente INSERT CANDIDATO (no existe en vivo), sin DML live. La política propone 48 horas como ventana (antes aprobada) solo en policy_config, **no 48 horas de espera para ingresar**. La autorización operativa exige backend, session gate y QA; no se inventa pantalla de cambio de contacto o medio de pago guardado.

**Pendientes:** sin canal histórico previamente verificado/no entrega no habilitar limitado, soporte alternativo gobernado pendiente de prueba independiente; IDV pendiente, selfie NO, política central propuesta no instalada, CI y autoridad de promoción por verificar. Las reglas B2B #3844/#3846, políticas 19/20/23/25 y compartidos REG_ALR_003/REG_UNI_002 sin cambios.
