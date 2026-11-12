# L22 — Criterios de aceptación para Producto y QA (NO ejecutados)

**Contrato:** Input Governance verifica que la evidencia presentada por Producto/QA satisface las reglas **sin convertirse en el equipo que diseña o construye el ledger**.

**Estado de este checklist:** `PENDIENTE_DE_EJECUCION_PRODUCTO_QA` para cada criterio; los `[ ]` están intencionalmente sin marcar. **No hay SQL del ledger ni pruebas de implementación de este lote.**

**Trazabilidad:** cada código `Cxx` agrupa requisitos duplicados, enlazando con cada regla, cita literal y estado en `01_reglas_y_requisitos_trazados.json`. Esto no constituye una especificación de tablas/triggers, ni una autorización para implantar políticas de cobro.

## Checklist por capacidad consolidada

### C01 — Aislamiento de operaciones por cuenta autenticada

Reutilizado por 1 regla(s): `REG_CLIENT_MY_OPERATIONS_SCOPE_001`.

- [ ] QA presenta una cuenta A y otra B con deudas distintas; verifica que una consulta autenticada de A nunca devuelve importes, planes ni documentos de B.
- [ ] Evidencia exigida: prueba de autorización server-side con sujeto real, respuestas readback por cuenta y fallo de acceso cruzado; sin DNI/account_id suministrado como autoridad por frontend.
- [ ] Revisión de Producto: resolver canónico de identidad y pertenencia Q03.

### C02 — Quote, selección y versión previamente validados

Reutilizado por 3 regla(s): `REG_CLIENT_CHECKOUT_ENTRY_001`, `REG_CLIENT_CHECKOUT_PRICING_QUOTE_001`, `REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001`.

- [ ] QA prueba quote vigente contra uno vencido, versión distinta, selección modificada y operación duplicada: ninguno de los inválidos habilita envío del cobro.
- [ ] Evidencia: selección/quote server-side firmado o trazable, versión, checksum, estado y decisión de rechazo; ningún cálculo de monto decidido en navegador.
- [ ] Pendiente: integración del quote canónico, autorización de configuración de pricing, Q02/Q03.

### C03 — Elegibilidad de medio y modalidad en backend

Reutilizado por 3 regla(s): `REG_CLIENT_CHECKOUT_INSTALLMENTS_VIEW_001`, `REG_CLIENT_CHECKOUT_PAY_ONLY_VIEW_001`, `REG_CLIENT_CHECKOUT_PAYMENT_METHOD_ELIGIBILITY_001`.

- [ ] QA compara pago único/CUOTAS con combinación de aliado, oferta, plan, monto y proveedor; solo se ofrece medio elegible por fuente real.
- [ ] Evidencia: resolución backend y su configuración versionada; caso sin medio muestra indisponibilidad y cero intentos enviados.
- [ ] La presencia de CARD/YAPE en un mockup no acredita elegibilidad; requiere partner/proveedor/producto.

### C04 — Handoff previo a intento, sin falso cobro

Reutilizado por 1 regla(s): `REG_CLIENT_CHECKOUT_PROVIDER_HANDOFF_001`.

- [ ] QA simula sesión preparada sin envío y sesión efectivamente entregada; ninguna preparación o fallo previo se muestra como cargo ni como PAYMENT_PENDING_CONFIRMATION.
- [ ] Evidencia: referencia de sesión opaca, marca de aceptación del proveedor, orden temporal trazado y outcomes correctos.
- [ ] Prohibido inferir que abrir SDK equivale a cobrar.

### C05 — Catálogo de outcomes y confirmación autorizada

Reutilizado por 3 regla(s): `REG_CLIENT_CHECKOUT_ERROR_STATE_001`, `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001`, `REG_CLIENT_PAYMENT_SUCCESS_VIEW_001`.

- [ ] QA ejecuta resultados PAYMENT_CONFIRMED, PAYMENT_PENDING_CONFIRMATION, PAYMENT_DECLINED_CONFIRMED, PAYMENT_NOT_SUBMITTED y PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT.
- [ ] Evidencia: evento origen proveedor/normalización persistido, reason_code, marca de tiempo y referencia; solo CONFIRMED con aprobación autoritativa afecta saldo/cuenta.
- [ ] Verificar error visual: PENDING no se presenta como fallo terminal ni prueba de ausencia de cargo.

