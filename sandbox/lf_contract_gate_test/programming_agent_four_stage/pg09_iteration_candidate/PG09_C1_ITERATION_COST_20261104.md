# PG-09_C1 — Gobernador de iteraciones y costos, fuente candidata (2026-11-04)

## Mandato oficial

`PG-09_C1`: “Límites de iteración y costo por lote y presupuesto por pedido medido con consumo real (D16/D17): aviso al 80 %, REQUIRES_DECISION al 100 %; reutiliza el límite de intentos del Worker”.

Criterio de salida: **“Política fijada; prueba de presupuesto agotado → se detiene sin recortar calidad”**. Fuente del plan: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

## Reutilización

No se crea un segundo Worker, motor de retry ni despachador. El código consume:
- `PG07_C1_WORKER_DISPATCH_PLAN_CANDIDATE_V1`: vínculo de corrida, proveedor/modelo y moneda de precios declarada.
- `PG07_C5_ITERATION_GUARD_CANDIDATE_V1`: iteraciones previamente proyectadas y bloqueo de cambios de objetivo/scope.
- Contrato `max_attempts_per_solution` y referencia `existing_worker_limit_ref`, **sin conceder intentos** ni sustituir el límite real del Worker.

## Implementación

`tools/pg09_c1_iteration_cost_governor_candidate_v1.py`

Función: `prepare_pg09_c1(pg07_c1, pg07_c5, budget_policy, usage_observations)`.

El invocador debe aportar una política explícita de moneda, tope por solicitud, tope por lote, máximo de intentos y referencia a la política existente. Se usa aritmética decimal, sin convertir monedas ni inventar tarifas.

Cada solución declara `GPT_NATIVE`, `CLAUDE_NATIVE` o `WORKER_API`, lote, intentos consumidos y llamadas con proveedor, modelo, tokens de entrada/salida/caché, referencia a recibo y costo reportado.

- **Menos de 80 %:** solo `REPORTED_WITHIN_BUDGET_UNVERIFIED`.
- **Desde 80 %, antes de 100 %:** `WARN_80_PERCENT`.
- **Desde 100 %:** `REQUIRES_DECISION`; la salida nunca autoriza otra iteración.
- **Límite de intentos alcanzado:** `REQUIRES_DECISION`.
- **Costo no observable o incompleto:** `REQUIRES_DECISION`, no se contabiliza como cero.

Para ejecuciones `GPT_NATIVE/CLAUDE_NATIVE`, incluso si se declarara un costo, no se asume equivalencia con el modelo de facturación API del Worker: el costo sigue clasificado como desconocido para decidir el consumo contractual, hasta que exista medición y política autorizada para esos modos.

Se comprueba forma de referencias, identidad de llamadas única, contadores enteros no negativos, moneda consistente y no se infiere cómo el proveedor factura tokens caché. `reported_cost` es un valor aportado por el invocador, no una verificación de la factura ni del ledger.

## Limitaciones y autoridad

Esta implementación **no** obtiene gastos reales del proveedor, no autentica recibos, no prueba que el límite de intentos declarado corresponda al Worker real y no interviene en la ejecución del modelo. Las declaraciones de costos inferiores al tope **no son evidencia de presupuesto libre**.

La salida mantiene `usage_receipts_authenticated=false`, `budget_policy_authenticated=false`, `worker_limits_authenticated=false`, `provider_costs_verified=false`, `iteration_authorized=false`, `retry_authorized=false`, `pg09_c1_pass=false`, `pg09_c1_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

**Estado:** `PG09_C1_SOURCE_PREPARED / RUNTIME_SPEND_UNVERIFIED / OFFICIAL_PENDING`.

Para calificar el checkpoint se necesita observar consumos reales, revalidar política por corrida, probar aviso al 80 % y bloqueo al 100 % con recibos auténticos y obtener dictamen independiente. No se ejecutaron pruebas oficiales por la pausa establecida por el Owner. Sin cambios en Análisis, Supabase, main ni producto. El desarrollo queda aislado en PR #3528 draft.

**Siguiente:** PG-09_C2 — detección de ausencia de convergencia en iteraciones repetidas.
