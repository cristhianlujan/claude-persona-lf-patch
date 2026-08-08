-- PR93 · Production readiness P0
-- Fix mutable search_path on externally executable non-trigger functions.
-- Restrict state-mutating functions to their minimum established callers.

begin;

alter function lf_ops.fn_b2b_native_numeric_id(text, text)
  set search_path = pg_catalog, lf_ops;
alter function lf_ops.fn_normalize_relation_segment(text)
  set search_path = pg_catalog, lf_ops;
alter function lf_ops.fn_relation_code(text, text, text, text)
  set search_path = pg_catalog, lf_ops;

alter function public.fn_kb_quality_score(public.lf_knowledge_base)
  set search_path = pg_catalog, public;
alter function public.fn_restock_url_queue(text[], text, text)
  set search_path = pg_catalog, public;
alter function public.lf_register_strategy_event(text, text, text, jsonb, text, text)
  set search_path = pg_catalog, public;
alter function public.lf_validar_cierre_verificacion(
  text, text, text, text, boolean, text, text, text, text, jsonb
) set search_path = pg_catalog, public;
alter function public.sbx_lf_validation_engine_check_run(text, boolean, boolean, text)
  set search_path = pg_catalog, public;
alter function public.sbx_lf_validation_engine_check_step(integer, text, boolean, jsonb)
  set search_path = pg_catalog, public;
alter function public.sbx_lf_validation_engine_evidence_ref_ok(jsonb)
  set search_path = pg_catalog, public;
alter function public.sbx_lf_validation_engine_source_ref_ok(jsonb)
  set search_path = pg_catalog, public;
alter function public.sbx_lf_validation_engine_valid_proof()
  set search_path = pg_catalog, public;

-- This RPC writes queue state and has a demonstrated service-role caller.
revoke execute on function public.fn_restock_url_queue(text[], text, text)
  from public, anon, authenticated;
grant execute on function public.fn_restock_url_queue(text[], text, text)
  to service_role;

-- This RPC writes canonical strategy events. service_role cannot satisfy the
-- current private event-contract trigger and is therefore not an established
-- caller. Keep execution owner/admin-only until a governed caller is defined.
revoke execute on function public.lf_register_strategy_event(
  text, text, text, jsonb, text, text
) from public, anon, authenticated, service_role;

commit;
