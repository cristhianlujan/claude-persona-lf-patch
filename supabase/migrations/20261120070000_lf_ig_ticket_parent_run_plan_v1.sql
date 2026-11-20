-- LF / Input Governance E2E / 2026-11-20
-- Fix: consume only a skill selected by the CURRENT PARENT RUN.
-- Previous consumer looked up a fresh profile/channel plan with NULL semantic decision,
-- losing the sticky optional skill and returning SKILL_TICKET_POLICY_NOT_CURRENT (HTTP 403).
-- NO changes to tickets, identity, budget, expiry, reuse, tenant/screen scope or IG rules.
-- Deployment: Migration Merge Train only, never direct SQL patch in production.
BEGIN;

DO $lf_ig_parent_plan_fix$
DECLARE
  v_def text;
  v_after text;
  v_old CONSTANT text := 'v_plan:=public.lf_profile_execution_plan_v1(v_profile,v_channel,NULL);';
  v_new CONSTANT text := 'v_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);';
BEGIN
  v_def:=pg_get_functiondef(
    'public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)'::regprocedure);

  -- Exact deployed preimage, observed by direct pg_proc readback.
  IF md5(v_def) IS DISTINCT FROM '507ce5b8edcdd993ccb3ea978220ecea' THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_skill_runtime_ticket_consume_v1';
  END IF;
  IF to_regprocedure('public.lf_profile_execution_plan_for_run_v1(text,jsonb)') IS NULL
     OR (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1
     OR strpos(v_def,v_new)>0 THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:skill_ticket_parent_plan_anchor';
  END IF;

  -- Keep every other SQL security and one-use ticket check byte-for-byte.
  EXECUTE replace(v_def,v_old,v_new);

  v_after:=pg_get_functiondef(
    'public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)'::regprocedure);
  IF strpos(v_after,v_new)=0 OR strpos(v_after,v_old)>0 THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:skill_ticket_parent_plan_postreadback';
  END IF;
END $lf_ig_parent_plan_fix$;

COMMIT;
