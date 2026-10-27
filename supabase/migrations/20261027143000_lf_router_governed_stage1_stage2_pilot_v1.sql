-- ACT-0001 governed execution pilot:
-- request_intake -> stage1_seal -> stage2_route
-- Reuses the existing operation execution/step recorder framework.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> '045a1ae1b541d31b6e626c56bb907a85' THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_ROUTE_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.lf_router_stage1_validate_v2(jsonb)'::regprocedure
     )) <> 'b1a76e64645401871646658d5ee3826d' THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_STAGE1_VALIDATOR_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)'::regprocedure
     )) <> '311a0377c43c0698ec12826c1a7f6a78' THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_RESERVE_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
     )) <> 'f22b183b8af9ac93a7b71c55e10a94b4' THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_CORE_SOURCE_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_ROUTER_LF'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_OPERATION_ALREADY_EXISTS';
  END IF;
END
$precheck$;

INSERT INTO public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id,lifecycle_state_code
) VALUES (
  'EJECUCION_ROUTER_LF',
  'v0.1-pilot',
  'PRODUCCION_CONTROLADA_READ_ONLY',
  'SUPABASE_STRUCTURED_OPERATION',
  'cristhianlujan/claude-persona-lf-patch',
  jsonb_build_array(
    'public.lf_router_stage1_validate_v2',
    'public.lf_router_route_v1',
    'public.lf_operation_execution',
    'public.lf_operation_execution_steps',
    'public.lf_record_operation_step_core_v1'
  ),
  'Pilot governed runtime for ACT-0001. Reuses operation-neutral execution enforcement. No Router effect authority. Stage2 must consume the sealed Stage1 of the same execution.',
  'ORCHESTRATION',
  'ROUTER_EXECUTION',
  'ROUTER_EXECUTION',
  'DOC',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'OP_OPERATIONAL'
);

INSERT INTO public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  'CONTRACT-EJECUCION-ROUTER-LF-v0.1',
  'public.lf_operation_contracts/EJECUCION_ROUTER_LF/CONTRACT-EJECUCION-ROUTER-LF-v0.1',
  NULL,
  jsonb_build_array('request_intake','stage1_seal'),
  jsonb_build_object(
    'read_only',true,
    'router_asset','ACT-0001',
    'dynamic_route',true,
    'stage2_requires_sealed_stage1',true,
    'stage2_reads_stage1_from_execution',true,
    'caller_selects_next_step',false,
    'effect_authority',false
  ),
  jsonb_build_array(
    'direct_stage2_without_stage1',
    'stage1_literal_mismatch',
    'stage1_not_valid',
    'stage1_digest_mismatch',
    'fabricated_trust_validation'
  ),
  '[]'::jsonb,
  'ACTIVE_ENFORCEMENT',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027'
);

INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,execution_sql,fail_condition,created_by_execution_id,updated_by_execution_id
) VALUES
(
  'EJECUCION_ROUTER_LF','request_intake',10,10,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.1',
  'Bind the literal request to one durable ACT-0001 execution before any model classification.',
  jsonb_build_array('request_literal'),
  'public.lf_router_pipeline_begin_v1',
  jsonb_build_array('original_request_text','request_sha256','stage1_required'),
  jsonb_build_array('server_validated'),
  jsonb_build_array('request_digest_mismatch','execution_binding_mismatch'),
  'BLOCK_ROUTER_REQUEST_INTAKE_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array('original_request_text','request_sha256','stage1_required'),
  'stage1_seal','RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'The request literal is immutable for the execution.',
  NULL,NULL,
  'EXEC-ROUTER-PIPELINE-PILOT-20261027','EXEC-ROUTER-PIPELINE-PILOT-20261027'
),
(
  'EJECUCION_ROUTER_LF','stage1_seal',20,20,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.1',
  'Validate and seal LF_ROUTER_STAGE1_V2 produced for the exact request literal.',
  jsonb_build_array('stage1_output'),
  'public.lf_router_stage1_validate_v2',
  jsonb_build_array('stage1_payload','stage1_sha256','stage1_validation'),
  jsonb_build_array('server_validated'),
  jsonb_build_array('stage1_invalid','stage1_literal_mismatch','stage1_digest_mismatch'),
  'BLOCK_ROUTER_STAGE1_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array('stage1_payload','stage1_sha256','stage1_validation'),
  'stage2_route','RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'Stage1 provenance is execution-bound; structural validity alone is insufficient.',
  NULL,NULL,
  'EXEC-ROUTER-PIPELINE-PILOT-20261027','EXEC-ROUTER-PIPELINE-PILOT-20261027'
),
(
  'EJECUCION_ROUTER_LF','stage2_route',30,30,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.1',
  'Run ACT-0001 Stage2 only from the sealed Stage1 stored in this execution.',
  jsonb_build_array('sealed_stage1'),
  'public.lf_router_route_v1',
  jsonb_build_array('route_result','stage1_sha256','route_step'),
  jsonb_build_array('server_validated'),
  jsonb_build_array('stage1_not_clean','route_result_mismatch','route_not_act0001'),
  'BLOCK_ROUTER_STAGE2_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array('route_result','stage1_sha256','route_step'),
  'DYNAMIC_FROM_ROUTE_RESULT','RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'Caller cannot supply Stage1 to Stage2; Stage2 reads the sealed payload by execution_id.',
  NULL,NULL,
  'EXEC-ROUTER-PIPELINE-PILOT-20261027','EXEC-ROUTER-PIPELINE-PILOT-20261027'
);

INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
)
SELECT
  c.operation_code,c.step_order,c.step_id,true,
  (
    SELECT string_agg(x,'; ' ORDER BY ord)
    FROM jsonb_array_elements_text(c.required_evidence_keys)
         WITH ORDINALITY AS e(x,ord)
  ),
  'public.lf_operation_step_contracts/'||c.operation_code||'/'||c.step_id,
  NULL,true,c.execution_order,
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027'
FROM public.lf_operation_step_contracts c
WHERE c.operation_code='EJECUCION_ROUTER_LF';

INSERT INTO public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,
  status,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  'public.lf_operation_judges/EJECUCION_ROUTER_LF/JUDGE-EJECUCION-ROUTER-LF-v0.1',
  NULL,
  jsonb_build_array('server_validated'),
  jsonb_build_array('server_validation_failed'),
  jsonb_build_array(
    'STEP_PASS_WITH_EVIDENCE',
    'RETURN_TO_ORCHESTRATOR',
    'BLOCKED_ROUTER_PIPELINE_NOT_CLEAN'
  ),
  'ACTIVE_ENFORCEMENT',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027'
);

INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
SELECT
  c.operation_code,c.step_order,c.step_id,'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE',
  'BLOCKED_ROUTER_PIPELINE_NOT_CLEAN',
  'RETURN_TO_ORCHESTRATOR',
  c.required_evidence_keys,
  'ACTIVE_ENFORCEMENT',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027',
  'EXEC-ROUTER-PIPELINE-PILOT-20261027'
FROM public.lf_operation_step_contracts c
WHERE c.operation_code='EJECUCION_ROUTER_LF';

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

-- Harden the generic recorder specifically for EJECUCION_ROUTER_LF:
-- caller-provided trust is ignored and recomputed server-side.
DO $patch_core$
DECLARE
  d text;
  old_anchor text := $old$
  if v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;
  -- Frozen execution contract is authoritative when present. No silent fallback
$old$;
  new_anchor text := $new$
  if v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;

  if v_execution.operation_code='EJECUCION_ROUTER_LF' then
    p_trust_validation:=public.lf_router_execution_trust_validation_v1(
      p_execution_id,p_step_id,p_evidence_payload
    );
  end if;

  -- Frozen execution contract is authoritative when present. No silent fallback
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_anchor,'')))/length(old_anchor)<>1 THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_CORE_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_anchor,new_anchor);
  EXECUTE d;
