-- Extend governed ACT-0001 pilot with deterministic dynamic next-transition resolution.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> '045a1ae1b541d31b6e626c56bb907a85' THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_ROUTE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
     )) <> '1ae6dfb5654b1dc4c6a2926e3b2e88fc' THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_TRUST_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_pipeline_stage2_continue_v1(text)'::regprocedure
     )) <> '0889d1e2329fcf1d391550d348bf84e2' THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STAGE2_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
     )) <> 'fe08a25c8e3c023d7181194d2dfdee0d' THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_CORE_SOURCE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND version='v0.1-pilot'
      AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  ) THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_PILOT_BASELINE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND step_id='resolve_next_transition'
  ) THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STEP_ALREADY_EXISTS';
  END IF;
END
$precheck$;

INSERT INTO public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'EJECUCION_ROUTER_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'mode','ROUTER_DYNAMIC_TRANSITION_GOVERNANCE_BOOTSTRAP',
    'governance_bootstrap',true,
    'bootstrap_operation_code','EJECUCION_ROUTER_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'candidate_only',true,
    'production_allowed',false,
    'runtime_activation',false,
    'router_cutover_executed',false,
    'change_scope','ADD_RESOLVE_NEXT_TRANSITION_STEP'
  ),
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
);

UPDATE public.lf_operation_registry
SET version='v0.2-pilot',
    notes='Pilot governed runtime for ACT-0001. request_intake -> stage1_seal -> stage2_route -> resolve_next_transition. Next transition is deterministic from sealed Stage2 output; caller cannot select it. No Router effect authority and no production cutover.',
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='CANDIDATO_READ_ONLY'
  AND lifecycle_state_code='OP_CANDIDATE';

UPDATE public.lf_operation_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.2',
    contract_path='public.lf_operation_contracts/EJECUCION_ROUTER_LF/CONTRACT-EJECUCION-ROUTER-LF-v0.2',
    allowed=allowed||jsonb_build_object(
      'dynamic_transition_resolution',true,
      'transition_source','SEALED_STAGE2_ROUTE_RESULT',
      'transition_resolver','public.lf_router_route_transition_resolve_v1',
      'transition_caller_supplied',false
    ),
    blocked=blocked||jsonb_build_array(
      'direct_transition_without_stage2',
      'caller_supplied_transition',
      'transition_result_mismatch',
      'unmapped_route_step'
    ),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.2',
    next_if_pass=CASE
      WHEN step_id='stage2_route' THEN 'resolve_next_transition'
      ELSE next_if_pass
    END,
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
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
  'resolve_next_transition',
  40,
  40,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.2',
  'Resolve the next governed Router state deterministically from the sealed Stage2 route result.',
  jsonb_build_array('sealed_stage2_route_result'),
  'public.lf_router_route_transition_resolve_v1',
  jsonb_build_array('route_step','transition_result','transition_sha256'),
  jsonb_build_array('server_validated'),
  jsonb_build_array(
    'stage2_not_clean',
    'route_result_mismatch',
    'transition_result_mismatch',
    'unmapped_route_step'
  ),
  'BLOCK_ROUTER_NEXT_TRANSITION_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array('route_step','transition_result','transition_sha256'),
  'DYNAMIC_FROM_TRANSITION_RESULT',
  'RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'The caller cannot supply route_result or next_step. Both are recovered and resolved server-side from this execution.',
  NULL,
  NULL,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
);

INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  40,
  'resolve_next_transition',
  true,
  'route_step; transition_result; transition_sha256',
  'public.lf_operation_step_contracts/EJECUCION_ROUTER_LF/resolve_next_transition',
  NULL,
  true,
  40,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
);

INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  40,
  'resolve_next_transition',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE',
  'BLOCKED_ROUTER_PIPELINE_NOT_CLEAN',
  'RETURN_TO_ORCHESTRATOR',
  jsonb_build_array('route_step','transition_result','transition_sha256'),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
);

