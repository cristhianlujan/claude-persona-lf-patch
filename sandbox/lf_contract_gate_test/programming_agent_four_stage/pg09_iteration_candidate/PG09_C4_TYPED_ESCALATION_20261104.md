# PG-09_C4 — Escalamiento tipado RETURN o BLOCKED (2026-11-04)

## Contrato oficial

El checkpoint `PG-09_C4` requiere **“Escalamiento tipado: RETURN o BLOCKED con diagnóstico”**. Su criterio de salida es **“Salida tipada”**. La ruta está definida en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

Este artefacto es exclusivamente **fuente candidata**. No ejecuta escalamiento, entrega mensajes, invoca al Worker, ni concede decisiones o nuevos intentos.

## Componente

Archivo: `tools/pg09_c4_typed_escalation_candidate_v1.py`.

API: `prepare_pg09_c4(pg09_c1, pg09_c2, pg09_c3, escalation_context)`.

Reutiliza los candidatos existentes:
- **PG-09_C1**: presupuesto por pedido/lote e intentos; si se reporta costo desconocido, límite alcanzado o presupuesto agotado, produce `BUDGET_DECISION`.
- **PG-09_C2**: estancamiento de iteraciones `STAGNATION` o alteración de alcance `MATERIAL_SCOPE_DRIFT`.
- **PG-09_C3**: intentos de bypass `QUALITY_BYPASS` y solicitudes de revisión de waiver `WAIVER_REVIEW`.

Exige digest SHA-256 de C1, C2 y C3, cadena C2→C1 y C3→C2, conjunto idéntico de soluciones, referencia de la corrida de C1 y referencia al Owner y evidencia diagnóstica para cada solución.

## Salidas

- `BLOCKED`: `QUALITY_BYPASS`, `STAGNATION` o `MATERIAL_SCOPE_DRIFT`. Si hay varios motivos, prevalece `BLOCKED`.
- `RETURN`: `BUDGET_DECISION`, `WAIVER_REVIEW` o `REVIEW_REQUIRED`, siempre que no exista un motivo de bloqueo. `RETURN` pide revisión, **no** es permiso de continuar.

La salida incluye `escalation_type`, `reason_codes`, `owner_decision_ref_reported`, `diagnostic_evidence_refs_reported` y vínculo a la corrida.

## Límites importantes

- El campo `owner_decision_ref` es una referencia proporcionada por el invocador, **no una solicitud enviada** ni una autorización recibida.
- La proyección conserva los diagnósticos reportados pero no autentica evidencia, costo real, contenido del diff o waivers.
- No reemplaza la autoridad del orquestador ni el enrutamiento gobernado de PG-10.
- Incluso si el diagnóstico reportado es `RETURN`, no se permite reintentar, escribir ni continuar.

Todos los resultados mantienen `escalation_delivered=false`, `owner_authorization_verified=false`, `evidence_authenticated=false`, `worker_execution_observed=false`, `retry_authorized=false`, `pg09_c4_pass=false`, `pg09_c4_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Estado

`PG09_C4_SOURCE_PREPARED / ESCALATION_NOT_DELIVERED / OFFICIAL_PENDING`.

**Siguiente:** PG-09_C5 — aseguramiento con casos de bucle adversariales y veredicto de calificación. Las pruebas oficiales continúan pausadas.

El PR #3528 permanece en draft. No se modifica Análisis, Supabase, main ni el producto.
