# Lote 25 — Paquete de propuestas Q03/Q04 con adenda E/F

**Alcance documental:** solo SELECT en Supabase vivo; reglas CANDIDATO PROPUESTAS, ninguna instalada, aprobada ni promovida. Cero DML/DDL, cero producción, cero RUN modificados y ningún SQL de gates editado. El auditor y juez es **GPT-6, mismo modelo, NO independiente**; no se acredita identidad Claude. Todas las propuestas/juicios se clasifican `REQUIERE_REVISION_SEMANTICA`; las filas reales/hash de SELECT son `OBJETIVO`.

## Conteo y estado

| Documento | Conteo | Situación |
|---|---:|---|
| Nuevas reglas `lf_ops.reglas` | **5** | CANDIDATO documental, códigos no existentes |
| Cambios sobre reglas vigentes | **4** | CANDIDATO de nueva versión; **NO UPDATE** del VIGENTE |
| Reglas revisadas sin cambio | **4** | Se conserva estado, descripción y config reales |
| Parámetro configurable (no es una regla existente) | **1** | CANDIDATO de configuración, valor inicial 12 meses, mantenimiento Producto pendiente |
| **Total de fichas de reglas** | **13** | **0 adoptadas** |

El archivo `01_propuestas_reglas.json` contiene **todas las descripciones y `valor_config` completos** en el formato de `lf_ops.reglas`; `04_diffs_literal_pre_post.json` guarda **antes/después literal** para cada cambio. `06_parametro_antiguedad_candidato.json` separa la variable del runtime. **No insertar una regla con código idéntico a otra VIGENTE:** hace falta sucesora/operación gobernada posterior.

## Decisiones del dueño — alcance exacto

- **A (Q03):** Niubiz único proveedor de recaudo, tarjeta y Yape. Contrato/operación real NO VERIFICADO. No interpretar como autorización de recurrencia Yape.
- **B (Q04):** toda cuota nace PENDIENTE; EN_PROCESO corresponde a intento abierto; PAGADA y CANCELADA finales; VENCIDA solo por fecha vencida sin gracia, corte 00:00 America/Lima. Rechazo aislado NO marca VENCIDA.
- **C (Q04):** reconciliar todas las EN_PROCESO al corte. Confirmado→PAGADA; rechazado→VENCIDA solo cuando pasó la fecha contractual, sino PENDIENTE; NO_DETERMINADO por falta de respuesta/referencia/duplicado/monto irregular→EN_PROCESO, excepción, alerta y escalamiento humano. Idempotente. Archivo Niubiz sin formato acreditado.
- **D+E (CONFIRMADAS):** cuota o plan pueden solicitar cancelación; PAGADA/CANCELADA no cambian. EN_PROCESO **NO puede cancelarse hasta reconciliar**, VENCIDA **SÍ puede cancelarse**. Se elimina el supuesto y la reserva Legal de la versión documental anterior, sin extender esta confirmación a otros asuntos.
- **F (CONFIRMADA):** antigüedad automática medida desde la fecha de cuota, umbral variable inicial **12 meses calendario**. Si una VENCIDA cumple el umbral, cancelar automáticamente todas las PENDIENTE/VENCIDA del plan, distinguiendo causa disparadora (`AUTO_ANTIGUEDAD`) y arrastre (`ARRASTRE_PLAN_AUTO`). PAGADA conserva su pago y CANCELADA no cambia. Si existe EN_PROCESO, reconciliar primero y reevaluar plan en corrida siguiente **sin cancelar mientras tanto**. Registrar causa+fecha e idempotencia. Falta/invalidación de parámetro→falla cerrada y alerta.
- **INCOBRABLE:** solo el importe de cuotas efectivamente canceladas, NUNCA importes ya pagados. El estado exacto, representación del saldo/deuda y destino contable requieren revisión explícita de **Negocio, Legal y Finanzas** antes de instalación. No se inventan asientos, castigos, fechas contables ni habilitación de Carta de No Adeudo.
- **Fuera de este lote:** mora, reintentos, recordatorios, formato Niubiz, contrato del proveedor, y cualquier regla adicional no expresamente decidida.

## Fichas de reglas, Curator por SELECT y diffs

### L25-01 — `REG_CLIENT_INSTALLMENT_STATUS_025`

