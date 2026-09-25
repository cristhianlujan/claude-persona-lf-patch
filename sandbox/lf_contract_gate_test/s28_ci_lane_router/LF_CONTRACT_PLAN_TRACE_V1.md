# LF_CONTRACT_PLAN_TRACE_V1

## Propósito

Persistir la decisión de applicability de `lf-contract-check` sin crear una nueva autoridad de routing, un nuevo registry, una nueva operación ni una nueva tabla.

La solución transforma el `lf-ci-execution-plan/v2` existente en un envelope durable para `GITHUB_CONTRACT_GATE_LF` y reutiliza `public.fn_lf_operation_reserve_execution_v1` / `public.lf_operation_execution` como autoridad de ejecución.

## Frontera

Esta solución **sí**:

- valida que el plan corresponde al exact head;
- valida `changed_paths`, `required_controls`, razones, carriers, currentness y digests;
- genera identidad idempotente por GitHub run + attempt + exact source;
- conserva en `manifest` los datos necesarios para reconstruir por qué se seleccionó cada control;
- genera SQL para la autoridad existente de reserva de ejecución.

Esta solución **no**:

- clasifica cambios;
- decide controles o soluciones;
- calcula dependency closure;
- ejecuta controles;
- conecta por sí misma a Supabase;
- finaliza la ejecución;
- escribe EKB;
- modifica Migration Parity;
- crea un workflow paralelo.

## Entrada

Plan canónico `lf-ci-execution-plan/v2` producido por `LF_CI_EXECUTION_PLAN_V2`, más contexto exacto de GitHub:

- repository;
- run id;
- run attempt;
- workflow event;
- exact source SHA.

## Salida

`lf-contract-plan-trace/v1` con:

- `changed_files` / `changed_paths`;
- `lane_mode`;
- `required_controls`;
- `required_control_reasons`;
- `not_applicable_controls`;
- `carrier_controls`;
- `full_regression` y razón;
- `plan_sha256`;
- `applicability_sha256`;
- `evidence_sha256`;
- currentness y authority revision.

El `request_sha256` de la reserva es `evidence_sha256`, por lo que el mismo run/attempt/source solo puede repetir exactamente el mismo plan. Un plan distinto con la misma idempotency key debe fallar cerrado mediante la autoridad existente.

## Evolución semántica

El campo actual sigue llamándose `required_controls` porque esa es la semántica de `LF_CI_EXECUTION_PLAN_V2` vigente. El envelope marca explícitamente `REQUIRED_CONTROLS_PRE_SOLUTION_REFACTOR`; no adelanta el cambio a `required_solutions` antes de que exista el contrato arquitectónico correspondiente.

## Dependencias

- `CI_FAST_DEEP_LANE_ROUTER` — produce applicability.
- `LF_CI_EXECUTION_PLAN_V2` — produce el plan canónico y dependency closure.
- `CURRENTNESS_AUTHORITY` — queda representada por `source_authority` y `authority_evidence_revision`.
- `public.fn_lf_operation_reserve_execution_v1` — persistencia idempotente existente.
- `public.lf_operation_execution` — ledger existente.

## Consumo previsto

`GITHUB_CONTRACT_GATE_LF` debe consumir esta solución en un PR independiente de wiring. Ese PR debe ejecutar el emitter inmediatamente después de congelar el plan, antes de ejecutar soluciones/controles, y reutilizar la misma identidad de ejecución para PRE_EKB y cierre final.

## Invariantes

1. Una sola autoridad de applicability: no se recalcula aquí.
2. Una sola identidad de ejecución por run/attempt/source.
3. Exact-head obligatorio.
4. `evidence_sha256` debe recalcular correctamente sobre el plan enriquecido.
5. La unión de `carrier_controls` debe ser exactamente `required_controls`.
6. El emitter es transport-only: no ejecuta SQL.
7. No ZIP.
