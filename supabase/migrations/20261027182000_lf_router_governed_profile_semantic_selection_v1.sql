-- Extend governed ACT-0001 pilot with execution-bound semantic profile selection.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
     )) <> 'b82ab48dd95083218198d4cfeb6162e3' THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_TRUST_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
     )) <> 'fe08a25c8e3c023d7181194d2dfdee0d' THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_CORE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)'::regprocedure
     )) <> '94ad81b357882a19c92a0bcac8febe5e' THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_CONSUMER_SOURCE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND version='v0.2-pilot'
      AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_V02_BASELINE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND step_id='profile_semantic_selection'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_STEP_ALREADY_EXISTS';
  END IF;
END
$precheck$;

INSERT INTO public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'EJECUCION_ROUTER_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'mode','ROUTER_PROFILE_SEMANTIC_SELECTION_GOVERNANCE_BOOTSTRAP',
    'governance_bootstrap',true,
    'bootstrap_operation_code','EJECUCION_ROUTER_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'candidate_only',true,
    'production_allowed',false,
    'runtime_activation',false,
    'router_cutover_executed',false,
    'change_scope','ADD_PROFILE_SEMANTIC_SELECTION_STEP'
  ),
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
);

UPDATE public.lf_operation_registry
SET version='v0.3-pilot',
    notes='Pilot governed runtime for ACT-0001. request_intake -> stage1_seal -> stage2_route -> resolve_next_transition -> profile_semantic_selection when required. Semantic selection is execution-bound to the sealed deterministic candidate catalog. No Router effect authority and no production cutover.',
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='CANDIDATO_READ_ONLY'
  AND lifecycle_state_code='OP_CANDIDATE';

UPDATE public.lf_operation_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.3',
    contract_path='public.lf_operation_contracts/EJECUCION_ROUTER_LF/CONTRACT-EJECUCION-ROUTER-LF-v0.3',
    allowed=allowed||jsonb_build_object(
      'profile_semantic_selection',true,
      'semantic_request_source','SEALED_STAGE2_PROFILE_SELECTION_REQUEST',
      'semantic_request_caller_supplied',false,
      'semantic_result_server_validated',true
    ),
    blocked=blocked||jsonb_build_array(
      'profile_selection_without_transition',
      'caller_supplied_profile_catalog',
      'profile_selection_request_mismatch',
      'semantic_result_outside_sealed_catalog',
      'forged_semantic_validation'
    ),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.3',
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,execution_sql,fail_condition,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  'profile_semantic_selection',
  50,
  50,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.3',
  'Consume and validate semantic profile selection only against the deterministic candidate catalog sealed in Stage2 for this execution.',
  jsonb_build_array('execution_bound_profile_selection_request','model_raw_output'),
  'public.lf_profile_selector_semantic_consume_raw_v1',
  jsonb_build_array(
    'profile_selection_request_sha256',
    'semantic_result',
    'semantic_validation',
    'semantic_receipt_sha256',
    'decision'
  ),
  jsonb_build_array('server_validated'),
  jsonb_build_array(
    'transition_not_profile_selection',
    'sealed_request_missing',
    'semantic_result_invalid',
    'semantic_result_stale',
    'semantic_result_outside_catalog',
    'semantic_receipt_invalid'
  ),
  'BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array(
    'profile_selection_request_sha256',
    'semantic_result',
    'semantic_validation',
    'semantic_receipt_sha256',
    'decision'
  ),
  'DYNAMIC_FROM_SEMANTIC_DECISION',
  'RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'The caller supplies only raw model output. Candidate catalog and semantic request are recovered from sealed Stage2 evidence of this execution.',
  NULL,
  NULL,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
);

INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  50,
  'profile_semantic_selection',
  true,
  'profile_selection_request_sha256; semantic_result; semantic_validation; semantic_receipt_sha256; decision',
  'public.lf_operation_step_contracts/EJECUCION_ROUTER_LF/profile_semantic_selection',
  NULL,
  true,
  50,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
);

INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  50,
  'profile_semantic_selection',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE',
  'BLOCKED_ROUTER_PIPELINE_NOT_CLEAN',
  'RETURN_TO_ORCHESTRATOR',
  jsonb_build_array(
    'profile_selection_request_sha256',
    'semantic_result',
    'semantic_validation',
    'semantic_receipt_sha256',
    'decision'
  ),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
);

CREATE OR REPLACE FUNCTION public.lf_router_profile_semantic_selection_trust_v1(
  p_execution_id text,
  p_evidence_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s2 public.lf_operation_execution_steps%rowtype;
  st public.lf_operation_execution_steps%rowtype;
  v_request jsonb;
  v_result jsonb;
  v_validation jsonb;
  v_expected_validation jsonb;
  v_request_sha text;
  hard jsonb:='[]'::jsonb;
BEGIN
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_PROFILE_SELECTION_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  END IF;

  SELECT * INTO st
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='resolve_next_transition';

  IF NOT FOUND
     OR st.status<>'STEP_PASS_WITH_EVIDENCE'
     OR st.evidence_payload#>>'{transition_result,next_step}'<>'profile_semantic_selection'
     OR st.evidence_payload#>>'{transition_result,transition_code}'<>'PROFILE_SELECTION_REQUIRED'
  THEN
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;

  SELECT * INTO s2
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage2_route';

  IF NOT FOUND
     OR s2.status<>'STEP_PASS_WITH_EVIDENCE'
     OR jsonb_typeof(s2.evidence_payload#>'{route_result,profile_selection_request}')<>'object'
  THEN
    hard:=hard||jsonb_build_array('server_validation_failed');
  ELSE
    v_request:=s2.evidence_payload#>'{route_result,profile_selection_request}';
    v_request_sha:=encode(
      extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),
      'hex'
    );
    v_result:=p_evidence_payload->'semantic_result';
    v_validation:=p_evidence_payload->'semantic_validation';

    IF jsonb_typeof(v_result)<>'object'
       OR jsonb_typeof(v_validation)<>'object'
    THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    ELSE
      v_expected_validation:=public.lf_profile_selector_semantic_validate_v1(
        v_request,v_result
      );

      IF p_evidence_payload->>'profile_selection_request_sha256'
           IS DISTINCT FROM v_request_sha
         OR v_validation IS DISTINCT FROM v_expected_validation
         OR v_expected_validation->>'status'<>'VALID'
         OR p_evidence_payload->>'semantic_receipt_sha256'
           IS DISTINCT FROM v_result->>'semantic_receipt_sha256'
         OR p_evidence_payload->>'decision'
           IS DISTINCT FROM v_result->>'decision'
      THEN
        hard:=hard||jsonb_build_array('server_validation_failed');
      END IF;
    END IF;
  END IF;

  IF jsonb_array_length(hard)>0 THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_PROFILE_SELECTION_SERVER_VALIDATION_FAILED',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',hard
    );
  END IF;

  RETURN jsonb_build_object(
    'valid',true,
    'code','ROUTER_PROFILE_SELECTION_SERVER_VALIDATED',
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_semantic_selection_trust_v1(text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_semantic_selection_trust_v1(text,jsonb)
  TO postgres;

DO $patch_router_trust$
DECLARE
  d text;
  old_decl text := $old$
  hard jsonb:='[]'::jsonb;
BEGIN
$old$;
  new_decl text := $new$
  hard jsonb:='[]'::jsonb;
  v_profile_semantic_trust jsonb;
BEGIN
$new$;
  old_tail text := $oldtail$
  ELSE
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;
$oldtail$;
  new_tail text := $newtail$
  ELSIF p_step_id='profile_semantic_selection' THEN
    v_profile_semantic_trust:=
      public.lf_router_profile_semantic_selection_trust_v1(
        p_execution_id,p_evidence_payload
      );

    IF coalesce((v_profile_semantic_trust->>'valid')::boolean,false) IS NOT TRUE THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;

  ELSE
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;
$newtail$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1 THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_TRUST_DECL_ANCHOR_DRIFT';
  END IF;

  IF (length(d)-length(replace(d,old_tail,'')))/length(old_tail)<>1 THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_TRUST_TAIL_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_decl,new_decl);
  d:=replace(d,old_tail,new_tail);
  EXECUTE d;
END
$patch_router_trust$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s2 public.lf_operation_execution_steps%rowtype;
  st public.lf_operation_execution_steps%rowtype;
  v_request jsonb;
  v_request_sha text;
BEGIN
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO st
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='resolve_next_transition';

  IF NOT FOUND
     OR st.status<>'STEP_PASS_WITH_EVIDENCE'
     OR st.evidence_payload#>>'{transition_result,next_step}'<>'profile_semantic_selection'
     OR st.evidence_payload#>>'{transition_result,transition_code}'<>'PROFILE_SELECTION_REQUIRED'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_TRANSITION_NOT_READY',
      'execution_id',p_execution_id
    );
  END IF;

  SELECT * INTO s2
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage2_route';

  v_request:=s2.evidence_payload#>'{route_result,profile_selection_request}';

  IF jsonb_typeof(v_request)<>'object'
     OR v_request->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_REQUEST_MISSING',
      'execution_id',p_execution_id
    );
  END IF;

  v_request_sha:=encode(
    extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','resolve_next_transition',
    'next_step','profile_semantic_selection',
    'profile_selection_request_sha256',v_request_sha,
    'profile_selection_request',v_request,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(
  p_execution_id text,
  p_raw text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_prepare jsonb;
  v_request jsonb;
  v_consumed jsonb;
  v_result jsonb;
  v_validation jsonb;
  v_request_sha text;
  v_step jsonb;
  v_decision text;
  v_next_step text;
  v_status text;
BEGIN
  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(
    p_execution_id
  );

  IF v_prepare->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
    RETURN v_prepare;
  END IF;

  IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED',
      'execution_id',p_execution_id
    );
  END IF;

  v_request:=v_prepare->'profile_selection_request';
  v_request_sha:=v_prepare->>'profile_selection_request_sha256';

  v_consumed:=public.lf_profile_selector_semantic_consume_raw_v1(
    v_request,p_raw
  );

  IF v_consumed->>'status'<>'VALID'
     OR jsonb_typeof(v_consumed->'result')<>'object'
     OR jsonb_typeof(v_consumed->'validation')<>'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
      'execution_id',p_execution_id,
      'semantic_consume_result',v_consumed
    );
  END IF;

  v_result:=v_consumed->'result';
  v_validation:=v_consumed->'validation';
  v_decision:=v_result->>'decision';

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'profile_semantic_selection',
    'router-profile-selection://'||v_result->>'semantic_receipt_sha256',
    jsonb_build_object(
      'profile_selection_request_sha256',v_request_sha,
      'semantic_result',v_result,
      'semantic_validation',v_validation,
      'semantic_receipt_sha256',v_result->>'semantic_receipt_sha256',
      'decision',v_decision
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(
        v_step->>'code',
        'BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_NOT_CLEAN'
      ),
      'execution_id',p_execution_id,
      'step_result',v_step
    );
  END IF;

  IF v_decision='SELECTED' THEN
    v_next_step:='profile_after_selection';
    v_status:='PROFILE_SELECTION_READY';
  ELSIF v_decision='AMBIGUOUS' THEN
    v_next_step:='profile_selection_decision';
    v_status:='PROFILE_SELECTION_AMBIGUOUS';
  ELSE
    v_next_step:='blocked_no_profile_match';
    v_status:='PROFILE_SELECTION_NO_MATCH';
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','profile_semantic_selection',
        'next_step',v_next_step,
        'profile_selection_decision',v_decision,
        'selected_profile_code',v_result->>'selected_profile_code',
        'semantic_receipt_sha256',v_result->>'semantic_receipt_sha256'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  RETURN jsonb_build_object(
    'status',v_status,
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','profile_semantic_selection',
    'next_step',v_next_step,
    'semantic_result',v_result,
    'semantic_validation',v_validation,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(text) IS
'Governed ACT-0001 semantic profile-selection preparation. Returns only the deterministic candidate request sealed in this execution after Stage2 and transition resolution.';

COMMENT ON FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(text,text) IS
'Governed ACT-0001 semantic profile-selection submission. Caller supplies raw model output only; Supabase consumes, validates and records the result against the execution-bound sealed candidate catalog.';

DO $postcheck$
DECLARE
  v_begin jsonb;
  v_exec text;
  v_stage1 jsonb;
  v_flow jsonb;
  v_prepare jsonb;
  v_submit jsonb;
  v_status jsonb;
  v_raw text;
  v_fake jsonb;
  v_begin2 jsonb;
  v_exec2 text;
BEGIN
  IF (
    SELECT count(*)
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND status='ACTIVE_ENFORCEMENT'
  )<>5 THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_STEP_COUNT_FAILED';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_profile_semantic_prepare_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_profile_semantic_submit_v1(text,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_READONLY_ACL_FAILED';
  END IF;

  BEGIN
    v_begin:=public.lf_router_pipeline_begin_v1(
      'Analiza técnicamente el Login B2B sin realizar cambios.'
    );
    v_exec:=v_begin->>'execution_id';

    -- Semantic prepare cannot run before the governed transition says it is next.
    v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(v_exec);
    IF v_prepare->>'blocking_code'
         <>'BLOCK_ROUTER_PROFILE_SELECTION_TRANSITION_NOT_READY'
    THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_EARLY_PREPARE_NOT_BLOCKED:%',v_prepare;
    END IF;

    v_stage1:=jsonb_build_object(
      'schema_version','LF_ROUTER_STAGE1_V2',
      'texto_original','Analiza técnicamente el Login B2B sin realizar cambios.',
      'es_operacion',true,
      'respuesta_directa',false,
      'accion','analizar técnicamente',
      'sujeto','Login B2B',
      'correcciones','[]'::jsonb,
      'formas_busqueda',jsonb_build_array('Login B2B'),
      'ambiguo',false,
      'alternativas','[]'::jsonb,
      'pregunta_usuario',null,
      'capability_hint',null,
      'downstream_execution_allowed',false,
      'canal_candidato','PROGRAMACION',
      'negocio_codigo','LF',
      'negocios_afectados','[]'::jsonb,
      'ruta_transversal',null,
      'razon_seleccion','Análisis técnico',
      'alcance',jsonb_build_object(
        'target_type','PANTALLA',
        'target_hint','B2B-AUTH-001',
        'resolution_status','UNRESOLVED'
      )
    );

    v_flow:=public.lf_router_pipeline_stage1_submit_v1(v_exec,v_stage1);

    IF v_flow->>'status'<>'NEXT_TRANSITION_READY'
       OR v_flow->>'next_step'<>'profile_semantic_selection'
    THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_STAGE2_FLOW_FAIL:%',v_flow;
    END IF;

    v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(v_exec);

    IF v_prepare->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED'
       OR v_prepare#>>'{profile_selection_request,schema_version}'
            <>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
       OR coalesce(
         (v_prepare#>>'{profile_selection_request,catalog_profile_count}')::integer,
         0
       )<1
    THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_PREPARE_FAIL:%',v_prepare;
    END IF;

    v_raw:=jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','ACT-0051',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Frontend implementation analysis matches the declared ACT-0051 purpose and activation scope.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'profile_code','ACT-0051',
          'kind','PURPOSE',
          'source_section','Purpose'
        )
      ),
      'material_ambiguities','[]'::jsonb
    )::text;

    v_submit:=public.lf_router_pipeline_profile_semantic_submit_v1(
      v_exec,v_raw
    );

    IF v_submit->>'status'<>'PROFILE_SELECTION_READY'
       OR v_submit->>'current_step'<>'profile_semantic_selection'
       OR v_submit->>'next_step'<>'profile_after_selection'
       OR v_submit#>>'{semantic_result,decision}'<>'SELECTED'
       OR v_submit#>>'{semantic_result,selected_profile_code}'<>'ACT-0051'
       OR v_submit#>>'{semantic_validation,status}'<>'VALID'
    THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_VALID_FLOW_FAIL:%',v_submit;
    END IF;

    v_status:=public.lf_router_pipeline_status_v1(v_exec);
    IF jsonb_array_length(v_status->'steps')<>5
       OR v_status#>>'{steps,4,step_id}'<>'profile_semantic_selection'
       OR v_status#>>'{steps,4,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{manifest,next_step}'<>'profile_after_selection'
    THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_STATUS_FAIL:%',v_status;
    END IF;

    -- A second execution with no governed transition cannot forge a semantic PASS
    -- by calling the generic recorder and supplying valid=true.
    v_begin2:=public.lf_router_pipeline_begin_v1(
      'Consulta el Login B2B sin realizar cambios.'
    );
    v_exec2:=v_begin2->>'execution_id';

    v_fake:=public.lf_record_operation_step_core_v1(
      v_exec2,
      'profile_semantic_selection',
      'forged://profile-selection',
      jsonb_build_object(
        'profile_selection_request_sha256',repeat('0',64),
        'semantic_result',jsonb_build_object(
          'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
          'decision','SELECTED',
          'selected_profile_code','ACT-0051',
          'semantic_receipt_sha256',repeat('0',64)
        ),
        'semantic_validation',jsonb_build_object('status','VALID'),
        'semantic_receipt_sha256',repeat('0',64),
        'decision','SELECTED'
      ),
      v_exec2,
      'EJECUCION_ROUTER_LF',
      'DOC',
      'ACTIVE_ENFORCEMENT',
      'ACTIVE_ENFORCEMENT',
      'ACTIVE_ENFORCEMENT',
      jsonb_build_object(
        'valid',true,
        'server_assertions',jsonb_build_array('server_validated'),
        'server_hard_fails','[]'::jsonb
      ),
      false,
      'FORGED_PROFILE_SELECTION_CALLER'
    );

    IF v_fake->>'outcome'<>'BLOCKED' THEN
      RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_FORGED_NOT_BLOCKED:%',v_fake;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ303',
      MESSAGE='ROUTER_PROFILE_SELECTION_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ303' THEN
      NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE operation_code='EJECUCION_ROUTER_LF'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_POSTCHECK_RESIDUE';
  END IF;
END
$postcheck$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001',
    manifest=manifest||jsonb_build_object(
      'result','ROUTER_PROFILE_SEMANTIC_SELECTION_PILOT_REGISTERED',
      'operation_code','EJECUCION_ROUTER_LF',
      'operation_version','v0.3-pilot',
      'operation_status','CANDIDATO_READ_ONLY',
      'operation_lifecycle_state','OP_CANDIDATE',
      'production_allowed',false,
      'router_cutover_executed',false
    )
WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
  AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
  AND status='IN_PROGRESS'
  AND manifest->>'bootstrap_operation_code'='EJECUCION_ROUTER_LF'
  AND manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE';

DO $bootstrap_close_postcheck$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V03-20261027-001'
      AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND target_code='EJECUCION_ROUTER_LF'
      AND status='COMPLETED'
      AND completed_at IS NOT NULL
      AND manifest->>'result'='ROUTER_PROFILE_SEMANTIC_SELECTION_PILOT_REGISTERED'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PROFILE_SELECTION_BOOTSTRAP_CLOSE_FAILED';
  END IF;
END
$bootstrap_close_postcheck$;

COMMIT;