- **Tipo:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** B: PENDIENTE al crear; EN_PROCESO por intento abierto; PAGADA y CANCELADA finales; VENCIDA por fecha contractual, sin gracia, corte 00:00 America/Lima; rechazo solo no vence. NO_DETERMINADO conserva EN_PROCESO en conciliación.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 0, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **Nueva propuesta:** no tiene preimagen por código en `lf_ops.reglas` (G25_02=0); contrato íntegro en `01_propuestas_reglas.json`.

### L25-02 — `REG_CLIENT_INSTALLMENT_MIDNIGHT_RECON_025`

- **Tipo:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** C: reconciliación a medianoche de EN_PROCESO contra Niubiz; confirmado→PAGADA, rechazado→VENCIDA si pasó la fecha o PENDIENTE si no; no determinado→EN_PROCESO con excepción; idempotente. Archivo/formato Niubiz real desconocido.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 0, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **Nueva propuesta:** no tiene preimagen por código en `lf_ops.reglas` (G25_02=0); contrato íntegro en `01_propuestas_reglas.json`.

### L25-03 — `REG_CLIENT_INSTALLMENT_RECON_ALERT_025`

- **Tipo:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `notificacion` / `CONTENIDO_COMUNICACIONES`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** C: alerta de excepción NO_DETERMINADO por correo al destinatario PARAMETRO CONFIGURABLE, campos cuota, referencia, monto, fecha, motivo; escalamiento humano, sin nombres ni datos de tarjeta. No es política de recordatorios.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 0, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **Nueva propuesta:** no tiene preimagen por código en `lf_ops.reglas` (G25_02=0); contrato íntegro en `01_propuestas_reglas.json`.

### L25-04 — `REG_CLIENT_INSTALLMENT_CANCELLATION_025`

- **Tipo:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** D+E: cancelación por cuota o plan; PAGADA/CANCELADA nunca mutan; EN_PROCESO no cancelable hasta reconciliar (CONFIRMADO); VENCIDA cancelable (CONFIRMADO). No se introduce mora ni reintentos.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 0, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **Nueva propuesta:** no tiene preimagen por código en `lf_ops.reglas` (G25_02=0); contrato íntegro en `01_propuestas_reglas.json`.

### L25-05 — `REG_NIU_001`

- **Tipo:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `niubiz` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** A: Niubiz proveedor ÚNICO de recaudo para tarjeta y Yape. La decisión no resuelve cómo pagar cuotas siguientes con Yape ni autoriza recurrencia.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (9 palabras):** «Niubiz es el gateway de pago principal del producto».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-05` (5 cambios de campo).

### L25-06 — `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001`

- **Tipo:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** B+C: el campo overdue_authority de gracia pasa a fecha contractual sin gracia America/Lima; rechazo no marca vencida; NO_DETERMINADO mantiene EN_PROCESO. Mora sigue pendiente.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 1, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (9 palabras):** «fecha contractual y de una política de gracia/mora gobernada.».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-06` (6 cambios de campo).
- **Diff literal clave:** `overdue_authority`: `CONTRACTUAL_SCHEDULE_PLUS_CANONICAL_GRACE_POLICY` → `CONTRACTUAL_DUE_DATE_NO_GRACE_AMERICA_LIMA`.
- **Señal NO concluyente:** `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001`; claves JSON compartidas pueden tener distinto significado, requiere juicio humano.

### L25-07 — `REG_CHK_CUO_006`

- **Tipo:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** D+E: cambio VIGENTE REG_CHK_CUO_006: quitar promesa incondicional «en cualquier momento», preservar sin penalidades, restringir EN_PROCESO hasta conciliar y permitir cancelar VENCIDA; copy de checkout pendiente de aprobación visual.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 2, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (9 palabras):** «en cualquier momento. No hay penalidades por cancelación anticipada.».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-07` (6 cambios de campo).
- **Diff del copy:** `Podrás cancelar tu plan cuando lo necesites. Sin penalidades.` → `Puedes cancelar tu plan sin penalidades. Si hay un cobro en proceso, primero debe reconciliarse.` (PROPUESTA UX, no publicada).
- **Señal NO concluyente:** `REG_CHK_020`, `REG_CHK_CUO_008`; claves JSON compartidas pueden tener distinto significado, requiere juicio humano.

### L25-08 — `REG_CHK_014`

- **Tipo:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** D+E: cambio VIGENTE REG_CHK_014: idem en Mis operaciones, preserva sin penalidad y carta solo tras deuda efectivamente cancelada. EN_PROCESO bloqueada; VENCIDA permitida.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (11 palabras):** «en cualquier momento desde "Mis operaciones". La cancelación no genera penalidades.».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-08` (4 cambios de campo).

