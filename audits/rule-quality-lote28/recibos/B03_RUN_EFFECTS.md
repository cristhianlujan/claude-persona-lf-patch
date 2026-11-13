# PLANTILLA VACÍA — B03_RUN_EFFECTS (G02)

> Formato para recepción futura. NO_ES_RECIBO_EMITIDO. Este documento NO acredita control, no autoriza producción, no implica revisión y no tiene firma.

## Identificación — completar solo con evidencia futura
| Campo obligatorio | Valor |
|---|---|
| ID de bloqueo | B03_RUN_EFFECTS |
| Gate de aceptación | G02 |
| Proyecto(s) / familia(s) afectadas | ____________________ |
| Alcance literal / exclusiones | ____________________ |
| Entorno / instancia | ____________________ |
| RUN / operación (si aplica) | ____________________ |
| Versión de contrato / commit | ____________________ |
| Responsable de evidencia / identidad / sub | ____________________ |
| Autoridad firmante / identidad / sub | ____________________ |
| Fecha UTC / as_of | ____________________ |
| Fuente RAW / ruta / ID | ____________________ |
| Hash SHA-256 y método | ____________________ |
| Prueba positiva / referencia | ____________________ |
| Prueba negativa / referencia | ____________________ |
| Readback independiente / referencia | ____________________ |
| Dependencias cerradas / recibos enlazados | ____________________ |
| Excepciones y riesgo residual | ____________________ |
| Evidencia de segregación y auditoría | ____________________ |
| Firma autenticada / recibo | ____________________ |
| Dictamen / justificación textual | ____________________ |

## Lista de aceptación — SIN MARCAR
- [ ] RUN_PREIMAGE y EFFECT_RECON individuales, escritor, idempotency key y sinks; evidencia / ID / SHA: ____________________
- [ ] LIVENESS real de worker/heartbeat, clasificación A/B/C/D revisada y 8 leases; evidencia / ID / SHA: ____________________
- [ ] Guardas SUCCEEDED y readback de commits/efectos externos, sin cierres/reintentos ciegos; evidencia / ID / SHA: ____________________
- [ ] Identidad, competencia, firma y ámbito comprobados; readback: ____________________
- [ ] Gate G02 revisado contra texto L21; veredicto verificado: ____________________

## Veredicto — SIN SELECCIONAR
- [ ] ACEPTADO — recibo auténtico válido, dependencias y negativos acreditados
- [ ] RECHAZADO — insuficiente o contradictorio
- [ ] PENDIENTE — falta evidencia o autoridad

**Referencia de aceptación:** `audits/rule-quality-lote21/04_go_no_go_firmable.md`, gate G02; matriz `02_matriz_bloqueos_produccion.md` (base `4c3e376c`).

**Nunca completar con fixtures, promesas, conversación, autodeclaraciones ni hashes sin correlato RAW.**