### C06 — Operación pendiente, reintento y conciliación

Reutilizado por 1 regla(s): `REG_CLIENT_CHECKOUT_CONFIRMING_STATE_001`.

- [ ] QA simula timeout después de enviar al proveedor y cierre del navegador: el intento queda pendiente, se impide reintento paralelo y se reanuda conciliación con la misma operación.
- [ ] Evidencia: id de operación, transición persistida, callback/readback del proveedor y pruebas de idempotencia para callbacks duplicados.
- [ ] Solo outcome terminal autoritativo habilita siguiente acción; no resolver ambigüedad por timeout.

### C07 — Pago inicial confirmado activa plan

Reutilizado por 2 regla(s): `REG_CLIENT_PAYMENT_CONFIRMED_POST_ACTIONS_001`, `REG_CLIENT_PAYMENT_SUCCESS_INSTALLMENTS_001`.

- [ ] QA confirma pago inicial, luego verifica activación de plan y registro de pago; pago pendiente, rechazado o no enviado nunca activa plan.
- [ ] Evidencia: vínculo entre operación confirmada, obligación/deuda y snapshot contractual; estado de carta sigue NOT_ELIGIBLE si deuda no liquidada.
- [ ] Separar activación de cuotas de liquidación completa.

### C08 — Snapshot contractual inmutable

Reutilizado por 1 regla(s): `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001`.

- [ ] QA compara snapshot de versión/plan/montos/fechas/modos/condiciones/referencia inicial con relecturas posteriores; cambio de oferta o pricing no altera contrato.
- [ ] Evidencia: snapshot conservado y su hash/versiones, referencia de deuda/oferta y pago inicial; intento de alteración rechazado o requiere flujo gobernado separado.
- [ ] La cantidad de cuotas, plazos y fechas provienen de configuración aceptada; no hardcodear.

### C09 — Cuotas, pago/fallo y modo de cobro

Reutilizado por 2 regla(s): `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001`, `REG_CLIENT_INSTALLMENT_PAYMENT_DUE_001`.

- [ ] QA registra cuota pendiente, cobro fallido confirmado y reintento posteriormente confirmado; una cuota se marca pagada solo por PAYMENT_CONFIRMED.
- [ ] Evidencia: cronograma contractual, collection_mode, operación por cuota, outcome y readback del estado; prohibir intentos simultáneos automático/manual.
- [ ] NO derivar mora/atraso de rechazo técnico: Legal/Negocio Q04 define parámetros futuros.

### C10 — Mandato recurrente, evidencia y obligaciones remanentes

Reutilizado por 2 regla(s): `REG_CLIENT_CHECKOUT_AUTODEBIT_CONSENT_CONTEXT_001`, `REG_CLIENT_RECURRING_PAYMENT_MANAGEMENT_001`.

- [ ] QA prueba autorización explícita antes del primer cobro recurrente, ausencia de mandato cuando se exige, y revocación; revocar nunca liquida deuda ni borra cuotas.
- [ ] Evidencia: consentimiento/mandato versionado, política por modalidad y transición de medio; trazas de bloqueo/reanudación del cobro según backend.
- [ ] Legal/Negocio Q04 pendientes para copy, consecuencias, terminación, penalidades y fallback.

### C11 — Confirmación QR solo por evidencia del proveedor

Reutilizado por 1 regla(s): `REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001`.

- [ ] QA pulsa Ya escaneé antes de confirmación y después de confirmación autoritativa: el clic nunca confirma por sí solo; no nace segunda operación.
- [ ] Evidencia: mismo id de operación, verificación callback/polling, resultado normalizado, caso QR vencido y respuesta segura.
- [ ] No fijar vencimiento QR ni proveedor sin contrato canónico.

### C12 — Saldo/estado por deuda y settlement condicionado

Reutilizado por 1 regla(s): `REG_CLIENT_DEBT_SETTLEMENT_STATUS_001`.

