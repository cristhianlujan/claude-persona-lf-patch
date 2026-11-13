-- Exact pg_get_functiondef read-only SELECT on current Supabase (2026-11-13).
-- Preimage md5(pg_get_functiondef) = 7cf717887006e278356a716f3fd80182.
-- Test fixture only: no credentials, RUN data or production writes.
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_trust jsonb;
begin
  v_trust:=public.lf_profile_execution_trust_validation_v2(
    p_execution_id,p_step_id,p_evidence_payload
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_execution_step_v1'
  );
end
$function$;
