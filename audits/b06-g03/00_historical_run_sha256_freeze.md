# B06 G03 — Freeze de hashes de RUN históricos (SOLO READ-ONLY)

Origen: SELECT de `public.lf_operation_execution` y `public.lf_operation_execution_steps` en Supabase LF actual.
Fecha: 2026-11-13. Corte de cohorte: `started_at < 2026-11-13 07:20:12.513028+00` (inicio del RUN real de backfill #3806).
**Advertencia temporal:** esta captura se hizo **después** del backfill #3806; es una preimagen congelada PARA READBACK FUTURO y NO demuestra por sí sola que las filas estén idénticas al estado ANTERIOR a #3806.

## Cobertura
- RUN históricos congelados: **2456/2456** IDs únicos
- Pasos vinculados a esos RUN: **8244** (en 1306 RUN; los RUN sin pasos se incluyen con count=0 y digest NULL)
- 13 CSV particionados y ordenados por `execution_id COLLATE "C"`; ninguna fila de contenido/manifest sensible se exporta, solo ID y SHA-256.
- `row_sha256=SHA256(UTF8(to_jsonb(lf_operation_execution.*)::text))` sin omitir campos; incluye status, lease, manifest, timestamps y todo el row.
- `steps_bundle_sha256=SHA256(UTF8(string_agg(step_order TAB step_id TAB SHA256(UTF8(to_jsonb(step.*)::text)), LF ORDER BY step_order,step_id COLLATE "C")))`; null si no hay pasos.
- Root de la cohorte `SHA256(UTF8(string_agg(execution_id TAB row_sha256 TAB steps_count TAB COALESCE(steps_bundle_sha256,'-'),LF ORDER BY execution_id COLLATE "C")))`.
- **Root SHA-256 SQL antes/después del freeze:** `7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02`.
- Confirmados conteos y root idénticos en dos SELECT antes/después de extraer los 13 fragmentos.

## Límite de la prueba
El conjunto congelado en este commit se cotejará por ID y hashes con un readback nuevo, para acreditar integridad POST-FREEZE. **No equivale a comparar con preimagen PRE-BACKFILL**. Para afirmar `cero RUN antiguos alterados desde antes de #3806` se requiere snapshot previo del mismo universo/algoritmo, copia de backup temporal previa o cadena de auditoría por fila comparable. Hasta entonces: aspecto retroactivo NO ACREDITADO. No modificar RUNs.

Referencia normativa: `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md`, apartado `B06_OWNER · G03`, rama `lf/issue-3779-lote28-blocker-closure-plan-v1`.
