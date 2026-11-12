# LF — LOTE 25 | Propuestas de reglas para cuotas (Q03/Q04)

**Resultado documental: PROPUESTAS / NO-GO / UNVERIFIED.** Se leen reglas VIGENTE y CANDIDATO en Supabase vivo sin modificarlas. No hay DML/DDL, operaciones, tests PG18 ni edición de gates en L25. El juez que redacta y revisa es **GPT-6, mismo modelo, NO independiente**; no se acredita identidad «Claude».

**Alcance:** exclusivamente las decisiones literales A–D aportadas por el dueño en L25. Formato real del archivo/data Niubiz, políticas de mora, reintentos y recordatorios, cancelación de VENCIDA y confirmación del bloqueo EN_PROCESO: **PENDIENTE**; no se completan por inferencia.

## Resumen verificable

| Tipo | Cantidad | Gobierno |
|---|---:|---|
| Reglas nuevas | 4 | CANDIDATO propuesto, no INSERT |
| Cambios sobre VIGENTE | 4 | Sustitución/versión gobernada pendiente, no UPDATE en sitio |
| Reglas revisadas sin modificación | 4 | Mantienen literalmente estado y configuración vigentes/candidatos |
| Total | **12** | **0 aprobaciones / 0 mutaciones** |

**Chequeo Curator SELECT G25_02:** cuatro códigos nuevos libres (0 coincidencias), ocho códigos referidos existentes (1 coincidencia cada uno), **0 duplicados literales de contenido contra VIGENTE**. Doce de doce propuestas coinciden con el mapeo de categorías del **fixture L13**, no con un registro de familias aprobado en vivo. Se observan 4 señales de claves compartidas diferentes (1 en L25-06, 2 en L25-07, 1 en L25-11), que **no son prueba de contradicción semántica**. SHA-256 G25_02: `596bc90a902c5d65d0569b224bf0bd567dc32374b7f3833052ff94abb6c8ea39`.

## Formalización de los requisitos del dueño

- **A / Q03:** Niubiz único proveedor de recaudo; tarjeta y Yape. NO se infiere débito recurrente Yape, habilitación comercial, SDK ni formato de archivo.
- **B / Q04:** PENDIENTE inicial; EN_PROCESO por intento abierto; PAGADA confirmada terminal; VENCIDA por fecha, sin gracia, corte 00:00 America/Lima; CANCELADA terminal; rechazo solo no vence.
- **C / Q04:** cada EN_PROCESO se reconcilia al corte. Confirmado→PAGADA. Rechazado→VENCIDA si ya venció; caso contrario PENDIENTE. NO_DETERMINADO→continúa EN_PROCESO con excepción, escalamiento humano y correo con datos permitidos y destinatario configurable. Idempotencia exigida. **La frase general «ninguna cuota puede quedar EN_PROCESO» tiene esta excepción expresa del dueño.**
- **D / Q04:** cancelación por cuota o plan, PAGADA/CANCELADA no cambian; EN_PROCESO bloqueada hasta reconciliar es **SUPUESTO NO CONFIRMADO**, y VENCIDA queda **PENDIENTE_DE_LEGAL**. No crear política sustitutiva.

## 12 fichas de propuesta

### L25-01 · `REG_CLIENT_INSTALLMENT_STATUS_025`

- **Clase:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(B): cinco estados de cuota; PENDIENTE inicial, EN_PROCESO si intento abierto, PAGADA/CANCELADA finales, VENCIDA por fecha 00:00 Lima sin gracia. Excepción NO_DETERMINADO preserva EN_PROCESO.
- **OBJETIVO — SELECT Curator:** código vivo 0; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **Contrato propuesto completo:** `01_propuestas_reglas.json`; solo nueva, sin preimagen de regla del mismo código.

### L25-02 · `REG_CLIENT_INSTALLMENT_MIDNIGHT_RECON_025`

- **Clase:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(C): conciliación a medianoche con Niubiz; confirmado→PAGADA, rechazado→VENCIDA o PENDIENTE según fecha, indeterminado→EN_PROCESO y excepción; idempotencia; archivo real desconocido.
- **OBJETIVO — SELECT Curator:** código vivo 0; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **Contrato propuesto completo:** `01_propuestas_reglas.json`; solo nueva, sin preimagen de regla del mismo código.

