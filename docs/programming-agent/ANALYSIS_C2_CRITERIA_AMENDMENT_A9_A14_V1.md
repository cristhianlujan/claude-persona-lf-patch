# Enmienda de criterios C2 para A9Q–A14Q (V1)

Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Alcance: solo los checkpoints `A9Q_C2` a `A14Q_C2`. Fecha: 2026-10-14 (America/Lima).

## Decisión del propietario

Ante la advertencia de que A9–A15 piden en C2 evidencia que un chat de GPT no puede producir (recibo del runtime, latencia y tokens medidos, identidad del proveedor, conciliación Git–Supabase), el propietario (Cristhian) respondió el 2026-10-14 00:37: "si no se puede medir entonces debemos eliminar esa regla". Se le presentó una tabla con el texto exacto de cada criterio reducido y respondió "ok" a las 00:41.

## Criterios (texto aprobado)

| Unidad | Criterio original (se conserva en la metadata) | Criterio de C2 enmendado |
|---|---|---|
| A9Q_C2 | Snapshot real A9 persistido con identidad y huellas verificables | Snapshot A9 producido por GPT con huellas del RAW verificadas |
| A10Q_C2 | Ejecuciones reales heterogéneas con evidencias por caso | Casos heterogéneos producidos por GPT con evidencia por caso |
| A11Q_C2 | Ejecuciones reales adversariales sobre ruta gobernada | Casos adversariales producidos por GPT, sin ejecución gobernada |
| A12Q_C2 | Inferencia real de ambos brazos con latencia y tokens observables | Ambos brazos producidos por GPT; latencia y tokens fuera del criterio |
| A13Q_C2 | Cambio del método no especializado al caso y nueva ejecución | Cambio de método propuesto por GPT; sin reejecución |
| A14Q_C2 | Respuestas reales en holdout con identidad del proveedor y costos | Respuestas de holdout por GPT; sin proveedor ni costos |

`A15Q_C2` **no** se enmienda: su criterio es la reconciliación misma y no tiene parte medible en un chat. Queda PENDING.

## Qué significa DONE bajo esta enmienda

DONE en estas unidades significa solo: GPT Native produjo el contenido en un chat, está atado por hash a la entrada congelada y pasó las comprobaciones deterministas del paquete. **No** significa que se midió, ejecutó ni atestó nada. Cada cierre registra `criterion_amendment` con el criterio original y el enmendado, y mantiene `provider_attested=false`, `real_execution_receipt=false`, `independent_review=false`.

## Qué no cambia

- El `exit_criterion` y los `acceptance_criteria` a nivel de unidad (p. ej. "3 current, real, independently verifiable checkpoint receipts, no false READY") siguen vigentes: la unidad no queda cualificada por esta enmienda.
- Las cláusulas contra recibos falsos del contrato de validador siguen aplicando a cualquier recibo real; la captura de chat no se presenta como recibo.
- C3 de todas las unidades y `A15Q_C1`/`A15Q_C2` no están cubiertos.
- No se escribe en `plan_units.exit_criterion` ni en el catálogo; la enmienda vive en el registro de cierre de cada checkpoint.