### L25-09 — `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001`

- **Tipo:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `notificacion` / `CONTENIDO_COMUNICACIONES`; **estado propuesto:** `VIGENTE`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** SIN CAMBIO: los recordatorios siguen pendientes. Una alerta excepcional de conciliación no crea frecuencia/canal de recordatorios al cliente.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (11 palabras):** «La política exacta de anticipación, frecuencia y canales debe ser configurable».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-09` (0 cambios de campo).
- **Sin cambio decidido:** preimagen y propuesta coinciden; no se modifica ningún atributo de regla.

### L25-10 — `REG_CHK_CUO_003`

- **Tipo:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** SIN CAMBIO: proveedor Niubiz no establece modalidad de pagos futuros Yape, ni autoriza WhatsApp recurrente.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (8 palabras):** «Las cuotas siguientes no pueden cobrarse por Yape.».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-10` (0 cambios de campo).
- **Sin cambio decidido:** preimagen y propuesta coinciden; no se modifica ningún atributo de regla.

### L25-11 — `REG_CHK_CUO_009`

- **Tipo:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado propuesto:** `VIGENTE`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** SIN CAMBIO: carta de no adeudo por deuda realmente pagada/cancelada según contrato vigente; cancelar cuotas por incobrabilidad no acredita deuda SETTLED_CONFIRMED.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 1, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (14 palabras):** «la carta de no adeudo se emite cuando el usuario completa el pago total».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-11` (0 cambios de campo).
- **Sin cambio decidido:** preimagen y propuesta coinciden; no se modifica ningún atributo de regla.
- **Señal NO concluyente:** `REG_CHK_017`; claves JSON compartidas pueden tener distinto significado, requiere juicio humano.

### L25-12 — `REG_CHK_011`

- **Tipo:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** SIN CAMBIO: Yape en cuotas futuras y recordatorios no se deciden a partir del proveedor único.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 1, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **OBJETIVO — cita literal de fuente (13 palabras):** «El mecanismo para cobrar las cuotas siguientes cuando el usuario pagó con Yape».
- **Diff antes/después:** `04_diffs_literal_pre_post.json` → `L25-12` (0 cambios de campo).
- **Sin cambio decidido:** preimagen y propuesta coinciden; no se modifica ningún atributo de regla.

### L25-13 — `REG_CLIENT_INSTALLMENT_AUTO_CANCELLATION_025`

- **Tipo:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado propuesto:** `CANDIDATO`.
- **REQUIERE_REVISION_SEMANTICA — alcance:** F: cuota VENCIDA con antigüedad ≥ parámetro 12 meses calendario inicial desde fecha cuota; cancelar todas PENDIENTE/VENCIDA del mismo plan, causa AUTO_ANTIGUEDAD para disparadora y ARRASTRE_PLAN_AUTO para arrastradas; PAGADA/CANCELADA intactas; cualquier EN_PROCESO difiere cancelación completa a siguiente corrida tras reconciliar. Si falta/inválido parámetro: cero cancelaciones y alerta. Idempotente, audita causa+fecha. Importe cancelado excluye pagado; INCOBRABLE/destino contable pendientes Negocio/Legal/Finanzas.
- **OBJETIVO — Curator G25_02:** mismo código en vivo 0, duplicado literal exacto VIGENTE 0, señales de claves config compartidas 0, mapa L13 fixture 1.
- **Nueva propuesta:** no tiene preimagen por código en `lf_ops.reglas` (G25_02=0); contrato íntegro en `01_propuestas_reglas.json`.

## Parámetro CANDIDATO — antigüedad automática

| Campo | Propuesta | Tratamiento |
|---|---|---|
| Código | `ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES` | **Decisión F del dueño** |
| Valor inicial | `12` | **Meses calendario**, no días fijos |
| Referencia del plazo | `FECHA_CUOTA` | Localidad `America/Lima` por contrato B |
| Fuente de valor | Variable/configuración versionada | **No hardcodear 12 en el proceso** |
| Si falta o es inválido | No cancelar ninguna cuota, registrar/emitir alerta | **Falla cerrada** |
| Pantalla de mantenimiento | A construir por **Producto**, fuera de IG | Solo propuesta, no implementación |
| Obligaciones IG | Historial de cambios, rol autorizado, rango válido | Mínimos confirmados; límites min/max aún NO DECIDIDOS |
| Borde de meses calendario | Fin de mes / año bisiesto | `REQUIERE_REVISION_SEMANTICA`, sin inventar regla |
| Registro vivo | G25_07: 0 apariciones del código en `lf_ops.reglas` | **No prueba ausencia en todas las fuentes** |

El parámetro NO se convierte en regla existente, tabla, interfaz funcional ni valor de producción por redactarlo. Véase `06_parametro_antiguedad_candidato.json`.

## Contradicciones, impactos y reconciliación previa

| Fuente o código | Evidencia OBJETIVO | Efecto de aprobar E/F | Dictamen / actuación propuesta |
|---|---|---|---|
| `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` VIGENTE | `overdue_authority=CONTRACTUAL_SCHEDULE_PLUS_CANONICAL_GRACE_POLICY` | **Contradicción directa B:** regla de vencimiento depende de gracia aunque dueño eliminó gracia para VENCIDA | Proponer sucesora gobernada; **mora sigue sin definición** |
| `REG_CHK_CUO_006` VIGENTE | «en cualquier momento. No hay penalidades por cancelación anticipada.» | **Contradicción E:** cancelación incondicional frente a EN_PROCESO bloqueada | Diff literal L25-07, sin cambiar gratuidad y con copy propuesto |
| `REG_CHK_014` VIGENTE | «en cualquier momento desde "Mis operaciones". La cancelación no genera penalidades.» | **Contradicción E:** restricción EN_PROCESO aunque conservar cancelación VENCIDA | Diff literal L25-08; UX/Legal revisan copy sin reinterpretar decisión E |
| `REG_CLIENT_DEBT_SETTLEMENT_STATUS_001` VIGENTE | `states=[ACTIVE_BALANCE,FINAL_PAYMENT_PENDING_CONFIRMATION,SETTLED_CONFIRMED]` | **Brecha F:** no hay estado INCOBRABLE en este catálogo; no equivale a deuda saldada | Negocio/Legal/Finanzas deciden estatus y tratamiento contable; no cambiar regla ahora |
| `REG_CHK_CUO_009` y `REG_CHK_017` VIGENTE | Carta de no adeudo ligada a pago total/cancelación de deuda | **Riesgo F:** cancelación automática por deuda incobrable NO equivale a pago total | Conciliar Legal/ledger; no emitir carta por mero proceso F |
| `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001` VIGENTE | Canonical ledger `PEND-CLIENT-PAYMENT-LEDGER-001` pendiente | F requiere importe contractual por cuota, causas y fecha, sin contar PAGADA | Bloqueo Q02 ledger; no inventar tablas/campos físicos |
| `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` VIGENTE | Solo confirmación autoritativa acredita pago | F y C requieren respetar EN_PROCESO e idempotencia | Mantener control, verificar contrato Niubiz real |
| `REG_NIU_001` VIGENTE | Gateway «principal», todo pago vía Niubiz en MVP | **Precisión A:** dueño especifica único para tarjeta/Yape | Cambio documental L25-05, no extender a Yape recurrente |
| `REG_CHK_CUO_003`, `REG_CHK_011` CANDIDATO y `REG_CHK_010` VIGENTE | Historial de Yape y cobro inicial | A no decide recurrencia, recordatorio ni mecanismo cuota siguiente | NO MODIFICAR por este lote |
| `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001` VIGENTE | Política de recordatorios pendiente | Alerta de excepción a humano no es recordatorio al cliente | NO CAMBIO |

El resultado G25_06 halló exactamente **tres** reglas VIGENTE por patrón de gracia/cancelación: `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001`, `REG_CHK_CUO_006`, `REG_CHK_014`. Es búsqueda dirigida, NO auditoría universal. G25_02 encontró cuatro señales estructurales de key compartida (`L25-06`:1, `L25-07`:2, `L25-11`:1); **no** equivalen a cuatro contradicciones de negocio.

## Dependencias y orden propuesto (no ejecutado)

| Orden sugerido | Bloqueo | Prueba o decisión aceptable | Estado |
|---:|---|---|---|
| 1 | Aprobación formal de estas reglas candidatas | Firma del dueño y revisión de las sucesoras sin borrar VIGENTE | `PENDIENTE` |
| 2 | Ledger Q02 e identidad de plan/cuota | Monto contractual, fecha de cuota, estados, fuente del pago, registros de causa, idempotencia | `NO_PROBADO` L22 es solo requisitos |
| 3 | Contrato Niubiz + formato real de data/archivo | Claves de referencia, unicidad, importes, resultados, timestamps; no inventar layouts | `REQUIERE_REVISION_SEMANTICA` |
| 4 | Configuración F y pantalla de Producto | Parámetro versionado, valor inicial 12, autorización, historial, rango válido confirmado; negativo falta/inválido | `NO_IMPLEMENTADO` |
| 5 | Tratamiento de deuda INCOBRABLE | Estado, impacto contable, reporte, vínculo a saldo cancelado sin importes pagados, sin falsa carta de no adeudo | `PENDIENTE_NEGOCIO_LEGAL_FINANZAS` |
| 6 | Auditoría/alertas | Correo de excepción C con destinatario parámetro, sin PAN ni nombre; alerta de F falla cerrada sin canal supuesto | `PENDIENTE_OPERATIVO` |
| 7 | Owner de familia/Curator real | Mapa L13/17 fixture no prueba owner real; requiere identidad, dictamen y nueva autorización gobernada | `NO_PROBADO` |
| 8 | Definiciones no autorizadas | Mora/reintentos/recordatorios permanecen pendientes, no se rellenan | `PENDIENTE` |

## Evidencias SELECT y SHA-256 servidor

| SELECT | Filas | SHA-256 JSONB completo | Alcance OBJETIVO |
|---|---:|---|---|
| `G25_01` | 5 | `e062cf7af6d929a44d5ea5d07e85e8da7fe37905fa24bd559734ae83c490aa68` | Conteo por categoría y estado |
| `G25_02` | 13 | `d6bd8de4ad5e4ba404e362acac25158db7e5e92030bcbe95a1a040a18defaa8f` | Comparación Curator 13 propuestas, códigos, duplicados, keys y mapa L13 fixture |
| `G25_03` | 16 | `f4b5c23c1e0087b398a4439ecfb413f6789d1597d02d94a2a4789b0e2fe8bb06` | 16 reglas cercanas, citas de fuente truncadas a máximo 12 palabras |
| `G25_04` | 5 | `615577b24d8da32f8e8a6118ab859427fda83eaefc42e5b79bbaa266d8a2f48c` | MD5 reales de funciones LEGADAS en Supabase vivo |
| `G25_05` | 8 | `69562194551fcc4776e191ad35ea533d170869f3314a0cfac1dd0286a705cfb6` | 8 preimágenes y SHA-256 por regla revisada |
| `G25_06` | 3 | `ccde80ceaafe4aa2568e204e33220fbad2d0cfc76a9f83a6eadae7508d61660f` | Búsqueda dirigida por gracia y cancelación en VIGENTE |
| `G25_07` | 1 | `65980d83241ab76857f93f98c6b623508679a44faef41537d1048ff019143a64` | Códigos de reglas F y parámetro no presentes en lf_ops.reglas (búsqueda literal) |
| `G25_08` | 8 | `f338ec8eefbc51b7a4e93eb800f48951327cdb6342f9a413190f55bdb24b0c7f` | 8 reglas de pagos y deuda, incluyendo estados canónicos sin INCOBRABLE |
| `G25_09` | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` | Búsqueda literal de INCOBRABLE/antigüedad automática: 0 filas |

