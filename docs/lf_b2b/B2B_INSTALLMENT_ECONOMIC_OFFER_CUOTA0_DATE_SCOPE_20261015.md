# LF Backoffice Empresa — aclaración de cuotas y trazado del descuento (2026-10-15)

**Estado:** decisión funcional candidata LF B2B y auditoría del contrato Cliente VIGENTE leída solo para interoperabilidad. No cambia normas `REG_CLIENT_*`, ni tablas reales, ni genera pantallas.

## 1. Dónde se usa el monto de oferta / ahorro de la selección

| Productor o consumidor | Fuente verificada | Uso y riesgo |
|---|---|---|
| B2B carga `B2B_IMP_OFFER_AMOUNT` (campo ID280) | `lf_ops.campos` | Monto de oferta aportado; no confundir deuda, importe de la cuota ni precio final |
| B2B `B2B-RULE-INSTALLMENT-PLAN-001` (617) | `lf_ops.reglas` | Monto económico total para esa alternativa de plan (`offer_amount_semantic=TOTAL_ECONOMIC_AMOUNT_OF_PLAN`) |
| B2B `B2B-RULE-INSTALLMENT-001` (422) | `lf_ops.reglas` | Conciliación exacta de cuota0 + cuotas regulares = total económico de ese plan |
| B2B `B2B-RULE-LOAD-MULTI-OFFER-001` | `lf_ops.reglas` | `REFERENCIA_EMPRESA + PLAN` es vínculo del archivo, no PK ni oferta idéntica entre planes |
| Cliente `REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001` | `lf_ops.reglas`, VIGENTE | Consume `PLAN_BELONGS_TO_CONTEXT_OFFER` y `EXACTLY_ONE_PLAN_PER_OFFER_WHEN_COMMITTED`; no hay cambios autorizados a Cliente aquí |
| Cliente `REG_CLIENT_HOME_MULTI_OFFER_001` | `lf_ops.reglas`, VIGENTE | Selección independiente de varias ofertas/deudas; resumen desde cotización server-side |
| Cliente `REG_CLIENT_CHECKOUT_ENTRY_001` | `lf_ops.reglas`, VIGENTE | Revalida oferta, versión, plan, importes y ahorro por cada selección; excluye las inválidas |
| Cliente `REG_CLIENT_CHECKOUT_PRICING_QUOTE_001` | `lf_ops.reglas`, VIGENTE | Cotización versionada y cálculo de `total_savings` bajo backend, luego de ajustes aplicables |
| Checkout persistido | `lf_proto.checkout_pricing_quotes` | Columnas `offers_subtotal_today`, `final_customer_price`, `total_savings`, `savings_verified` |
| Quote de acceso | `public.fn_lf_my_checkout_pricing_quote(text)` | Solo delega a `lf_proto.fn_lf_my_checkout_pricing_quote_internal`; la función interna devuelve la cotización ya materializada, **no acredita generar descuentos**. El generador canónico sigue pendiente según regla VIGENTE |

**Decisión comercial nueva:** cada plan tiene su propia oferta económica, aunque la arquitectura física puede seguir usando una oferta contenedora para presentar alternativas. **No duplicar la deuda original al sumar planes alternativos**, ni multiplicar su descuento. Una transacción con múltiples deudas incluye solamente una alternativa explícita validada por deuda; el total y ahorro los autoriza un quote canónico, no el frontend.

**Diferencia por resolver al modelar:** `offer_may_have_multiple_plans=true` (B2B 617) vs la expresión del owner "cada plan tiene su propia oferta" y las reglas Cliente VIGENTE. El contrato actual Cliente vincula plan a contexto de oferta. Se ha aclarado la **independencia del precio**, pero **no** se ha autorizado modificar cardinalidad física oferta ↔ plan o reglas Cliente. Eso requiere reconciliación de identidad, versiones y descuentos con el equipo Cliente durante desarrollo.

## 2. Cuota 0 parametrizada y opcional

La política candidata existente `B2B-RULE-INSTALLMENT-PLAN-001.initial_payment_excel_policy` es la fuente; el validador `B2B_IMP_VAL_INITIAL_PAYMENT` ya permite 0. La nueva aclaración del owner establece `required_per_plan=false` y umbral de activación `activation_amount_min_exclusive=1`, almacenado en política, no en una pantalla.

| Monto cargado | Validez de importe | ¿Cuota inicial activa? |
|---:|---|---|
| Sin fila cuota 0 | Puede omitirse | No |
| 0 | Permitido como dato explícito | No; no se considera cuota inicial activa |
| 1.00 | No supera el umbral | No |
| 1.01 | Supera el umbral | Sí, cuota inicial aplicable |

`PAGO_INICIAL_ACTIVO` no implica `PLAN_ACTIVADO`: la activación contractual necesita el evento de cobro confirmado si aplica. Para planes sin cuota 0 activa, la condición de activación sigue **PENDING_FUNCTIONAL_DEFINITION**. No inventar pago ficticio de 0 ni activar el plan por omisión.

La conciliación económica debe sumar el importe real de cuota 0 cuando aplique, sin duplicar el campo en cabecera. Cuotas regulares 1…N conservan la regla de conciliación. La política numérica candidata todavía NO cuenta con pruebas de ejecución frontend/backend.

## 3. Fechas: propuestas, no modelo físico final

La política `first_installment_date_policy.prepay_schedule=SERVER_PROPOSED` y `REG_CLIENT_CHECKOUT_SCHEDULE_CONTEXT_001.PREPAY_PROPOSED_SCHEDULE` ya distinguen borrador de contrato. El futuro `POSTPAY_CONTRACTUAL_SCHEDULE` exige snapshot de plan activado; NO prueba que exista en runtime hoy.

Pendiente en modelado físico: referencia plan↔oferta económica, fecha de evento de activación real cuando no hay cuota 0 activa, calendario de empresa, ventana mínima, corte/ciclo, fechas históricas y modificadas, obligaciones y pagos de ledger, snapshot contractual. No crear DATE fija ni regla por 30 días en frontend. Ninguna fecha ilustrativa del Excel o mockup es compromiso contractual automáticamente.

## 4. Riesgos y controles en desarrollo

1. Mismo `REFERENCIA_EMPRESA`, varias alternativas: distinguir ID de plan y oferta económica; garantizar que selecciona **una** alternativa económica por deuda.
2. Multi-oferta: descontar solo deudas elegidas una vez; validar cada quote, comisiones y ajustes por deuda; total `total_savings` coherente con `final_customer_price`.
3. Cambio de selección/expiración/modificación de plan: invalidar/revalidar quote y recabar reconfirmación; no actualizar ahorros localmente.
4. Cuota cero: negativos 0 y 1, positivo 1.01; comprobar moneda/precisión y configuración del umbral.
5. Fechas: no generar snapshot postpago ni vencimiento definitivo hasta establecer relación causal con evento de pago y modelo autorizado.
6. No duplicar tablas de Cliente en LF B2B ni pasar autoridad comercial del servidor al frontend.

**Criterio de cierre:** migración B2B por Train Git→ledger→DB, y después cambios Cliente/checkout en su carril con sus propias pruebas E2E. No confundir regla candidata con runtime.
