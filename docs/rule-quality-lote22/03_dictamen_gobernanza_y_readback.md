# LOTE 22 — Dictamen de Input Governance sobre requisitos de un ledger Cliente

**Alcance corregido por dueño:** `LECTURA + DOCUMENTOS`. No diseñar ni crear tablas/triggers/roles/fixtures de ledger, no crear pruebas financieras, no ejecutar PG18 nuevo, no alterar fuentes oficiales ni los gates existentes.

**Resultado documental:** 36 reglas trazadas con cita literal máxima de 15 palabras, incluidas **21/21** del grupo `tecnico/ledger` de L16. La clasificación es `OBJETIVO` o `REQUIERE_REVISION_SEMANTICA`; ninguna es un PASS de implementación.

**Fuentes leídas (sin cambios):**
- EKB: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado `CANDIDATO VERIFICADO PARCIALMENTE`.
- Supabase vivo `lf_ops.reglas`: solo SELECT de `codigo, categoria, estado, pendiente_decision, descripcion, valor_config`. Evidencia por regla: `01_reglas_y_requisitos_trazados.json`.
- Archivo L16: `audits/rule-quality-lote16/02_pendientes_57.csv` de la rama `lf/issue-3779-lote16-owner-triage-v1`.
- Referencia de ciclo de vida: L13 y L20; no se invocó transición ninguna.

## 1. Estado real de la base y dependencias

**Readback actual vía SELECT:**
- 65 reglas `REG_CLIENT_*` existentes y VIGENTE (48 con `pendiente_decision=true`).
- 57 reglas `VIGENTE` con `pendiente_decision=true` en `lf_ops.reglas`, incluyendo las 48 anteriores.
- La búsqueda de nombres en `information_schema.tables` de `public`, `lf_ops` y `saly` no devolvió tablas base que coincidan con `ledger|pago|cuota|installment|payment|settlement|transac`. **No equivale a demostrar que no existe ninguna tabla de soporte con otro nombre**.
- 36 reglas pertinentes a este dictamen; 21 corresponden exactamente al grupo histórico `tecnico/ledger`.

### Cobertura de dependencia (NO cobertura implementada)

| Muestra de reglas | Requisito ledger directo | Compartido con otras áreas | No exige ledger | Total |
|---|---:|---:|---:|---:|
| Grupo L16 `tecnico/ledger` | 9 | 5 | 7 | **21** |
| Otras reglas Cliente relevantes | 3 | 12 | 0 | **15** |
| **Total** | **12** | **17** | **7** | **36** |

**Importante:** las 21 reglas del grupo no significan 21 requisitos técnicos de ledger. Siete son controles externos —PCI/tarjeta, documentos, rutas legales, recuperación IDV y resolución DNI— y permanecen fuera del ledger. Las 5 compartidas requieren más de un sistema. **Cobertura implementada acreditada: 0**, porque aquí no se construye ni verifica producto.

## 2. Matriz literal — las 21 reglas del grupo técnico L16

Cada fila muestra una exigencia comprobable, su cita literal de la regla vigente y su destino en el checklist `Cxx` del archivo `02_checklist_aceptacion_producto_qa.md`.