- [ ] QA cubre pago inicial insuficiente, último pago pendiente y último pago confirmado; SETTLED_CONFIRMED solo cuando se cumplen importes y la confirmación del aliado si está contractualmente exigida.
- [ ] Evidencia: fuente transaccional/saldo reconstruible, acuerdo versionado por deuda, conciliación de proveedor y confirmación del aliado cuando aplique.
- [ ] La regla no define un porcentaje, plazo o tolerancia de deuda; Q04 pendiente.

### C13 — Refund separado de billetera/cupón

Reutilizado por 1 regla(s): `REG_CLIENT_PAYMENT_REFUND_POLICY_001`.

- [ ] QA ejecuta devolución de pago confirmado con evidencia del proveedor; comprueba que no surge saldo/cupón interno ni se vuelve a presentar el pago como íntegramente aplicado.
- [ ] Evidencia: referencia de pago original, autorización de devolución, estado de proveedor, trazabilidad de destino y ajuste financiero; rechazo de devolución sin autorización.
- [ ] Ruta preferente de devolución original depende de soporte y reconciliación reales; no inventar política de refund.

### C14 — Carta por deuda: elegibilidad, estado y disponibilidad

Reutilizado por 2 regla(s): `REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001`, `REG_CLIENT_NO_DEBT_LETTER_STATUS_001`.

- [ ] QA evalúa deuda activa, último pago pendiente, deuda SETTLED_CONFIRMED y carta AVAILABLE: solo la última habilita descarga oficial, con estados normalizados.
- [ ] Evidencia: estado de deuda y condición de aliado, registro documental por deuda, versión/documento oficial, recibo de entrega y readback del estado.
- [ ] SLA, firma electrónica, liberación e integración del aliado pendientes; nunca prometer emisión inmediata.

### C17 — Cronograma propuesto versus contrato activado

Reutilizado por 3 regla(s): `REG_CLIENT_CHECKOUT_SCHEDULE_CONTEXT_001`, `REG_CLIENT_HOME_INSTALLMENT_PLAN_DETAIL_001`, `REG_CLIENT_HOME_INSTALLMENT_PLAN_MODAL_001`.

- [ ] QA en checkout ve PREPAY_PROPOSED_SCHEDULE; tras pago confirmado ve POSTPAY_CONTRACTUAL_SCHEDULE desde snapshot inmutable, sin sobreescritura por cambios de oferta.
- [ ] Evidencia: quote/selección previo, snapshot posterior y readback con importes/fechas de fuente canónica; sin defaults 5/15/30.
- [ ] La selección de plan no lo activa ni autoriza automáticamente cobro recurrente.

### C18 — Recordatorios consumen hechos, no definen política

Reutilizado por 1 regla(s): `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001`.

- [ ] QA genera un ejemplo usando cuota pendiente y plan activo, verificando que fechas/montos provienen del cronograma; con cuota pagada o plan inactivo no emite el mismo recordatorio.
- [ ] Evidencia: origen de cuota/plan, regla de disparo parametrizada y plantilla autorizada; sin payload sensible en canal abierto.
- [ ] Anticipación, frecuencia, canales y copy son Q04 Operaciones/Legal y permanecen sin valores por defecto.

### C19 — Lectura de operaciones financieras por cliente

Reutilizado por 1 regla(s): `REG_CLIENT_INSTALLMENT_PLAN_VIEW_001`.

- [ ] QA observa cuotas pagadas/pedientes, referencia, historial, estado de carta y deuda por la cuenta autorizada; pago pendiente no aparece confirmado.
- [ ] Evidencia: readbacks del sistema financiero con referencias y outcomes; rutas/pantallas deben estar canónicamente aprobadas fuera del ledger.
- [ ] No usar oferta original, fecha vencida o mockup como fuente de pago.

### C20 — Frontera PCI/provider (fuera del ledger)

Reutilizado por 1 regla(s): `REG_CLIENT_CHECKOUT_CARD_DATA_BOUNDARY_001`.

- [ ] QA con proveedor real demuestra que PAN/CVV/vencimiento nunca llegan a LF, Supabase, logs, analytics ni replay; solo tokens y datos enmascarados.
- [ ] Evidencia: revisión de flujo PCI, payload capturado en ambiente de pruebas, configuración de hosted fields/SDK autorizada, análisis de logs.
- [ ] Responsabilidad: seguridad/pagos y proveedor, no pedir a IG diseñar almacenamiento de tarjeta.