END
$patch_core$;

CREATE OR REPLACE FUNCTION public.lf_record_router_execution_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_trust jsonb;
BEGIN
  v_trust:=public.lf_router_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );

  RETURN public.lf_record_operation_step_core_v1(
    p_execution_id,
    p_step_id,
    p_evidence_ref,
    p_evidence_payload,
    p_actor_execution_id,
    'EJECUCION_ROUTER_LF',
    'DOC',
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    v_trust,
    false,
    'lf_record_router_execution_step_v1'
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_record_router_execution_step_v1(text,text,text,jsonb,text)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_record_router_execution_step_v1(text,text,text,jsonb,text)
  TO postgres;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_begin_v1(
  p_request_text text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_request text:=btrim(coalesce(p_request_text,''));
  v_request_sha text;
  v_execution_id text;
  v_begin jsonb;
  v_step jsonb;
BEGIN
  IF v_request='' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_REQUIRED'
    );
  END IF;

  v_request_sha:=encode(
    extensions.digest(convert_to(v_request,'UTF8'),'sha256'),
    'hex'
  );
  v_execution_id:='EXEC-ROUTER-'||
    upper(replace(gen_random_uuid()::text,'-',''));

  v_begin:=public.fn_lf_operation_reserve_execution_v1(
    v_execution_id,
    'EJECUCION_ROUTER_LF',
    'DOC',
    'ACT-0001',
    'router-pipeline:'||v_execution_id,
    v_request_sha,
    v_execution_id,
    'cristhianlujan/claude-persona-lf-patch',
    'ACT-0001',
    jsonb_build_object(
      'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
      'router','ACT-0001',
      'original_request_text',v_request,
      'request_sha256',v_request_sha,
      'pipeline_mode','GOVERNED_DYNAMIC_STATE_MACHINE',
      'current_step','request_intake',
      'next_step','stage1_seal',
      'effect_authority',false
    )
  );

  IF v_begin->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_RESERVE_FAILED',
      'begin',v_begin
    );
  END IF;

  v_step:=public.lf_record_router_execution_step_v1(
    v_execution_id,
    'request_intake',
    'router-request://'||v_request_sha,
    jsonb_build_object(
      'original_request_text',v_request,
      'request_sha256',v_request_sha,
      'stage1_required',true
    ),
    v_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_INTAKE_NOT_CLEAN',
      'execution_id',v_execution_id,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','request_intake',
        'next_step','stage1_seal'
      ),
      updated_by_execution_id=v_execution_id,
      updated_at=now()
  WHERE execution_id=v_execution_id;

  RETURN jsonb_build_object(
    'status','STAGE1_REQUIRED',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',v_execution_id,
    'request_sha256',v_request_sha,
    'stage1_contract','LF_ROUTER_STAGE1_V2',
    'current_step','request_intake',
    'next_step','stage1_seal',
    'caller_selects_next_step',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_begin_v1(text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_begin_v1(text)
  TO service_role;

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
        'next_step',coalesce(v_route->>'paso','UNKNOWN'),
        'stage2_route_step',v_route->>'paso'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  RETURN jsonb_build_object(
    'status','STAGE2_READY',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','stage2_route',
    'next_step',v_route->>'paso',
    'route_result',v_route,
    'caller_selects_next_step',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_stage2_continue_v1(text)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_stage2_continue_v1(text)
  TO postgres;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_stage1_submit_v1(
  p_execution_id text,
  p_stage1 jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_validation jsonb;
  v_stage1_sha text;
  v_step jsonb;
  v_stage2 jsonb;
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

  IF p_stage1 IS NULL OR jsonb_typeof(p_stage1)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_STAGE1_REQUIRED',
      'execution_id',p_execution_id
    );
  END IF;

  v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
  v_stage1_sha:=encode(
    extensions.digest(convert_to(p_stage1::text,'UTF8'),'sha256'),
    'hex'
  );

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'stage1_seal',
    'router-stage1://'||v_stage1_sha,
    jsonb_build_object(
      'stage1_payload',p_stage1,
      'stage1_sha256',v_stage1_sha,
      'stage1_validation',v_validation
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_step->>'code','BLOCK_ROUTER_STAGE1_NOT_CLEAN'),
      'execution_id',p_execution_id,
      'stage1_validation',v_validation,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','stage1_seal',
        'next_step','stage2_route',
        'stage1_sha256',v_stage1_sha
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  v_stage2:=public.lf_router_pipeline_stage2_continue_v1(p_execution_id);

  RETURN v_stage2||jsonb_build_object(
    'stage1_status','SEALED',
    'stage1_sha256',v_stage1_sha
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_stage1_submit_v1(text,jsonb)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_stage1_submit_v1(text,jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_status_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT CASE
    WHEN e.execution_id IS NULL THEN jsonb_build_object(
      'status','NOT_FOUND',
      'execution_id',p_execution_id
    )
    ELSE jsonb_build_object(
      'status','FOUND',
      'execution_id',e.execution_id,
      'operation_code',e.operation_code,
      'execution_status',e.status,
      'request_sha256',e.request_sha256,
      'manifest',e.manifest,
      'steps',coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'step_order',s.step_order,
            'step_id',s.step_id,
            'status',s.status,
            'evidence_ref',s.evidence_ref
          )
          ORDER BY s.step_order
        )
        FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=e.execution_id
      ),'[]'::jsonb)
    )
  END
  FROM (SELECT 1) x
  LEFT JOIN public.lf_operation_execution e
    ON e.execution_id=p_execution_id
   AND e.operation_code='EJECUCION_ROUTER_LF'
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_status_v1(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_status_v1(text)
  TO service_role,supabase_read_only_user;

COMMENT ON FUNCTION public.lf_router_pipeline_begin_v1(text) IS
'Pilot governed entry for ACT-0001. Creates one EJECUCION_ROUTER_LF execution, binds the immutable literal request and returns STAGE1_REQUIRED. It does not accept or skip Stage1.';

COMMENT ON FUNCTION public.lf_router_pipeline_stage1_submit_v1(text,jsonb) IS
'Pilot governed continuation for ACT-0001. Validates and seals LF_ROUTER_STAGE1_V2 for the exact execution, then automatically executes Stage2 from the sealed server-side payload. Caller does not choose Stage2.';

COMMENT ON FUNCTION public.lf_router_pipeline_stage2_continue_v1(text) IS
'Internal-only ACT-0001 Stage2 continuation. Reads sealed Stage1 from lf_operation_execution_steps; direct service-role invocation is revoked.';

-- Transactional acceptance test. The sentinel rolls back only test executions,
-- not the schema/contract changes in this migration.
DO $postcheck$
DECLARE
  v_begin jsonb;
  v_exec text;
  v_direct jsonb;
  v_bad jsonb;
  v_good jsonb;
  v_status jsonb;
  v_stage1_good jsonb;
  v_stage1_bad jsonb;
  v_fake_core jsonb;
  v_exec2 text;
  v_begin2 jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND operation_family='ORCHESTRATION'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_REGISTRY_POSTCHECK_FAILED';
  END IF;

  IF (
    SELECT count(*)
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND status='ACTIVE_ENFORCEMENT'
  )<>3 THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_STEP_COUNT_FAILED';
  END IF;

  IF has_function_privilege(
       'service_role',
       'public.lf_router_pipeline_stage2_continue_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_stage2_continue_v1(text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_STAGE2_DIRECT_GRANT_FORBIDDEN';
  END IF;

  BEGIN
    v_begin:=public.lf_router_pipeline_begin_v1(
      'Analiza técnicamente el Login B2B sin realizar cambios.'
    );
    IF v_begin->>'status'<>'STAGE1_REQUIRED' THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_BEGIN_FAIL:%',v_begin;
    END IF;
    v_exec:=v_begin->>'execution_id';

    -- Even postgres/internal Stage2 cannot skip Stage1.
    v_direct:=public.lf_router_pipeline_stage2_continue_v1(v_exec);
    IF v_direct->>'blocking_code'<>'BLOCK_ROUTER_STAGE1_NOT_CLEAN' THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_DIRECT_STAGE2_NOT_BLOCKED:%',v_direct;
    END IF;

    v_stage1_bad:=jsonb_build_object(
      'schema_version','LF_ROUTER_STAGE1_V2',
      'texto_original','OTRO TEXTO',
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

    v_bad:=public.lf_router_pipeline_stage1_submit_v1(v_exec,v_stage1_bad);
    IF v_bad->>'status'<>'BLOCKED' THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_BAD_STAGE1_NOT_BLOCKED:%',v_bad;
    END IF;

    v_stage1_good:=v_stage1_bad||jsonb_build_object(
      'texto_original','Analiza técnicamente el Login B2B sin realizar cambios.'
    );

    v_good:=public.lf_router_pipeline_stage1_submit_v1(v_exec,v_stage1_good);
    IF v_good->>'status'<>'STAGE2_READY'
       OR v_good#>>'{route_result,paso}'
            IS DISTINCT FROM 'PROGRAMACION_PROFILE_SELECTION_REQUIRED'
       OR v_good#>>'{route_result,router}' IS DISTINCT FROM 'ACT-0001'
    THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_VALID_FLOW_FAIL:%',v_good;
    END IF;

    v_status:=public.lf_router_pipeline_status_v1(v_exec);
    IF v_status->>'status'<>'FOUND'
       OR jsonb_array_length(v_status->'steps')<>3
       OR v_status#>>'{steps,0,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{steps,1,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{steps,2,status}'<>'STEP_PASS_WITH_EVIDENCE'
    THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_STATUS_FAIL:%',v_status;
    END IF;

    -- Direct calls to the generic core cannot forge trust for this operation.
    v_begin2:=public.lf_router_pipeline_begin_v1(
      'Consulta el estado operativo del Login B2B sin modificar nada.'
    );
    v_exec2:=v_begin2->>'execution_id';

    v_fake_core:=public.lf_record_operation_step_core_v1(
      v_exec2,
      'stage2_route',
      'forged://stage2',
      jsonb_build_object(
        'route_result',jsonb_build_object(
          'router','ACT-0001',
          'paso','OPERACIONES_PROFILE_SELECTION_REQUIRED',
          'downstream_execution_allowed',false
        ),
        'stage1_sha256',repeat('0',64),
        'route_step','OPERACIONES_PROFILE_SELECTION_REQUIRED'
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
      'FORGED_CALLER'
    );

    IF v_fake_core->>'outcome'<>'BLOCKED'
       OR v_fake_core->>'code' NOT IN (
         'PRIOR_REQUIRED_STEP_NOT_CLEAN',
         'ROUTER_PIPELINE_SERVER_VALIDATION_FAILED'
       )
    THEN
      RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_FAKE_CORE_NOT_BLOCKED:%',v_fake_core;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ301',
      MESSAGE='ROUTER_PIPELINE_PILOT_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ301' THEN
      NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND created_by_execution_id LIKE 'EXEC-ROUTER-%'
  ) THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_POSTCHECK_EXECUTION_RESIDUE';
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
       ),
       'v_execution.operation_code=''EJECUCION_ROUTER_LF'''
     )=0
  THEN
    RAISE EXCEPTION 'ROUTER_PIPELINE_PILOT_CORE_TRUST_HOOK_MISSING';
  END IF;
END
$postcheck$;

COMMIT;
