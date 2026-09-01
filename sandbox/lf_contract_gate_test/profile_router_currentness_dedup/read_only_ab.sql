-- RESEARCH_ONLY / READ_ONLY
-- LF EMPRESA / B2B-CARGA-001
-- No DDL. No DML. No Router/contract mutation. No SCOPED_PASS/downstream authorization.
-- Purpose: prove whether the already-existing known-current stage summary preserves
-- semantics after currentness has been established, before any implementation.

-- Positive/current control: run 218 must be current through both existing checks.
select
  programacion.fn_input_readiness_run_is_current(218) as full_current,
  programacion.fn_input_readiness_run_is_current_cached_v1(218) as cached_current;

-- Exact semantic A/B for the current run. Expected: true.
select
  programacion.fn_input_stage_gate_summary(218)
  = programacion.fn_input_stage_gate_summary_known_current_v1(218, true)
  as current_stage_exact_equal;

-- Negative/stale control: run 217 must remain rejected as current. Expected false/false.
select
  programacion.fn_input_readiness_run_is_current(217) as stale_full_current,
  programacion.fn_input_readiness_run_is_current_cached_v1(217) as stale_cached_current;

-- Fail-closed negative. This call MUST raise INPUT_STAGE_GATE_KNOWN_CURRENT_REQUIRED:217.
-- It is intentionally left commented so the file itself remains composable by read-only runners.
-- select programacion.fn_input_stage_gate_summary_known_current_v1(217, false);

-- Observed live before source creation (not an oracle; remeasure on execution):
-- run218 full stage summary ~14.55 s
-- run218 known-current stage summary ~11.3 ms
-- exact JSON equality = true
-- stale run217 full_current=false, cached_current=false
-- known-current(false) raises INPUT_STAGE_GATE_KNOWN_CURRENT_REQUIRED
--
-- Candidate direction only, NOT implementation authority:
-- fn_input_governance_execute currently calls fn_input_context_manifest(v_run),
-- whose current live definition recomputes fn_input_readiness_run_is_current and then
-- fn_input_stage_gate_summary. A future governed patch may deduplicate those checks only
-- after this A/B is independently re-run and context-manifest output identity is proven.
