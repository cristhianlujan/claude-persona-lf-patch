# Decisión documental 23:38 Lima — acceso Cliente LIMITADO inmediato (identity_verified=false)

**PR** #3847 DRAFT; EKB LF V1.4 consultada. Supabase solo SELECT; no API de modelos, no writer vivo, no migración ni VIGENTE.

El dueño reemplaza la espera para ingresar: **aprobación(es) parametrizadas + aviso ENTREGADO por el OTRO canal histórico previamente verificado → acceso LIMITADO inmediato**. El reloj de seguridad comienza allí; **no bloquea los pagos a deuda existente**. Si se recupera celular, avisar al correo anterior; si se recupera correo, avisar al celular anterior. Rechazo/rebote/no canal verificado → SIN acceso limitado y soporte alternativo auditable sin bypass. Un contacto secundario NO es obligatorio para registrarse en ONB_004. Una objeción verificable del dueño real → cierre inmediato de la sesión y revocación de tokens.

## Parámetros de la nueva política Cliente (solo CANDIDATO)
`lf_ops.politicas_seguridad`: `SEC-CLIENT-RECOVERY-LIMITED-ACCESS`; estado CANDIDATO, 0 filas reales observadas por SELECT.
- `approvers_required`: 1 inicial en policy_config, opciones 1/2, creador del caso distinto de aprobador(es).
- `security_window_hours`: 48 exclusivamente en policy_config. Es la ventana de seguridad previa aprobada, **no una espera para entrar**.
- `limited_allowed_actions`: DEBT_READ, INSTALLMENTS_READ, PAY_EXISTING_INSTALLMENT, PAY_EXISTING_DEBT_SINGLE.
- `limited_blocked_actions`: EMAIL_CHANGE, PHONE_CHANGE, PASSWORD_CHANGE, ACCEPT_NEW_OFFER, ACCEPT_NEW_INSTALLMENT_PLAN, NO_DEBT_LETTER_REQUEST, NO_DEBT_LETTER_DELIVERY, SAVED_PAYMENT_METHOD_CHANGE, SAVED_PAYMENT_METHOD_ADD, SAVED_PAYMENT_METHOD_DELETE.
- Aviso entregado: evento DELIVERED verificable en servidor, no aceptación de API ni envío sin confirmación.
- Para pagar deuda existente, prohibir que se active nuevo plan u oferta durante la misma acción. La Carta puede pasar a estado interno pendiente si la deuda se cancela, pero **ni solicitar ni entregar** mientras dure la ventana.
- Tras vencer la ventana, reevaluar autorización normal; no otorgar sesión completa automáticamente.
## Mapeo probado por SELECT — acciones y pantallas
| Acción | Pantalla(s) | Regla(s) | Conclusión |
|---|---|---|---|
| Ver deuda / cuotas | — (sin pantalla Mis operaciones) | REG_CLIENT_MY_OPERATIONS_SCOPE_001; REG_CLIENT_INSTALLMENT_PLAN_VIEW_001 | REGLAS VIGENTE, sin pantalla propia vinculada |
| Pagar cuotas | CHECKOUT_CUOTAS_MEDIO_PAGO; CHECKOUT_PAGO_EXITOSO | REG_CLIENT_CHECKOUT_INSTALLMENTS_VIEW_001 | PANTALLAS Y REGLAS |
| Pagar deuda existente de pago único | CHECKOUT_PAGO_UNICO_MEDIO_PAGO; CHECKOUT_ESTADO_YAPE_QR | REG_CLIENT_CHECKOUT_PAY_ONLY_VIEW_001 | PANTALLAS Y REGLAS |
| Aceptar oferta/plan nuevo | HOME_002; PASO3_CUOTAS_SELECCION; PASO3_OFERTA_UNICA_PAGO_UNICO_V2 | REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001 | PANTALLAS Y REGLAS |
| Solicitar/recibir Carta No Adeudo | CHECKOUT_CUOTAS_MEDIO_PAGO; HOME_002 | REG_CHK_008; REG_CLIENT_NO_DEBT_LETTER_STATUS_001 | REGLAS transversales; sin pantalla de solicitud específica hallada |
| Datos alta de Cliente | ONB_004 | REG_NEW_CLIENT_COMPLETION_SUBMIT_001; REG_NEW_CLIENT_DATA_COMPLETION_001 | ALTA de correo obligatorio; no contacto secundario exigido |
| Cambiar correo/celular/contraseña Cliente | — | — | NO SE IDENTIFICÓ pantalla de edición Cliente; B2B-AUTH-003 es B2B, no Cliente |
| Cambiar medio de pago guardado | — | — | NO SE IDENTIFICÓ pantalla; checkout medio de pago es selección para pago, no edición de método guardado |

## Cambios documentales propuestos
- **11 UPDATE** basados en fila fuente real y SHA256, de los cuales **5 REC_001 originalmente VIGENTE se proponen CANDIDATO**, sin editar vivo ni cambiar globalmente ONB_004, checkout, ofertas o los controles centrales.
- **9 INSERT** de reglas CANDIDATO (**12 vínculos**); 3 nuevas reglas REC_001: sesión limitada, guard de ventana y objeción del titular.
- **1 INSERT** de política de seguridad CANDIDATO, ausente en vivo; todas las acciones y duración se leen de policy_config, no de textos de reglas.
- PG17.6/18.7 en Docker: UPDATE/INSERT+ROLLBACK con SHA pre/during/post y pruebas SQL de 5 casos centrales más negativos (canal contrario, 2 aprobadores, sesión y autorización, desconocida/revocación).

## Pendientes / bloqueos
- No hay pantalla Cliente de cambio de contacto ni medio guardado; añadirlas requiere iniciativa de Producto/QA, sin inferir rutas desde checkout u ONB_004.
- Política propuesta todavía no instalada; la autorización real por token / backend y emisión del evento de objeción requerirán controles y QA.
- Sin canal histórico verificable ni aviso DELIVERED, soporte alternativo auditado sigue fail-closed hasta definir prueba independiente; no fabricar autorizaciones. Proveedor IDV pendiente y selfie no activa.
