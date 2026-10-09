create or replace function programacion.fn_engineering_soak_observation_history_v2(
   p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default false
 ) returns jsonb
 language sql
 set search_path to programacion,public,pg_catalog
 as $$
   select programacion.fn_engineering_historical_evidence_reevaluate_v1(
     p_plan_code,p_unit_code,p_checkpoint_code,p_apply
   );
 $$;