| Código regla | Criterio QA | Requisito verificable para el sistema receptor | Cita exacta (máx. 15 palabras) | Relación con ledger | Dictamen semántico |
|---|---|---|---|---|---|
| `REG_CLIENT_CHECKOUT_CARD_DATA_BOUNDARY_001` | `C20` | Debe aceptar solo referencia opaca autorizada y no almacenar datos crudos de tarjeta. | «resulte elegible, los datos sensibles de tarjeta deben ser capturados dentro de componentes alojados» | `NO_APLICA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_CONFIRMING_STATE_001` | `C06` | Debe conservar operación pendiente y permitir reconciliación sin nuevos intentos equivalentes. | «de pago cuyo resultado autoritativo aún está siendo validado o reconciliado. La operación continúa» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_ERROR_STATE_001` | `C05` | Debe distinguir resultados terminales recuperables de confirmación pendiente. | «CHECKOUT_ERROR_PAGO no puede usarse para PAYMENT_PENDING_CONFIRMATION. Solo representa resultados donde backend» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_INSTALLMENTS_VIEW_001` | `C03` | Debe consumir monto/plan/medio autorizados, no habilitar cobro desde datos visuales. | «UI muestra únicamente medios de pago elegibles resueltos server-side y no fija tarjeta, Yape» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_CHECKOUT_PAYMENT_METHOD_ELIGIBILITY_001` | `C03` | Debe impedir registrar intentos con métodos no elegibles para modalidad/plan. | «pago que el backend determine elegibles para la combinación vigente de aliado, oferta, modalidad,» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_CHECKOUT_PRICING_QUOTE_001` | `C02` | Debe enlazar movimientos con quote autorizado y versión/selección correctas. | «debe consumir un quote server-side vigente para la selección exacta. La estructura existente lf_proto.checkout_pricing_quotes» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_CHECKOUT_PROVIDER_HANDOFF_001` | `C04` | Debe separar preparación de sesión del intento realmente enviado al proveedor. | «En este estado todavía no se considera enviado un intento de cobro ni existe» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001` | `C11` | Debe reconocer pago QR solo por evidencia del proveedor y conservar operación. | «la operación QR; el clic del usuario nunca establece PAYMENT_CONFIRMED. El backend conserva la» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_DOC_DEMO_VERSIONING_001` | `C21` | No exige ledger adicional; requiere documento canónico/versionado separado del DEMO. | «utilizar contenido o documento DEMO cuando el documento oficial aún no esté cerrado, exclusivamente» | `NO_APLICA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001` | `C08` | Debe conservar plan contractual inmutable y vínculo al pago inicial confirmado. | «debe consolidar un snapshot inmutable de las condiciones aceptadas para ese plan. Las cuotas» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_INSTALLMENT_PLAN_VIEW_001` | `C19` | Debe consultar cuotas e historial desde fuentes financieras autoritativas. | «datos desde el snapshot contractual y el ledger de pagos. Debe mostrar estado real» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_MY_OPERATIONS_SCOPE_001` | `C01` | Debe filtrar deudas/operaciones por titular autenticado en servidor. | «pagos y documentos pertenecientes a la cuenta Cliente autenticada. El backend resuelve la pertenencia;» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_PAYMENT_CONFIRMED_POST_ACTIONS_001` | `C07` | Debe activar cuotas solo tras pago confirmado y liquidar deuda por separado. | «Para CUOTAS, el pago inicial confirmado activa el plan y registra el pago de» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` | `C05` | Debe persistir outcome normalizado basado en evidencia del proveedor. | «Todo resultado del proveedor de pago se normaliza server-side antes de» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_PAYMENT_SUCCESS_INSTALLMENTS_001` | `C07` | Debe acreditar pago inicial y activación antes de emitir confirmación al usuario. | «caso en que PAYMENT_CONFIRMED corresponde al pago inicial de un plan en cuotas y» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_PAYMENT_SUCCESS_VIEW_001` | `C05` | Debe suministrar referencia/fecha/monto de un pago confirmado. | «pantalla de éxito solo se renderiza después de PAYMENT_CONFIRMED. Debe mostrar una referencia de» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_PUBLIC_LEGAL_NAV_001` | `C23` | No exige ledger; requiere rutas públicas legales canónicas separadas. | «Política de Privacidad, Términos y Condiciones, Política de Cookies y Libro» | `NO_APLICA` | `OBJETIVO` |
| `REG_CLIENT_RECOVERY_IDV_OUTCOME_001` | `C22` | No exige ledger; requiere catálogo de resultados de recuperación/IDV. | «en backend a resultados funcionales estables. VERIFIED habilita únicamente la reasignación atómica gobernada; RETRYABLE_FAILURE» | `NO_APLICA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_RECOVERY_IDV_STEPUP_001` | `C22` | No exige ledger; requiere mecanismo de identidad reforzada. | «recuperación Cliente requiere validación reforzada de identidad cuando el usuario no controla el celular» | `NO_APLICA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_RECOVERY_PHONE_CONTROL_001` | `C22` | No exige ledger; requiere control de celular actual verificado para recuperación. | «existente y el celular actual no está vinculado a ella, el celular de la» | `NO_APLICA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_ONB003_DNI_RESOLUTION_ATOMIC_001` | `C24` | No exige ledger; requiere resolución DNI idempotente por sesión OTP. | «server-side de forma atómica dentro de la misma sesión OTP verificada. Solicitudes concurrentes no» | `NO_APLICA` | `REQUIERE_REVISION_SEMANTICA` |

## 3. Otras 15 reglas Cliente que imponen requisitos compartidos

