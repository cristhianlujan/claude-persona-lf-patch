# Enmienda de criterios C3 para A9Q, A12Q y A13Q (V1)

Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Alcance: solo los checkpoints `A9Q_C3`, `A12Q_C3` y `A13Q_C3`. Fecha: 2026-10-14 (America/Lima).

## Decisión del propietario

La decisión `ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1` dejó dicho que los criterios C3 no medibles de A9, A12 y A13 requerían una enmienda aprobada aparte. Se presentó al propietario (Cristhian) el texto exacto de cada criterio reducido y respondió "Sí, aprobar los 3" el 2026-10-14.

## Criterios (texto aprobado)

| Unidad | Criterio original (se conserva en la metadata) | Criterio de C3 enmendado |
|---|---|---|
| A9Q_C3 | PG-01 consume exacto recibo; negativos de drift/bloqueo rechazan | Revisor ciego verifica que el snapshot A9 es coherente con A7 y A8 de la entrada y que un snapshot con deriva se rechaza |
| A12Q_C3 | Juez independiente calcula calidad, costo y sobreanálisis sin proxies | Revisor ciego verifica cobertura de ambos brazos y totales exactos de la comparación, sin calidad, costo ni latencia |
| A13Q_C3 | Regresión adversarial y semántica confirma mejora sin pérdidas | Revisor ciego verifica que el cambio de método propuesto es general, acotado a un componente y no afirma ejecución ni mejora medida |

## Qué significa DONE bajo esta enmienda

DONE en estas unidades significa solo: un chat de GPT distinto al del productor de C2 recibió el paquete ciego (salida real más un señuelo), aplicó los tres chequeos del criterio enmendado, aprobó la salida real y rechazó el señuelo, y la respuesta pasó el verificador determinista fijado antes de verla. No significa que se haya ejecutado una regresión, calculado calidad o costo, ni contado con un recibo real del proveedor. Cada cierre registra `provider_attested=false`, `real_execution_receipt=false` e `independent_review=false`.

## Qué no cambia

- El `exit_criterion` y los `acceptance_criteria` a nivel de unidad siguen vigentes: la unidad no queda cualificada por esta enmienda.
- No se escribe en `plan_units.exit_criterion` ni en el catálogo; la enmienda vive en el registro de cierre de cada checkpoint.
- No cubre `A15Q_C1`, `A15Q_C2` ni `A15Q_C3`.
- Reversible hacia adelante: un recibo real del proveedor puede reemplazar este nivel.
