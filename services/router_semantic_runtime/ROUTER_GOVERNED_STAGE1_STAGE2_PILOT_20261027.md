# ACT-0001 governed Stage1 → Stage2 pilot — 2026-10-27

Purpose: prove execution provenance before cutting over the existing Router entrypoints.

The operation is registered only as `CANDIDATO_READ_ONLY / OP_CANDIDATE`; it is not a Router cutover. Its governance rows are created under a `VULNERABILITY_COVERAGE_REPAIR_LF` bootstrap execution and that bootstrap is closed after materialization.\n\nThis pilot does not create a second routing engine. It registers `EJECUCION_ROUTER_LF` in the existing operation-governance framework and reuses:
- `public.lf_operation_execution`
- `public.lf_operation_execution_steps`
- `public.lf_record_operation_step_core_v1`
- `public.lf_router_stage1_validate_v2`
- `public.lf_router_route_v1`

Pilot sequence:
1. `request_intake`: bind immutable literal request to one router execution.
2. `stage1_seal`: validate LF_ROUTER_STAGE1_V2 and bind its digest to the same literal/execution.
3. `stage2_route`: internal-only continuation reads the sealed Stage1 from execution state and invokes Stage2.

External pilot surface:
- `public.lf_router_pipeline_begin_v1(text)` — service_role only.
- `public.lf_router_pipeline_stage1_submit_v1(text,jsonb)` — service_role only.
- `public.lf_router_pipeline_status_v1(text)` — audit/readback.
- `public.lf_router_pipeline_stage2_continue_v1(text)` is internal-only.

Anti-bypass:
- Stage2 cannot be invoked by service_role or read-only roles.
- The generic recorder core recomputes router trust server-side for `EJECUCION_ROUTER_LF`; caller-supplied `valid=true` is ignored.
- Stage2 reads Stage1 from durable execution evidence, never from caller input.
- Structural validity alone is insufficient: Stage1 literal and digest must match the execution intake.

Acceptance matrix is executed transactionally in the migration and rolled back:
- Stage2 before Stage1 => blocked.
- Valid-looking Stage1 for a different literal => blocked.
- Correct Stage1 => Stage2 route succeeds.
- Forged direct generic-recorder call => blocked.
- No postcheck execution residue.

This is a pilot only. Existing direct `lf_router_route_v1` grants are not removed until the governed path is proven and a separate cutover is approved.
