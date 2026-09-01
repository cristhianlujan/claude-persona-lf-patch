-- RESEARCH_ONLY / READ_ONLY
-- LF EMPRESA / B2B-CARGA-001 / Issue #402 / PR #417
-- Purpose: isolate the cost of currentness-related subcomponents without changing
-- Router, Input Governance contracts, timeout, adapter authority, or downstream state.
-- No DDL. No DML. No SCOPED_PASS. No downstream/production authorization.

-- Current/stale controls.
select
  programacion.fn_input_readiness_run_is_current_cached_v1(218) as current_run_218,
  programacion.fn_input_readiness_run_is_current_cached_v1(217) as stale_run_217;

-- Current family cardinality used by cached currentness.
select count(*) as run218_assessments
from programacion.input_family_assessments
where run_id=218;

-- Cost probes. Re-run with EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) in the
-- authorized LF Supabase sandbox; do not treat comments below as an oracle.
explain (analyze,buffers,format json)
select programacion.fn_input_design_binding_graph_v2(43);

explain (analyze,buffers,format json)
select programacion.fn_input_api_contract_resolution(43);

explain (analyze,buffers,format json)
select programacion.fn_input_stage_gate_summary_known_current_v1(218,true);

explain (analyze,buffers,format json)
select programacion.fn_input_readiness_run_is_current_cached_v1(218);

-- Observed live before source creation on 2026-09-01; remeasure before use:
-- design_binding_graph_v2(43)              ~269.88 ms
-- input_api_contract_resolution(43)         ~46.92 ms
-- stage_gate_summary_known_current(218)     ~44.24 ms
-- readiness_run_is_current_cached_v1(218) ~10411.23 ms
--
-- Source inspection showed the cached-currentness function still builds the
-- current canonical graph and iterates the run's family assessments, invoking
-- fn_input_governance_bootstrap_classify_v2_cached_v1 for each family before
-- depth/successor/source-manifest checks. Run 218 currently has 47 assessments.
--
-- Candidate interpretation only:
-- the dominant measured cost is currentness/classifier revalidation, not the
-- design graph, API resolution, or known-current stage summary. Any future patch
-- must preserve the same fail-closed currentness decision, exact source snapshot,
-- classifier SHA binding, stale-successor rejection and negative controls.