CREATE OR REPLACE FUNCTION public.lf_router_route_transition_resolve_v1(
  p_route_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_step text;
  v_channel text;
  v_transition_code text;
  v_transition_class text;
  v_next_step text;
BEGIN
  IF p_route_result IS NULL
     OR jsonb_typeof(p_route_result)<>'object'
     OR p_route_result->>'schema_version'<>'LF_ROUTER_ROUTE_V1'
     OR p_route_result->>'router'<>'ACT-0001'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_ROUTE_RESULT_INVALID',
      'schema_version','LF_ROUTER_NEXT_TRANSITION_V1'
    );
  END IF;

  v_step:=nullif(btrim(coalesce(p_route_result->>'paso','')),'');
  v_channel:=nullif(btrim(coalesce(p_route_result->>'canal_candidato','')),'');

  CASE v_step
    WHEN 'PRODUCTO_PROFILE_SELECTION_REQUIRED' THEN
      v_transition_code:='PROFILE_SELECTION_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='profile_semantic_selection';
    WHEN 'PROGRAMACION_PROFILE_SELECTION_REQUIRED' THEN
      v_transition_code:='PROFILE_SELECTION_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='profile_semantic_selection';
    WHEN 'OPERACIONES_PROFILE_SELECTION_REQUIRED' THEN
      v_transition_code:='PROFILE_SELECTION_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='profile_semantic_selection';
    WHEN 'DIRECT_ANSWER' THEN
      v_transition_code:='DIRECT_RESULT';
      v_transition_class:='TERMINAL';
      v_next_step:='result_direct';
    WHEN 'ASK_USER' THEN
      v_transition_code:='CLARIFICATION_REQUIRED';
      v_transition_class:='WAIT_USER';
      v_next_step:='clarification';
    WHEN 'MULTINEGOCIO_PENDIENTE' THEN
      v_transition_code:='BUSINESS_AUTHORITY_REQUIRED';
      v_transition_class:='WAIT_GOVERNANCE';
      v_next_step:='business_authority';
    WHEN 'NEGOCIO_NO_HABILITADO' THEN
      v_transition_code:='BUSINESS_NOT_ENABLED';
      v_transition_class:='BLOCKED';
      v_next_step:='blocked_business';
    WHEN 'RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA' THEN
      v_transition_code:='TRANSVERSAL_GOVERNED_OPERATION_REQUIRED';
      v_transition_class:='HANDOFF';
      v_next_step:='transversal_governed_operation';
    WHEN 'PROPUESTA_PERFIL' THEN
      v_transition_code:='PROFILE_PROPOSAL_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='profile_proposal';
    WHEN 'CANDIDATO_UNICO' THEN
      v_transition_code:='IDENTITY_CONFIRMATION_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='identity_confirmation';
    WHEN 'ELEGIR_O_PROFUNDIZAR' THEN
      v_transition_code:='CANDIDATE_DISAMBIGUATION_REQUIRED';
      v_transition_class:='CONTINUE';
      v_next_step:='candidate_disambiguation';
    WHEN 'NIVEL_2_CONSENTIMIENTO' THEN
      v_transition_code:='LEVEL2_CONSENT_REQUIRED';
      v_transition_class:='WAIT_USER';
      v_next_step:='level2_consent';
    WHEN 'NIVEL_2_RESULTADO' THEN
      v_transition_code:='LEVEL2_RESULT_READY';
      v_transition_class:='CONTINUE';
      v_next_step:='level2_result';
    WHEN 'INVALID_STAGE1_V2' THEN
      v_transition_code:='INVALID_STAGE1_BLOCKED';
      v_transition_class:='BLOCKED';
      v_next_step:='blocked_invalid_stage1';
    WHEN 'INVALID_STAGE1' THEN
      v_transition_code:='INVALID_STAGE1_BLOCKED';
      v_transition_class:='BLOCKED';
      v_next_step:='blocked_invalid_stage1';
    WHEN 'SYSTEM_NOT_SUPPORTED' THEN
      v_transition_code:='LEGACY_ROUTE_FORBIDDEN';
      v_transition_class:='BLOCKED';
      v_next_step:='blocked_legacy_route';
    WHEN 'DISPATCHED' THEN
      v_transition_code:='LEGACY_ROUTE_FORBIDDEN';
      v_transition_class:='BLOCKED';
      v_next_step:='blocked_legacy_route';
    ELSE
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_ROUTER_ROUTE_STEP_UNMAPPED',
        'schema_version','LF_ROUTER_NEXT_TRANSITION_V1',
        'route_step',v_step
      );
  END CASE;

  RETURN jsonb_build_object(
    'status','RESOLVED',
    'schema_version','LF_ROUTER_NEXT_TRANSITION_V1',
    'router','ACT-0001',
    'route_step',v_step,
    'channel',v_channel,
    'transition_code',v_transition_code,
    'transition_class',v_transition_class,
    'next_step',v_next_step,
    'caller_selects_next_step',false,
    'effect_authority',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_route_transition_resolve_v1(jsonb)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_route_transition_resolve_v1(jsonb)
  TO postgres;

CREATE OR REPLACE FUNCTION public.lf_router_execution_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
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
  v_stage1 jsonb;
  v_validation jsonb;
  v_stage1_sha text;
  v_expected_route jsonb;
  v_stage1_step public.lf_operation_execution_steps%rowtype;
  v_stage2_step public.lf_operation_execution_steps%rowtype;
  v_expected_transition jsonb;
  v_transition_sha text;
  hard jsonb:='[]'::jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_step_id,'')),'') IS NULL
     OR p_evidence_payload IS NULL
     OR jsonb_typeof(p_evidence_payload)<>'object'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_PIPELINE_TRUST_INPUT_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_type<>'DOC'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_PIPELINE_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  END IF;

  IF p_step_id='request_intake' THEN
    IF p_evidence_payload->>'original_request_text'
         IS DISTINCT FROM e.manifest->>'original_request_text'
       OR p_evidence_payload->>'request_sha256'
         IS DISTINCT FROM e.request_sha256
       OR p_evidence_payload->>'request_sha256'
         IS DISTINCT FROM encode(
           extensions.digest(
             convert_to(coalesce(e.manifest->>'original_request_text',''),'UTF8'),
             'sha256'
           ),
           'hex'
         )
       OR coalesce((p_evidence_payload->>'stage1_required')::boolean,false)
          IS NOT TRUE
    THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;

  ELSIF p_step_id='stage1_seal' THEN
    v_stage1:=p_evidence_payload->'stage1_payload';
    IF jsonb_typeof(v_stage1)<>'object' THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    ELSE
      v_validation:=public.lf_router_stage1_validate_v2(v_stage1);
      v_stage1_sha:=encode(
        extensions.digest(convert_to(v_stage1::text,'UTF8'),'sha256'),
        'hex'
      );

      IF coalesce((v_validation->>'valid')::boolean,false) IS NOT TRUE
         OR v_stage1->>'texto_original'
              IS DISTINCT FROM e.manifest->>'original_request_text'
         OR p_evidence_payload->>'stage1_sha256'
              IS DISTINCT FROM v_stage1_sha
         OR p_evidence_payload->'stage1_validation'
              IS DISTINCT FROM v_validation
      THEN
        hard:=hard||jsonb_build_array('server_validation_failed');
      END IF;
    END IF;

  ELSIF p_step_id='stage2_route' THEN
    SELECT * INTO v_stage1_step
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='stage1_seal';

    IF NOT FOUND
       OR v_stage1_step.status<>'STEP_PASS_WITH_EVIDENCE'
       OR jsonb_typeof(v_stage1_step.evidence_payload->'stage1_payload')<>'object'
    THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    ELSE
      v_stage1:=v_stage1_step.evidence_payload->'stage1_payload';
      v_stage1_sha:=encode(
        extensions.digest(convert_to(v_stage1::text,'UTF8'),'sha256'),
        'hex'
      );
      v_expected_route:=public.lf_router_route_v1(v_stage1,'{}'::jsonb,false);

      IF p_evidence_payload->>'stage1_sha256'
           IS DISTINCT FROM v_stage1_sha
         OR p_evidence_payload->'route_result'
           IS DISTINCT FROM v_expected_route
         OR p_evidence_payload->>'route_step'
           IS DISTINCT FROM v_expected_route->>'paso'
         OR v_expected_route->>'router' IS DISTINCT FROM 'ACT-0001'
         OR coalesce((v_expected_route->>'downstream_execution_allowed')::boolean,true)
              IS TRUE
      THEN
        hard:=hard||jsonb_build_array('server_validation_failed');
      END IF;
    END IF;

  ELSIF p_step_id='resolve_next_transition' THEN
    SELECT * INTO v_stage2_step
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='stage2_route';

    IF NOT FOUND
       OR v_stage2_step.status<>'STEP_PASS_WITH_EVIDENCE'
       OR jsonb_typeof(v_stage2_step.evidence_payload->'route_result')<>'object'
    THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    ELSE
      v_expected_route:=v_stage2_step.evidence_payload->'route_result';
      v_expected_transition:=
        public.lf_router_route_transition_resolve_v1(v_expected_route);
      v_transition_sha:=encode(
        extensions.digest(
          convert_to(v_expected_transition::text,'UTF8'),
          'sha256'
        ),
        'hex'
      );

      IF v_expected_transition->>'status'<>'RESOLVED'
         OR p_evidence_payload->>'route_step'
              IS DISTINCT FROM v_expected_route->>'paso'
         OR p_evidence_payload->'transition_result'
              IS DISTINCT FROM v_expected_transition
         OR p_evidence_payload->>'transition_sha256'
              IS DISTINCT FROM v_transition_sha
      THEN
        hard:=hard||jsonb_build_array('server_validation_failed');
      END IF;
    END IF;

  ELSE
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;

  IF jsonb_array_length(hard)>0 THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_PIPELINE_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',hard
    );
  END IF;

  RETURN jsonb_build_object(
    'valid',true,
    'code','ROUTER_PIPELINE_SERVER_VALIDATED',
    'details',jsonb_build_object(
      'execution_id',p_execution_id,
      'step_id',p_step_id
    ),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_execution_trust_validation_v1(text,text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_execution_trust_validation_v1(text,text,jsonb)
  TO postgres;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_resolve_next_transition_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s2 public.lf_operation_execution_steps%rowtype;
  v_route jsonb;
  v_transition jsonb;
  v_transition_sha text;
  v_step jsonb;
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

  SELECT * INTO s2
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage2_route';

  IF NOT FOUND
     OR s2.status<>'STEP_PASS_WITH_EVIDENCE'
     OR jsonb_typeof(s2.evidence_payload->'route_result')<>'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_STAGE2_NOT_CLEAN',
      'execution_id',p_execution_id,
      'current_step',e.manifest->>'current_step',
      'expected_step','stage2_route'
    );
  END IF;

  v_route:=s2.evidence_payload->'route_result';
  v_transition:=public.lf_router_route_transition_resolve_v1(v_route);

  IF v_transition->>'status'<>'RESOLVED' THEN
    RETURN v_transition||jsonb_build_object(
      'execution_id',p_execution_id,
      'route_result',v_route
    );
  END IF;

  v_transition_sha:=encode(
    extensions.digest(convert_to(v_transition::text,'UTF8'),'sha256'),
    'hex'
  );

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'resolve_next_transition',
    'router-transition://'||v_transition_sha,
    jsonb_build_object(
      'route_step',v_route->>'paso',
      'transition_result',v_transition,
      'transition_sha256',v_transition_sha
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(
        v_step->>'code',
        'BLOCK_ROUTER_NEXT_TRANSITION_NOT_CLEAN'
      ),
      'execution_id',p_execution_id,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'transition_code',v_transition->>'transition_code',
        'transition_class',v_transition->>'transition_class'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  RETURN jsonb_build_object(
    'status','NEXT_TRANSITION_READY',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','resolve_next_transition',
    'next_step',v_transition->>'next_step',
    'transition',v_transition,
    'route_result',v_route,
    'caller_selects_next_step',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_resolve_next_transition_v1(text)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_resolve_next_transition_v1(text)
  TO postgres;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_stage2_continue_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s1 public.lf_operation_execution_steps%rowtype;
  v_stage1 jsonb;
  v_stage1_sha text;
  v_route jsonb;
  v_step jsonb;
  v_transition jsonb;
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

  SELECT * INTO s1
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage1_seal';

  IF NOT FOUND OR s1.status<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_STAGE1_NOT_CLEAN',
      'execution_id',p_execution_id,
      'current_step',e.manifest->>'current_step',
      'expected_step','stage1_seal'
    );
  END IF;

  v_stage1:=s1.evidence_payload->'stage1_payload';
  v_stage1_sha:=encode(
    extensions.digest(convert_to(v_stage1::text,'UTF8'),'sha256'),
    'hex'
  );

  v_route:=public.lf_router_route_v1(v_stage1,'{}'::jsonb,false);

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'stage2_route',
    'router-stage2://'||v_stage1_sha,
    jsonb_build_object(
      'route_result',v_route,
      'stage1_sha256',v_stage1_sha,
      'route_step',v_route->>'paso'
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_step->>'code','BLOCK_ROUTER_STAGE2_NOT_CLEAN'),
      'execution_id',p_execution_id,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','stage2_route',
        'next_step','resolve_next_transition',
        'stage2_route_step',v_route->>'paso'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  v_transition:=
    public.lf_router_pipeline_resolve_next_transition_v1(p_execution_id);

  RETURN v_transition||jsonb_build_object(
    'stage2_status','SEALED',
    'stage2_route_step',v_route->>'paso',
    'route_result',v_route
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_stage2_continue_v1(text)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_stage2_continue_v1(text)
  TO postgres;

COMMENT ON FUNCTION public.lf_router_route_transition_resolve_v1(jsonb) IS
'Internal deterministic ACT-0001 transition resolver. Maps the sealed Stage2 route result to the next governed state; never grants effect authority.';

COMMENT ON FUNCTION public.lf_router_pipeline_resolve_next_transition_v1(text) IS
'Internal-only ACT-0001 continuation. Reads sealed Stage2 evidence from the execution, resolves and records the next transition, and does not accept caller-supplied route or next-step input.';

DO $postcheck$
DECLARE
  v_begin jsonb;
  v_exec text;
  v_direct jsonb;
  v_good jsonb;
  v_status jsonb;
  v_stage1 jsonb;
  v_fake jsonb;
  v_map jsonb;
  v_unknown jsonb;
BEGIN
  IF (
    SELECT count(*)
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND status='ACTIVE_ENFORCEMENT'
  )<>4 THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STEP_COUNT_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND step_id='stage2_route'
      AND next_if_pass='resolve_next_transition'
  ) THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STAGE2_NEXT_NOT_BOUND';
  END IF;

  IF has_function_privilege(
       'service_role',
       'public.lf_router_pipeline_resolve_next_transition_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_resolve_next_transition_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.lf_router_route_transition_resolve_v1(jsonb)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_INTERNAL_ACL_FAILED';
  END IF;

  v_map:=public.lf_router_route_transition_resolve_v1(
    jsonb_build_object(
      'schema_version','LF_ROUTER_ROUTE_V1',
      'router','ACT-0001',
      'paso','ASK_USER',
      'downstream_execution_allowed',false
    )
  );
  IF v_map->>'transition_code'<>'CLARIFICATION_REQUIRED'
     OR v_map->>'next_step'<>'clarification'
     OR v_map->>'transition_class'<>'WAIT_USER'
  THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_ASK_USER_MAP_FAILED:%',v_map;
  END IF;

  v_map:=public.lf_router_route_transition_resolve_v1(
    jsonb_build_object(
      'schema_version','LF_ROUTER_ROUTE_V1',
      'router','ACT-0001',
      'paso','DIRECT_ANSWER',
      'downstream_execution_allowed',false
    )
  );
  IF v_map->>'transition_code'<>'DIRECT_RESULT'
     OR v_map->>'next_step'<>'result_direct'
     OR v_map->>'transition_class'<>'TERMINAL'
  THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_DIRECT_MAP_FAILED:%',v_map;
  END IF;

  v_unknown:=public.lf_router_route_transition_resolve_v1(
    jsonb_build_object(
      'schema_version','LF_ROUTER_ROUTE_V1',
      'router','ACT-0001',
      'paso','NON_EXISTENT_ROUTE_STEP',
      'downstream_execution_allowed',false
    )
  );
  IF v_unknown->>'status'<>'BLOCKED'
     OR v_unknown->>'blocking_code'<>'BLOCK_ROUTER_ROUTE_STEP_UNMAPPED'
  THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_UNKNOWN_NOT_BLOCKED:%',v_unknown;
  END IF;

  BEGIN
    v_begin:=public.lf_router_pipeline_begin_v1(
      'Analiza técnicamente el Login B2B sin realizar cambios.'
    );
    IF v_begin->>'status'<>'STAGE1_REQUIRED' THEN
      RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_BEGIN_FAIL:%',v_begin;
    END IF;
    v_exec:=v_begin->>'execution_id';

    -- Even internal continuation cannot resolve a transition before Stage2 is clean.
    v_direct:=public.lf_router_pipeline_resolve_next_transition_v1(v_exec);
    IF v_direct->>'blocking_code'<>'BLOCK_ROUTER_STAGE2_NOT_CLEAN' THEN
      RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_DIRECT_NOT_BLOCKED:%',v_direct;
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

    v_good:=public.lf_router_pipeline_stage1_submit_v1(v_exec,v_stage1);

    IF v_good->>'status'<>'NEXT_TRANSITION_READY'
       OR v_good->>'current_step'<>'resolve_next_transition'
       OR v_good->>'next_step'<>'profile_semantic_selection'
       OR v_good#>>'{transition,transition_code}'<>'PROFILE_SELECTION_REQUIRED'
       OR v_good#>>'{transition,transition_class}'<>'CONTINUE'
       OR v_good#>>'{route_result,paso}'
            <>'PROGRAMACION_PROFILE_SELECTION_REQUIRED'
    THEN
      RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_VALID_FLOW_FAIL:%',v_good;
    END IF;

    v_status:=public.lf_router_pipeline_status_v1(v_exec);
    IF v_status->>'status'<>'FOUND'
       OR jsonb_array_length(v_status->'steps')<>4
       OR v_status#>>'{steps,0,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{steps,1,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{steps,2,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{steps,3,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{manifest,next_step}'<>'profile_semantic_selection'
    THEN
      RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STATUS_FAIL:%',v_status;
    END IF;

    -- A forged transition cannot be recorded even with caller-supplied valid=true.
    v_fake:=public.lf_record_operation_step_core_v1(
      v_exec,
      'resolve_next_transition',
      'forged://transition',
      jsonb_build_object(
        'route_step','PROGRAMACION_PROFILE_SELECTION_REQUIRED',
        'transition_result',jsonb_build_object(
          'status','RESOLVED',
          'schema_version','LF_ROUTER_NEXT_TRANSITION_V1',
          'router','ACT-0001',
          'route_step','PROGRAMACION_PROFILE_SELECTION_REQUIRED',
          'transition_code','DIRECT_RESULT',
          'transition_class','TERMINAL',
          'next_step','result_direct',
          'caller_selects_next_step',false,
          'effect_authority',false
        ),
        'transition_sha256',repeat('0',64)
      ),
      v_exec,
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
      'FORGED_TRANSITION_CALLER'
    );

    IF v_fake->>'outcome'<>'BLOCKED'
       OR v_fake->>'code' NOT IN (
         'STEP_ALREADY_RECORDED_DIFFERENT',
         'ROUTER_PIPELINE_SERVER_VALIDATION_FAILED'
       )
    THEN
      RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_FORGED_NOT_BLOCKED:%',v_fake;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ302',
      MESSAGE='ROUTER_DYNAMIC_TRANSITION_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ302' THEN
      NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE operation_code='EJECUCION_ROUTER_LF'
  ) THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_POSTCHECK_RESIDUE';
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_router_pipeline_stage2_continue_v1(text)'::regprocedure
       ),
       'public.lf_router_pipeline_resolve_next_transition_v1'
     )=0
  THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_STAGE2_CHAIN_MISSING';
  END IF;
END
$postcheck$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001',
    manifest=manifest||jsonb_build_object(
      'result','ROUTER_DYNAMIC_TRANSITION_PILOT_REGISTERED',
      'operation_code','EJECUCION_ROUTER_LF',
      'operation_version','v0.2-pilot',
      'operation_status','CANDIDATO_READ_ONLY',
      'operation_lifecycle_state','OP_CANDIDATE',
      'production_allowed',false,
      'router_cutover_executed',false
    )
WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
  AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
  AND status='IN_PROGRESS'
  AND manifest->>'bootstrap_operation_code'='EJECUCION_ROUTER_LF'
  AND manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE';

DO $bootstrap_close_postcheck$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V02-20261027-001'
      AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND target_code='EJECUCION_ROUTER_LF'
      AND status='COMPLETED'
      AND completed_at IS NOT NULL
      AND manifest->>'result'='ROUTER_DYNAMIC_TRANSITION_PILOT_REGISTERED'
  ) THEN
    RAISE EXCEPTION 'ROUTER_DYNAMIC_TRANSITION_BOOTSTRAP_CLOSE_FAILED';
  END IF;
END
$bootstrap_close_postcheck$;

COMMIT;
