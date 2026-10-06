# Input Governance — política de persistencia de tests en sandbox

Estado: PROPUESTA. No cambia runtime ni base de datos.

## Regla

Ningún test, checkpoint de ingeniería, shadow run, probe, self-test o calificación puede persistir runs canónicos en `programacion.input_readiness_runs` del sandbox.

Los tests que necesiten ejercitar Curator/Validator deben usar datos efímeros con rollback transaccional o una superficie explícitamente no canónica. Un test no puede dejar como “último run” de una pantalla un run creado para validación técnica.

## Hallazgos actuales

- M3.9 / `SHADOW_RUN` es el caso prioritario: su spec ejecuta corpus real de tres pantallas, ids `[1,43,58]`.
- El repositorio contiene checkpoints/packets M3.9 en:
  - `supabase/migrations/20261005195626_engineering_capability_bind_receipt_completion_v1.sql`
  - `supabase/migrations/20261005210500_m39_shadow_sample3_policy_alignment_v1.sql`
  - `supabase/migrations/20261005183158_engineering_shadow_tequiv_run_test_chain_v1.sql`
  - `supabase/migrations/20261005195608_engineering_run_test_executable_packet_v1.sql`
- Los escritores runtime de runs canónicos incluyen bootstrap, recurate/source-stale y curator rebind/successor. Los tests que los invoquen contra pantallas reales deben demostrar no-persistencia.

## Criterio de aceptación

1. Antes/después del test, el último run canónico por `(version_id,pantalla_id)` es idéntico.
2. No aumenta el conteo persistente de `input_readiness_runs`, `input_family_assessments` ni `input_gap_proposals` por efecto del test.
3. M3.9 SHADOW_RUN conserva sus tres pantallas como corpus de lectura/ejecución, pero no deja runs canónicos.
4. Toda excepción requiere una migración/operación explícita, no un test.
