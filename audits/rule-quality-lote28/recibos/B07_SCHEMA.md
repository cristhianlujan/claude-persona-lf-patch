# PLANTILLA VACÍA — B07_SCHEMA (G11)

> Formato para recepción futura. NO_ES_RECIBO_EMITIDO. Este documento NO acredita control, no autoriza producción, no implica revisión y no tiene firma.

## Identificación — completar solo con evidencia futura
| Campo obligatorio | Valor |
|---|---|
| ID de bloqueo | B07_SCHEMA |
| Gate de aceptación | G11 |
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
- [ ] Draft UP/DOWN LF cuatro campos y SALY cinco con lifecycle_state diferenciado; evidencia / ID / SHA: ____________________
- [ ] Backfill, índices, RLS/GRANT, contratos de consumidores y rollback post-datos no destructivo; evidencia / ID / SHA: ____________________
- [ ] Evidencia de migración simulada representativa con readback y aceptación diseño; evidencia / ID / SHA: ____________________
- [ ] Identidad, competencia, firma y ámbito comprobados; readback: ____________________
- [ ] Gate G11 revisado contra texto L21; veredicto verificado: ____________________

## Veredicto — SIN SELECCIONAR
- [ ] ACEPTADO — recibo auténtico válido, dependencias y negativos acreditados
- [ ] RECHAZADO — insuficiente o contradictorio
- [ ] PENDIENTE — falta evidencia o autoridad

**Referencia de aceptación:** `audits/rule-quality-lote21/04_go_no_go_firmable.md`, gate G11; matriz `02_matriz_bloqueos_produccion.md` (base `4c3e376c`).

**Nunca completar con fixtures, promesas, conversación, autodeclaraciones ni hashes sin correlato RAW.**