| Código regla | Criterio QA | Requisito verificable para el sistema receptor | Cita exacta (máx. 15 palabras) | Relación con ledger | Dictamen semántico |
|---|---|---|---|---|---|
| `REG_CLIENT_CHECKOUT_AUTODEBIT_CONSENT_CONTEXT_001` | `C10` | Debe bloquear la activación de cobro automático sin autorización y evidencia previa. | «La autorización explícita de débito automático bloquea el pago únicamente cuando la» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_CHECKOUT_ENTRY_001` | `C02` | Debe exigir selección/quote vigente revalidado e idempotencia antes de enviar un cobro. | «una selección válida. Antes de crear cualquier intento de cobro, el backend revalida de» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_PAY_ONLY_VIEW_001` | `C03` | Debe admitir modalidad pago único separada del plan en cuotas. | «de medio para PAGO_UNICO y reutiliza entrada, quote, elegibilidad, tarjeta segura y QR existentes.» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_CHECKOUT_SCHEDULE_CONTEXT_001` | `C17` | Debe distinguir cronograma propuesto del contractual posterior a pago confirmado. | «dos contextos gobernados. PREPAY_PROPOSED_SCHEDULE se usa durante checkout antes de PAYMENT_CONFIRMED: muestra el plan» | `DIRECTA` | `OBJETIVO` |
| `REG_CLIENT_DEBT_SETTLEMENT_STATUS_001` | `C12` | Debe calcular liquidación por deuda con pagos confirmados y condición del aliado cuando corresponda. | «liquidación confirmada. El estado SETTLED_CONFIRMED solo se alcanza cuando todos los importes exigibles para» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_HOME_INSTALLMENT_PLAN_DETAIL_001` | `C17` | Debe distinguir propuesta editable de snapshot contractual activado. | «PASO3_CUOTAS_DESGLOSE_V2 muestra un plan seleccionado aún no activado. Plan, oferta y versión deben seguir» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_HOME_INSTALLMENT_PLAN_MODAL_001` | `C17` | Debe conservar selección explícita del plan sin inferir compromiso contractual. | «del Home. El sistema no elige un plan por defecto. En una selección nueva,» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001` | `C02` | Debe usar plan elegido y validado, sin fijar número de cuotas por mockup. | «por el mockup. Ningún plan queda seleccionado por defecto. selected_plan_id inicia null salvo restauración» | `PARCIAL_EXTERNA` | `OBJETIVO` |
| `REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001` | `C14` | Debe derivar elegibilidad de carta por deuda liquidada, nunca por visita/pago inicial. | «Sistema Cliente, la Carta de No Adeudo solo es elegible por deuda cuando REG_CLIENT_DEBT_SETTLEMENT_STATUS_001» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` | `C09` | Debe registrar fallo sin marcar cuota pagada ni crear mora automáticamente. | «cuota como pagada. PAYMENT_DECLINED_CONFIRMED mantiene la cuota sin pagar y puede habilitar una acción» | `DIRECTA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001` | `C18` | Debe exponer fecha y saldo de cuota para notificaciones sin establecer anticipación. | «pendiente se generan únicamente desde un plan activo y su cronograma contractual. Son comunicaciones» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_INSTALLMENT_PAYMENT_DUE_001` | `C09` | Debe identificar modalidad de cobro y no duplicar un intento automático pendiente. | «pendiente depende del collection_mode guardado en el snapshot del plan, no del nombre del» | `DIRECTA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_NO_DEBT_LETTER_STATUS_001` | `C14` | Debe exponer elegibilidad y estados por deuda sin fingir documento disponible. | «por deuda y solo entra al flujo documental después de SETTLED_CONFIRMED. Para operaciones administradas» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_PAYMENT_REFUND_POLICY_001` | `C13` | Debe distinguir reembolso del pago y no crear wallet/crédito interno. | «Cliente trata la devolución como retorno de dinero y no como creación de una» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |
| `REG_CLIENT_RECURRING_PAYMENT_MANAGEMENT_001` | `C10` | Debe distinguir gestión del mandato de liquidación de obligaciones financieras. | «operación las habilite. Detener o revocar un débito automático no puede marcar la deuda» | `PARCIAL_EXTERNA` | `REQUIERE_REVISION_SEMANTICA` |

## 4. Modelo de gobernanza de estado (propuesta, no mutación)

**Estado real de las 36:** `VIGENTE`; el flag real `pendiente_decision` se conserva individualmente en el JSON de trazabilidad. **No cambiar estados para compensar que el producto aún no exista.**

| Caso | Estado de regla sugerido | Dependencia por declarar | Condición para considerar implementación cumplida |
|---|---|---|---|
| Requisito directo o compartido aún sin ledger/producto | Mantener `VIGENTE` con pendiente / brecha de implementación declarada | `DEPENDENCIA_EXTERNA_LEDGER_NO_ACREDITADA` (etiqueta documental propuesta, **no columna ni estado real**) | Evidencia de Producto/QA, autoridad del dueño, readback y controles por código |
| Regla de PCI/documentos/IDV/rutas/DNI | Mantener `VIGENTE` | `DEPENDENCIA_EXTERNA_NO_LEDGER` (documental) | QA/Security/Legal/Identidad, no ledger |
| Regla `REQUIERE_REVISION_SEMANTICA` | Mantener `VIGENTE` hasta que owner autorice procedimiento | Deuda de semántica/legal/proveedor/operaciones | Abrir revisión gobernada; NO cambiar por inferencia a EN_REVISION |
| Regla incompatible con futuro código demostrado | **Proponer** corrección/sucesora por L13/L20 | Evidencia de discrepancia semántica y owner | Aplicar transiciones L13/L20 solo con autorización y readback |
| Funcionalidad no implementada y no verificada | `VIGENTE` como especificación, **NO** declaración de producto operativo | `PENDIENTE_PRODUCTO_QA` | Bloquear claims/promoción funcional que den por probado un ledger inexistente |

Nunca inferir `SUCEDIDA` ni `CADUCADA` por fecha, falta de código o decisión pendiente; L13/L20 requieren decisión explícita de owner y, cuando se autorice en producto, sincronización con la fuente. **Todas son sugerencias, ninguna ha sido escrita en Supabase.**

## 5. Lista resumida de aceptación: responsabilidad de Producto/QA

**No ejecutado en L22:** los 22 grupos de aceptación están redactados como casillas sin marcar en `02_checklist_aceptacion_producto_qa.md`, enlazadas por `Cxx` a cada regla del inventario. La evidencia admisible incluye:

- Escenarios confirmados, fallidos y pendientes con prueba de proveedor, readback e idempotencia.
- Plan contractual activado tras pago inicial confirmado y snapshot inmutable; fechas/montos solo de fuentes aceptadas.
- Estado de deuda por deuda/aliado, sin liquidación por simple fecha o pago inicial.
- Refund reconciliado sin billetera y carta únicamente elegible tras settlement total confirmado y política de liberación aplicable.
- Acceso a operaciones por identidad backend, con aislamiento entre cuentas.
- Prohibición de asumir mora/gracia/plazos/avisos por defecto. **Q04 requiere decisión Legal/Negocio/Operaciones.**

Las pruebas y el diseño se reservan a equipos Producto/Ingeniería/QA; **Input Governance no escribe el ledger ni sustituye su arquitectura**, solo registra el requisito, solicita evidencia y juzga cumplimiento dentro del flujo gobernado.

## 6. Decisiones faltantes y límites de autoridad

**BLOQUEA_IMPLEMENTACION_POR_IG** hasta que el dueño apruebe:
- **Q02 (opción B):** adopción de modelo canónico del sistema financiero Cliente, sin inferir el detalle técnico desde el nombre de la opción.
- **Q03:** decisión del dueño y contrato correspondiente, sin atribuirle alcance no documentado en estas fuentes.
- **Q04:** Legal/Negocio/Operaciones para mora, gracia, plazos, settlement condicionado, canales/recordatorios, consecuencias de cobro recurrente. **Sin defaults**.

### Hashes y límites de verificación

L22 **no ejecutó PostgreSQL 18 ni gates**. Como evidencia de NO ALTERACIÓN de fuentes SQL se conserva el baseline probado en L20:

| Gate PG18 baseline L20 | MD5 verificado entonces |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8_guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

**Live SELECT distinto de PG18:** en `public` Supabase vivo se encontró `lf_rule_promotion_apply_v1(text)` con MD5 `d7fe763c999db6f6259b6b1e2bd69644`; los otros tres nombres/firmas exactos de L20 no estaban presentes bajo `public`. **No afirmar equivalencia de código PG18 y despliegue real ni que L22 haya modificado algo.** Hallazgo documental de discrepancia de entorno; su reconciliación oficial queda fuera del alcance de esta extracción.

**Auditoría:** no hay firma de Claude independiente; agente ejecutor del chat GPT-6. Las citas son de reglas leídas con SELECT; `OBJETIVO` significa requisito normativo objetivo, no prueba de producto.

**Estado final:** requisitos de IG documentados y verificables; **ledger no implementado aquí**, evidencia de cumplimiento de Producto/QA `NO_PROBADO`, gobernanza productiva `NO-GO / UNVERIFIED`.