### L25-03 · `REG_CLIENT_INSTALLMENT_RECON_ALERT_025`

- **Clase:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `notificacion` / `CONTENIDO_COMUNICACIONES`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(C): correo de excepción a humano con cuota/referencia/monto/fecha/motivo; destinatario parametrizable; sin tarjeta ni nombre. Separada de recordatorios.
- **OBJETIVO — SELECT Curator:** código vivo 0; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **Contrato propuesto completo:** `01_propuestas_reglas.json`; solo nueva, sin preimagen de regla del mismo código.

### L25-04 · `REG_CLIENT_INSTALLMENT_CANCELLATION_025`

- **Clase:** `NUEVA_PROPUESTA`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(D): cancelar cuota o plan, PAGADA/CANCELADA inmutables; EN_PROCESO bloqueado solo como supuesto pendiente del dueño; VENCIDA pendiente Legal.
- **OBJETIVO — SELECT Curator:** código vivo 0; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **Contrato propuesto completo:** `01_propuestas_reglas.json`; solo nueva, sin preimagen de regla del mismo código.

### L25-05 · `REG_NIU_001`

- **Clase:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `niubiz` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q03(A): convierte proveedor «principal» en «único» para recaudo con tarjeta y Yape; preserva exclusividad MVP, sin decidir recurrencia Yape.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (9 palabras):** «Niubiz es el gateway de pago principal del producto».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-05`; 5 cambios de campo.

### L25-06 · `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001`

- **Clase:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `pago` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(B/C): sustituye overdue_authority dependiente de gracia por fecha contractual sin gracia, corte Lima y excepción indeterminada; mora sin definir.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 1; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (9 palabras):** «fecha contractual y de una política de gracia/mora gobernada.».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-06`; 6 cambios de campo.
- **Campo relevante antes → después:** `valor_config.overdue_authority`: `CONTRACTUAL_SCHEDULE_PLUS_CANONICAL_GRACE_POLICY` → `CONTRACTUAL_DUE_DATE_NO_GRACE_AMERICA_LIMA`.
- **REQUIERE_REVISION_SEMANTICA — señal de keys:** `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001`; revisar significado antes de decidir, no afirmar contradicción automáticamente.

### L25-07 · `REG_CHK_CUO_006`

- **Clase:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(D): «en cualquier momento» requiere excepción propuesta EN_PROCESO; conserva sin penalidades y visibilidad en checkout; copy pendiente.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 2; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (9 palabras):** «en cualquier momento. No hay penalidades por cancelación anticipada.».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-07`; 5 cambios de campo.
- **REQUIERE_REVISION_SEMANTICA — señal de keys:** `REG_CHK_020`, `REG_CHK_CUO_008`; revisar significado antes de decidir, no afirmar contradicción automáticamente.

### L25-08 · `REG_CHK_014`

- **Clase:** `CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Q04(D): similar incompatibilidad con «en cualquier momento» en Mis operaciones; conserva sin penalidades y no adeudo solo ante deuda totalmente cancelada.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (11 palabras):** «en cualquier momento desde "Mis operaciones". La cancelación no genera penalidades.».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-08`; 4 cambios de campo.

### L25-09 · `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001`

- **Clase:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `notificacion` / `CONTENIDO_COMUNICACIONES`; **estado:** `VIGENTE` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Sin cambio: recordatorios siguen pendientes. Correo de excepción de conciliación tiene propósito diferente.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (11 palabras):** «La política exacta de anticipación, frecuencia y canales debe ser configurable».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-09`; 0 cambios de campo.
- **Decisión:** `SIN_CAMBIO`; JSON literal antes/después idéntico. No se resuelve aquello que el dueño dejó pendiente.

### L25-10 · `REG_CHK_CUO_003`

- **Clase:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Sin cambio: decisión de proveedor único no resuelve Yape para cuotas siguientes ni se añade recordatorio WhatsApp.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (8 palabras):** «Las cuotas siguientes no pueden cobrarse por Yape.».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-10`; 0 cambios de campo.
- **Decisión:** `SIN_CAMBIO`; JSON literal antes/después idéntico. No se resuelve aquello que el dueño dejó pendiente.

### L25-11 · `REG_CHK_CUO_009`

- **Clase:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado:** `VIGENTE` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Sin cambio: no adeudo tras total de deuda pagada; cancelar plan/cuota no acredita deuda cancelada.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 1; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (14 palabras):** «la carta de no adeudo se emite cuando el usuario completa el pago total».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-11`; 0 cambios de campo.
- **Decisión:** `SIN_CAMBIO`; JSON literal antes/después idéntico. No se resuelve aquello que el dueño dejó pendiente.
- **REQUIERE_REVISION_SEMANTICA — señal de keys:** `REG_CHK_017`; revisar significado antes de decidir, no afirmar contradicción automáticamente.

