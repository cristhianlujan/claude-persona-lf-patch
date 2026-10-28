-- LF Router V2 -> EJECUCION_PERFIL_LF: keep a single governed admission.
-- Transport and handoff contracts remain unchanged. No direct writes outside the
-- existing lf_profile_execution_begin_from_handoff_v1 operation reservation.
BEGIN;

DO $assert$ BEGIN
  IF to_regprocedure('public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)') IS NULL
     OR to_regprocedure('public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_ROUTER_V2_PROFILE_GOVERNED_CHAIN_MISSING';
  END IF;
END $assert$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)
  TO service_role;

DO $verify$ BEGIN
  IF has_function_privilege('anon','public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR has_function_privilege('supabase_read_only_user','public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'LF_ROUTER_V2_PROFILE_ADMISSION_ACL_INCORRECT';
  END IF;
END $verify$;
COMMIT;