**Integridad de gates:** `G25_04` leyó funciones **LEGADAS** de Supabase: `lf_rule_promotion_apply_v1` md5 `d7fe763c999db6f6259b6b1e2bd69644`. Las cuatro funciones PG18 de L23 habían quedado intactas (apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8 guard `522d12f0843be1da3c785cef3c0bf3fc`). **L25 NO reejecutó PG18 ni modificó gates**. No comparar md5 legado y gate nuevo como si fuesen misma función.

**Fuente de mapa L13:** `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/02_seed_synthetic.sql` en base L22, fixture PG18; **no certificado como registro de owners desplegado**. Los 13 mapeos nominales `pago/niubiz/checkout → CHECKOUT_PAGOS`, `notificacion → CONTENIDO_COMUNICACIONES` son propuesta, no autorización de implementación.

**Fuentes de confianza:** inputs E/F del dueño, SELECT G25_01..09, preimágenes `04_diffs_literal_pre_post.json`, L22 solo contrato de requisitos ledger, L23 PG18 sandbox Curator no ejecutado aquí. Afirmaciones `OBJETIVO` solo sobre datos consultados; todo estado de adopción, causa contable, mapa de familia vivo y decisión de instalación es `REQUIERE_REVISION_SEMANTICA`.

**Resultado:** 13 propuestas + 1 parámetro CANDIDATO, 9 SELECT reproducibles, **0 reglas adoptadas**, **NO-GO / UNVERIFIED**.
