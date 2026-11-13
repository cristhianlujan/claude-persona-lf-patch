# PLANTILLA VACÍA — B14_RESTORE (G10)

> Formato para recepción futura. NO_ES_RECIBO_EMITIDO. Este documento NO acredita control, no autoriza producción, no implica revisión y no tiene firma.

## Identificación — completar solo con evidencia futura
| Campo obligatorio | Valor |
|---|---|
| ID de bloqueo | B14_RESTORE |
| Gate de aceptación | G10 |
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
- [ ] Job de restore real desde backup/PITR en entorno aislado autorizado; evidencia / ID / SHA: ____________________
- [ ] Readback y SHA/checksum antes/después, integridad y roles/keys; evidencia / ID / SHA: ____________________
- [ ] RPO/RTO medidos, bitácora del ensayo, firma DBA/Continuidad y dueño; evidencia / ID / SHA: ____________________
- [ ] Identidad, competencia, firma y ámbito comprobados; readback: ____________________
- [ ] Gate G10 revisado contra texto L21; veredicto verificado: ____________________

## Veredicto — SIN SELECCIONAR
- [ ] ACEPTADO — recibo auténtico válido, dependencias y negativos acreditados
- [ ] RECHAZADO — insuficiente o contradictorio
- [ ] PENDIENTE — falta evidencia o autoridad

**Referencia de aceptación:** `audits/rule-quality-lote21/04_go_no_go_firmable.md`, gate G10; matriz `02_matriz_bloqueos_produccion.md` (base `4c3e376c`).

**Nunca completar con fixtures, promesas, conversación, autodeclaraciones ni hashes sin correlato RAW.**
