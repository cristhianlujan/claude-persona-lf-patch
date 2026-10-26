BEGIN;
-- Punto 3. Route result only: no invocation of admission or effects.
DO $pre$
BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure))
     IS DISTINCT FROM '7517e452f5fa3ab2686c073bd6604b78' THEN
    RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_CLASSIFY_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
     IS DISTINCT FROM '8bf503bf17f038a18124783c038d9793' THEN
    RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_PREPARE_SOURCE_DRIFT';
  END IF;
END $pre$;

CREATE TEMP TABLE pg01_patch_provenance(name text PRIMARY KEY, old_definition text NOT NULL, insertion text NOT NULL, anchor text NOT NULL) ON COMMIT DROP;

DO $patch_classify$
DECLARE d text; a text := E'  IF jsonb_typeof(v_repair_execution)=\'object\'\n'; p integer; ins text;
BEGIN
  d := pg_get_functiondef('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure);
  IF (length(d)-length(replace(d,a,'')))/length(a) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_CLASSIFY_ANCHOR_DRIFT';
  END IF;
  ins := $insert$
  -- Typed terminal handoff: never reenter Stage1 and never select a profile.
  IF v_output_type='PROGRAMMING_ANALYSIS_PACKAGE_READY' THEN
    -- A package declared ready cannot also declare itself blocked or incomplete.
    IF v_status IN ('BLOCKED','NEEDS_INPUT','NEEDS_REPAIR')
       OR v_self_verdict IN ('NEEDS_INPUT','NEEDS_ADJUSTMENT','BLOCKED')
       OR coalesce((p_profile_output->>'blocked')::boolean,false) IS TRUE
       OR (jsonb_typeof(p_profile_output->'missing_inputs')='array'
           AND jsonb_array_length(p_profile_output->'missing_inputs')>0)
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_RESULT_PROGRAMMING_ANALYSIS_CONTRADICTORY',
        'source_execution_id',p_execution_id,'source_profile_code',p_profile_code);
    END IF;
    IF jsonb_typeof(p_profile_output->'programming_handoff') IS DISTINCT FROM 'object'
       OR NOT ((p_profile_output->'programming_handoff') ?& ARRAY[
         'context_id','context_sha256','target_ref','requested_scope_ids',
         'producer_execution_ref','entry_contract_digest_sha256']) THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_RESULT_PROGRAMMING_HANDOFF_INVALID',
        'source_execution_id',p_execution_id,'source_profile_code',p_profile_code);
    END IF;
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','CONTINUE','code','PROFILE_RESULT_PROGRAMMING_ANALYSIS_READY',
      'next_action','ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION',
      'programming_handoff',p_profile_output->'programming_handoff',
      'source_execution_id',p_execution_id,'source_profile_code',p_profile_code);
  END IF;

$insert$;
  INSERT INTO pg01_patch_provenance VALUES ('classify',d,ins,a);
  p := strpos(d,a);
  EXECUTE substring(d from 1 for p-1)||ins||substring(d from p);
END $patch_classify$;

DO $patch_prepare$
DECLARE d text; a text := E'  v_output_sha:=\'sha256:\'||encode('; p integer; ins text;
BEGIN
  d := pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure);
  IF (length(d)-length(replace(d,a,'')))/length(a) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_PREPARE_ANCHOR_DRIFT';
  END IF;
  ins := $insert$
  -- Prepare a request only. Do not invoke SECURITY INVOKER admission under
  -- this SECURITY DEFINER function's postgres identity.
  IF v_decision->>'next_action'='ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION' THEN
    IF e.manifest#>>'{router_profile_handoff,channel}' IS DISTINCT FROM 'PROGRAMACION' THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
        'status','BLOCKED','code','PROFILE_RESULT_PROGRAMMING_CHANNEL_MISMATCH');
    END IF;
    IF jsonb_typeof(e.manifest#>'{router_profile_handoff,semantic_request,router_action_binding}') IS DISTINCT FROM 'object'
       OR nullif(e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,binding_sha256}','') IS NULL THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
        'status','BLOCKED','code','PROFILE_RESULT_ROUTER_BINDING_NOT_AVAILABLE');
    END IF;
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status',v_decision->>'status','code',v_decision->>'code',
      'execution_id',p_execution_id,'profile_code',e.target_code,
      'next_action','ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION',
      'decision',v_decision,
      'programming_admission_request',jsonb_build_object(
        'entrypoint','public.lf_programming_development_admission_v1',
        'router_action_binding',e.manifest#>'{router_profile_handoff,semantic_request,router_action_binding}',
        'programming_handoff',v_decision->'programming_handoff',
        'source_execution_id',p_execution_id));
  END IF;

$insert$;
  INSERT INTO pg01_patch_provenance VALUES ('prepare',d,ins,a);
  p := strpos(d,a);
  EXECUTE substring(d from 1 for p-1)||ins||substring(d from p);
END $patch_prepare$;

DO $after$
DECLARE r record; updated text; sig regprocedure;
BEGIN
  FOR r IN SELECT * FROM pg01_patch_provenance LOOP
    sig := CASE WHEN r.name='classify'
      THEN 'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
      ELSE 'public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure END;
    updated := pg_get_functiondef(sig);
    IF updated IS NOT DISTINCT FROM r.old_definition OR
       replace(updated,r.insertion,'') IS DISTINCT FROM r.old_definition OR
       (length(updated)-length(replace(updated,r.insertion,'')))/length(r.insertion) IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_%_POSTCHECK_FAILED',upper(r.name);
    END IF;
    IF NOT has_function_privilege('service_role',sig,'EXECUTE') OR
       NOT has_function_privilege('supabase_read_only_user',sig,'EXECUTE') THEN
      RAISE EXCEPTION 'PROGRAMACION_ANALYSIS_%_ACL_DRIFT',upper(r.name);
    END IF;
  END LOOP;
END $after$;
COMMIT;