### L25-12 · `REG_CHK_011`

- **Clase:** `REVISADA_SIN_CAMBIO_PROPUESTO`; **categoría/familia propuesta:** `checkout` / `CHECKOUT_PAGOS`; **estado:** `CANDIDATO` (en cambios: versión conceptual, no tocar VIGENTE).
- **REQUIERE_REVISION_SEMANTICA — alcance:** Sin cambio: Niubiz como proveedor no determina la recurrencia Yape ni nuevos recordatorios.
- **OBJETIVO — SELECT Curator:** código vivo 1; duplicados de contenido exactos VIGENTE 0; diferencia estructural potencial en otros VIGENTE 0; mapeo L13 fixture coincide.
- **OBJETIVO — cita literal de fuente (13 palabras):** «El mecanismo para cobrar las cuotas siguientes cuando el usuario pagó con Yape».
- **Diff completo:** `04_diffs_literal_pre_post.json` → `L25-12`; 0 cambios de campo.
- **Decisión:** `SIN_CAMBIO`; JSON literal antes/después idéntico. No se resuelve aquello que el dueño dejó pendiente.

## Contradicciones de políticas existentes si se adopta el paquete

| Regla vigente | Evidencia OBJETIVO | Riesgo frente a decisión del dueño | Clasificación / acción propuesta |
|---|---|---|---|
| `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` | `overdue_authority=CONTRACTUAL_SCHEDULE_PLUS_CANONICAL_GRACE_POLICY` | **Contradicción directa** con SIN gracia para VENCIDA. | REQUIERE_REVISION_SEMANTICA: sustituir mediante versión gobernada y conservar definición de mora pendiente. |
| `REG_CHK_CUO_006` | «en cualquier momento» y sin penalidad | **Contradicción condicional** si el dueño confirma no cancelar EN_PROCESO. | Pendiente de confirmación y copy; no cambiar aún. |
| `REG_CHK_014` | «en cualquier momento» desde Mis operaciones | **Contradicción condicional** con EN_PROCESO si el dueño confirma. | Versionar sin prometer cancelación irrestricta. |
| `REG_NIU_001` | define «principal» pero todo pago por Niubiz en MVP | **Precisión insuficiente**, no contradicción dura: Q03 especifica proveedor único para tarjeta/Yape. | Cambio propuesto al mismo contrato; validar integración/contrato Niubiz. |
| `REG_CHK_CUO_009` y `REG_CHK_017` | última cuota pagada versus cancelación de deuda total | Potencial incoherencia de condiciones de Carta de No Adeudo ya existente, **no originada** por cancelación del plan. | Revisar Legal/ledger; no afirmar que cancelar plan extingue deuda. |
| `REG_CHK_CUO_003`, `REG_CHK_011`, `REG_CHK_010` | Yape inicial y textos históricos con cuotas manuales/recordatorios | Q03 solo decide proveedor; no autoriza modalidad recurrente Yape ni recordatorios. | NO CAMBIO / detalle pendiente; no extender política. |
| `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001` | `schedule_policy=PENDING_CANONICAL_DUE_REMINDER_POLICY` | No contradice alerta humana por excepción: recordatorios de cliente son otra función. | NO CAMBIO / mantener pendientes canales y plazos. |
| `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` | outcomes autoritativos y bloqueo mientras confirmación pendiente | Compatible en principio con reconciliación, pero necesita mapping Niubiz real. | Sin cambio; contrato del proveedor y ledger pendientes. |

**Señales estructurales G25_02:** `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` frente L25-06, `REG_CHK_020` y `REG_CHK_CUO_008` frente L25-07, y `REG_CHK_017` frente L25-11. Los dos del checkout provienen de claves compartidas con **significados distintos** (p. ej. `posicion`); no elevar a conflicto semántico sin justificar.

## Dependencias de adopción / gates de gobierno

