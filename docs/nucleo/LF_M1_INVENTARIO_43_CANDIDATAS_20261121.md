# M1 PAYMENTS_CHECKOUT — inventario y seis candidatas
Base 672841b460d3cb8030ac7eaf33530e96113ce5fc. EKB focal releída. Decisiones del dueño 21/11/2026 20:04 Lima en #4602: D01 parámetro comisión LF sin cifra, tabla/columna por definir con Paulo; D02 Yape cuotas posteriores POR INVESTIGAR, no política firme; D03 descarga de documentos permitida desde modal de solo lectura, reconciliar «sin acciones».
61 fuentes recuperadas por lf_ops.nucleo_regla_familia + v_reglas_compat_v1; 53 con enlaces directos, 8 sin alcance efectivo, 19 con DERIVED_GLOBAL en IG_EFECTIVAS. No implica aplicabilidad universal. Los 43 grupos se definieron por contenido, no equivalencia certificada; los V2 publicados aún no exigibles. Prefijos CHK=REG_CHK_, CUO=REG_CHK_CUO_, CLIENT=REG_CLIENT_, NIU=REG_NIU_, SUC=REG_SUC_, TEC=REG_TEC_.
| Grupo | Fuentes | Preparación |
|---|---|---|
| 01 Consolidación | CHK_001 | M1-C01 |
| 02 Suma importes | CHK_002 | V2 parcial alcance; no comisión |
| 03 Outcomes | CHK_003, NIU_004, CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001 | Paulo |
| 04 Reintento seguro | CHK_004 | Candidata existente |
| 05 Éxito confirmado | CHK_005 | Candidata existente |
| 06 Comisión visible y precio final | CHK_006, NIU_002 | D01; fuente Paulo, no cifra |
| 07 Resumen inmutable | CHK_007 | NO TOCAR |
| 08 Carta | CHK_008, CHK_017, CUO_009, SUC_004 | Candidata parcial, residual |
| 09 Activación plan | CHK_009, CUO_001, CLIENT_PAYMENT_CONFIRMED_POST_ACTIONS_001 | Migrar, Paulo |
| 10 Tarjeta recomendada | CHK_010, CUO_002 | Migrar |
| 11 Yape cuotas posteriores | CHK_011, CUO_003 | D02 POR INVESTIGAR |
| 12 Marcas autorizadas | CHK_012, CUO_004, NIU_006 | Contrato |
| 13 Consentimiento | CHK_013, CUO_005 | Candidata existente |
| 14 Cancelación recurrencia | CHK_014, CUO_006 | M1-C02, residual aviso UI/carta |
| 15 Cronograma | CHK_015, CHK_016, CHK_021, CHK_022, CUO_007 | D03 reconciliar descarga |
| 16 Resumen plan visible | CHK_018, CUO_008 | Migrar |
| 17 Identidad Niubiz | CHK_019 | Contrato |
| 18 Soporte WhatsApp | CHK_020, CUO_011 | Migrar |
| 19 Confirmación QR | CHK_026, CLIENT_CHECKOUT_QR_CONFIRMATION_001 | Candidata existente |
| 20 Pago único medios | CLIENT_CHECKOUT_PAY_ONLY_VIEW_001 | Paulo + visual |
| 21 Handoff proveedor | CLIENT_CHECKOUT_PROVIDER_HANDOFF_001 | Paulo |
| 22 Vencimiento cuotas | CLIENT_INSTALLMENT_COLLECTION_FAILURE_001 | Paulo |
| 23 Cobro automático/manual | CLIENT_INSTALLMENT_PAYMENT_DUE_001 | Paulo; D02 |
| 24 Snapshot | CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001 | Paulo |
| 25 Correo técnico | CLIENT_NIUBIZ_UNIQUE_EMAIL_001 | Sandbox proveedor |
| 26 Rebotes | CLIENT_NIUBIZ_GENERIC_BOUNCE_001 | Sandbox proveedor |
| 27 Recibo correo real | CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001 | M1-C03, fuente candidata |
| 28 Refund sin wallet | CLIENT_PAYMENT_REFUND_POLICY_001 | Paulo |
| 29 Gateway | NIU_001 | Migrar |
| 30 Datos tarjeta | NIU_003 | Paulo |
| 31 Sandbox/producción | NIU_005 | M1-C04 |
| 32 Copy éxito | SUC_001 | Validación dueño texto |
| 33 Resumen operación | SUC_002 | Paulo |
| 34 Documentos | SUC_003 | Paulo |
| 35 Orientación | SUC_005 | Validación texto |
| 36 Soporte | SUC_006 | Validación fuente |
| 37 Mis operaciones | SUC_007 | Migrar |
| 38 Sellos | SUC_008 | Contrato |
| 39 Offline checkout | TEC_007 | V2 parcial |
| 40 Offline onboarding | TEC_007 | M1-C05, residual |
| 41 Idempotencia checkout | TEC_009 | Candidata existente |
| 42 Idempotencia onboarding | TEC_009 | M1-C06, residual |
| 43 Precio final separado de subtotal | CHK_002, CHK_006, NIU_002 | V2 solo exclusión de fórmula; D01, Paulo |
Los 43 grupos incluyen la desagregación de precio final del grupo comisión; no se afirma inventario atómico completo. Referencias exactas de los seis paquetes en migración. C01 módulo CLIENT_PAYMENTS, condición de presentación; fuera del módulo pendiente. C02 BACKEND, cancelar sin penalidad; aviso UI y liquidación siguen residuales. C03 BACKEND; correo técnico independiente. C04 BACKEND; falta evidencia real proveedor. C05 CLIENT_ONBOARDING con guard de pasos 1/2; conservar offline de checkout fuera. C06 BACKEND con guard submit inicial; recuperar respuesta equivalente dentro de ventana central; generación de clave y contrato de recuperación se mantienen pendientes de binding, no absorción íntegra.
Hechos lógicos M1 nuevos sin tabla_ref/columna_ref; no representan fuentes acreditadas. Pruebas deterministas con entradas sintéticas; juicio independiente ausente: se espera BLOQUEADA por JUICIO, no aprobación. No hay publicación ni deprecación, no FK legada, ni cambio lectores, ni REG_CHK_007. CI reproduce migración exacta dentro de BEGIN/ROLLBACK y compara snapshot; caso negativo comisión literal. Candidatas solo si la puerta acepta todas. Tablero 71/100 hasta evidencia de main.
Dueño: 25 textos pantalla; D03 resuelto funcionalmente, D01 principio resuelto, D02 investigación no decisión. Paulo: fuente comisión, autorización/métodos/quote, ledger/outcomes/reconciliación/QR, fuentes correo y sandbox, cancelación y snapshot, offline e idempotencia onboarding. No inventar tabla ni endpoint.