### C21 — Documento maestro/versiones (fuera del ledger)

Reutilizado por 1 regla(s): `REG_CLIENT_DOC_DEMO_VERSIONING_001`.

- [ ] QA distingue DEMO de oficial y comprueba que un documento no se publica como válido sin versión/trazabilidad/estado autorizado.
- [ ] Evidencia: registro documental, recibo de publicación, permisos y consulta en las dos superficies cuando corresponda.
- [ ] Legal/Operaciones deben aprobar documento/copy/formatos y política de liberación.

### C22 — Recuperación e IDV (fuera del ledger)

Reutilizado por 3 regla(s): `REG_CLIENT_RECOVERY_IDV_OUTCOME_001`, `REG_CLIENT_RECOVERY_IDV_STEPUP_001`, `REG_CLIENT_RECOVERY_PHONE_CONTROL_001`.

- [ ] QA verifica step-up de identidad, normalización de outcome y control del número verificado, sin reutilizar un identificador ajeno ni autorizar acceso por fallo.
- [ ] Evidencia: contrato con proveedor IDV, readback de sesión/OTP y validación canónica de vinculación del número.
- [ ] No convertir el grupo técnico de L16 en cobertura de ledger artificial.

### C23 — Navegación legal pública (fuera del ledger)

Reutilizado por 1 regla(s): `REG_CLIENT_PUBLIC_LEGAL_NAV_001`.

- [ ] QA valida acceso público a privacidad, términos, cookies y Libro de Reclamaciones a través de rutas canónicas, sin login Cliente/B2B.
- [ ] Evidencia: contratos de rutas oficiales, pruebas UI/routing y contenido/legal publicado.
- [ ] No crear route_pattern por inferencia ni pedir tabla financiera.

### C24 — Resolución DNI idempotente (fuera del ledger)

Reutilizado por 1 regla(s): `REG_ONB003_DNI_RESOLUTION_ATOMIC_001`.

- [ ] QA evalúa resolución del mismo DNI/sesión OTP repetida sin crear duplicados ni permitir reatribución por condición de carrera.
- [ ] Evidencia: registros de autorización/OTP, restricciones de unicidad de la fuente de identidad, tests de concurrencia.
- [ ] No crear nuevo almacenamiento de identidad desde el proyecto ledger.


## Reglas de recepción de evidencia por Input Governance

- [ ] La evidencia identifica versión de la regla vigente, código, alcance, dueño, sistema o proveedor, entorno y fecha.
- [ ] Cada PASS tiene resultado de QA reproducible, data sintética/no sensible, fuente de verdad y readback; un mockup o documento no equivale a persistencia financiera.
- [ ] Cada regla marcada `REQUIERE_REVISION_SEMANTICA` conserva su dependencia de Legal/Negocio/Operaciones/Proveedor; IG no asume una decisión ausente.
- [ ] Cualquier test de pago pendiente/rechazado demuestra **ausencia de confirmación** sin inferir que no hubo cargo por simple timeout.
- [ ] El flujo financiero y los derechos de cliente se acreditan contra el productor/autorizador real, no contra una ejecución simulada IG.
- [ ] QA enlaza evidencia por regla y capacidad compartida sin duplicar ejecución artificialmente cuando una misma prueba cubre reglas distintas.
- [ ] Ninguna regla se promociona afirmando que el ledger existe mientras la fuente canónica de ledger/plan/pago/deuda y sus controles no estén aprobados y probados.
- [ ] Los parámetros de mora, gracia, ventanas de reintento, anticipación de avisos, plazos y settlement por aliado siguen **sin valores por defecto**, sujetos a Q04 (Legal/Negocio/Operaciones).
- [ ] El dueño resuelve Q02 (**opción B**), Q03 y Q04 antes de aprobar adopción de arquitectura financiera o afirmar preparación productiva.

**Responsable del diseño/implementación, pruebas de producto y QA:** equipo de Producto/Ingeniería/QA. **Responsable IG:** trazabilidad semántica, requisitos, recepción/verificación de evidencias y propuesta de estado gobernado; sin cambio de fuente oficial.
