-- DRAFT ONLY. DO NOT EXECUTE or MERGE WITHOUT CRISTHIAN REVIEW.
-- Risk: public.fn_lf_decision_context_asof_record_v1 is SECURITY DEFINER,
-- callable by anon/authenticated and inserts into private.lf_decision_context_asof_v1.
-- Source: live pg_get_functiondef readback, 2026-10-12.
-- Confirm public is exposed in Settings -> API before asserting REST exploitability.
-- Review the legitimate SQL/worker callers and default ACL grants first.
REVOKE EXECUTE ON FUNCTION
  public.fn_lf_decision_context_asof_record_v1(jsonb,text)
FROM PUBLIC, anon, authenticated;

-- Not included by default: seven programacion functions, because
-- API "Exposed schemas" cannot be read through the current connector.
-- These functions also have anon/authenticated EXECUTE, but both roles lack
-- USAGE on programacion in the observed catalog. Scope any further revokes
-- only after consumer impact review.