| Orden sugerido | Dependencia | Evidencia que falta | Estado |
|---:|---|---|---|
| 1 | Firma de dueño y Legal | Decisión sobre EN_PROCESO; Legal sobre cancelar VENCIDA; regla de estado sin gracia | **PENDIENTE** |
| 2 | Ledger Q02 canónico | Identidad cuota, cronograma contractual, monto confirmable, estados e idempotencia en fuente autoritativa | **NO_VERIFICADO**; L22 solo requisitos |
| 3 | Contrato Niubiz tarjeta/Yape | Acuerdo/credenciales y outcomes reales, referencia, monto, conciliación, límites del proveedor | **NO_VERIFICADO** |
| 4 | Data o archivo Niubiz | Formato real, unicidad de referencia, tiempo de respuesta, semántica confirmado/rechazado/no determinado | **REQUIERE_REVISION_SEMANTICA**; no inventado |
| 5 | Configuración de alertas | Parámetro de destinatario de correo sin direcciones embebidas, control de detalle y escalamiento | **PENDIENTE** |
| 6 | Familias y owners | Mapeo categoría/familia y perfil owner LF validados fuera del fixture L13/L17 | **NO_VERIFICADO** |
| 7 | Contratos pendientes | Mora, reintentos, recordatorios continúan SIN definición nueva | **PENDIENTE** |
| 8 | Adopción futura | Curator real, revisión independiente si contrato lo exige, firmas, tests E2E, backup/rollback y operaciones gobernadas | **NO-GO** |

## Evidencia SELECT y clasificación

| Consulta | Filas | SHA-256 servidor | Qué verifica |
|---|---:|---|---|
| `G25_01` | 5 | `e062cf7af6d929a44d5ea5d07e85e8da7fe37905fa24bd559734ae83c490aa68` | Conteos por categoría/estado |
| `G25_02` | 12 | `596bc90a902c5d65d0569b224bf0bd567dc32374b7f3833052ff94abb6c8ea39` | 12 comparaciones Curator (código/duplicados/keys/L13) |
| `G25_03` | 16 | `a0aebc613bd8a8358bec8d9a3ee9801ee3a22301cd8ffa75ac73129784a80107` | 16 reglas relacionadas para detectar contradicciones |
| `G25_04` | 5 | `615577b24d8da32f8e8a6118ab859427fda83eaefc42e5b79bbaa266d8a2f48c` | MD5 de funciones legadas que están en vivo |
| `G25_05` | 8 | `69562194551fcc4776e191ad35ea533d170869f3314a0cfac1dd0286a705cfb6` | 8 SHA-256 por preimagen literal |

**MD5 de gates:** en Supabase vivo G25_04 se ve `public.lf_rule_promotion_apply_v1` LEGADA md5 `d7fe763c999db6f6259b6b1e2bd69644`; no es el gate PG18 nuevo. Los cuatro MD5 PG18 inalterados fueron verificados en L23 (ejecución anterior; **NO se reejecutaron en L25**): apply `86b0494984edf95cf0f9c0a0df67000b`, capture `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation `773a62783baa5edbe967200cac66b8c3`, L8 `522d12f0843be1da3c785cef3c0bf3fc`. Ningún SQL de gates se edita desde esta rama.

Fuentes: `01_propuestas_reglas.json`, `02_curator_live_readonly.sql`, `03_curator_readback.json`, `04_diffs_literal_pre_post.json`; L13 mapa de prueba Git blob `52cbec6d11b66709b03bcf9e2c0ef2eebe005d38`; L22 ledger blob `522f98fa6af610656e53373955d8daddc55f94da`; EKB V1.4 SHA-256 `234fafb2b06b91e96a979feac138069ec75863aae1bd75aea93c72740c075f79`.

**Límite:** SELECT confirma ausencia de duplicado exacto bajo igualdad literal, no demuestra equivalencia semántica general. El mapeo L13 es sintético, no registro de owners desplegado. Q03/Q04 son decisiones comunicadas por el dueño, pero las nuevas reglas/cambios siguen siendo **PROPUESTAS CANDIDATO que requieren aprobación de dueño y operación gobernada posterior**.

**Resultado: DOCUMENTOS_VERIFICABLES / REGLAS_NO_ADOPTADAS / NO-GO / UNVERIFIED.**
